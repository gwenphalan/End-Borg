import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from PIL import Image, ImageDraw
from adaptive_icon_policy import (choose_background, classify, contain, contrast_surface, extend_rounded_square, full_bleed_tile, trim_visible,
                                  harmonize_color, harmonize_fit, remove_border_background, source_key, theme_colors)
from process_all_icons import build, harmonize_families, metadata_for, themed_icon


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
            self.assertEqual(metadata_for("test-game", desktop, colors, "theme", root, {})["presentation"], "fill")
            self.assertEqual(metadata_for("ASTRONEER", desktop, colors, "theme", root, {})["presentation"], "fill")
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
    def test_background_tracks_theme_and_contrasts_with_glyph(self):
        image = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(image).ellipse((8, 8, 55, 55), fill="#707070")
        plum = choose_background(image, {"primary": "#573A70", "neutral": "#2C292E"})
        green = choose_background(image, {"primary": "#286E51", "neutral": "#282E2B"})
        self.assertNotEqual(plum[0], green[0])
        for color, _ in (plum, green):
            self.assertGreater(max(abs(int(color[i:i + 2], 16) - 112) for i in (1, 3, 5)), 35)
    def test_theme_resolution_is_exact_and_path_bounded(self):
        self.assertIsNotNone(themed_icon(("blender",)))
        self.assertIsNone(themed_icon(("../../private",)))

    def test_monochrome_symbol_gets_visible_tint_without_alpha_damage(self):
        image = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(image).ellipse((12, 12, 52, 52), fill=(190, 190, 190, 255))
        recolored = harmonize_fit(image, {"primary": "#D080E0", "neutral": "#242430"})
        self.assertEqual(recolored.getpixel((0, 0))[3], 0)
        self.assertNotEqual(recolored.getpixel((32, 32))[:3], image.getpixel((32, 32))[:3])
    def test_theme_accent_changes_white_symbol_without_recoloring_brand(self):
        white = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(white).ellipse((8, 8, 55, 55), fill="white")
        colors = {"primary": "#573A70", "accent": "#DCB9F8", "neutral": "#2C292E"}
        output = harmonize_fit(white, colors)
        self.assertEqual(output.getpixel((0, 0)), white.getpixel((0, 0)))
        self.assertGreater(output.getpixel((32, 32))[2], output.getpixel((32, 32))[1])
        brand = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(brand).ellipse((8, 8, 55, 55), fill="#EE301A")
        self.assertEqual(harmonize_fit(brand, colors).tobytes(), brand.tobytes())

    def test_background_keeps_dark_icons_legible_and_palette_cohesive(self):
        colors = {"primary": "#573A70", "secondary": "#4E4256",
                  "tertiary": "#653A40", "neutral": "#2C292E", "accent": "#DCB9F8"}
        dark = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(dark).ellipse((8, 8, 55, 55), fill="#17131B")
        light = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(light).ellipse((8, 8, 55, 55), fill="#EEE1F2")
        dark_bg, _ = choose_background(dark, colors)
        light_bg, _ = choose_background(light, colors)
        self.assertGreater(sum(bytes.fromhex(dark_bg[1:])), sum(bytes.fromhex(light_bg[1:])))
        self.assertNotEqual(dark_bg, colors["accent"])

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
        self.assertEqual(classify(Image.new("RGB", (100, 100), "red"))[0], "fill")
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
        entries = {name: {"app_id": name, "is_game": False, "bg_role": "neutral",
                          "bg_color": "#2C292E"} for name in
                   ("libreoffice-calc", "libreoffice-writer", "libreoffice-impress")}
        other = {"app_id": "other", "is_game": False, "bg_role": "neutral", "bg_color": "#2C292E"}
        entries["other"] = other
        colors = {"secondary": "#4E4256", "neutral": "#2C292E",
                  "accent": "#DCB9F8", "drawer": "#221E24"}
        harmonize_families(entries, colors)
        self.assertTrue(all(entries[name]["bg_color"] == contrast_surface(
                                colors["secondary"], colors["drawer"], colors["accent"])
                            for name in ("libreoffice-calc", "libreoffice-writer", "libreoffice-impress")))
        self.assertNotEqual(entries["libreoffice-calc"]["bg_color"], colors["secondary"])
        self.assertEqual(other["bg_color"], "#2C292E")

    def test_colored_circular_icon_gets_distinct_drawer_tile(self):
        icon = Image.new("RGBA", (64, 64))
        ImageDraw.Draw(icon).ellipse((0, 0, 63, 63), fill="#1D93D8")
        ImageDraw.Draw(icon).polygon(((20, 24), (44, 32), (20, 40)), fill="white")
        colors = {"primary": "#573A70", "secondary": "#4E4256",
                  "tertiary": "#653A40", "neutral": "#2C292E"}
        self.assertNotEqual(choose_background(icon, colors)[0], colors["neutral"])

    def test_five_color_logos_rotate_together_and_six_color_art_is_preserved(self):
        import colorsys
        colors = {"accent": "#DCB9F8"}
        def stripes(count):
            icon = Image.new("RGBA", (60, 60))
            for index in range(count):
                hue = (index * (3 if count == 5 else 2) + .5) / 16
                rgb = tuple(round(c * 255) for c in colorsys.hsv_to_rgb(hue, .85, .9))
                ImageDraw.Draw(icon).rectangle((index * 10, 0, index * 10 + 9, 59),
                                               fill=rgb + (255,))
            return icon
        five = stripes(5)
        corrected = harmonize_color(five, colors)
        self.assertEqual(corrected.getchannel("A").tobytes(), five.getchannel("A").tobytes())
        self.assertTrue(all(corrected.getpixel((i * 10 + 5, 30)) != five.getpixel((i * 10 + 5, 30))
                            for i in range(5)))
        six = stripes(6)
        self.assertEqual(harmonize_color(six, colors).tobytes(), six.tobytes())

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

    def test_alpha_and_brand_signature(self):
        icon = Image.new("RGBA", (8, 8), (240, 30, 30, 135))
        output = harmonize_fit(icon, {"neutral": "#424250", "primary": "#3030D0"})
        self.assertEqual(output.getpixel((0, 0)), icon.getpixel((0, 0)))

    def test_theme_and_source_invalidate_cache(self):
        self.assertNotEqual(source_key(b"a", "dark", "fit"), source_key(b"a", "light", "fit"))
        self.assertNotEqual(source_key(b"a", "dark", "fit"), source_key(b"b", "dark", "fit"))
        with tempfile.TemporaryDirectory() as folder:
            theme = Path(folder) / "colors.json"
            theme.write_text(json.dumps({"primary_container": "#112233", "secondaryContainer": "#667788"}))
            self.assertEqual(theme_colors(theme)["primary"], "#112233".upper())
            self.assertEqual(theme_colors(Path(folder) / "absent")["neutral"], "#40404A")

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
            self.assertEqual(len(list((cache / "adaptive").glob("*.png"))), 1)


if __name__ == "__main__":
    unittest.main()
