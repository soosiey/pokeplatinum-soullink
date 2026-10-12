-- Actual network and lobby modules with a deterministic in-memory relay.
local N = dofile("tools/soullink/network.lua")
local L = dofile("tools/soullink/lobby.lua")
local queues = { host = {}, client = {"SL1|1|relay|WELCOME|client1"} }
local function socket(role)
    return {
        socketServerGetInfo = function() return "127.0.0.1:7777" end,
        socketServerSetTimeout = function(ms) assert(ms == 1) end,
        socketServerResponse = function() return table.remove(queues[role], 1) or "" end,
        socketServerSend = function(message)
            local target = role == "host" and "client" or "host"
            if role == "client" then message = message:gsub("|client|", "|client1|", 1) end
            queues[target][#queues[target] + 1] = message
            return #message
        end,
    }
end
local rooms, nets = {}, {}
for _, role in ipairs({"host", "client"}) do
    local cfg = {role=role,host="127.0.0.1",port=7777,allowSinglePlayer=false}
    nets[role] = N.connect(cfg, 258, socket(role), function() end)
    rooms[role] = L.new(cfg, nets[role], function() end)
end
local function step(frame)
    for _, role in ipairs({"host", "client"}) do
        nets[role].update(frame); rooms[role].update()
    end
end
local hostIntent = {type=2,personality=123,otId=456,pairId=0,species=0,location=0,flags=1,reserved=1}
local clientIntent = {type=2,personality=789,otId=900,pairId=0,species=0,location=0,flags=1,reserved=1}
rooms.host.offer(hostIntent); rooms.client.offer(clientIntent)
for frame=1,20 do step(frame) end
assert(rooms.host.pending.flags == 2 and rooms.client.pending.flags == 2)
local function cancel(nonce)
    return {type=2,personality=0,otId=0,pairId=0,species=0,location=0,flags=0,reserved=nonce}
end
rooms.client.offer(cancel(1))
for frame=1,20 do step(frame) end
assert(rooms.client.pending == nil and rooms.host.pending.flags == 1)
-- A delayed approval for the cancelled attempt is ignored at title.
assert(nets.client.onmessage("host", "GATE", "client1,123,456,0,0,50,3,1"))
assert(rooms.client.pending == nil)
clientIntent.reserved = 2
rooms.client.offer(clientIntent)
for frame=1,20 do step(frame) end
assert(rooms.host.pending.flags == 2 and rooms.client.pending.flags == 2)
rooms.host.offer(cancel(1))
for frame=1,20 do step(frame) end
assert(rooms.host.pending == nil and rooms.client.pending.flags == 1)
hostIntent.reserved = 2
rooms.host.offer(hostIntent)
for frame=1,20 do step(frame) end
assert(rooms.host.pending.flags == 2 and rooms.client.pending.flags == 2)
hostIntent.flags = 0x101
rooms.host.offer(hostIntent)
for frame=21,40 do step(frame) end
for _, role in ipairs({"host", "client"}) do
    local grant = rooms[role].pending
    assert(grant.flags == 3 and grant.personality == 123 and grant.otId == 456)
    assert(grant.location == (role == "host" and 0x31 or 0x32))
end
print("PASS: network/lobby integration delivers host-selected identity and distinct persistent slots")
