-- BizHawk 2.11.1 / melonDS adapter. Keep emulator APIs out of mailbox.lua.
local M = {}

function M.connect(symbols, log)
    assert(emu and memory and gameinfo and client, "Run this script in BizHawk's Lua Console")
    assert(client.getversion() == "2.11.1", "This adapter requires BizHawk 2.11.1")
    assert(emu.getsystemid() == "NDS", "Load the Nintendo DS ROM first")
    local domains = {}
    log("BizHawk " .. client.getversion() .. " NDS memory domains:")
    -- BizHawk returns a zero-indexed table; ipairs would miss its first entry.
    for _, name in pairs(memory.getmemorydomainlist()) do
        domains[name] = memory.getmemorydomainsize(name)
        log(string.format("  %s: 0x%X bytes", name, domains[name]))
    end
    -- Verify the melonDS domain profile, not just a similarly named RAM region.
    -- The Lua API returns uint32 sizes; 4-GiB bus domains report zero.
    assert(domains["Main RAM"] == 0x400000 and domains["ARM9 System Bus"] ~= nil
        and domains["ARM7 System Bus"] ~= nil,
        "Unsupported DS core/domain layout; select melonDS in DS mode")
    local function validate_game()
        assert(emu.getsystemid() == "NDS", "DS ROM was closed or replaced; stopping")
        local hash = gameinfo.getromhash():lower():gsub("^sha1:", "")
        assert(hash == symbols.rom_sha1, "ROM/symbol mismatch; rebuild and load the matching ROM")
    end
    validate_game()
    assert(symbols.version == 0x0102 and symbols.size == 128,
        "Unsupported symbol manifest ABI")
    local address = symbols.mailbox
    assert(type(address) == "number" and address % 32 == 0
        and address >= 0x02000000 and address + symbols.size <= 0x02400000,
        "Invalid mailbox address")
    local base = address - 0x02000000
    log(string.format("melonDS Main RAM: mailbox 0x%08X -> offset 0x%X", address, base))

    local function bounds(offset, size)
        assert(offset >= 0 and offset + size <= symbols.size and offset % size == 0,
            "Mailbox access out of bounds or unaligned")
        return base + offset
    end
    local function writable(offset, size)
        assert((offset >= 64 and offset + size <= 96) or (offset == 96 and size == 4),
            "Lua may only write the incoming slot and outgoing acknowledgement")
        return bounds(offset, size)
    end
    return {
        validate_game = validate_game,
        read16 = function(o) return memory.read_u16_le(bounds(o, 2), "Main RAM") end,
        read32 = function(o) return memory.read_u32_le(bounds(o, 4), "Main RAM") end,
        write16 = function(o, v) memory.write_u16_le(writable(o, 2), v, "Main RAM") end,
        write32 = function(o, v) memory.write_u32_le(writable(o, 4), v, "Main RAM") end,
    }
end

return M
