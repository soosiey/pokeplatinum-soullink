#!/usr/bin/env python3
"""Export the resident mailbox from a linked ARM ELF/NEF, bound to its ROM."""

import argparse
import hashlib
import struct
from pathlib import Path


def mailbox_symbol(data):
    if data[:7] != b"\x7fELF\x01\x01\x01":
        raise ValueError("expected a little-endian ELF32/NEF")
    header = struct.unpack_from("<16sHHIIIIIHHHHHH", data)
    if header[2] != 40 or header[11] != 40:  # EM_ARM, ELF32 section header size
        raise ValueError("expected an ARM ELF with 40-byte section headers")
    sections = [struct.unpack_from("<10I", data, header[6] + i * 40)
                for i in range(header[12])]

    def contents(section):
        start, size = section[4:6]
        if start + size > len(data):
            raise ValueError("truncated ELF section")
        return data[start:start + size]

    def name(strings, offset):
        return strings[offset:strings.index(b"\0", offset)].decode("ascii")

    names = contents(sections[header[13]])
    found = []
    for section in sections:
        if section[1] != 2:  # SHT_SYMTAB
            continue
        if section[9] != 16:
            raise ValueError("unexpected symbol entry size")
        strings = contents(sections[section[6]])
        for entry in struct.iter_unpack("<IIIBBH", contents(section)):
            offset, address, size, info, _, index = entry
            if name(strings, offset) != "gSoulLinkMailbox":
                continue
            if index == 0 or index >= len(sections):
                raise ValueError("mailbox is not defined in a resident section")
            if name(names, sections[index][0]) != "main" or info & 15 != 1:
                raise ValueError("mailbox must be an object in static main, not an overlay")
            if size != 128 or address % 32 or not 0x02000000 <= address <= 0x023FFF80:
                raise ValueError("mailbox size, alignment, or ARM9 main RAM address is invalid")
            found.append(address)
    if len(found) != 1:
        raise ValueError("expected exactly one gSoulLinkMailbox symbol")
    return found[0]


def export(build_dir):
    address = mailbox_symbol((build_dir / "main.nef").read_bytes())
    with (build_dir / "pokeplatinum.us.nds").open("rb") as rom:
        digest = hashlib.sha1()
        for chunk in iter(lambda: rom.read(1024 * 1024), b""):
            digest.update(chunk)
    output = build_dir / "soullink-symbols.lua"
    temporary = output.with_suffix(".lua.tmp")
    temporary.write_text(
        "-- Generated from main.nef; never guess or edit this address.\n"
        "return {\n"
        f"    mailbox = 0x{address:08X},\n"
        "    size = 128,\n"
        "    version = 0x0101,\n"
        f'    rom_sha1 = "{digest.hexdigest()}",\n'
        "}\n", encoding="ascii")
    temporary.replace(output)
    print(f"Soul Link mailbox: 0x{address:08X} (Main RAM + 0x{address - 0x02000000:X})")
    print(f"Symbols: {output}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_dir", type=Path)
    args = parser.parse_args()
    export(args.build_dir)


if __name__ == "__main__":
    main()
