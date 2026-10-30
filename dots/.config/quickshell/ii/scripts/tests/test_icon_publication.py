import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import global_app_icons as publisher
import process_all_icons as builder


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apps = self.root / "local/applications"
        self.icons = self.root / "local/icons/hicolor/256x256/apps"
        self.manifest = self.root / "cache/global-icons.json"
        self.source = self.root / "exports/applications/nested/app.desktop"
        self.source.parent.mkdir(parents=True)
        self.source.write_text("[Desktop Entry]\nName=Example\nIcon=original\nExec=original\n"
                               "# retain comment\n[Desktop Action Open]\nName=Open\nExec=open\n")
        self.variants = {}
        for mode, color in (("dark", "blue"), ("light", "white")):
            path = self.root / (mode + ".png")
            Image.new("RGBA", (256, 256), color).save(path)
            self.variants["path_" + mode] = str(path)
        self.meta = {"nested-app": {"app_id": "nested-app", "desktop_file": str(self.source),
                                    **self.variants}}
        self.enterContext(patch.object(builder, "DEFAULT_CACHE", self.root / "unrelated-cache"))

    def export(self, mode="dark"):
        return publisher.export(self.meta, mode, self.manifest, self.apps, self.icons)

    def test_nested_custom_origin_roundtrip(self):
        original = self.source.read_bytes()
        self.export()
        target = self.apps / "nested-app.desktop"
        self.assertTrue(target.read_text().startswith(publisher.MARKER))
        self.assertIn("[Desktop Action Open]\nName=Open\nExec=open", target.read_text())
        self.assertEqual(self.source.read_bytes(), original)

        entries = builder.desktop_entries([self.apps], self.manifest)
        self.assertEqual(entries["nested-app"]["icon"], "original")
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertFalse(target.exists())
        self.assertEqual(self.source.read_bytes(), original)

    def test_unchanged_publication_performs_no_writes(self):
        self.export()
        with patch.object(publisher, "atomic_bytes", side_effect=AssertionError("unexpected publication")):
            self.export()

    def test_edited_desktop_and_its_icon_are_not_overwritten(self):
        self.export()
        target = self.apps / "nested-app.desktop"
        target.write_text(target.read_text() + "# user edit\n")
        icon = self.icons / "quickshell-generated-nested-app.png"
        before = icon.read_bytes()
        self.export("light")
        self.assertTrue(target.read_text().endswith("# user edit\n"))
        self.assertEqual(before, icon.read_bytes())

    def test_upstream_desktop_changes_are_not_pinned(self):
        self.export()
        updated = self.source.read_text().replace("Exec=original", "Exec=updated").replace(
            "Icon=original", "Icon=updated")
        self.source.write_text(updated)
        entries = builder.desktop_entries([self.apps], self.manifest)
        self.assertEqual(entries["nested-app"]["icon"], "updated")
        self.export()
        target = self.apps / "nested-app.desktop"
        self.assertIn("Exec=updated", target.read_text())
        records = json.loads(self.manifest.read_text())
        self.assertEqual(records["nested-app"]["original"], updated)

    def test_valid_empty_metadata_does_not_publish_stale_argument(self):
        self.manifest.parent.mkdir(parents=True)
        (self.manifest.parent / "app_icons_meta.json").write_text("{}")
        self.export()
        self.assertFalse((self.apps / "nested-app.desktop").exists())

    def test_discovery_respects_user_edits_after_unpromoted_install(self):
        real_write = publisher.atomic_bytes
        writes = 0
        def write(path, data):
            nonlocal writes
            if path == self.manifest:
                writes += 1
                if writes == 2:
                    raise OSError("simulated interruption before manifest promotion")
            return real_write(path, data)
        with patch.object(publisher, "atomic_bytes", side_effect=write), self.assertRaises(OSError):
            self.export()
        target = self.apps / "nested-app.desktop"
        target.write_text(target.read_text().replace(
            "Icon=quickshell-generated-nested-app", "Icon=user-choice"))
        entries = builder.desktop_entries([self.apps], self.manifest)
        self.assertEqual(entries["nested-app"]["icon"], "user-choice")

    def test_custom_cache_cli_requires_explicit_destinations(self):
        result = subprocess.run([sys.executable, publisher.__file__, "--mode", "dark",
                                 "--cache-dir", str(self.root / "staged")],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--applications-dir", result.stderr)

    def test_custom_icon_destination_does_not_escape_to_parent(self):
        with patch.object(publisher, "THEME_INDEX", self.source):
            publisher.export(self.meta, "dark", self.manifest, self.apps, self.root / "custom-icons")
        self.assertTrue((self.root / "custom-icons/index.theme").is_symlink())
        self.assertFalse((self.root.parent / "index.theme").is_symlink()
                         and (self.root.parent / "index.theme").resolve() == self.source)

    def fail_desktop_write(self):
        real_write = publisher.atomic_bytes
        target = self.apps / "nested-app.desktop"
        def write(path, data):
            if path == target:
                raise OSError("simulated interrupted desktop installation")
            return real_write(path, data)
        return patch.object(publisher, "atomic_bytes", side_effect=write)

    def test_first_install_can_resume_after_desktop_write_failure(self):
        with self.fail_desktop_write(), self.assertRaises(OSError):
            self.export()
        self.assertIn("pending_rendered", json.loads(self.manifest.read_text())["nested-app"])
        self.export()
        target = self.apps / "nested-app.desktop"
        self.assertTrue(target.read_text().startswith(publisher.MARKER))
        self.assertNotIn("pending_rendered", json.loads(self.manifest.read_text())["nested-app"])

    def test_upstream_update_can_resume_after_desktop_write_failure(self):
        self.export()
        self.source.write_text(self.source.read_text().replace("Exec=original", "Exec=updated"))
        with self.fail_desktop_write(), self.assertRaises(OSError):
            self.export()
        self.export()
        self.assertIn("Exec=updated", (self.apps / "nested-app.desktop").read_text())

    def test_restore_recovers_an_install_that_never_wrote_desktop(self):
        with self.fail_desktop_write(), self.assertRaises(OSError):
            self.export()
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertFalse(self.manifest.exists())
        self.assertFalse((self.apps / "nested-app.desktop").exists())


if __name__ == "__main__":
    unittest.main()
