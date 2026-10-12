-- Exercise the actual frame loop, including a reply visible one frame before ack.
local M = dofile(arg[4] or "tools/soullink/mailbox.lua")
local ram, frame, dueAck, replySequence, loggedPass = {}, 0, nil, 0, false
local function put(o, v, n)
    for i = 0, n - 1 do ram[o + i] = (v >> (8 * i)) & 255 end
end
local function get(o, n)
    local v = 0
    for i = 0, n - 1 do v = v | ((ram[o + i] or 0) << (8 * i)) end
    return v
end
local io = {
    validate_game = function() end,
    read16 = function(o) return get(o, 2) end,
    read32 = function(o) return get(o, 4) end,
    write16 = function(o, v) assert(o >= 64 and o < 96); put(o, v, 2) end,
    write32 = function(o, v) assert(o >= 64 and o <= 96); put(o, v, 4) end,
}
local function publish(token, flags)
    local seq = M.next_sequence(get(32, 4))
    put(36, token, 4); put(40, 0, 4)
    put(44, 1, 2); put(46, 0, 2); put(48, 0, 2); put(50, 0, 2)
    put(52, flags, 2); put(54, 0, 2)
    local message = { sequence = seq, personality = token, otId = 0, type = 1,
        pairId = 0, species = 0, location = 0, flags = flags, reserved = 0 }
    put(56, M.checksum(message), 4); put(32, seq, 4)
end
local env = setmetatable({
    dofile = function(path)
        assert(not arg[1], "Portable script attempted to load an external module: " .. path)
        if path:match("mailbox.lua$") then return M end
        if path:match("bizhawk.lua$") then return { connect = function() return io end } end
        if path:match("network.lua$") then return dofile(path) end
        if path:match("soullink%-symbols.lua$") then return {} end
        error("Unexpected file: " .. path)
    end,
    console = { log = function(text)
        if text:find("PASS:", 1, true) then loggedPass = true end
    end },
    emu = { frameadvance = function()
        frame = frame + 1
        if frame == 3 then
            put(0, M.magic, 4); put(4, M.version, 2); put(6, M.size, 2)
            publish(1, 0)
        end
        put(8, frame, 4)
        if dueAck and frame >= dueAck then
            put(12, replySequence, 4); dueAck = nil
        end
        if frame >= 3 and not dueAck and get(64, 4) ~= get(12, 4)
            and get(32, 4) == get(96, 4) then
            local ping = assert(M.read_message(io, 64))
            publish(ping.personality, 1)
            replySequence, dueAck = ping.sequence, frame + 1
        end
        if frame >= 800 then error("TEST_END") end
    end },
}, { __index = _G })
if arg[1] then
    local base = tonumber(arg[3]) - 0x02000000
    env.client = { getversion = function() return "2.11.1" end }
    env.gameinfo = { getromhash = function() return arg[2] end }
    env.emu.getsystemid = function() return "NDS" end
    env.memory = {
        getmemorydomainlist = function()
            return { [0] = "Main RAM", "ARM9 System Bus", "ARM7 System Bus" }
        end,
        getmemorydomainsize = function(d) return d == "Main RAM" and 0x400000 or 0 end,
        read_u16_le = function(o) return io.read16(o - base) end,
        read_u32_le = function(o) return io.read32(o - base) end,
        write_u16_le = function(o, v) io.write16(o - base, v) end,
        write_u32_le = function(o, v) io.write32(o - base, v) end,
    }
end
local ok, err = pcall(assert(loadfile(arg[1] or "soullink.lua", "t", env)))
assert(not ok and tostring(err):find("TEST_END", 1, true), tostring(err))
assert(loggedPass, "Frame loop never completed its acceptance check")
print("PASS: Lua frame loop, initialization wait, ROM PING and delayed incoming acknowledgement")
