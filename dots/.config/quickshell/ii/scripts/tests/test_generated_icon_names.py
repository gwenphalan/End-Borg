import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import global_app_icons as publisher


class GeneratedIconNameTests(unittest.TestCase):
    def test_safe_ids_keep_exact_existing_names(self):
        for app_id in ("org.example.Sample", "safe-ID_123", ".hidden", "two-words"):
            self.assertEqual(publisher.generated_icon_name(app_id),
                             "quickshell-generated-" + app_id)

    def test_unsafe_ids_use_ascii_slug_and_original_id_hash(self):
        for app_id in ("two words", "two/words", "two\twords", "naïve", "///", ""):
            with self.subTest(app_id=app_id):
                name = publisher.generated_icon_name(app_id)
                self.assertRegex(name, r"\Aquickshell-generated-[A-Za-z0-9._-]+\Z")
                digest = hashlib.sha256(app_id.encode()).hexdigest()[:12]
                self.assertTrue(name.endswith("-" + digest))
                self.assertEqual(name, publisher.generated_icon_name(app_id))
        self.assertEqual(publisher.generated_icon_name("two words"),
                         "quickshell-generated-two-words-" +
                         hashlib.sha256(b"two words").hexdigest()[:12])

    def test_sanitized_collisions_and_safe_ids_remain_distinct(self):
        ids = ("two words", "two/words", "two?words", "two-words", "two_words")
        self.assertEqual(len({publisher.generated_icon_name(app_id) for app_id in ids}), len(ids))

    def test_long_unsafe_id_fits_filesystem_component(self):
        self.assertLessEqual(len((publisher.generated_icon_name("long " * 100) + ".png").encode()), 255)


class GeneratedIconMigrationTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.apps = self.root / "applications"
        self.icons = self.root / "hicolor/256x256/apps"
        self.apps.mkdir()
        self.icons.mkdir(parents=True)
        self.manifest = self.root / "cache/global-icons.json"
        self.manifest.parent.mkdir()
        self.app_id = "Example Game"
        self.target = self.apps / (self.app_id + ".desktop")
        self.original = "[Desktop Entry]\nName=Example\nIcon=original\nExec=example\n"
        self.legacy_name = "quickshell-generated-" + self.app_id
        self.legacy_icon = self.icons / (self.legacy_name + ".png")
        self.legacy_rendered = publisher.MARKER + "\n" + self.original.replace(
            "Icon=original", "Icon=" + self.legacy_name)
        self.target.write_text(self.legacy_rendered)
        self.variants = {}
        for mode, color in (("dark", "#202020"), ("light", "#EEEEEE")):
            path = self.root / (mode + ".png")
            Image.new("RGBA", (256, 256), color).save(path)
            self.variants["path_" + mode] = str(path)
        self.legacy_icon.write_bytes(Path(self.variants["path_dark"]).read_bytes())
        self.record = {"original": self.original, "source": str(self.target),
                       "rendered": self.legacy_rendered}
        self.manifest.write_text(json.dumps({self.app_id: self.record}))
        self.meta = {self.app_id: {"app_id": self.app_id, **self.variants}}

    def export(self, mode="dark"):
        return publisher.export(self.meta, mode, self.manifest, self.apps, self.icons)

    def record_now(self):
        return json.loads(self.manifest.read_text())[self.app_id]

    def new_icon(self):
        return self.icons / (publisher.generated_icon_name(self.app_id) + ".png")

    def test_owned_legacy_migrates_in_both_modes_and_preserves_desktop_id(self):
        for mode in ("light", "dark"):
            with self.subTest(mode=mode):
                self.export(mode)
                self.assertIn("Icon=" + publisher.generated_icon_name(self.app_id) + "\n",
                              self.target.read_text())
                self.assertEqual(self.new_icon().read_bytes(), Path(self.variants["path_" + mode]).read_bytes())
                self.assertFalse(self.legacy_icon.exists())
                record = self.record_now()
                self.assertEqual(record["icon_name"], publisher.generated_icon_name(self.app_id))
                self.assertNotIn("pending_icon_name", record)
                self.assertNotIn("retired_icon_names", record)
                self.assertEqual(set(json.loads(self.manifest.read_text())), {self.app_id})
                self.assertEqual(self.target.name, self.app_id + ".desktop")
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertEqual(self.target.read_text(), self.original)
        self.assertFalse(self.new_icon().exists())
        self.assertFalse(self.legacy_icon.exists())

    def test_user_edited_legacy_desktop_prevents_migration_and_asset_deletion(self):
        edited = self.legacy_rendered + "# user edit\n"
        self.target.write_text(edited)
        original_icon = self.legacy_icon.read_bytes()
        self.export("light")
        self.assertEqual(self.target.read_text(), edited)
        self.assertEqual(self.legacy_icon.read_bytes(), original_icon)
        self.assertFalse(self.new_icon().exists())
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertEqual(self.target.read_text(), edited)
        self.assertEqual(self.legacy_icon.read_bytes(), original_icon)
        self.assertTrue(self.manifest.exists())

    def test_user_edited_new_desktop_preserves_current_and_retired_assets(self):
        self.export()
        self.legacy_icon.write_bytes(b"user-preserved legacy file")
        self.target.write_text(self.target.read_text() + "# user edit\n")
        before = self.new_icon().read_bytes()
        self.export("light")
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertEqual(self.new_icon().read_bytes(), before)
        self.assertEqual(self.legacy_icon.read_bytes(), b"user-preserved legacy file")
        self.assertTrue(self.target.read_text().endswith("# user edit\n"))

    def test_restore_legacy_manifest_removes_only_legacy_asset(self):
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertFalse(self.legacy_icon.exists())
        self.assertEqual(self.target.read_text(), self.original)
        self.assertFalse(self.manifest.exists())

    def fail_write(self, destination):
        write = publisher.atomic_bytes

        def interrupted(path, data):
            if path == destination:
                raise OSError("simulated interrupted installation")
            return write(path, data)

        return patch.object(publisher, "atomic_bytes", side_effect=interrupted)

    def test_journal_precedes_new_icon_write_and_restore_handles_interruption(self):
        with self.fail_write(self.new_icon()), self.assertRaises(OSError):
            self.export()
        record = self.record_now()
        self.assertEqual(record["pending_icon_name"], publisher.generated_icon_name(self.app_id))
        self.assertEqual(record["retired_icon_names"], [self.legacy_name])
        self.assertEqual(self.target.read_text(), self.legacy_rendered)
        self.assertTrue(self.legacy_icon.exists())
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertEqual(self.target.read_text(), self.original)
        self.assertFalse(self.new_icon().exists())
        self.assertFalse(self.legacy_icon.exists())

    def test_failed_desktop_install_keeps_legacy_and_resumes(self):
        with self.fail_write(self.target), self.assertRaises(OSError):
            self.export()
        self.assertTrue(self.legacy_icon.exists())
        self.assertTrue(self.new_icon().exists())
        self.assertEqual(self.target.read_text(), self.legacy_rendered)
        self.export("light")
        self.assertFalse(self.legacy_icon.exists())
        self.assertEqual(self.new_icon().read_bytes(), Path(self.variants["path_light"]).read_bytes())

    def test_restore_cleans_both_names_after_failed_desktop_install(self):
        with self.fail_write(self.target), self.assertRaises(OSError):
            self.export()
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertFalse(self.legacy_icon.exists())
        self.assertFalse(self.new_icon().exists())
        self.assertEqual(self.target.read_text(), self.original)

    def test_failed_promotion_keeps_legacy_until_retry_or_restore(self):
        write = publisher.atomic_bytes
        manifest_writes = 0

        def interrupted(path, data):
            nonlocal manifest_writes
            if path == self.manifest:
                manifest_writes += 1
                if manifest_writes == 2:
                    raise OSError("simulated interruption before promotion")
            return write(path, data)

        with patch.object(publisher, "atomic_bytes", side_effect=interrupted), self.assertRaises(OSError):
            self.export()
        self.assertTrue(self.legacy_icon.exists())
        self.assertEqual(self.record_now()["pending_icon_name"], publisher.generated_icon_name(self.app_id))
        self.export("light")
        self.assertFalse(self.legacy_icon.exists())
        self.assertNotIn("pending_icon_name", self.record_now())

    def test_user_edit_after_pending_migration_preserves_both_assets(self):
        with self.fail_write(self.target), self.assertRaises(OSError):
            self.export()
        self.target.write_text(self.target.read_text() + "# edit during recovery\n")
        self.export("light")
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertTrue(self.legacy_icon.exists())
        self.assertTrue(self.new_icon().exists())
        self.assertTrue(self.manifest.exists())

    def test_first_export_does_not_delete_unowned_legacy_filename(self):
        self.manifest.unlink()
        self.target.write_text(self.original)
        before = self.legacy_icon.read_bytes()
        self.export()
        self.assertEqual(self.legacy_icon.read_bytes(), before)
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertFalse(self.new_icon().exists())
        self.assertEqual(self.legacy_icon.read_bytes(), before)

    def test_cleanup_failure_is_journaled_and_restore_removes_both_names(self):
        unlink = Path.unlink

        def interrupted(path, *args, **kwargs):
            if path == self.legacy_icon:
                raise OSError("simulated legacy cleanup interruption")
            return unlink(path, *args, **kwargs)

        with patch.object(Path, "unlink", interrupted), self.assertRaises(OSError):
            self.export()
        self.assertTrue(self.legacy_icon.exists())
        self.assertTrue(self.new_icon().exists())
        record = self.record_now()
        self.assertEqual(record["icon_name"], publisher.generated_icon_name(self.app_id))
        self.assertNotIn("pending_rendered", record)
        self.assertEqual(record["retired_icon_names"], [self.legacy_name])
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertFalse(self.legacy_icon.exists())
        self.assertFalse(self.new_icon().exists())
        self.assertEqual(self.target.read_text(), self.original)

    def test_first_install_interruption_does_not_claim_legacy_asset(self):
        self.manifest.unlink()
        self.target.write_text(self.original)
        before = self.legacy_icon.read_bytes()
        with self.fail_write(self.target), self.assertRaises(OSError):
            self.export()
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertFalse(self.new_icon().exists())
        self.assertEqual(self.legacy_icon.read_bytes(), before)
        self.assertEqual(self.target.read_text(), self.original)

    def test_actual_token_collision_refuses_before_publication(self):
        crafted_safe_id = publisher.generated_icon_name(self.app_id).removeprefix(
            "quickshell-generated-")
        self.meta[crafted_safe_id] = {"app_id": crafted_safe_id, **self.variants}
        before = self.manifest.read_bytes()
        with self.assertRaisesRegex(ValueError, "collision"):
            self.export()
        self.assertEqual(self.manifest.read_bytes(), before)
        self.assertEqual(self.target.read_text(), self.legacy_rendered)
        self.assertTrue(self.legacy_icon.exists())
        self.assertFalse(self.new_icon().exists())

    def test_colliding_sanitized_ids_export_independent_assets(self):
        other_id = self.app_id.replace(" ", "-")
        other = self.apps / (other_id + ".desktop")
        other.write_text(self.original)
        self.meta[other_id] = {"app_id": other_id, **self.variants}
        self.export("light")
        other_icon = self.icons / (publisher.generated_icon_name(other_id) + ".png")
        self.assertNotEqual(other_icon, self.new_icon())
        self.assertTrue(other_icon.is_file())
        self.assertTrue(self.new_icon().is_file())
        self.assertIn("Icon=" + publisher.generated_icon_name(other_id), other.read_text())
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertFalse(other_icon.exists())
        self.assertFalse(self.new_icon().exists())

    def test_legacy_cleanup_preserves_other_user_edited_desktop_reference(self):
        other_id = "Other"
        other = self.apps / (other_id + ".desktop")
        other_rendered = publisher.MARKER + "\n" + self.original.replace(
            "Icon=original", "Icon=" + self.legacy_name)
        other.write_text(other_rendered + "# user edit\n")
        records = {self.app_id: self.record, other_id: {
            "original": self.original, "source": str(other), "rendered": other_rendered}}
        self.manifest.write_text(json.dumps(records))
        before = self.legacy_icon.read_bytes()
        self.export("light")
        self.assertEqual(self.legacy_icon.read_bytes(), before)
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertEqual(self.legacy_icon.read_bytes(), before)
        self.assertTrue(other.read_text().endswith("# user edit\n"))

    def test_manifest_cannot_request_cleanup_outside_app_icon_allowlist(self):
        other = self.icons / "quickshell-generated-unrelated.png"
        other.write_bytes(b"unrelated icon")
        records = {self.app_id: dict(self.record, retired_icon_names=[other.stem, "../escape"])}
        self.manifest.write_text(json.dumps(records))
        self.export()
        self.assertTrue(other.exists())
        publisher.restore(self.manifest, self.apps, self.icons)
        self.assertEqual(other.read_bytes(), b"unrelated icon")

    @unittest.skipUnless(shutil.which("gtk-update-icon-cache"), "GTK cache utility is unavailable")
    def test_migrated_names_generate_and_validate_real_gtk_cache(self):
        self.export()
        root = self.icons.parent.parent
        generated = subprocess.run(["gtk-update-icon-cache", "-f", "-i", str(root)],
                                   capture_output=True, text=True)
        self.assertEqual(generated.returncode, 0, generated.stderr)
        checked = subprocess.run(["gtk-update-icon-cache", "-v", str(root)],
                                 capture_output=True, text=True)
        self.assertEqual(checked.returncode, 0, checked.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
