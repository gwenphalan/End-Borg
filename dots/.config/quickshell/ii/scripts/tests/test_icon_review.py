import json
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from adaptive_icon_policy import extend_exterior_edges, render_adaptive, theme_colors
from icon_review import bridge
from process_all_icons import metadata_for


class ReviewTests(unittest.TestCase):
    def test_fill_extends_only_exterior_and_preserves_holes(self):
        image = Image.new("RGBA", (256, 256))
        draw = ImageDraw.Draw(image)
        draw.ellipse((10, 10, 245, 245), fill="#8D5AB0")
        draw.ellipse((100, 100, 155, 155), fill=(0, 0, 0, 0))
        filled = extend_exterior_edges(image)
        self.assertEqual(filled.getpixel((0, 0))[3], 255)
        self.assertEqual(filled.getpixel((128, 128))[3], 0)
        self.assertEqual(filled.getpixel((128, 50)), image.getpixel((128, 50)))


    def test_validation_rejects_unbounded_values(self):
        for value in (True, float("nan"), 91, "12"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                bridge.validate({"hue_shift": value})
        for payload in ({"bg_color": "red"}, {"note": "x" * 501},
                        {"other": "x"}, {"presentation": "../../file"}):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                bridge.validate(payload)
        self.assertEqual(bridge.validate({"strength": 1, "saturation": 1,
                                          "hue_shift": 0, "flag": "looks good"}),
                         {"flag": "looks good"})
        self.assertRaises(ValueError, bridge.validate, {"strength": float("inf")})

    def test_native_bridge_preview_and_save(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "art.png"
            Image.new("RGBA", (64, 64), "#7B42CC").save(source)
            alternative = root / "different.png"
            Image.new("RGBA", (64, 64), "#30B874").save(alternative)
            theme = root / "theme.json"
            theme.write_text(json.dumps({"primary": "#DAAADD"}))
            cache = root / "cache"
            cache.mkdir()
            live_hints = root / "borg-intelligence" / "icon-hints.json"
            live_hints.parent.mkdir()
            live_hints.write_text(json.dumps({"sample": {"alternate_icon": "brand", "note": "prior"}}))
            reviews = root / "icon-review" / "reviews.json"
            reviews.parent.mkdir()
            reviews.write_text(json.dumps({"other": {"flag": "looks good"},
                                           "sample": {"note": "prior", "future_field": "retained"}}))
            options = {"presentation": "fit", "hue_shift": 25, "saturation": .85,
                       "strength": .5, "flag": "needs work", "note": "try more"}
            generated = metadata_for("sample", {"icon": str(source), "name": "Sample"},
                                     theme_colors(theme), "theme", cache, {"sample": options})
            (cache / "app_icons_meta.json").write_text(json.dumps({"sample": generated}))
            initial_hints = live_hints.read_bytes()
            initial_cache = {p.relative_to(cache): hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in cache.rglob("*") if p.is_file()}
            with patch.object(bridge, "DEFAULT_CACHE", cache), patch.object(bridge, "REVIEWS", reviews), \
                 patch.object(bridge, "DEFAULT_THEME", theme), patch.object(bridge, "PREVIEWS", root / "previews"), \
                 patch.object(bridge, "ALTERNATIVES", root / "icon-review" / "alternatives"):
                catalog = bridge.handle({"operation": "catalog"})
                self.assertEqual(len(catalog["apps"]), 1)
                self.assertEqual(catalog["reviews"]["sample"]["future_field"], "retained")
                path = bridge.handle({"operation": "preview", "id": "sample", "review": options})["path"]
                self.assertEqual(Image.open(path).tobytes(), Image.open(generated["path"]).tobytes())
                with_alternative = dict(options, alternate_icon=str(alternative))
                alt_path = bridge.handle({"operation": "preview", "id": "sample", "review": with_alternative})["path"]
                expected, _ = render_adaptive(Image.open(alternative).convert("RGBA"), "fit",
                                              theme_colors(theme), False, options)
                self.assertEqual(Image.open(alt_path).convert("RGBA").tobytes(), expected.tobytes())
                self.assertNotEqual(Image.open(alt_path).tobytes(), Image.open(path).tobytes())
                self.assertRaises(ValueError, bridge.handle, {"operation": "preview", "id": "../etc",
                                                              "review": options})
                saved = bridge.handle({"operation": "save", "id": "sample", "review": with_alternative})["saved"]
                self.assertEqual(saved["flag"], "needs work")
                self.assertEqual(saved["future_field"], "retained")
                self.assertEqual(Path(saved["alternate_icon"]).read_bytes(), alternative.read_bytes())
                alternative.unlink()
                self.assertEqual(bridge.handle({"operation": "catalog"})["reviews"]["sample"], saved)
                self.assertEqual(bridge.handle({"operation": "catalog"})["reviews"]["other"]["flag"], "looks good")
                restored = {k: v for k, v in saved.items() if k in bridge.FIELDS}
                self.assertEqual(bridge.handle({"operation": "preview", "id": "sample",
                                                "review": restored})["path"], alt_path)
                (root / "linked.png").symlink_to(live_hints)
                for invalid in ("relative.png", "https://example.org/art.png", str(root / "missing.png"),
                                str(live_hints), str(root / "linked.png"), str(root / "fake.png")):
                    if invalid.endswith("fake.png"):
                        (root / "fake.png").write_text("not an image")
                    with self.subTest(invalid=invalid), self.assertRaises((ValueError, OSError)):
                        bridge.handle({"operation": "save", "id": "sample",
                                       "review": {"alternate_icon": invalid}})
                self.assertEqual(bridge.handle({"operation": "save", "id": "sample",
                                                "review": {"note": "clear artwork"}})["saved"],
                                 {"note": "clear artwork", "future_field": "retained"})
                self.assertRaises(ValueError, bridge.handle, {"operation": "rebuild"})
            self.assertEqual(live_hints.read_bytes(), initial_hints)
            self.assertEqual({p.relative_to(cache): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in cache.rglob("*") if p.is_file()}, initial_cache)


if __name__ == "__main__":
    unittest.main()
