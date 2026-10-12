local N = dofile("tools/soullink/network.lua")
local function config(role)
    return { role = role, host = "127.0.0.1", port = 7777, allowSinglePlayer = false }
end
local function load(value)
    return N.load_config("test-config.lua", function() return function() return value end end)
end
assert(load(config("host")))
assert(load(config("client")))
for _, value in ipairs({ false, {}, { role = "host", host = "", port = 7777 },
    { role = "client", host = "localhost", port = 7777, allowSinglePlayer = true },
    { role = "host", host = "localhost", port = 1.5 },
    { role = "host", host = "localhost", port = 65536 } }) do
    assert(not load(value))
end
assert(not N.load_config("missing", function() return nil, "missing file" end))
assert(not N.load_config("broken", function() return function() error("broken") end end))

local function setup(role)
    local test = { inbox = {}, sent = {}, logs = {}, time = 0, receives = 0 }
    test.socket = {
        socketServerGetInfo = function() return "127.0.0.1:7777" end,
        socketServerSetTimeout = function(ms) assert(ms == 1) end,
        socketServerSend = function(message)
            test.sent[#test.sent + 1] = message
            return #message
        end,
        socketServerResponse = function()
            test.receives = test.receives + 1
            return table.remove(test.inbox, 1) or ""
        end,
    }
    test.state = N.connect(config(role), 257, test.socket,
        function(s) test.logs[#test.logs + 1] = s end, function() return test.time end)
    function test.receive(message, frame)
        test.inbox[#test.inbox + 1] = message
        test.state.update(frame or 1)
    end
    return test
end

for _, role in ipairs({ "host", "client" }) do
    local t = setup(role)
    local sender = role == "host" and "client1" or "host"
    assert(t.state.active and t.sent[1] == "SL1|1|" .. role .. "|HELLO|257")
    if role == "client" then
        t.receive("SL1|1|relay|WELCOME|client2")
        assert(t.state.identity == "client2")
    end
    t.receive("SL1|2|" .. sender .. "|KEEPALIVE|60")
    assert(not t.state.peers[sender])
    t.receive("SL1|1|" .. sender .. "|HELLO|18")
    assert(not t.state.peers[sender])
    t.receive("SL1|1|" .. sender .. "|HELLO|257")
    assert(t.state.peers[sender])
    t.receive("SL1|2|" .. sender .. "|KEEPALIVE|60", 300)
    assert(t.sent[2] == "SL1|2|" .. role .. "|KEEPALIVE|300")
    local peer = t.state.peers[sender]
    assert(peer.keepalives == 1)
    t.time = 50
    t.receive("SL1|2|" .. sender .. "|KEEPALIVE|60")
    assert(peer.keepalives == 1 and peer.seen == 0)
    for _, message in ipairs({ "garbage", "SL2|3|" .. sender .. "|HELLO|257",
        "SL1|3|intruder|HELLO|257", "SL1|3|" .. sender .. "|KEEPALIVE|bad",
        "SL1|3|" .. sender .. "|DEATH|1", "SL1|inf|" .. sender .. "|HELLO|257" }) do
        t.receive(message)
        assert(t.state.peers[sender] == peer and peer.sequence == 2)
    end
    local before = t.receives
    t.inbox = { "", "" }
    t.state.update(301)
    assert(t.receives == before + 1 and #t.inbox == 1)
    t.time = 600
    t.state.update(302)
    assert(not t.state.peers[sender])
    t.receive("SL1|1|" .. sender .. "|HELLO|257")
    assert(t.state.peers[sender])
    t.socket.socketServerSend = function() return -1 end
    t.state.update(600)
    assert(not t.state.active and next(t.state.peers) == nil)
    before = t.receives
    t.state.update(900)
    assert(t.receives == before)
end
local t = setup("host")
t.socket.socketServerResponse = function() error("connection lost") end
t.state.update(1)
assert(not t.state.active)
assert(not N.connect(nil, 257, nil, function() end).active)
assert(not N.connect(config("host"), 257, nil, function() end).active)
assert(not N.connect(config("host"), 257, {}, function() end).active)
print("PASS: network config, both roles, HELLO/KEEPALIVE, version refusal, duplicates, timeout and errors")
