-- Host-owned startup agreement. No socket or emulator API calls in this module.
local M = {}
local WAIT, READY, APPROVED, REJECTED = 1, 2, 3, 4

local function encode(m)
    return table.concat({ m.personality, m.otId, m.pairId, m.species,
        m.location, m.flags, m.reserved }, ",")
end

local function decode(payload)
    if type(payload) ~= "string" or #payload > 100 then return nil end
    local values = { payload:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)$") }
    if #values ~= 7 then return nil end
    for i, value in ipairs(values) do
        values[i] = tonumber(value)
        if values[i] > (i <= 2 and 0xFFFFFFFF or 65535) then return nil end
    end
    return { personality = values[1], otId = values[2], pairId = values[3],
        species = values[4], location = values[5], flags = values[6], reserved = values[7] }
end

local function action(m) return m.flags & 255 end
local function slot(m) return m.location & 15 end
local function mask(m) return (m.location >> 4) & 15 end
local function valid_intent(m)
    -- A zero-action intent withdraws this nonce without resetting the transport.
    if m and m.reserved ~= 0 and m.flags == 0 then
        return m.personality == 0 and m.otId == 0 and m.pairId == 0
            and m.species == 0 and m.location == 0
    end
    if not m or m.reserved == 0 or (m.flags & ~0x103) ~= 0
        or (action(m) ~= 1 and action(m) ~= 2) then return false end
    if action(m) == 1 then return m.location == 0 and m.pairId == 0 and m.species == 0 end
    return m.location <= 0x2FF and (m.location >> 8) >= 1
        and slot(m) >= 1 and slot(m) <= 4 and (mask(m) & 1) == 1
        and (mask(m) & (1 << (slot(m) - 1))) ~= 0
        and (m.personality ~= 0 or m.otId ~= 0)
end

local function reply(intent, status, low, high, settingsLow, settingsHigh, player, roster)
    return { type = 3, personality = low or 0, otId = high or 0,
        pairId = settingsLow or 0, species = settingsHigh or 0,
        location = (player or 0) | ((roster or 0) << 4), flags = status, reserved = intent.reserved }
end

function M.new(config, net, log)
    local state = { pending = nil }
    local localIntent, locked, lastStatus
    local intents, sent = {}, {}
    local function deliver(name, intent, result)
        local payload = encode(result)
        if name == "host" then
            if sent.host ~= payload then state.pending = result; sent.host = payload end
        elseif sent[name] ~= payload then
            if net.send("GATE", name .. "," .. payload) then sent[name] = payload end
        end
    end
    function state.offer(message)
        if not valid_intent(message) then log("Invalid local lobby intent"); return end
        if action(message) == 0 then
            if localIntent and localIntent.reserved == message.reserved then
                if config and config.role == "host" then
                    for name, record in pairs(intents) do
                        deliver(name, record.value, reply(record.value, WAIT))
                    end
                end
                localIntent, locked, lastStatus, state.pending, sent = nil, nil, nil, nil, {}
                if config and config.role == "client" then net.send("INTENT", encode(message)) end
                log("Lobby: cancelled; returned to title")
            end
            return
        end
        if not localIntent or localIntent.reserved ~= message.reserved then
            locked, sent, state.pending = nil, {}, nil
        end
        localIntent = message
        if config and config.role == "client" then net.send("INTENT", encode(message)) end
    end
    net.onmessage = function(sender, kind, payload)
        if config.role == "host" and kind == "INTENT" then
            local intent = decode(payload)
            if not valid_intent(intent) then return false, "invalid lobby intent" end
            if action(intent) == 0 then
                local previous = intents[sender]
                if previous and previous.value.reserved == intent.reserved then
                    intents[sender], sent[sender] = nil, nil
                    -- Do not retain a START request while a peer is at title.
                    if localIntent then localIntent.flags = action(localIntent) end
                end
                return true
            end
            intents[sender] = { value = intent, peer = net.peers[sender] }
            sent[sender] = nil -- Re-send after Lua restart or retransmitted intent.
            return true
        elseif config.role == "client" and sender == "host" and kind == "GATE" then
            local target, body = payload:match("^(client[1-3]),(.*)$")
            local message = decode(body)
            if not message or message.flags < WAIT or message.flags > REJECTED then
                return false, "invalid gate response"
            end
            if target == net.identity and localIntent and message.reserved == localIntent.reserved then
                message.type = 3
                state.pending = message
            end
            return true
        end
        return false, "unsupported lobby message"
    end
    function state.update()
        if not config or not localIntent then return end
        if config.role ~= "host" then
            if not net.active or not net.peers.host then state.pending = reply(localIntent, WAIT) end
            return
        end
        local roster = { { name = "host", value = localIntent } }
        local status, reason = WAIT, "waiting for compatible ready players"
        for i = 1, 3 do
            local name = "client" .. i
            if net.peers[name] then
                local record = intents[name]
                roster[#roster + 1] = { name = name,
                    value = record and record.peer == net.peers[name] and record.value or nil }
            end
        end
        if locked then
            for _, player in ipairs(roster) do
                if player.value then
                    local grant = locked[player.name]
                    -- A newly connected transient identity cannot silently inherit a slot.
                    local record = intents[player.name]
                    if grant and grant.reserved == player.value.reserved
                        and (player.name == "host" or grant.peer == (record and record.peer)) then
                        deliver(player.name, player.value, grant)
                    else deliver(player.name, player.value, reply(player.value, REJECTED)) end
                end
            end
            return
        end
        local ready = net.active and #roster >= (config.allowSinglePlayer and 1 or 2)
        local allMask, expected = 0, mask(localIntent)
        for _, player in ipairs(roster) do
            local m = player.value
            if not m then ready = false
            elseif action(m) ~= action(localIntent) then status, reason, ready = REJECTED, "New Game/Continue mismatch", false
            elseif action(m) == 2 then
                local bit = 1 << (slot(m) - 1)
                if m.personality ~= localIntent.personality or m.otId ~= localIntent.otId
                    or m.pairId ~= localIntent.pairId or m.species ~= localIntent.species
                    or mask(m) ~= expected or (allMask & bit) ~= 0
                    or (player.name == "host" and slot(m) ~= 1)
                    or (player.name ~= "host" and slot(m) == 1) then
                    status, reason, ready = REJECTED, "saved run or roster mismatch", false
                end
                allMask = allMask | bit
            end
        end
        if next(net.incompatible) then status, reason, ready = REJECTED, "incompatible peer protocol", false end
        if action(localIntent) == 2 and allMask ~= expected then ready = false end
        if ready then status, reason = READY, "roster ready; Player 1 press START" end
        if ready and (action(localIntent) == 2 or (localIntent.flags & 0x100) ~= 0) then
            local activeMask = action(localIntent) == 2 and expected or (1 << #roster) - 1
            if localIntent.personality == 0 and localIntent.otId == 0 then
                status, reason = REJECTED, "invalid run ID proposal"
            else
                locked = {}
                for i, player in ipairs(roster) do
                    local playerSlot = action(localIntent) == 2 and slot(player.value) or i
                    locked[player.name] = reply(player.value, APPROVED, localIntent.personality,
                        localIntent.otId, localIntent.pairId, localIntent.species, playerSlot, activeMask)
                    locked[player.name].peer = net.peers[player.name]
                    deliver(player.name, player.value, locked[player.name])
                end
                status, reason = APPROVED, "roster locked and approved"
            end
        end
        if not locked then
            for _, player in ipairs(roster) do
                if player.value then deliver(player.name, player.value, reply(player.value, status)) end
            end
        end
        if lastStatus ~= reason then log("Lobby: " .. reason); lastStatus = reason end
    end
    return state
end

return M
