#!/usr/bin/env python3
"""Copy the built bundle to /tmp/soullink-plat/{host,client}, without rebuilding.

Existing destination configs retain their settings except for role. New configs
inherit .build/client/soullink-config.lua. Saves and other local files are left
alone. For remote play, set the client's host IP and EmuHawk launch flags.
ROM filenames include the role to keep filename-based emulator saves separate.
"""

import re
import shutil
from pathlib import Path


ARTIFACTS = ("pokeplatinum.us.nds", "soullink.lua", "soullink_bridge.py")
CONFIG = "soullink-config.lua"
ROLE = re.compile(r"^(\s*role\s*=\s*)([\"'])(host|client)\2", re.MULTILINE)


def output_name(name, role):
    return f"pokeplatinum-{role}.nds" if name == "pokeplatinum.us.nds" else name


def copy_bundle(source, destination):
    for name in (*ARTIFACTS, CONFIG):
        if not (source / name).is_file():
            raise ValueError(f"Missing {source / name}; run ./build-modern.sh first")

    # Validate both configs and destinations before replacing any files.
    configs = {}
    for role in ("host", "client"):
        folder = destination / role
        for path in (destination, folder,
                     *(folder / output_name(n, role) for n in (*ARTIFACTS, CONFIG))):
            if path.is_symlink():
                raise ValueError(f"Refusing symlink destination: {path}")
        config = folder / CONFIG
        original = config if config.exists() else source / CONFIG
        content, count = ROLE.subn(lambda m: f'{m[1]}"{role}"', original.read_text())
        if count != 1:
            raise ValueError(f"Expected exactly one role assignment in {original}")
        configs[role] = content

    for role, content in configs.items():
        folder = destination / role
        folder.mkdir(parents=True, exist_ok=True)
        for name in ARTIFACTS:
            shutil.copyfile(source / name, folder / output_name(name, role))
        (folder / CONFIG).write_text(content)
        print(f"Copied {role} bundle: {folder}")


if __name__ == "__main__":
    repo = Path(__file__).resolve().parent
    try:
        copy_bundle(repo / ".build/client", Path("/tmp/soullink-plat"))
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
