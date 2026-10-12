#ifndef POKEPLATINUM_SOUL_LINK_GATE_H
#define POKEPLATINUM_SOUL_LINK_GATE_H

#include "soul_link.h"
#include "soul_link_save.h"

void SoulLinkGate_Reset(void);
void SoulLinkGate_Begin(SoulLinkSave *save, BOOL newGame, u32 low, u32 high);
void SoulLinkGate_Tick(void);
BOOL SoulLinkGate_Receive(const SoulLinkMessage *message);
void SoulLinkGate_Start(void);
u16 SoulLinkGate_Status(void);
BOOL SoulLinkGate_Apply(void);
void SoulLinkGate_End(void);
void SoulLinkGate_Cancel(void);

#endif
