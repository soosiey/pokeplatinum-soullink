"""Audit actual ARM-compiled save sizes, not host ABI guesses."""
import re
import shutil
import subprocess
import unittest
from pathlib import Path


def constant_return(disassembly):
    # The pinned compiler emits these three forms for constant sizeof returns.
    if re.search(r"ldr\s+r0, \[pc, #0\]", disassembly):
        match = re.search(r"\.word\s+(0x[0-9a-f]+)", disassembly)
        if match:
            return int(match[1], 16)
    match = re.search(r"movs\s+r0, #(\d+)", disassembly)
    if match:
        shift = re.search(r"lsls\s+r0, r0, #(\d+)", disassembly)
        return int(match[1]) << (int(shift[1]) if shift else 0)
    raise ValueError("unrecognized constant-size function: " + disassembly)


class SaveLayoutTests(unittest.TestCase):
    def test_compiled_save_budget(self):
        objects = Path(".build/rom/main.nef.p")
        if not objects.exists():
            self.skipTest("build the ROM to audit save sizes")
        objdump = shutil.which("arm-none-eabi-objdump")
        self.assertIsNotNone(objdump)
        source = Path("src/savedata/save_table.c").read_text().split("const int gSaveTableSize")[0]
        entries = re.findall(r"\{ (SAVE_TABLE_ENTRY_\w+), (SAVE_BLOCK_ID_\w+), "
                             r"\(SaveEntrySizeFunc\)(\w+)", source)
        sizes = {}
        for path in objects.glob("src_*.o"):
            data = path.read_bytes()
            for _, _, name in entries:
                if name.encode() + b"\0" not in data:
                    continue
                output = subprocess.check_output([objdump, "-d", "--disassemble=" + name,
                                                  str(path)], text=True)
                marker = "<" + name + ">:"
                if marker in output:
                    body = output.split(marker, 1)[1].split("Disassembly of section")[0]
                    self.assertNotIn(name, sizes, "duplicate size symbol")
                    self.assertIn("bx\tlr", body)
                    sizes[name] = constant_return(body)
        self.assertEqual(len(sizes), len(entries))
        self.assertEqual(sizes["SoulLinkSave_Size"], 32)
        self.assertEqual(entries[-2][0], "SAVE_TABLE_ENTRY_SOUL_LINK")
        self.assertEqual(entries[-1][0], "SAVE_TABLE_ENTRY_PC_BOXES")
        blocks = {"SAVE_BLOCK_ID_NORMAL": 20, "SAVE_BLOCK_ID_BOXES": 20}  # ARM footer
        for _, block, name in entries:
            size = sizes[name]
            blocks[block] += size + 4 - size % 4 + 4  # SaveTableEntry_BodySize
        sectors = sum((size + 4095) // 4096 for size in blocks.values())
        self.assertLessEqual(sectors, 32)
        self.assertLessEqual(sum(blocks.values()), 32 * 4096)
        print(f"Save layout: {blocks}, {sectors}/32 sectors (both mirrors use this layout)")
