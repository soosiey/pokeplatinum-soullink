import runpy
import tempfile
import unittest
from pathlib import Path


COPY = runpy.run_path(str(Path(__file__).resolve().parents[2] / "copy-client.py"))


class CopyClientTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "source"
        self.destination = Path(self.temp.name) / "destination"
        self.source.mkdir()
        for name in COPY["ARTIFACTS"]:
            (self.source / name).write_text(name)
        (self.source / COPY["CONFIG"]).write_text(
            'return {\n    role = "host",\n    host = "127.0.0.1",\n    port = 7777,\n}\n'
        )

    def copy(self):
        COPY["copy_bundle"](self.source, self.destination)

    def test_copy_and_refresh_preserve_settings_and_saves(self):
        self.copy()
        for role in ("host", "client"):
            folder = self.destination / role
            for name in COPY["ARTIFACTS"]:
                output = f"pokeplatinum-{role}.nds" if name.endswith(".nds") else name
                self.assertEqual((folder / output).read_bytes(), (self.source / name).read_bytes())
            self.assertFalse((folder / "pokeplatinum.us.nds").exists())
            self.assertIn(f'role = "{role}"', (folder / COPY["CONFIG"]).read_text())
        folder = self.destination / "client"
        config = folder / COPY["CONFIG"]
        config.write_text("return {\n role = 'host',\n host = '10.0.0.2',\n port = 8888,\n}\n")
        save = folder / "game.sav"
        save.write_bytes(b"save data")
        (self.source / "soullink.lua").write_text("updated")
        self.copy()
        self.assertIn('role = "client"', config.read_text())
        self.assertIn("host = '10.0.0.2'", config.read_text())
        self.assertIn("port = 8888", config.read_text())
        self.assertEqual(save.read_bytes(), b"save data")
        self.assertEqual((folder / "soullink.lua").read_text(), "updated")

    def test_missing_build_leaves_destination_untouched(self):
        (self.source / "soullink.lua").unlink()
        with self.assertRaisesRegex(ValueError, "build-modern"):
            self.copy()
        self.assertFalse(self.destination.exists())

    def test_bad_config_leaves_destination_untouched(self):
        (self.source / COPY["CONFIG"]).write_text("return {}")
        with self.assertRaisesRegex(ValueError, "role assignment"):
            self.copy()
        self.assertFalse(self.destination.exists())

    def test_symlink_destination_is_refused(self):
        self.destination.symlink_to(self.source, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.copy()

    def test_renamed_rom_symlink_is_refused(self):
        folder = self.destination / "client"
        folder.mkdir(parents=True)
        (folder / "pokeplatinum-client.nds").symlink_to(self.source / "pokeplatinum.us.nds")
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.copy()
        self.assertFalse((self.destination / "host").exists())


if __name__ == "__main__":
    unittest.main()
