import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from PIL import Image, ImageDraw
from adaptive_icon_policy import (classify, compose_icon, contain, extend_rounded_square,
                                  full_bleed_tile, icon_backplates, remove_border_background,
                                  render_adaptive, source_key, squircle_mask, trim_visible)
from process_all_icons import build, metadata_for, themed_icon


class AdaptiveIconTests(unittest.TestCase):
    def test_trim_before_square_game_decision(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / "game.png"
            image = Image.new("RGBA", (100, 100))
            ImageDraw.Draw(image).rectangle((20, 20, 79, 79), fill="#345678")
            image.save(path)
            self.assertEqual(trim_visible(image).size, (60, 60))
            desktop = {"icon": str(path), "name": "Game", "categories": "Game;"}
            colors = {"primary": "#573A70", "neutral": "#2C292E"}
            self.assertEqual(metadata_for("test-game", desktop, colors, "theme", root, {})["presentation"], "fit")
            self.assertEqual(metadata_for("ASTRONEER", desktop, colors, "theme", root, {})["presentation"], "fit")
    def test_safe_bleed_rejects_round_icons_and_shaped_folders(self):
        tile = Image.new("RGBA", (256, 256))
        ImageDraw.Draw(tile).rounded_rectangle((0, 0, 255, 255), radius=28, fill="#7475A0")
        self.assertTrue(full_bleed_tile(tile))
        circle = Image.new("RGBA", (256, 256))
        ImageDraw.Draw(circle).ellipse((0, 0, 255, 255), fill="red")
        self.assertFalse(full_bleed_tile(circle))
        folder = Image.new("RGBA", (256, 256))
        ImageDraw.Draw(folder).rectangle((0, 70, 255, 255), fill="blue")
        self.assertFalse(full_bleed_tile(folder))
    def test_background_is_complementary_and_independent_of_theme(self):
        image = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(image).ellipse((8, 8, 55, 55), fill="#C02030")
        colors = icon_backplates(image)
        self.assertEqual(colors, icon_backplates(image))
        self.assertGreater(sum(bytes.fromhex(colors["light"][1:])),
                           sum(bytes.fromhex(colors["dark"][1:])))
    def test_neutral_artwork_does_not_invent_a_hue(self):
        image = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(image).ellipse((6, 6, 57, 57), fill="#B0B0B0")
        for color in icon_backplates(image).values():
            channels = bytes.fromhex(color[1:])
            self.assertLessEqual(max(channels) - min(channels), 1)
    def test_theme_resolution_is_exact_and_path_bounded(self):
        self.assertIsNotNone(themed_icon(("blender",)))
        self.assertIsNone(themed_icon(("../../private",)))

    def test_monochrome_symbol_stays_unmodified(self):
        image = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(image).ellipse((12, 12, 52, 52), fill=(190, 190, 190, 255))
        output, _ = render_adaptive(image, "fit", {"accent": "#D080E0"})
        self.assertEqual(output.getpixel((128, 128)), (190, 190, 190, 255))

    def test_g2_mask_and_fit_margin(self):
        mask = squircle_mask()
        self.assertEqual(mask.getpixel((0, 0)), 0)
        self.assertGreater(mask.getpixel((128, 2)), 200)
        image = Image.new("RGBA", (256, 256), "#FF0000")
        tile = compose_icon(image, "#0000FF", "fit")
        self.assertEqual(tile.getpixel((128, 128))[:3], (255, 0, 0))
        self.assertEqual(tile.getpixel((5, 128))[:3], (0, 0, 255))

    def test_round_tile_extends_but_circle_does_not(self):
        rounded = Image.new("RGBA", (256, 256))
        draw = ImageDraw.Draw(rounded)
        draw.rounded_rectangle((0, 0, 255, 255), radius=28, fill="#3865A7")
        draw.rectangle((90, 90, 165, 165), fill="white")
        result = extend_rounded_square(rounded)
        self.assertIsNotNone(result)
        self.assertEqual(result.getpixel((0, 0))[3], 255)
        self.assertEqual(result.getpixel((128, 128)), rounded.getpixel((128, 128)))
        circle = Image.new("RGBA", (256, 256))
        ImageDraw.Draw(circle).ellipse((0, 0, 255, 255), fill="blue")
        self.assertIsNone(extend_rounded_square(circle))
    def test_legacy_null_paths_do_not_abort_rebuild(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            apps = root / "apps"
            apps.mkdir()
            (apps / "org.test.Missing.desktop").write_text(
                "[Desktop Entry]\nName=Missing\nIcon=/nonexistent/public-icon.png\n")
            cache = root / "cache"
            cache.mkdir()
            (cache / "app_icons_meta.json").write_text(json.dumps({"org.test.Missing": {"path": None}}))
            self.assertEqual(build(cache, root / "theme", {}, [apps]), {})
    def test_contain_preserves_rectangular_glyph(self):
        original = Image.new("RGBA", (60, 120), (210, 40, 60, 255))
        result = contain(original)
        self.assertEqual(result.size, (256, 256))
        self.assertEqual(result.getchannel("A").getbbox(), (64, 0, 192, 256))
        self.assertEqual(classify(original)[0], "fit")

    def test_square_art_and_transparent_folder(self):
        self.assertEqual(classify(Image.new("RGB", (100, 100), "red"))[0], "fit")
        icon = Image.new("RGBA", (100, 100))
        icon.paste((255, 255, 255, 255), (10, 25, 90, 75))
        self.assertEqual(classify(icon)[0], "fit")
        self.assertIsNone(extend_rounded_square(icon))
    def test_rounded_tiles_fill_while_round_badges_keep_padding(self):
        tile = Image.new("RGBA", (256, 256))
        ImageDraw.Draw(tile).rounded_rectangle((0, 0, 255, 255), radius=27, fill="white")
        badge = Image.new("RGBA", (256, 256))
        ImageDraw.Draw(badge).ellipse((0, 0, 255, 255), fill="white")
        self.assertEqual(classify(tile)[0], "fill")
        self.assertEqual(classify(badge)[0], "fit")
        complex_tile = tile.copy()
        ImageDraw.Draw(complex_tile).rectangle((0, 64, 255, 191), fill="#1177CC")
        self.assertEqual(classify(complex_tile)[0], "fit")
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name, image in (("cover", tile), ("badge", badge)):
                path = root / (name + ".png")
                image.save(path)
                entry = {"icon": str(path), "name": name, "categories": "Game;"}
                result = metadata_for(name, entry, {"neutral": "#2C292E"}, "theme", root, {})
                self.assertEqual(result["presentation"], "fill" if name == "cover" else "fit")

    def test_related_apps_share_surface_without_recoloring_distinct_art(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            apps = root / "apps"
            apps.mkdir()
            for suffix, color in (("calc", "#2266AA"), ("writer", "#AA6622")):
                icon = root / (suffix + ".png")
                Image.new("RGBA", (64, 64), color).save(icon)
                (apps / ("libreoffice-" + suffix + ".desktop")).write_text(
                    "[Desktop Entry]\nName=" + suffix + "\nIcon=" + str(icon) + "\n")
            entries = build(root / "cache", root / "theme", {}, [apps])
            calc, writer = (entries["libreoffice-" + suffix] for suffix in ("calc", "writer"))
            self.assertEqual(calc["bg_light"], writer["bg_light"])
            self.assertEqual(calc["bg_dark"], writer["bg_dark"])
            self.assertEqual(calc["bg_family"], "libreoffice")
            self.assertNotEqual(calc["source_hash"], writer["source_hash"])

    def test_colored_circular_icon_gets_complementary_tile(self):
        icon = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(icon).ellipse((0, 0, 63, 63), fill="#1D93D8")
        ImageDraw.Draw(icon).polygon(((20, 24), (44, 32), (20, 40)), fill="white")
        self.assertNotEqual(icon_backplates(icon)["dark"], "#1D93D8")

    def test_no_hue_saturation_or_strength_corrections(self):
        icon = Image.new("RGBA", (64, 64), "#C02030")
        corrected, _ = render_adaptive(icon, "fill", {"accent": "#00FF00"}, False,
                                        {"hue_shift": 180, "saturation": 0, "strength": 0})
        self.assertEqual(corrected.getpixel((128, 128))[:3], (192, 32, 48))

    def test_connected_background_preserves_internal_white(self):
        from PIL import ImageDraw
        image = Image.new("RGBA", (64, 64), "white")
        draw = ImageDraw.Draw(image)
        draw.rectangle((10, 10, 54, 54), fill="blue")
        draw.rectangle((25, 25, 38, 38), fill="white")
        output = remove_border_background(image)
        self.assertIsNotNone(output)
        self.assertEqual(output.getpixel((0, 0))[3], 0)
        self.assertEqual(output.getpixel((30, 30))[3], 255)

    def test_source_and_presentation_invalidate_artwork_cache(self):
        self.assertNotEqual(source_key(b"a", "", "fit"), source_key(b"a", "", "fill"))
        self.assertNotEqual(source_key(b"a", "", "fit"), source_key(b"b", "", "fit"))

    def test_identity_overrides_and_atomic_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            apps = root / "applications"
            apps.mkdir()
            image = root / "icon.png"
            Image.new("RGBA", (40, 70), "blue").save(image)
            (apps / "org.test.Sample.desktop").write_text(
                "[Desktop Entry]\nName=Sample\nIcon=" + str(image) + "\nExec=sample\n"
                "[Desktop Action Open]\nName=Wrong\nIcon=application-exit\n")
            cache = root / "cache"
            entries = build(cache, root / "missing-theme", {"org.test.Sample": {"presentation": "fit"}},
                            [apps])
            self.assertEqual(entries["org.test.Sample.desktop"]["name"], "Sample")
            self.assertEqual(entries["org.test.Sample"]["presentation"], "fit")
            self.assertTrue((cache / "app_icons_meta.json").is_file())
            self.assertEqual(len(list((cache / "adaptive").glob("*.png"))), 3)


if __name__ == "__main__":
    unittest.main()
