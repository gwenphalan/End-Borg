import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import process_all_icons as builder
from adaptive_icon_modes import render_variant, resolve_container
from adaptive_icon_policy import POLICY_VERSION, compose_icon


class ModeIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apps = self.root / "applications"
        self.apps.mkdir()
        self.cache = self.root / "cache"
        self.source = self.root / "source.png"
        image = Image.new("RGBA", (256, 256), "#EEEEEE")
        ImageDraw.Draw(image).ellipse((65, 65, 190, 190), fill="#303030")
        image.save(self.source)
        (self.apps / "sample.desktop").write_text(
            f"[Desktop Entry]\nName=Sample\nIcon={self.source}\n")
        self.enterContext(patch.object(builder, "DEFAULT_CACHE", self.root / "not-live"))
        self.enterContext(patch.object(builder, "APP_THEME", self.root / "not-theme"))
        self.enterContext(patch.object(builder, "Gtk", None))
        self.enterContext(patch.object(builder, "steamgriddb_enabled", return_value=False))

    def build(self):
        return builder.build(self.cache, directories=[self.apps])["sample"]

    def record(self):
        return json.loads((self.cache / "icon_dictionary.json").read_text())["icons"]["sample"]

    def test_mode_paths_match_final_artwork_and_keep_baseline(self):
        entry = self.build()
        record = self.record()
        self.assertGreater(POLICY_VERSION, 31)
        self.assertNotEqual(entry["path_light"], entry["path_dark"])
        for mode in ("light", "dark"):
            with Image.open(entry["source_pixels"]) as image:
                raw = render_variant(image.convert("RGBA"), mode)
            plate = record["baseline"]["backgrounds"][mode]["color"]
            preview = compose_icon(raw["artwork"], raw.get("backplate") or plate, raw["presentation"])
            final = resolve_container(raw, preview, mode)
            expected = compose_icon(final["artwork"], final.get("backplate") or plate,
                                    final["presentation"])
            with Image.open(entry["path_" + mode]) as actual:
                self.assertEqual(actual.tobytes(), expected.tobytes())
            with Image.open(entry["artwork_" + mode]) as actual:
                self.assertEqual(actual.tobytes(), final["artwork"].tobytes())
            self.assertTrue(Path(record["baseline"]["outputs"][mode]).is_file())
        with Image.open(entry["path_light"]) as light, Image.open(entry["path_dark"]) as dark:
            np.testing.assert_array_equal(np.asarray(light)[:, :, 3], np.asarray(dark)[:, :, 3])

    def test_missing_source_rebuilds_same_variants_from_retained_pixels(self):
        first = self.build()
        expected = {mode: Path(first["path_" + mode]).read_bytes() for mode in ("light", "dark")}
        self.source.unlink()
        second = self.build()
        self.assertEqual(self.record()["status"], "fallback")
        for mode in expected:
            self.assertEqual(expected[mode], Path(second["path_" + mode]).read_bytes())

    def test_finishing_failure_cannot_promote_partial_metadata(self):
        self.build()
        before = {name: (self.cache / name).read_bytes()
                  for name in ("icon_dictionary.json", "app_icons_meta.json")}
        with patch.object(builder, "resolve_container", side_effect=ValueError("test failure")):
            with self.assertRaises(ValueError):
                builder.build(self.cache, directories=[self.apps], force=True)
        for name, expected in before.items():
            self.assertEqual((self.cache / name).read_bytes(), expected)
    def test_missing_or_corrupt_diagnostics_do_not_block_valid_cached_recovery(self):
        first = self.build()
        expected = {mode: Path(first["path_" + mode]).read_bytes() for mode in ("light", "dark")}
        self.source.unlink()
        dictionary = self.cache / "icon_dictionary.json"
        for content in (None, "{", '{"icons":{"sample":null}}', '{"icons":null}'):
            with self.subTest(content=content):
                if content is None:
                    dictionary.unlink(missing_ok=True)
                else:
                    dictionary.write_text(content)
                second = self.build()
                self.assertEqual(self.record()["status"], "fallback")
                for mode in expected:
                    self.assertEqual(expected[mode], Path(second["path_" + mode]).read_bytes())

    def test_mode_assets_survive_stale_cache_pruning(self):
        entry = self.build()
        import os
        for path in (self.cache / "adaptive").glob("*.png"):
            os.utime(path, (1, 1))
        for index in range(270):
            unused = self.cache / "adaptive" / f"unused-{index:03}.png"
            unused.write_bytes(self.source.read_bytes())
            os.utime(unused, (0, 0))
        second = self.build()
        self.assertLess(len(list((self.cache / "adaptive").glob("unused-*.png"))), 270)
        for key in ("path", "path_light", "path_dark", "source_pixels",
                    "artwork_light", "artwork_dark"):
            self.assertEqual(entry[key], second[key])
            self.assertTrue(Path(second[key]).is_file())

    def test_unchanged_registry_does_not_decode_render_or_write(self):
        first = self.build()
        before = {path: path.stat().st_mtime_ns for path in self.cache.rglob("*") if path.is_file()}
        with patch.object(builder, "metadata_for", side_effect=AssertionError("unexpected analysis")), \
                patch.object(builder, "load_icon", side_effect=AssertionError("unexpected decoding")), \
                patch.object(builder, "render_variant", side_effect=AssertionError("unexpected rendering")), \
                patch.object(builder, "atomic_bytes", side_effect=AssertionError("unexpected write")):
            self.assertEqual(first, self.build())
        self.assertEqual(before, {path: path.stat().st_mtime_ns for path in before})

    def test_new_app_only_analyzes_new_entry(self):
        self.build()
        (self.apps / "new.desktop").write_text(
            f"[Desktop Entry]\nName=New\nIcon={self.source}\n")
        with patch.object(builder, "metadata_for", wraps=builder.metadata_for) as analyze:
            meta = builder.build(self.cache, directories=[self.apps])
        self.assertEqual([call.args[0] for call in analyze.call_args_list], ["new"])
        self.assertIn("new", meta)

    def test_changed_source_only_rebuilds_affected_app(self):
        self.build()
        Image.new("RGBA", (256, 256), "#00CC44").save(self.source)
        with patch.object(builder, "metadata_for", wraps=builder.metadata_for) as analyze:
            self.build()
        self.assertEqual([call.args[0] for call in analyze.call_args_list], ["sample"])

    def test_existing_cache_migrates_without_rendering(self):
        first = self.build()
        dictionary = self.cache / "icon_dictionary.json"
        records = json.loads(dictionary.read_text())
        records["icons"]["sample"].pop("input_stamp")
        dictionary.write_text(json.dumps(records))
        with patch.object(builder, "metadata_for", side_effect=AssertionError("unexpected rebuild")), \
                patch.object(builder, "render_variant", side_effect=AssertionError("unexpected render")):
            self.assertEqual(first, self.build())
        self.assertIn("input_stamp", self.record())

    def test_removed_app_is_removed_without_rebuilding_survivors(self):
        self.build()
        (self.apps / "sample.desktop").unlink()
        with patch.object(builder, "metadata_for", side_effect=AssertionError("unexpected rebuild")):
            self.assertEqual(builder.build(self.cache, directories=[self.apps]), {})

    def test_missing_generated_variant_is_repaired(self):
        first = self.build()
        Path(first["artwork_dark"]).unlink()
        with patch.object(builder, "metadata_for", wraps=builder.metadata_for) as analyze:
            second = self.build()
        self.assertEqual(analyze.call_count, 1)
        self.assertTrue(Path(second["artwork_dark"]).is_file())


if __name__ == "__main__":
    unittest.main()
