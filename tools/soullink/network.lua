-- Modern Emerald SL1 handshake, adapted to Platinum's mailbox version.
-- Deliberately retains BizHawk's blocking socket API and its known limitations.
local M = {}

function M.load_config(path, loader)
    local chunk, reason = (loader or loadfile)(path)
    if not chunk then return nil, "network disabled: " .. tostring(reason) end
    local ok, config = pcall(chunk)
    if not ok then return nil, "cannot load config: " .. tostring(config) end
    if type(config) ~= "table" or (config.role ~= "host" and config.role ~= "client")
        or type(config.host) ~= "string" or config.host == ""
        or type(config.port) ~= "number" or config.port ~= math.floor(config.port)
        or config.port < 1 or config.port > 65535
        or (config.allowSinglePlayer ~= nil and type(config.allowSinglePlayer) ~= "boolean")
        or (config.role ~= "host" and config.allowSinglePlayer == true) then
        return nil, "invalid network config in " .. path
    end
    config.allowSinglePlayer = config.allowSinglePlayer == true
    return config
end

function M.connect(config, version, socket, log, now)
    now = now or os.time
    local state = { peers = {}, incompatible = {}, active = false, identity = nil }
    local sequence, nextKeepalive = 1, 300
    local function disable(reason)
        state.active, state.peers = false, {}
        log(reason .. "; restart EmuHawk with socket arguments, then reload Lua")
    end
    local function send(kind, payload)
        local message = table.concat({ "SL1", tostring(sequence), config.role, kind, payload }, "|")
        local ok, sent = pcall(socket.socketServerSend, message)
        if not ok or type(sent) ~= "number" or sent <= 0 then
            disable("Network send failed: " .. tostring(sent))
            return false
        end
        sequence = sequence + 1
        return true
    end
    local function receive(message)
        local protocol, number, sender, kind, payload =
            message:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
        local seq = tonumber(number)
        if protocol ~= "SL1" or not seq or seq < 1 or seq == math.huge
            or seq ~= math.floor(seq) then return false, "malformed message" end
        if sender == "relay" then
            if config.role ~= "client" or kind ~= "WELCOME"
                or not payload:match("^client[1-3]$") then return false, "invalid WELCOME" end
            state.identity = payload
            log("Assigned transient identity " .. payload)
            return true
        end
        if (config.role == "host" and not sender:match("^client[1-3]$"))
            or (config.role == "client" and sender ~= "host") then
            return false, "invalid sender"
        end
        if kind == "HELLO" then
            if tonumber(payload) ~= version then
                state.peers[sender] = nil
                state.incompatible[sender] = true
                return false, "incompatible HELLO from " .. sender .. " (version " .. payload .. ")"
            end
            state.peers[sender] = { sequence = seq, seen = now(), keepalives = 0 }
            state.incompatible[sender] = nil
            log("HELLO received from " .. sender .. " (version " .. payload .. ")")
            return true
        end
        local peer = state.peers[sender]
        if not peer then return false, "KEEPALIVE before compatible HELLO" end
        if seq <= peer.sequence then return true end
        if kind ~= "KEEPALIVE" then
            if not state.onmessage then return false, "unsupported message type " .. kind end
            local valid, reason = state.onmessage(sender, kind, payload)
            if not valid then return false, reason end
            peer.sequence, peer.seen = seq, now()
            return true
        end
        if not payload:match("^%d+$") then return false, "invalid KEEPALIVE" end
        peer.sequence, peer.seen = seq, now()
        peer.keepalives = peer.keepalives + 1
        if peer.keepalives == 1 then log("PASS: HELLO/KEEPALIVE received from " .. sender) end
        return true
    end
    function state.update(frame)
        if not state.active then return end
        if frame >= nextKeepalive then
            if not send("KEEPALIVE", tostring(frame)) then return end
            nextKeepalive = frame + 300
        end
        -- One response per frame, as in the reference. BizHawk handles framing.
        local ok, message = pcall(socket.socketServerResponse)
        if not ok then disable("Network receive failed: " .. tostring(message)); return end
        if message and message ~= "" then
            local valid, reason = receive(message)
            if not valid then log("Ignored network message: " .. reason) end
        end
        for sender, peer in pairs(state.peers) do
            if now() - peer.seen >= 600 then
                state.peers[sender] = nil
                log(sender .. " KEEPALIVE timed out")
            end
        end
    end
    function state.send(kind, payload)
        if not state.active then return false end
        return send(kind, payload)
    end
    if not config then return state end
    if not socket then log("Network disabled: BizHawk comm API unavailable"); return state end
    local ok, info = pcall(socket.socketServerGetInfo)
    if not ok or not info or info == "" then
        disable("Socket not initialized")
        return state
    end
    -- Like the reference, the actual connection comes from EmuHawk CLI arguments,
    -- not config.host/port. Report both so mismatched setup is visible.
    log("Network role=" .. config.role .. ", socket=" .. info
        .. ", config=" .. config.host .. ":" .. config.port)
    ok, info = pcall(socket.socketServerSetTimeout, 1)
    if not ok then disable("Cannot set socket timeout: " .. tostring(info)); return state end
    state.active = true
    if send("HELLO", tostring(version)) then log("HELLO sent as " .. config.role) end
    return state
end

return M
