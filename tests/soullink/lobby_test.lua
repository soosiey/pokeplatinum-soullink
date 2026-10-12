local L = dofile("tools/soullink/lobby.lua")
local function intent(action, slot, mask, low, nonce)
    return { type = 2, personality = low or 11, otId = 22, pairId = 0, species = 0,
        flags = action, location = action == 2 and (slot | (mask << 4) | 0x100) or 0,
        reserved = nonce or 1 }
end
local function encode(m)
    return table.concat({m.personality,m.otId,m.pairId,m.species,m.location,m.flags,m.reserved}, ",")
end
local function setup(solo)
    local messages = {}
    local net = {active=true, peers={}, incompatible={}, send=function(kind,payload)
        messages[#messages+1] = {kind,payload}; return true
    end}
    local room = L.new({role="host",allowSinglePlayer=solo},net,function() end)
    local function remote(name,m)
        net.peers[name] = net.peers[name] or {}
        assert(net.onmessage(name,"INTENT",encode(m)))
    end
    return room,net,remote,messages
end
local room,net,remote,messages = setup(false)
room.offer(intent(1)); room.update(); assert(room.pending.flags == 1)
remote("client1",intent(1)); room.update(); assert(room.pending.flags == 2)
local start = intent(1); start.flags = 0x101
room.offer(start); room.update()
assert(room.pending.flags == 3 and room.pending.location == 0x31)
assert(messages[#messages][2]:match("^client1,11,22,0,0,50,3,1$"))
remote("client2",intent(1)); room.update()
assert(messages[#messages][2]:match("^client2,0,0,0,0,0,4,1$"))
assert(room.pending.location == 0x31) -- Late joins cannot resize the roster.
net.peers.client1 = {}; remote("client1",intent(1)); room.update()
assert(messages[#messages][2]:match("^client1,0,0,0,0,0,4,1$"))

room,net,remote = setup(true)
room.offer(start); room.update(); assert(room.pending.flags == 3 and room.pending.location == 0x11)
room,net,remote = setup(false)
room.offer(intent(2,1,7)); remote("client1",intent(2,3,7)); room.update()
assert(room.pending.flags == 1)
remote("client2",intent(2,2,7)); room.update()
assert(room.pending.flags == 3 and room.pending.location == 0x71) -- Swapped connection order.
for _, bad in ipairs({intent(2,1,3),intent(2,2,3,99),intent(1),intent(2,2,7)}) do
    room,net,remote = setup(false)
    room.offer(intent(2,1,3)); remote("client1",bad); room.update()
    assert(room.pending.flags == 4)
end
room,net,remote = setup(false)
room.offer(start); remote("client1",intent(1)); net.incompatible.client2=true
room.update(); assert(room.pending.flags == 4)
assert(not net.onmessage("client1","INTENT","bad"))

local clientNet = {active=true, peers={host={}}, identity="client2", send=function() return true end}
local client = L.new({role="client"},clientNet,function() end)
client.offer(intent(1))
assert(clientNet.onmessage("host","GATE","client1,11,22,0,0,49,3,1"))
assert(not client.pending)
assert(clientNet.onmessage("host","GATE","client2,11,22,0,0,50,3,2"))
assert(not client.pending)
assert(clientNet.onmessage("host","GATE","client2,11,22,0,0,50,3,1"))
assert(client.pending.flags == 3)
clientNet.active=false; client.update(); assert(client.pending.flags == 1)
print("PASS: lobby default/solo, host lock, exact Continue roster, persistent slot remapping, late joins and targeted grants")
