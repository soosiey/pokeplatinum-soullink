-- Stage 4: mailbox diagnostics, host-authoritative lobby, and startup gates.
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local root = source:match("^(.*[\\/])") or "./"
local mailbox = dofile(root .. "tools/soullink/mailbox.lua")
local adapter = dofile(root .. "tools/soullink/bizhawk.lua")
local network = dofile(root .. "tools/soullink/network.lua")
local lobby = dofile(root .. "tools/soullink/lobby.lua")
local symbols = dofile(root .. ".build/rom/soullink-symbols.lua")
local function log(message) console.log("[Soul Link] " .. message) end
local io = adapter.connect(symbols, log)
local frames, pending, lastHeartbeat = 0, nil, nil
local replies, romPings, stalled, reported = 0, 0, 0, false

log("Waiting for ROM initialization; let the game run.")
while true do
    io.validate_game()
    if mailbox.valid_header(io) then break end
    -- Zero magic means NitroMain has not initialized yet; a different ABI is fatal.
    assert(io.read32(0) == 0, "Mailbox ABI mismatch; no writes made")
    frames = frames + 1
    assert(frames < 1800, "Mailbox did not initialize within 1800 frames")
    emu.frameadvance()
end
log("Mailbox initialized. Testing PING in both directions.")
local config, configError = network.load_config(root .. "soullink-config.lua")
if configError then log(configError) end
local connection = network.connect(config, mailbox.version, comm, log)
local room = lobby.new(config, connection, log)

while true do
    io.validate_game()
    assert(mailbox.valid_header(io), "ROM reset or ABI changed; reload this script")
    local heartbeat = io.read32(8)
    if lastHeartbeat and heartbeat < lastHeartbeat then
        error("ROM reset or savestate rewind detected; reload this script")
    end
    stalled = heartbeat == lastHeartbeat and stalled + 1 or 0
    assert(stalled < 1800, "ROM heartbeat stopped for 1800 frames")
    lastHeartbeat = heartbeat

    local message = mailbox.receive(io)
    if message then
        if message.type == 2 then
            room.offer(message)
        elseif message.flags == 0 then
            romPings = romPings + 1
            log("ROM PING " .. message.sequence .. " acknowledged")
        elseif pending and message.personality == pending.token then
            -- A frame can end between publishing the reply and flushing the ack.
            pending.reply_seen = true
        else
            log("Acknowledged a reply from the previous Lua session")
        end
    end
    if pending and pending.reply_seen and io.read32(12) == pending.sequence then
        replies = replies + 1
        log("Lua PING " .. pending.sequence .. " acknowledged and echoed")
        pending = nil
    end
    if room.pending and not pending then
        if mailbox.send(io, room.pending) then room.pending = nil end
    elseif not pending and frames % 180 == 0 then
        local token = (heartbeat ~ 0x50494E47) & 0xFFFFFFFF
        local sequence = mailbox.send_ping(io, token)
        if sequence then pending = { sequence = sequence, token = token, frame = frames } end
    end
    assert(not pending or frames - pending.frame < 1800, "PING timeout; reload Lua after checking ROM/core")
    if not reported and replies >= 3 and romPings >= 1 then
        log("PASS: 3 Lua round trips and a ROM PING/ack. Keep this running across menus and battles.")
        reported = true
    end
    frames = frames + 1
    connection.update(frames)
    room.update()
    emu.frameadvance()
end
