#ifndef POKEPLATINUM_SOUL_LINK_H
#define POKEPLATINUM_SOUL_LINK_H

#include <nitro/types.h>

#define SOUL_LINK_MAILBOX_MAGIC 0x4B4E4C53
// DS lobby ABI 2, deliberately distinct from Emerald protocol 18.
#define SOUL_LINK_PROTOCOL_VERSION 0x0102
#define SOUL_LINK_EVENT_INTENT 2
#define SOUL_LINK_EVENT_GATE 3
#define SOUL_LINK_GATE_WAITING 1
#define SOUL_LINK_GATE_READY 2
#define SOUL_LINK_GATE_APPROVED 3
#define SOUL_LINK_GATE_REJECTED 4
#define SOUL_LINK_EVENT_PING 1
#define SOUL_LINK_PING_REPLY 1

typedef struct SoulLinkMessage {
    u32 sequence;
    u32 personality; // PING token or the low half of a run ID.
    u32 otId;
    u16 type;
    u16 pairId;
    u16 species;
    u16 location;
    u16 flags;
    u16 reserved;
} SoulLinkMessage;

typedef struct SoulLinkSlot {
    SoulLinkMessage message;
    u32 checksum;
    u32 padding;
} SoulLinkSlot;

// Each 32-byte cache line has one writer after initialization. Never flush
// Lua-owned lines from the ROM: doing so can overwrite external RAM writes.
typedef struct SoulLinkMailbox {
    struct {
        u32 magic;
        u16 protocolVersion;
        u16 size;
        u32 heartbeat;
        u32 incomingAck;
        u32 accepted;
        u32 rejected;
        u32 reserved[2];
    } rom;
    SoulLinkSlot outgoing;
    SoulLinkSlot incoming;
    struct {
        u32 outgoingAck;
        u32 reserved[7];
    } host;
} SoulLinkMailbox;

extern volatile SoulLinkMailbox gSoulLinkMailbox;

void SoulLink_Init(void);
void SoulLink_Update(void);
u32 SoulLink_MessageChecksum(const SoulLinkMessage *message);
BOOL SoulLink_Publish(SoulLinkMessage *message);

#endif
