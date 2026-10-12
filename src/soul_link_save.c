#include "soul_link_save.h"

#include <stddef.h>
#include <string.h>

#include "soul_link.h"

typedef char SoulLinkSaveSizeCheck[sizeof(SoulLinkSave) == 32 ? 1 : -1];
typedef char SoulLinkSaveRunOffsetCheck[offsetof(SoulLinkSave, runIdLow) == 8 ? 1 : -1];
typedef char SoulLinkSaveSlotOffsetCheck[offsetof(SoulLinkSave, playerSlot) == 22 ? 1 : -1];

int SoulLinkSave_Size(void)
{
    return sizeof(SoulLinkSave);
}

void SoulLinkSave_Init(SoulLinkSave *save)
{
    memset(save, 0, sizeof(*save));
    save->magic = SOUL_LINK_SAVE_MAGIC;
    save->version = SOUL_LINK_SAVE_VERSION;
    save->protocol = SOUL_LINK_PROTOCOL_VERSION;
}

static BOOL ValidRoster(u8 slot, u8 mask)
{
    return slot >= 1 && slot <= 4 && mask <= 15 && (mask & 1)
        && (mask & (1 << (slot - 1)));
}

BOOL SoulLinkSave_IsValid(const SoulLinkSave *save)
{
    unsigned int i;
    if (save->magic != SOUL_LINK_SAVE_MAGIC || save->version != SOUL_LINK_SAVE_VERSION
        || save->protocol != SOUL_LINK_PROTOCOL_VERSION) {
        return FALSE;
    }
    for (i = 0; i < sizeof(save->reserved); i++) {
        if (save->reserved[i] != 0) {
            return FALSE;
        }
    }
    if (save->status == SOUL_LINK_RUN_EMPTY) {
        return save->runIdLow == 0 && save->runIdHigh == 0 && save->settings == 0
            && save->playerSlot == 0 && save->activePlayerMask == 0 && save->nextGroupId == 0;
    }
    return (save->status == SOUL_LINK_RUN_ACTIVE || save->status == SOUL_LINK_RUN_COMPLETE)
        && (save->runIdLow != 0 || save->runIdHigh != 0)
        && ValidRoster(save->playerSlot, save->activePlayerMask)
        && save->nextGroupId != 0;
}

BOOL SoulLinkSave_IsLinked(const SoulLinkSave *save)
{
    return SoulLinkSave_IsValid(save) && save->status != SOUL_LINK_RUN_EMPTY;
}

BOOL SoulLinkSave_Matches(const SoulLinkSave *save, u32 low, u32 high, u32 settings, u8 slot, u8 mask)
{
    return SoulLinkSave_IsLinked(save) && save->runIdLow == low && save->runIdHigh == high
        && save->settings == settings && save->playerSlot == slot && save->activePlayerMask == mask;
}

BOOL SoulLinkSave_Assign(SoulLinkSave *save, u32 low, u32 high, u32 settings, u8 slot, u8 mask)
{
    if (!SoulLinkSave_IsValid(save) || (low == 0 && high == 0) || !ValidRoster(slot, mask)) {
        return FALSE;
    }
    if (save->status != SOUL_LINK_RUN_EMPTY) {
        // Duplicate approval is harmless; an unrelated run must never replace a save.
        return SoulLinkSave_Matches(save, low, high, settings, slot, mask);
    }
    save->runIdLow = low;
    save->runIdHigh = high;
    save->settings = settings;
    save->playerSlot = slot;
    save->activePlayerMask = mask;
    save->nextGroupId = 1;
    save->status = SOUL_LINK_RUN_ACTIVE;
    return TRUE;
}
