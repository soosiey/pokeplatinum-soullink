import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_symbols import elf

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools/soullink"))
from package_client import package


class PackageTests(unittest.TestCase):
    def test_portable_bundle_and_preserved_config(self):
        with tempfile.TemporaryDirectory(prefix="soullink-package-") as temporary:
            root = Path(temporary)
            build, bundle = root / "build", root / "bundle"
            build.mkdir()
            (build / "main.nef").write_bytes(elf())
            rom = b"test ROM for portable packaging"
            (build / "pokeplatinum.us.nds").write_bytes(rom)
            package(build, bundle)
            self.assertEqual({p.name for p in bundle.iterdir()},
                             {"pokeplatinum.us.nds", "soullink.lua", "soullink-config.lua",
                              "soullink_bridge.py"})
            self.assertEqual((bundle / "soullink_bridge.py").read_bytes(),
                             (REPO / "soullink_bridge.py").read_bytes())
            self.assertEqual((bundle / "pokeplatinum.us.nds").read_bytes(), rom)
            config = bundle / "soullink-config.lua"
            self.assertEqual(config.read_bytes(), (REPO / "soullink-config.example.lua").read_bytes())
            config.write_text('return { role = "client", host = "192.0.2.1", port = 7777 }\n')
            saved_config = config.read_bytes()
            (bundle / "player.sav").write_bytes(b"keep this save")
            package(build, bundle)
            self.assertEqual(config.read_bytes(), saved_config)
            self.assertEqual((bundle / "player.sav").read_bytes(), b"keep this save")
            # Move the output and execute from an unrelated working directory.
            moved = root / "folder with spaces"
            bundle.rename(moved)
            lua = os.environ.get("SOULLINK_LUA") or shutil.which("lua5.3")
            if not lua:
                self.fail("run tools/soullink/test.sh or set SOULLINK_LUA")
            lua = str(Path(shutil.which(lua) or lua).resolve())
            result = subprocess.run([
                lua, str(REPO / "tests/soullink/loop_test.lua"),
                str(moved / "soullink.lua"), hashlib.sha1(rom).hexdigest(),
                str(0x02100000), str(REPO / "tools/soullink/mailbox.lua"),
            ], cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS:", result.stdout)

    def test_reject_source_output(self):
        with self.assertRaises(ValueError):
            package(REPO / ".build/rom", REPO)
