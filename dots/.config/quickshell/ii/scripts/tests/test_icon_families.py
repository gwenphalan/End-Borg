import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from icon_families import infer_families
import process_all_icons as builder


class FamilyInferenceTests(unittest.TestCase):
    def test_suite_executable_and_corroborated_brand(self):
        entries = {"suite-one": {"name": "Suite One", "exec": "suite --one"},
                   "suite-two": {"name": "Suite Two", "exec": "suite --two"}}
        families = infer_families(entries)
        self.assertEqual(families["suite-one"]["key"], families["suite-two"]["key"])

    def test_brand_requires_name_and_independent_metadata(self):
        entries = {"net.rivet.Welcome": {"name": "Rivet Welcome"},
                   "rivet-install": {"name": "Rivet Installer"},
                   "net.rivet.Panel": {"name": "Panel"}}
        families = infer_families(entries)
        self.assertEqual({value["key"] for value in families.values()}, {"brand:rivet"})
        self.assertEqual(len(families), 2)
        self.assertNotIn("net.rivet.Panel", families)

    def test_common_path_components_and_runtime_labels_are_not_brands(self):
        entries = {"one": {"name": "Local One", "icon": "/home/person/.local/share/icons/one.png"},
                   "two": {"name": "Local Two", "icon": "/home/person/.local/share/icons/two.png"}}
        self.assertEqual(infer_families(entries), {})
        entries = {"python-one": {"name": "Python One", "exec": "python3 one.py"},
                   "python-two": {"name": "Python Two", "exec": "python3 two.py"}}
        self.assertEqual(infer_families(entries), {})

    def test_related_brand_does_not_admit_unrelated_same_author(self):
        entries = {"io.github.alice.One": {"name": "Alice One"},
                   "io.github.alice.Two": {"name": "Alice Two"},
                   "io.github.alice.Unrelated": {"name": "Completely Different"}}
        self.assertNotIn("io.github.alice.Unrelated", infer_families(entries))
    def test_versioned_runtime_labels_are_not_product_brands(self):
        for runtime in ("python3", "pypy3", "electron30", "node20"):
            with self.subTest(runtime=runtime):
                entries = {runtime + "-one": {"name": runtime + " One", "exec": runtime + " one"},
                           runtime + "-two": {"name": runtime + " Two", "exec": runtime + " two"}}
                self.assertEqual(infer_families(entries), {})

    def test_shared_transport_and_author_namespace_are_not_product_families(self):
        for command in ("flatpak run", "python3", "env python3", "sh -c", "electron"):
            entries = {"io.github.author.One": {"name": "One", "exec": command + " one"},
                       "io.github.author.Two": {"name": "Two", "exec": command + " two"}}
            self.assertEqual(infer_families(entries), {})

    def test_full_product_anchor_can_group_its_components(self):
        entries = {"org.example.Product": {"name": "Main"},
                   "org.example.Product.Tools": {"name": "Tools"},
                   "org.example.Productivity": {"name": "Unrelated"}}
        families = infer_families(entries)
        self.assertEqual(families["org.example.Product"]["key"],
                         families["org.example.Product.Tools"]["key"])
        self.assertNotIn("org.example.Productivity", families)

    def test_generic_icon_collision_does_not_establish_a_brand(self):
        entries = {"one": {"name": "Application One", "icon": "application-default-icon"},
                   "two": {"name": "Application Two", "icon": "application-default-icon"}}
        self.assertEqual(infer_families(entries), {})

    def test_grouping_is_independent_of_discovery_order(self):
        entries = {"suite-one": {"name": "Suite One", "exec": "suite --one"},
                   "suite-two": {"name": "Suite Two", "exec": "suite --two"}}
        self.assertEqual(infer_families(entries), infer_families(dict(reversed(list(entries.items())))))


class FamilyPublicationTests(unittest.TestCase):
    def test_shared_variants_and_native_artwork_are_independent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apps, cache = root / "apps", root / "cache"
            apps.mkdir()
            for suffix, color in (("one", "#0040AA"), ("two", "#FFCC30"), ("cover", "#40AA30")):
                image = Image.new("RGBA", (256, 256))
                draw = ImageDraw.Draw(image)
                if suffix == "cover":
                    draw.rectangle((0, 0, 255, 255), fill=color)
                else:
                    draw.ellipse((0, 0, 255, 255), fill=color)
                path = root / (suffix + ".png")
                image.save(path)
                (apps / ("suite-" + suffix + ".desktop")).write_text(
                    f"[Desktop Entry]\nName=Suite {suffix}\nExec=suite --{suffix}\nIcon={path}\n")
            with patch.object(builder, "Gtk", None), patch.object(builder, "DEFAULT_CACHE", root / "absent"):
                meta = builder.build(cache, directories=[apps])
                before = (cache / "icon_dictionary.json").read_bytes()
                builder.build(cache, directories=[apps])
            self.assertEqual(before, (cache / "icon_dictionary.json").read_bytes())
            self.assertNotIn("background_family", meta["suite-cover"])
            records = json.loads(before)["icons"]
            self.assertEqual(records["suite-one"]["background_family"]["members"],
                             ["suite-one", "suite-two"])
            self.assertEqual(records["suite-one"]["baseline"]["backgrounds"],
                             records["suite-two"]["baseline"]["backgrounds"])
            for app_id in ("suite-one", "suite-two"):
                for mode in ("light", "dark"):
                    self.assertEqual(meta[app_id]["bg_" + mode],
                                     records[app_id]["mode_variants"][mode]["backplate"])
            (root / "one.png").unlink()
            with patch.object(builder, "Gtk", None), \
                    patch.object(builder, "DEFAULT_CACHE", root / "absent"), \
                    patch.object(builder, "APP_THEME", root / "absent-theme"):
                retained = builder.build(cache, directories=[apps])
            records = json.loads((cache / "icon_dictionary.json").read_text())["icons"]
            self.assertEqual(records["suite-one"]["status"], "fallback")
            self.assertEqual(retained["suite-one"]["bg_dark"], retained["suite-two"]["bg_dark"])
            self.assertEqual(set(records["suite-one"]["outputs"]), {"artwork", "light", "dark"})


if __name__ == "__main__":
    unittest.main()
