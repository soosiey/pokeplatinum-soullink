#!/usr/bin/env bash
# Local, unprivileged Ubuntu x86_64 build. See docs/soullink-build.txt.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$repo"
action=${1:-build}
case "$action" in
    build|check|setup|clean) ;;
    *) printf 'Usage: ./build-modern.sh [setup|build|check|clean]\n' >&2; exit 2 ;;
esac
# Cleaning needs neither downloads nor the compiler; keep the configured build.
if [[ "$action" == clean ]]; then
    # Remove only generated bundle files, preserving player config and saves.
    rm -f -- .build/client/pokeplatinum.us.nds .build/client/soullink.lua
    rm -f -- .build/client/soullink_bridge.py
    if [[ ! -f .build/rom/build.ninja ]]; then
        printf 'Nothing to clean.\n'
        exit 0
    fi
    ninja_bin="$repo/.build/deps/usr/bin/ninja"
    if [[ ! -x "$ninja_bin" ]]; then
        ninja_bin=$(command -v ninja) || {
            printf 'Ninja is required to clean this build.\n' >&2
            exit 1
        }
    fi
    "$ninja_bin" -C .build/rom -t clean
    rm -f -- .build/rom/soullink-symbols.lua
    exit 0
fi
if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
    printf 'This local bootstrap supports Linux x86_64. Use INSTALL.md on other platforms.\n' >&2
    exit 1
fi
for dependency in gcc g++ make git python3 dpkg-deb wget sha256sum arm-none-eabi-gcc pkg-config; do
    command -v "$dependency" >/dev/null || { printf 'Missing system prerequisite: %s\n' "$dependency" >&2; exit 1; }
done
pkg-config --exists libpng
local_root="$repo/.build"
deps="$local_root/deps"
mkdir -p "$local_root/downloads" "$deps"
while read -r checksum package; do
    [[ -z "$checksum" || "$checksum" == \#* ]] && continue
    archive="$local_root/downloads/${package##*/}"
    if [[ ! -f "$archive" ]]; then
        wget -q --show-progress -O "$archive.part" "https://archive.ubuntu.com/ubuntu/$package"
        mv "$archive.part" "$archive"
    fi
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status
    dpkg-deb -x "$archive" "$deps"
done < tools/devtools/local-deps.lock
export PATH="$deps/usr/bin:$PATH"
export BISON_PKGDATADIR="$deps/usr/share/bison"
export M4="$deps/usr/bin/m4"
make meson skrew
# The compiler and its subprocesses need the same locally extracted ELF loader.
for binary in tools/metroskrew/bin/*; do
    [[ -f "$binary" && ! -L "$binary" ]] || continue
    if "$deps/usr/bin/patchelf" --print-interpreter "$binary" >/dev/null 2>&1; then
        "$deps/usr/bin/patchelf" --set-interpreter "$deps/lib32/ld-linux.so.2" \
            --set-rpath "$deps/lib32" "$binary"
    fi
done
tools/metroskrew/bin/mwccarm -wrap:sdk 2.0/sp2p2 --version
meson=subprojects/meson-1.12.0/meson.py
if [[ ! -f .build/rom/build.ninja ]]; then
    "$meson" setup --native-file=meson/native.ini --cross-file=meson/cross_unix.ini \
        --wrap-mode=nopromote -Drevision=1 -Dgdb_debugging=false -Dlogging_enabled=false \
        -Dbuild.c_args=-Wno-error=conversion -Dbuild.cpp_args=-Wno-error=conversion \
        .build/rom
fi
[[ "$action" == setup ]] && exit 0
ninja -C .build/rom -j "${SOULLINK_BUILD_JOBS:-$(nproc)}" pokeplatinum.us.nds
python3 tools/soullink/package_client.py .build/rom .build/client
if [[ "$action" == check ]]; then
    bash tools/soullink/test.sh
    # ARM9 changed intentionally. Assets and ARM7 must still match vanilla.
    "$meson" test -C .build/rom --no-rebuild --print-errorlogs \
        'Filesystem Checksums' 'SBIN Checksums - ARM7'
    sha1sum .build/rom/pokeplatinum.us.nds
    stat -c 'ROM size: %s bytes' .build/rom/pokeplatinum.us.nds
fi
