#include "soul_link_gate.h"

#include <string.h>

static SoulLinkSave *sSave;
static SoulLinkMessage sIntent, sApproval;
static u16 sNonce, sStatus;
static u32 sTicks;
static SoulLinkMessage sCancel;
static BOOL sCancelPending;

void SoulLinkGate_Reset(void)
{
    sSave = NULL;
    sNonce = 0;
    sStatus = 0;
    sCancelPending = FALSE;
}

void SoulLinkGate_Begin(SoulLinkSave *save, BOOL newGame, u32 low, u32 high)
{
    sSave = save;
    sTicks = 0;
    sNonce++;
    if (sNonce == 0) sNonce = 1;
    memset(&sIntent, 0, sizeof(sIntent));
    memset(&sApproval, 0, sizeof(sApproval));
    sIntent.type = SOUL_LINK_EVENT_INTENT;
    sIntent.flags = newGame ? 1 : 2;
    sIntent.reserved = sNonce;
    sIntent.personality = newGame ? low : save->runIdLow;
    sIntent.otId = newGame ? high : save->runIdHigh;
    sIntent.pairId = save->settings & 0xFFFF;
    sIntent.species = save->settings >> 16;
    sIntent.location = save->playerSlot | (save->activePlayerMask << 4) | (save->status << 8);
    sStatus = SOUL_LINK_GATE_WAITING;
    if (!SoulLinkSave_IsValid(save) || (newGame && save->status != SOUL_LINK_RUN_EMPTY)
        || (!newGame && !SoulLinkSave_IsLinked(save))) {
        sStatus = SOUL_LINK_GATE_REJECTED;
    }
}

void SoulLinkGate_Tick(void)
{
    if (sCancelPending) {
        if (SoulLink_Publish(&sCancel)) sCancelPending = FALSE;
        return;
    }
    if (sSave == NULL || sStatus == SOUL_LINK_GATE_REJECTED || sStatus == SOUL_LINK_GATE_APPROVED) return;
    // Refresh after Lua reload or reconnect; never overwrite a pending message.
    if (sTicks == 0 && SoulLink_Publish(&sIntent)) sTicks = 60;
    if (sTicks != 0) sTicks--;
}

void SoulLinkGate_Start(void)
{
    if (sSave != NULL && sStatus == SOUL_LINK_GATE_READY) {
        sIntent.flags |= 0x100;
        sTicks = 0;
    }
}

BOOL SoulLinkGate_Receive(const SoulLinkMessage *message)
{
    u8 slot = message->location & 15;
    u8 mask = (message->location >> 4) & 15;
    u32 settings = message->pairId | ((u32)message->species << 16);
    if (sSave == NULL || message->reserved != sNonce || message->location > 255
        || message->flags < SOUL_LINK_GATE_WAITING || message->flags > SOUL_LINK_GATE_REJECTED) return FALSE;
    if (sStatus == SOUL_LINK_GATE_APPROVED) {
        return message->flags == sApproval.flags && message->personality == sApproval.personality
            && message->otId == sApproval.otId && message->location == sApproval.location
            && message->pairId == sApproval.pairId && message->species == sApproval.species;
    }
    if (message->flags == SOUL_LINK_GATE_APPROVED) {
        SoulLinkSave candidate = *sSave;
        if ((sIntent.flags & 255) == 2) {
            if (!SoulLinkSave_Matches(sSave, message->personality, message->otId, settings, slot, mask)) return FALSE;
        } else if (!SoulLinkSave_Assign(&candidate, message->personality, message->otId, settings, slot, mask)) {
            return FALSE;
        }
        sApproval = *message;
    } else if (message->personality || message->otId || settings || message->location) {
        return FALSE;
    }
    sStatus = message->flags;
    if (sStatus == SOUL_LINK_GATE_WAITING || sStatus == SOUL_LINK_GATE_REJECTED) {
        sIntent.flags &= 255;
    }
    return TRUE;
}

u16 SoulLinkGate_Status(void)
{
    return sStatus;
}

BOOL SoulLinkGate_Apply(void)
{
    if (sSave == NULL || sStatus != SOUL_LINK_GATE_APPROVED) return FALSE;
    return SoulLinkSave_Assign(sSave, sApproval.personality, sApproval.otId,
        sApproval.pairId | ((u32)sApproval.species << 16),
        sApproval.location & 15, (sApproval.location >> 4) & 15);
}

void SoulLinkGate_End(void)
{
    sSave = NULL;
}

void SoulLinkGate_Cancel(void)
{
    memset(&sCancel, 0, sizeof(sCancel));
    sCancel.type = SOUL_LINK_EVENT_INTENT;
    sCancel.reserved = sNonce;
    sCancelPending = TRUE;
    SoulLinkGate_End();
}
