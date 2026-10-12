#include "nitro/types.h"
#define ATTRIBUTE_ALIGN(n) __attribute__((aligned(n)))
void DC_FlushRange(const void *address, u32 size);
void DC_InvalidateRange(void *address, u32 size);
