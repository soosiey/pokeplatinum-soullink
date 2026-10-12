#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "soul_link_gate.h"

static SoulLinkMessage published;
static BOOL writable;
BOOL SoulLink_Publish(SoulLinkMessage *message)
{
    if (!writable) return FALSE;
    published = *message;
    return TRUE;
}

int main(void)
{
    SoulLinkSave save, original;
    SoulLinkMessage grant = { 0 };
    SoulLinkGate_Reset();
    SoulLinkSave_Init(&save);
    original = save;
    SoulLinkGate_Begin(&save, TRUE, 11, 22);
    assert(SoulLinkGate_Status() == SOUL_LINK_GATE_WAITING);
    SoulLinkGate_Tick();
    assert(published.type == 0); // Busy outgoing slot does not drop intent.
    writable = TRUE;
    SoulLinkGate_Tick();
    assert(published.type == 2 && published.flags == 1 && published.personality == 11);
    grant.type = 3;
    grant.reserved = published.reserved;
    grant.flags = SOUL_LINK_GATE_READY;
    assert(SoulLinkGate_Receive(&grant));
    SoulLinkGate_Start();
    SoulLinkGate_Tick();
    assert(published.flags == 0x101);
    assert(memcmp(&save, &original, sizeof(save)) == 0);
    grant.flags = SOUL_LINK_GATE_APPROVED;
    grant.personality = 11;
    grant.otId = 22;
    grant.location = 0x32;
    grant.reserved++;
    assert(!SoulLinkGate_Receive(&grant)); // Stale/cross-request approval.
    grant.reserved--;
    assert(SoulLinkGate_Receive(&grant));
    assert(SoulLinkGate_Apply());
    assert(SoulLinkSave_Matches(&save, 11, 22, 0, 2, 3));
    assert(SoulLinkGate_Apply());
    grant.location = 0x71;
    assert(!SoulLinkGate_Receive(&grant)); // Approved roster is immutable.
    SoulLinkGate_End();
    assert(!SoulLinkGate_Apply());
    SoulLinkGate_Begin(&save, FALSE, 0, 0);
    SoulLinkGate_Tick();
    assert(published.flags == 2 && published.location == 0x132);
    grant.reserved = published.reserved;
    assert(!SoulLinkGate_Receive(&grant)); // Wrong saved slot/mask.
    grant.location = 0x32;
    grant.personality++;
    assert(!SoulLinkGate_Receive(&grant));
    grant.personality--;
    assert(SoulLinkGate_Receive(&grant) && SoulLinkGate_Apply());
    SoulLinkSave_Init(&save);
    SoulLinkGate_Begin(&save, FALSE, 0, 0);
    assert(SoulLinkGate_Status() == SOUL_LINK_GATE_REJECTED);
    assert(!SoulLinkGate_Apply());
    SoulLinkSave_Init(&save);
    original = save;
    SoulLinkGate_Begin(&save, TRUE, 11, 22);
    SoulLinkGate_Tick();
    grant.reserved = published.reserved;
    SoulLinkGate_Cancel();
    assert(!SoulLinkGate_Receive(&grant));
    assert(!SoulLinkGate_Apply());
    writable = FALSE;
    SoulLinkGate_Tick();
    assert(published.flags == 1);
    writable = TRUE;
    SoulLinkGate_Tick();
    assert(published.type == 2 && published.flags == 0 && published.reserved == grant.reserved);
    assert(memcmp(&save, &original, sizeof(save)) == 0);
    SoulLinkGate_Begin(&save, TRUE, 33, 44);
    SoulLinkGate_Tick();
    assert(published.reserved != grant.reserved);
    assert(!SoulLinkGate_Receive(&grant));
    puts("PASS: native startup gate, backpressure, request binding, immutable identity and Continue validation");
    return 0;
}
