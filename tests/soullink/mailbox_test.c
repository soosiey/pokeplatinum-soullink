// The production C code runs against a simulated CPU cache and physical RAM.
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../../src/soul_link.c"

static SoulLinkMailbox ram;
static unsigned int flushes;
static BOOL initializing;
static BOOL payloadPublished;

void DC_FlushRange(const void *address, u32 size)
{
    size_t offset = (const char *)address - (const char *)&gSoulLinkMailbox;
    assert(offset % 32 == 0 && size % 32 == 0 && offset + size <= 128);
    assert(initializing || (offset < 64 && offset + size <= 64));
    if (offset == 32) {
        if (gSoulLinkMailbox.outgoing.message.sequence != ram.outgoing.message.sequence) {
            assert(payloadPublished); // Payload was flushed before sequence.
            payloadPublished = FALSE;
        } else {
            payloadPublished = TRUE;
        }
    }
    memcpy((char *)&ram + offset, address, size);
    flushes++;
}

void DC_InvalidateRange(void *address, u32 size)
{
    size_t offset = (char *)address - (char *)&gSoulLinkMailbox;
    assert((offset == 64 || offset == 96) && size == 32);
    memcpy(address, (char *)&ram + offset, size);
}

static void Reset(void)
{
    initializing = TRUE;
    SoulLink_Init();
    initializing = FALSE;
    payloadPublished = FALSE;
    assert(ram.rom.magic == SOUL_LINK_MAILBOX_MAGIC);
    assert(ram.rom.protocolVersion == SOUL_LINK_PROTOCOL_VERSION);
    assert(ram.rom.size == 128);
    assert((uintptr_t)&gSoulLinkMailbox % 32 == 0);
}

static void WritePing(u32 sequence, u32 token, u16 type)
{
    memset(&ram.incoming, 0, sizeof(ram.incoming));
    ram.incoming.message.sequence = sequence;
    ram.incoming.message.personality = token;
    ram.incoming.message.type = type;
    ram.incoming.checksum = SoulLink_MessageChecksum(&ram.incoming.message);
}

int main(void)
{
    SoulLinkSlot unconsumed;
    unsigned int previous;
    Reset();
    SoulLink_Update();
    assert(ram.outgoing.message.sequence == 1 && ram.outgoing.message.flags == 0);
    unconsumed = ram.outgoing;
    for (int i = 0; i < 1000; i++) SoulLink_Update();
    assert(memcmp(&unconsumed, &ram.outgoing, sizeof(unconsumed)) == 0);
    assert(ram.rom.heartbeat == 1001); // Disconnect never stalls the main loop.

    WritePing(1, 0xDEADBEEF, SOUL_LINK_EVENT_PING);
    SoulLink_Update();
    assert(ram.rom.incomingAck == 0 && ram.rom.accepted == 0); // Backpressure.
    ram.host.outgoingAck = 1;
    SoulLink_Update();
    assert(ram.rom.incomingAck == 1 && ram.rom.accepted == 1);
    assert(ram.outgoing.message.sequence == 2 && ram.outgoing.message.flags == 1);
    assert(ram.outgoing.message.personality == 0xDEADBEEF);
    assert(ram.outgoing.checksum == SoulLink_MessageChecksum(&ram.outgoing.message));
    SoulLink_Update();
    assert(ram.rom.accepted == 1); // Duplicate sequence is not applied twice.

    ram.host.outgoingAck = 2;
    WritePing(2, 1234, SOUL_LINK_EVENT_PING);
    ram.incoming.message.sequence = 1; // Payload written, sequence not committed.
    SoulLink_Update();
    assert(ram.rom.accepted == 1);
    ram.incoming.message.sequence = 2;
    ram.incoming.checksum ^= 1; // Torn or malformed message remains unacknowledged.
    SoulLink_Update();
    assert(ram.rom.incomingAck == 1);
    ram.incoming.checksum ^= 1;
    SoulLink_Update();
    assert(ram.rom.incomingAck == 2 && ram.rom.accepted == 2);

    WritePing(4, 9999, SOUL_LINK_EVENT_PING); // Out of order.
    SoulLink_Update();
    assert(ram.rom.incomingAck == 2);
    WritePing(1, 9999, SOUL_LINK_EVENT_PING); // Older duplicate.
    SoulLink_Update();
    assert(ram.rom.accepted == 2);
    WritePing(3, 9999, 65535); // Valid envelope, unsupported event.
    SoulLink_Update();
    assert(ram.rom.incomingAck == 3 && ram.rom.rejected == 1);
    SoulLink_Update();
    assert(ram.rom.rejected == 1);

    gSoulLinkMailbox.rom.protocolVersion++;
    previous = flushes;
    SoulLink_Update();
    assert(previous == flushes); // Damaged ABI fails closed.

    Reset();
    // Force rollover internally; zero is always reserved for an empty slot.
    sIncomingSequence = 0xFFFFFFFF;
    sOutgoingSequence = 0xFFFFFFFF;
    ram.rom.incomingAck = 0xFFFFFFFF;
    ram.host.outgoingAck = 0xFFFFFFFF;
    WritePing(1, 42, SOUL_LINK_EVENT_PING);
    SoulLink_Update();
    assert(ram.rom.incomingAck == 1 && ram.outgoing.message.sequence == 1);
    assert(ram.rom.accepted == 1);
    puts("PASS: mailbox cache ownership, publication order, backpressure, torn writes, duplicates, rejection, reset, rollover");
    return 0;
}
