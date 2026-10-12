local adapter = dofile("tools/soullink/bizhawk.lua")
local log = function() end
local symbols = { mailbox = 0x02101020, size = 128, version = 0x0102,
    rom_sha1 = string.rep("a", 40) }
local domains = { ["Main RAM"] = 0x400000, ["ARM9 System Bus"] = 0,
    ["ARM7 System Bus"] = 0 }
local lastAddress, lastDomain, reads, writes = nil, nil, 0, 0
local hash, system, version = symbols.rom_sha1, "NDS", "2.11.1"
emu = { getsystemid = function() return system end }
client = { getversion = function() return version end }
gameinfo = { getromhash = function() return hash end }
local function read(a, d) lastAddress, lastDomain = a, d; reads = reads + 1; return 0 end
local function write(a, v, d) lastAddress, lastDomain = a, d; writes = writes + 1 end
memory = {
    getmemorydomainlist = function()
        return { [0] = "Main RAM", [1] = "ARM9 System Bus", [2] = "ARM7 System Bus" }
    end,
    getmemorydomainsize = function(d) return domains[d] end,
    read_u16_le = read, read_u32_le = read,
    write_u16_le = write, write_u32_le = write,
}
local io = adapter.connect(symbols, log)
assert(reads == 0 and writes == 0, "connecting must not touch memory")
io.read32(8)
assert(lastAddress == 0x101028 and lastDomain == "Main RAM")
io.write32(96, 1)
assert(lastAddress == 0x101080 and writes == 1)
assert(not pcall(io.write32, 0, 1), "ROM header write allowed")
assert(not pcall(io.write32, 32, 1), "ROM outgoing write allowed")
assert(not pcall(io.read32, 128), "out of bounds read allowed")
assert(not pcall(io.write32, 65, 1), "unaligned write allowed")
assert(writes == 1)
hash = string.rep("b", 40)
assert(not pcall(adapter.connect, symbols, log), "stale symbols allowed")
assert(not pcall(io.validate_game), "ROM replacement not detected")
hash = symbols.rom_sha1
domains["Main RAM"] = 0x1000000
assert(not pcall(adapter.connect, symbols, log), "DSi profile allowed")
domains["Main RAM"] = 0x400000
system = "GBA"
assert(not pcall(adapter.connect, symbols, log), "wrong platform allowed")
system = "NDS"; version = "2.10"
assert(not pcall(adapter.connect, symbols, log), "unsupported version allowed")
assert(writes == 1)
print("PASS: BizHawk domain enumeration, address mapping, write ownership, ROM binding and compatibility refusals")
