#include "soul_link.h"

#include <nitro.h>
#include <stddef.h>
#include <string.h>

volatile SoulLinkMailbox gSoulLinkMailbox ATTRIBUTE_ALIGN(32);
static u32 sIncomingSequence;
static u32 sOutgoingSequence;

// Compile these assertions with both the host test compiler and MetroWerks.
typedef char MessageSizeCheck[sizeof(SoulLinkMessage) == 24 ? 1 : -1];
typedef char SlotSizeCheck[sizeof(SoulLinkSlot) == 32 ? 1 : -1];
typedef char MailboxSizeCheck[sizeof(SoulLinkMailbox) == 128 ? 1 : -1];
typedef char OutgoingOffsetCheck[offsetof(SoulLinkMailbox, outgoing) == 32 ? 1 : -1];
typedef char IncomingOffsetCheck[offsetof(SoulLinkMailbox, incoming) == 64 ? 1 : -1];
typedef char HostOffsetCheck[offsetof(SoulLinkMailbox, host) == 96 ? 1 : -1];

static u32 NextSequence(u32 sequence)
{
    sequence++;
    return sequence == 0 ? 1 : sequence;
}

u32 SoulLink_MessageChecksum(const SoulLinkMessage *message)
{
    // Torn-write detection, not authentication. Hash explicit fields, not padding.
    return SOUL_LINK_MAILBOX_MAGIC ^ message->sequence
        ^ message->personality ^ message->otId
        ^ ((u32)message->type | ((u32)message->pairId << 16))
        ^ ((u32)message->species | ((u32)message->location << 16))
        ^ ((u32)message->flags | ((u32)message->reserved << 16));
}

static void CopyPayload(volatile SoulLinkMessage *dest, const SoulLinkMessage *src)
{
    dest->personality = src->personality;
    dest->otId = src->otId;
    dest->type = src->type;
    dest->pairId = src->pairId;
    dest->species = src->species;
    dest->location = src->location;
    dest->flags = src->flags;
    dest->reserved = src->reserved;
}

static BOOL Publish(SoulLinkMessage *message)
{
    if (gSoulLinkMailbox.host.outgoingAck != sOutgoingSequence) {
        return FALSE;
    }

    message->sequence = NextSequence(sOutgoingSequence);
    CopyPayload(&gSoulLinkMailbox.outgoing.message, message);
    gSoulLinkMailbox.outgoing.checksum = SoulLink_MessageChecksum(message);
    DC_FlushRange((const void *)&gSoulLinkMailbox.outgoing, 32);
    // Commit last, after the complete payload has reached physical main RAM.
    gSoulLinkMailbox.outgoing.message.sequence = message->sequence;
    DC_FlushRange((const void *)&gSoulLinkMailbox.outgoing, 32);
    sOutgoingSequence = message->sequence;
    return TRUE;
}

void SoulLink_Init(void)
{
    memset((void *)&gSoulLinkMailbox, 0, sizeof(gSoulLinkMailbox));
    sIncomingSequence = 0;
    sOutgoingSequence = 0;
    gSoulLinkMailbox.rom.protocolVersion = SOUL_LINK_PROTOCOL_VERSION;
    gSoulLinkMailbox.rom.size = sizeof(gSoulLinkMailbox);
    DC_FlushRange((const void *)&gSoulLinkMailbox, sizeof(gSoulLinkMailbox));
    gSoulLinkMailbox.rom.magic = SOUL_LINK_MAILBOX_MAGIC;
    DC_FlushRange((const void *)&gSoulLinkMailbox.rom, 32);
}

void SoulLink_Update(void)
{
    SoulLinkMessage message;
    u32 checksum;

    // Fail closed on a damaged header; do not reset sequence history in flight.
    if (gSoulLinkMailbox.rom.magic != SOUL_LINK_MAILBOX_MAGIC
        || gSoulLinkMailbox.rom.protocolVersion != SOUL_LINK_PROTOCOL_VERSION
        || gSoulLinkMailbox.rom.size != sizeof(gSoulLinkMailbox)) {
        return;
    }

    DC_InvalidateRange((void *)&gSoulLinkMailbox.incoming, 32);
    DC_InvalidateRange((void *)&gSoulLinkMailbox.host, 32);
    gSoulLinkMailbox.rom.heartbeat++;

    message.sequence = gSoulLinkMailbox.incoming.message.sequence;
    if (message.sequence == NextSequence(sIncomingSequence)) {
        message.personality = gSoulLinkMailbox.incoming.message.personality;
        message.otId = gSoulLinkMailbox.incoming.message.otId;
        message.type = gSoulLinkMailbox.incoming.message.type;
        message.pairId = gSoulLinkMailbox.incoming.message.pairId;
        message.species = gSoulLinkMailbox.incoming.message.species;
        message.location = gSoulLinkMailbox.incoming.message.location;
        message.flags = gSoulLinkMailbox.incoming.message.flags;
        message.reserved = gSoulLinkMailbox.incoming.message.reserved;
        checksum = gSoulLinkMailbox.incoming.checksum;

        if (message.sequence == gSoulLinkMailbox.incoming.message.sequence
            && checksum == SoulLink_MessageChecksum(&message)) {
            BOOL consumed = FALSE;
            u32 sequence = message.sequence;

            if (message.type != SOUL_LINK_EVENT_PING || message.flags != 0
                || message.pairId != 0 || message.species != 0
                || message.location != 0 || message.reserved != 0) {
                gSoulLinkMailbox.rom.rejected++;
                consumed = TRUE;
            } else {
                message.flags = SOUL_LINK_PING_REPLY;
                // Hold the incoming PING until its reply can be published.
                // An absent Lua reader must never block the game loop.
                if (Publish(&message)) {
                    gSoulLinkMailbox.rom.accepted++;
                    consumed = TRUE;
                }
            }

            if (consumed) {
                sIncomingSequence = sequence;
                gSoulLinkMailbox.rom.incomingAck = sequence;
            }
        }
    }

    if (gSoulLinkMailbox.rom.heartbeat % 300 == 1) {
        memset(&message, 0, sizeof(message));
        message.type = SOUL_LINK_EVENT_PING;
        message.personality = gSoulLinkMailbox.rom.heartbeat;
        Publish(&message);
    }

    DC_FlushRange((const void *)&gSoulLinkMailbox.rom, 32);
}
