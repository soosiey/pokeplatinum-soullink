local M = dofile("tools/soullink/mailbox.lua")
local ram, writes = {}, {}
local function put(o, v, n)
    for i = 0, n - 1 do ram[o + i] = (v >> (8 * i)) & 255 end
end
local function get(o, n)
    local v = 0
    for i = 0, n - 1 do v = v | ((ram[o + i] or 0) << (8 * i)) end
    return v
end
local io = {
    read16 = function(o) return get(o, 2) end,
    read32 = function(o) return get(o, 4) end,
    write16 = function(o, v) table.insert(writes, o); put(o, v, 2) end,
    write32 = function(o, v) table.insert(writes, o); put(o, v, 4) end,
}
put(0, M.magic, 4); put(4, M.version, 2); put(6, M.size, 2)
assert(M.send_ping(io, 0xDEADBEEF) == 1)
assert(writes[#writes] == 64, "sequence must be published last")
assert(M.read_message(io, 64).personality == 0xDEADBEEF)
local count = #writes
assert(M.send_ping(io, 1) == nil and #writes == count, "pending message overwritten")
put(12, 1, 4)
assert(M.send_ping(io, 123) == 2)
put(88, 0, 4)
assert(M.read_message(io, 64) == nil, "bad checksum accepted")
put(4, 18, 2)
count = #writes
assert(not pcall(M.send_ping, io, 4) and #writes == count)
put(4, M.version, 2)
put(64, 0xFFFFFFFF, 4); put(12, 0xFFFFFFFF, 4)
assert(M.send_ping(io, 42) == 1)
for i = 0, 31 do ram[32 + i] = ram[64 + i] end
local message = M.receive(io)
assert(message.personality == 42 and get(96, 4) == 1)
assert(M.receive(io) == nil)
put(32, 3, 4)
assert(not pcall(M.receive, io), "sequence gap must fail closed")
print("PASS: Lua publication order, backpressure, checksum, ABI refusal, rollover and acknowledgements")
