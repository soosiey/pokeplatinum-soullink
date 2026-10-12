import importlib.util
import struct
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("export_symbols", "tools/soullink/export_symbols.py")
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


def elf(address=0x02100000, size=128, section_name=b"main", symbol=True):
    names = b"\0" + section_name + b"\0.strtab\0.symtab\0.shstrtab\0"
    strings = b"\0gSoulLinkMailbox\0"
    symbols = struct.pack("<IIIBBH", 1 if symbol else 0, address, size, 0x11, 0, 1)
    data = bytearray(52 + 5 * 40)
    sections = [(0,) * 10, (1, 1, 3, 0x02000000, 0, 0, 0, 0, 32, 0)]
    for content, name, kind, link, entsize in [
        (strings, b".strtab", 3, 0, 0),
        (symbols, b".symtab", 2, 2, 16),
        (names, b".shstrtab", 3, 0, 0),
    ]:
        sections.append((names.index(name), kind, 0, 0, len(data), len(content), link, 0, 1, entsize))
        data.extend(content)
    struct.pack_into("<16sHHIIIIIHHHHHH", data, 0, b"\x7fELF\x01\x01\x01", 2, 40, 1,
                     0, 0, 52, 0, 52, 0, 0, 40, 5, 4)
    for i, section in enumerate(sections):
        struct.pack_into("<10I", data, 52 + 40 * i, *section)
    return data


class SymbolTests(unittest.TestCase):
    def test_resident_symbol(self):
        self.assertEqual(exporter.mailbox_symbol(elf()), 0x02100000)

    def test_reject_unsafe_layouts(self):
        for args in [dict(section_name=b"overlay5"), dict(address=0x027E0000),
                     dict(address=0x02100001), dict(size=68), dict(symbol=False)]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                exporter.mailbox_symbol(elf(**args))

    def test_reject_non_elf(self):
        with self.assertRaises(ValueError):
            exporter.mailbox_symbol(b"not an ELF")

    def test_real_build_when_available(self):
        path = Path(".build/rom/main.nef")
        if not path.exists():
            self.skipTest("build the ROM to verify its symbol")
        address = exporter.mailbox_symbol(path.read_bytes())
        self.assertEqual(address % 32, 0)


if __name__ == "__main__":
    unittest.main()
