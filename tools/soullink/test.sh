#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo"
mkdir -p .build/tests
gcc -std=c99 -Wall -Wextra -Werror -fsanitize=undefined \
    -Itests/soullink/stubs -Iinclude tests/soullink/mailbox_test.c \
    -o .build/tests/mailbox_test
.build/tests/mailbox_test
gcc -std=c99 -Wall -Wextra -Werror -fsanitize=undefined \
    -Itests/soullink/stubs -Iinclude tests/soullink/save_test.c src/soul_link_save.c \
    -o .build/tests/save_test
.build/tests/save_test
lua_bin=${SOULLINK_LUA:-}
if [[ -z "$lua_bin" ]]; then
    for candidate in "$repo/.build/deps/usr/bin/lua5.3" lua5.4 lua5.3 lua; do
        if command -v "$candidate" >/dev/null; then lua_bin=$candidate; break; fi
    done
fi
if [[ -z "$lua_bin" ]]; then
    printf 'Lua 5.3+ is required for adapter tests (or set SOULLINK_LUA).\n' >&2
    exit 1
fi
"$lua_bin" tests/soullink/mailbox_test.lua
"$lua_bin" tests/soullink/adapter_test.lua
"$lua_bin" tests/soullink/network_test.lua
"$lua_bin" tests/soullink/loop_test.lua
SOULLINK_LUA="$lua_bin" python3 -m unittest discover -s tests/soullink -p 'test_*.py'
