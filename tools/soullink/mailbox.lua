-- Platform-independent DS diagnostic ABI. All offsets are mailbox-relative.
local M = { magic = 0x4B4E4C53, version = 0x0101, size = 128 }
M.outgoing, M.incoming, M.host_ack = 32, 64, 96

function M.next_sequence(sequence)
    return sequence == 0xFFFFFFFF and 1 or sequence + 1
end

function M.checksum(m)
    return (M.magic ~ m.sequence ~ m.personality ~ m.otId
        ~ (m.type | (m.pairId << 16)) ~ (m.species | (m.location << 16))
        ~ (m.flags | (m.reserved << 16))) & 0xFFFFFFFF
end

function M.valid_header(io)
    return io.read32(0) == M.magic and io.read16(4) == M.version
        and io.read16(6) == M.size
end

function M.read_message(io, offset)
    local m = { sequence = io.read32(offset), personality = io.read32(offset + 4),
        otId = io.read32(offset + 8), type = io.read16(offset + 12),
        pairId = io.read16(offset + 14), species = io.read16(offset + 16),
        location = io.read16(offset + 18), flags = io.read16(offset + 20),
        reserved = io.read16(offset + 22) }
    if m.sequence == 0 or m.sequence ~= io.read32(offset)
        or M.checksum(m) ~= io.read32(offset + 24) then
        return nil
    end
    return m
end

function M.send_ping(io, token)
    assert(M.valid_header(io), "Mailbox ABI mismatch; no writes made")
    local offset = M.incoming
    local current = io.read32(offset)
    if current ~= io.read32(12) then return nil end
    local m = { sequence = M.next_sequence(current), personality = token,
        otId = 0, type = 1, pairId = 0, species = 0, location = 0,
        flags = 0, reserved = 0 }
    io.write32(offset + 4, m.personality)
    io.write32(offset + 8, m.otId)
    io.write16(offset + 12, m.type)
    io.write16(offset + 14, 0)
    io.write16(offset + 16, 0)
    io.write16(offset + 18, 0)
    io.write16(offset + 20, 0)
    io.write16(offset + 22, 0)
    io.write32(offset + 24, M.checksum(m))
    io.write32(offset, m.sequence) -- Publish last.
    return m.sequence
end

function M.receive(io)
    assert(M.valid_header(io), "Mailbox ABI mismatch; no writes made")
    local current = io.read32(M.outgoing)
    local ack = io.read32(M.host_ack)
    if current == ack then return nil end
    assert(current == M.next_sequence(ack), "ROM sequence discontinuity; reload Lua after reset")
    local m = M.read_message(io, M.outgoing)
    if not m then return nil end -- Payload has not been committed completely yet.
    assert(m.type == 1 and (m.flags == 0 or m.flags == 1)
        and m.pairId == 0 and m.species == 0 and m.location == 0
        and m.reserved == 0, "Unsupported ROM event; no acknowledgement sent")
    io.write32(M.host_ack, m.sequence)
    return m
end

return M
