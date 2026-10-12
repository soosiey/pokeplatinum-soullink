#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "soul_link_save.h"

int main(void)
{
    SoulLinkSave save, snapshot, restored;
    unsigned char serialized[32];
    assert(SoulLinkSave_Size() == sizeof(serialized));
    SoulLinkSave_Init(&save);
    assert(SoulLinkSave_IsValid(&save) && !SoulLinkSave_IsLinked(&save));
    snapshot = save;
    assert(!SoulLinkSave_Assign(&save, 0, 0, 42, 1, 3));
    assert(!SoulLinkSave_Assign(&save, 1, 2, 42, 0, 3));
    assert(!SoulLinkSave_Assign(&save, 1, 2, 42, 5, 3));
    assert(!SoulLinkSave_Assign(&save, 1, 2, 42, 2, 1));
    assert(!SoulLinkSave_Assign(&save, 1, 2, 42, 2, 2));
    assert(!SoulLinkSave_Assign(&save, 1, 2, 42, 1, 17));
    assert(memcmp(&save, &snapshot, sizeof(save)) == 0);
    assert(SoulLinkSave_Assign(&save, 1, 2, 42, 2, 3));
    assert(SoulLinkSave_IsLinked(&save));
    snapshot = save;
    assert(SoulLinkSave_Assign(&save, 1, 2, 42, 2, 3));
    assert(!SoulLinkSave_Assign(&save, 2, 2, 42, 2, 3));
    assert(!SoulLinkSave_Assign(&save, 1, 3, 42, 2, 3));
    assert(!SoulLinkSave_Assign(&save, 1, 2, 43, 2, 3));
    assert(!SoulLinkSave_Assign(&save, 1, 2, 42, 1, 3));
    assert(!SoulLinkSave_Assign(&save, 1, 2, 42, 2, 7));
    assert(memcmp(&save, &snapshot, sizeof(save)) == 0);
    memcpy(serialized, &save, sizeof(save));
    memset(&restored, 0, sizeof(restored));
    memcpy(&restored, serialized, sizeof(restored));
    assert(SoulLinkSave_Matches(&restored, 1, 2, 42, 2, 3));
    restored.version++;
    assert(!SoulLinkSave_IsValid(&restored));
    restored = save;
    restored.protocol++;
    assert(!SoulLinkSave_IsValid(&restored));
    restored = save;
    restored.reserved[0] = 1;
    assert(!SoulLinkSave_IsValid(&restored));
    restored = save;
    restored.status = SOUL_LINK_RUN_COMPLETE;
    assert(SoulLinkSave_IsLinked(&restored));
    SoulLinkSave_Init(&restored);
    assert(SoulLinkSave_Assign(&restored, 1, 0, 42, 1, 1));
    puts("PASS: save layout, identity, roster, idempotent assignment and byte round trip");
    return 0;
}
