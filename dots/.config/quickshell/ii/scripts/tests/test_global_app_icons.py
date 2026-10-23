import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from PIL import Image
from global_app_icons import export, restore, MARKER
from process_all_icons import desktop_entries


class GlobalIconTests(unittest.TestCase):
    def test_export_switch_and_restore_original_desktop_entry(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            apps, icons = root / "applications", root / "icons"
            apps.mkdir()
            original = "[Desktop Entry]\nName=Sample\nIcon=/tmp/source.png\nExec=sample\n"
            desktop = apps / "org.example.Sample.desktop"
            desktop.write_text(original)
            variants = {}
            for mode, color in (("light", "#D1DCE9"), ("dark", "#233448")):
                path = root / (mode + ".png")
                Image.new("RGBA", (256, 256), color).save(path)
                variants["path_" + mode] = str(path)
            entry = {"app_id": "org.example.Sample", **variants}
            meta = {"org.example.Sample": entry}
            manifest = root / "cache" / "global-icons.json"
            self.assertEqual(export(meta, "dark", manifest, apps, icons), 1)
            self.assertTrue(desktop.read_text().startswith(MARKER))
            self.assertIn("Icon=quickshell-generated-org.example.Sample\n", desktop.read_text())
            self.assertEqual((manifest.parent / "appearance-mode").read_text(), "dark")
            self.assertEqual(desktop_entries([apps], manifest)["org.example.Sample"]["icon"],
                             "/tmp/source.png")
            self.assertEqual(export(meta, "light", manifest, apps, icons), 1)
            self.assertEqual((icons / "quickshell-generated-org.example.Sample.png").read_bytes(),
                             Path(variants["path_light"]).read_bytes())
            restore(manifest, apps, icons)
            self.assertEqual(desktop.read_text(), original)
            self.assertFalse((icons / "quickshell-generated-org.example.Sample.png").exists())
    def test_restore_preserves_user_edits(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            apps, icons = root / "applications", root / "icons"
            apps.mkdir()
            desktop = apps / "org.example.Sample.desktop"
            desktop.write_text("[Desktop Entry]\nName=Sample\nIcon=sample\n")
            image = root / "icon.png"
            Image.new("RGBA", (256, 256), "red").save(image)
            manifest = root / "cache" / "global-icons.json"
            meta = {"sample": {"app_id": "org.example.Sample", "path_dark": str(image)}}
            export(meta, "dark", manifest, apps, icons)
            desktop.write_text(desktop.read_text() + "# personal change\n")
            restore(manifest, apps, icons)
            self.assertIn("# personal change", desktop.read_text())
            self.assertTrue(manifest.exists())


if __name__ == "__main__":
    unittest.main()
