#!/usr/bin/env python3
"""Package a built ROM and standalone Lua client; no toolchain ships to players."""

import argparse
import shutil
from pathlib import Path

from export_symbols import export

REPO = Path(__file__).resolve().parents[2]


def package(build_dir, output):
    build_dir, output = build_dir.resolve(), output.resolve()
    if output in (REPO, build_dir):
        raise ValueError("bundle directory must differ from the source and build directories")
    symbols = export(build_dir).read_text(encoding="ascii")
    script = (REPO / "soullink.lua").read_text(encoding="utf-8")
    for name, content in {
        "tools/soullink/mailbox.lua": (REPO / "tools/soullink/mailbox.lua").read_text(),
        "tools/soullink/bizhawk.lua": (REPO / "tools/soullink/bizhawk.lua").read_text(),
        "tools/soullink/network.lua": (REPO / "tools/soullink/network.lua").read_text(),
        "tools/soullink/lobby.lua": (REPO / "tools/soullink/lobby.lua").read_text(),
        ".build/rom/soullink-symbols.lua": symbols,
    }.items():
        loader = f'dofile(root .. "{name}")'
        if script.count(loader) != 1:
            raise ValueError(f"expected exactly one loader for {name}")
        script = script.replace(loader, "(function()\n" + content + "\nend)()")
    output.mkdir(parents=True, exist_ok=True)
    # Replace only generated artifacts; never overwrite a player's config/save.
    rom = output / "pokeplatinum.us.nds"
    temporary_rom = rom.with_suffix(".nds.tmp")
    shutil.copyfile(build_dir / rom.name, temporary_rom)
    temporary_rom.replace(rom)
    lua = output / "soullink.lua"
    temporary_lua = lua.with_suffix(".lua.tmp")
    temporary_lua.write_text("-- Generated portable client; edit repository sources instead.\n" + script,
                             encoding="utf-8")
    temporary_lua.replace(lua)
    bridge = output / "soullink_bridge.py"
    temporary_bridge = bridge.with_suffix(".py.tmp")
    shutil.copyfile(REPO / bridge.name, temporary_bridge)
    temporary_bridge.replace(bridge)
    config = output / "soullink-config.lua"
    if not config.exists():
        shutil.copyfile(REPO / "soullink-config.example.lua", config)
    print(f"Portable bundle: {output} (Stage 4 lobby and startup gates)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.build_dir, args.output)


if __name__ == "__main__":
    main()
