#ifndef POKEPLATINUM_SOUL_LINK_SAVE_H
#define POKEPLATINUM_SOUL_LINK_SAVE_H

#include <nitro/types.h>

#define SOUL_LINK_SAVE_MAGIC 0x534C5054
#define SOUL_LINK_SAVE_VERSION 1
#define SOUL_LINK_RUN_EMPTY 0
#define SOUL_LINK_RUN_ACTIVE 1
#define SOUL_LINK_RUN_COMPLETE 2

// Native normal-save entry: protected by Platinum's mirrored block checksum.
// Never serialize this struct onto the network or hash its raw representation.
typedef struct SoulLinkSave {
    u32 magic;
    u16 version;
    u16 protocol;
    u32 runIdLow;
    u32 runIdHigh;
    u32 settings;
    u16 nextGroupId;
    u8 playerSlot; // Persistent 1-4, never a relay connection ID.
    u8 activePlayerMask;
    u8 status;
    u8 reserved[7];
} SoulLinkSave;

int SoulLinkSave_Size(void);
void SoulLinkSave_Init(SoulLinkSave *save);
BOOL SoulLinkSave_IsValid(const SoulLinkSave *save);
BOOL SoulLinkSave_IsLinked(const SoulLinkSave *save);
BOOL SoulLinkSave_Assign(SoulLinkSave *save, u32 low, u32 high, u32 settings, u8 slot, u8 mask);
BOOL SoulLinkSave_Matches(const SoulLinkSave *save, u32 low, u32 high, u32 settings, u8 slot, u8 mask);

#endif
