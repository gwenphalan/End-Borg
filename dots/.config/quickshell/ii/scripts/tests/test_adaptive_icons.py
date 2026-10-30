import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import process_all_icons as builder
from adaptive_icon_policy import (backplate_decision, classify, compose_icon, contain,
                                  extend_exterior_edges, icon_backplates, render_adaptive,
                                  source_key, squircle_mask, trim_visible, _luminance)
from icon_geometry import analyze_geometry, decorative_frame, fit_layout, optical_layout, tile_layers


def shape(kind="circle", color="#2490C0"):
    image = Image.new("RGBA", (256, 256))
    draw = ImageDraw.Draw(image)
    if kind == "circle":
        draw.ellipse((0, 0, 255, 255), fill=color)
    elif kind == "tile":
        draw.rounded_rectangle((0, 0, 255, 255), radius=90, fill=color)
    elif kind == "triangle":
        draw.polygon(((0, 0), (255, 128), (0, 255)), fill=color)
    elif kind == "folder":
        draw.rectangle((0, 70, 255, 255), fill=color)
        draw.rectangle((0, 45, 90, 80), fill=color)
    return image


class GeometryTests(unittest.TestCase):
    def test_fit_layout_adds_a_modest_inset(self):
        _, original = optical_layout(shape())
        _, padded = fit_layout(shape())
        self.assertAlmostEqual(padded["scale"] / original["scale"], .95, delta=.01)
        self.assertEqual(padded["padding_scale"], .95)

    def test_uniform_near_square_substrate_can_be_rebuilt_as_square(self):
        image = Image.new("RGBA", (224, 204), "#3F3F3F")
        ImageDraw.Draw(image).rectangle((80, 40, 145, 165), fill="#CC2222")
        self.assertEqual(classify(image)[0], "extend")
        output, _ = render_adaptive(image, "extend")
        self.assertEqual(output.getpixel((128, 0)), (63, 63, 63, 255))
    def test_simple_tile_mark_is_optically_fitted_on_native_substrate(self):
        image = Image.new("RGBA", (256, 256), "#F4EEDD")
        draw = ImageDraw.Draw(image)
        draw.ellipse((65, 65, 190, 190), fill="#D43E18")
        draw.ellipse((96, 96, 159, 159), fill="#F4EEDD")
        foreground, substrate, detail = tile_layers(image)
        self.assertEqual(substrate, (244, 238, 221))
        self.assertEqual(foreground.getpixel((128, 128))[3], 0)
        self.assertGreater(detail["background_fraction"], .45)
        self.assertEqual(classify(image)[0], "extend")
        output, presentation = render_adaptive(image, classify(image)[0])
        self.assertEqual(presentation, "extend")
        self.assertEqual(output.getpixel((128, 0)), (244, 238, 221, 255))
        self.assertEqual(output.getpixel((128, 128)), (244, 238, 221, 255))
        expected = Image.new("RGBA", (256, 256), substrate + (255,))
        expected.alpha_composite(fit_layout(foreground)[0])
        self.assertEqual(output.tobytes(), expected.tobytes())

    def test_extracted_glyph_uses_same_inset_without_padding_background(self):
        image = Image.new("RGBA", (256, 256), "#303030")
        ImageDraw.Draw(image).ellipse((80, 60, 175, 195), fill="#EEEEEE")
        foreground, substrate, _ = tile_layers(image)
        expected = Image.new("RGBA", (256, 256), substrate + (255,))
        expected.alpha_composite(fit_layout(foreground)[0])
        actual, _ = render_adaptive(image, classify(image)[0])
        self.assertEqual(actual.tobytes(), expected.tobytes())
        self.assertEqual(actual.getpixel((128, 0)), substrate + (255,))
        self.assertEqual(actual.getpixel((0, 128)), substrate + (255,))
        self.assertAlmostEqual(fit_layout(foreground)[1]["scale"] /
                               optical_layout(foreground)[1]["scale"], .95, delta=.01)

    def test_detailed_cover_with_uniform_border_is_not_segmented(self):
        image = Image.new("RGBA", (256, 256), "#101010")
        pixels = np.array(image)
        pixels[32:224, 32:224, :3] = np.random.default_rng(15).integers(
            0, 256, size=(192, 192, 3), dtype=np.uint8)
        image = Image.fromarray(pixels)
        self.assertIsNone(tile_layers(image))
        self.assertEqual(classify(image)[0], "fill")
        output, presentation = render_adaptive(image, "fill")
        self.assertEqual(presentation, "fill")
        self.assertEqual(output.tobytes(), image.tobytes())

    def test_uniform_tile_has_no_invented_foreground(self):
        self.assertIsNone(tile_layers(Image.new("RGBA", (256, 256), "#303030")))
    def test_extracted_matte_reconstructs_native_colors_and_subtle_accents(self):
        image = Image.new("RGBA", (256, 256), "#505050")
        draw = ImageDraw.Draw(image)
        draw.rectangle((80, 80, 175, 175), fill="#D09070")
        draw.rectangle((60, 110, 70, 140), fill="#555555")
        foreground, substrate, _ = tile_layers(image)
        rebuilt = Image.new("RGBA", image.size, substrate + (255,))
        rebuilt.alpha_composite(foreground)
        self.assertLessEqual(np.max(np.abs(np.array(rebuilt).astype(int)
                                          - np.array(image).astype(int))), 1)
        self.assertGreater(foreground.getpixel((65, 120))[3], 0)
        self.assertEqual(optical_layout(foreground)[1]["alpha_bounds"][0], 0)

    def test_edge_connected_meaningful_stroke_is_not_deleted(self):
        image = Image.new("RGBA", (256, 256), "#505050")
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 100, 70, 108), fill="white")
        draw.ellipse((90, 90, 165, 165), fill="white")
        self.assertIsNone(tile_layers(image))

    def test_textured_background_flecks_do_not_set_glyph_bounds(self):
        pixels = np.full((256, 256, 4), (80, 80, 80, 255), dtype=np.uint8)
        pixels[::3, ::3, :3] = 85
        pixels[80:176, 80:176, :3] = 240
        pixels[10:12, 50:52, :3] = 112
        foreground, _, detail = tile_layers(Image.fromarray(pixels))
        self.assertFalse(detail["flat_substrate"])
        self.assertEqual(foreground.getchannel("A").getbbox(), (78, 78, 178, 178))

    def test_low_palette_high_frequency_cover_is_not_segmented(self):
        pixels = np.full((256, 256, 4), (16, 16, 16, 255), dtype=np.uint8)
        checker = np.indices((192, 192)).sum(axis=0) % 2 == 0
        pixels[32:224, 32:224, :3][checker] = (240, 240, 240)
        image = Image.fromarray(pixels)
        self.assertIsNone(tile_layers(image))
        output, _ = render_adaptive(image, classify(image)[0])
        self.assertEqual(output.tobytes(), image.tobytes())

    def test_tile_rim_does_not_become_foreground(self):
        image = Image.new("RGBA", (256, 256), "#505050")
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 0, 255, 2), fill="#777777")
        draw.rectangle((100, 90, 155, 165), fill="white")
        foreground, _, _ = tile_layers(image)
        self.assertEqual(foreground.getchannel("A").getbbox(), (100, 90, 156, 166))

    def test_translucent_tile_substrate_is_not_replaced_with_artwork(self):
        pixels = np.full((256, 256, 4), (60, 70, 80, 190), dtype=np.uint8)
        pixels[48:208, 48:208, :3] = np.random.default_rng(2).integers(
            0, 256, size=(160, 160, 3), dtype=np.uint8)
        pixels[48:208, 48:208, 3] = 255
        image = Image.fromarray(pixels)
        output, _ = render_adaptive(image, classify(image)[0])
        self.assertEqual(output.getpixel((128, 20)), (60, 70, 80, 190))
    def test_opaque_square_fills(self):
        self.assertEqual(classify(Image.new("RGBA", (256, 256), "red"))[0], "fill")

    def test_broad_concave_object_is_not_a_square_tile(self):
        image = Image.new("RGBA", (256, 256))
        draw = ImageDraw.Draw(image)
        draw.rectangle((24, 0, 231, 100), fill="white")
        draw.rectangle((0, 64, 255, 255), fill="#808080")
        self.assertEqual(classify(image)[0], "fit")
        self.assertGreater(analyze_geometry(image)["convexity_deficit"], .01)
    def test_rectangular_objects_fit_even_when_mostly_solid(self):
        for dimensions in ((224, 208), (208, 228)):
            image = Image.new("RGBA", dimensions)
            ImageDraw.Draw(image).rounded_rectangle(
                (0, 0, dimensions[0] - 1, dimensions[1] - 1), radius=10, fill="#707070")
            self.assertEqual(classify(image)[0], "fit")

    def test_low_alpha_threshold_is_safe(self):
        for alpha in (0, 7, 8, 9):
            image = Image.new("RGBA", (32, 32), (50, 60, 70, alpha))
            output, _ = optical_layout(image)
            self.assertEqual(output.size, (256, 256))

    def test_translucent_framed_tile_ignores_soft_shadow(self):
        image = Image.new("RGBA", (256, 256), (0, 0, 0, 12))
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((10, 25, 245, 244), radius=25, fill="white")
        draw.rounded_rectangle((15, 30, 240, 239), radius=20, fill=(25, 25, 25, 190))
        draw.rectangle((85, 85, 160, 180), fill="#00BBDD")
        self.assertIsNotNone(decorative_frame(image))
        self.assertEqual(classify(image)[0], "extend")

    def test_rounded_solid_tile_extends(self):
        image = shape("tile")
        self.assertEqual(classify(image)[0], "extend")
        output, presentation = render_adaptive(image, "extend")
        self.assertEqual(presentation, "extend")
        self.assertEqual(output.getpixel((0, 0)), (36, 144, 192, 255))
        self.assertEqual(output.getpixel((128, 128)), image.getpixel((128, 128)))

    def test_circles_folders_and_rectangles_fit(self):
        for image in (shape(), shape("folder"), Image.new("RGBA", (60, 120), "red")):
            self.assertEqual(classify(image)[0], "fit")
            self.assertFalse(analyze_geometry(image)["is_tile"])

    def test_multicolor_tile_does_not_need_uniform_rim(self):
        image = shape("tile")
        ImageDraw.Draw(image).rectangle((0, 64, 255, 191), fill="#D02050")
        self.assertEqual(classify(image)[0], "extend")

    def test_outline_is_not_a_tile(self):
        image = Image.new("RGBA", (256, 256))
        ImageDraw.Draw(image).rounded_rectangle((0, 0, 255, 255), radius=28, outline="white", width=5)
        self.assertEqual(classify(image)[0], "fit")
        self.assertIsNone(decorative_frame(image))

    def test_decorative_frame_cropped_only_over_solid_substrate(self):
        image = Image.new("RGBA", (256, 256))
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((0, 0, 255, 255), radius=28, fill="white")
        draw.rounded_rectangle((5, 5, 250, 250), radius=24, fill="#202020")
        draw.rectangle((95, 80, 160, 170), fill="#00AABB")
        frame = decorative_frame(image)
        self.assertIsNotNone(frame)
        output, _ = render_adaptive(image, classify(image)[0])
        self.assertLess(max(output.getpixel((128, 0))[:3]), 70)

    def test_broad_border_is_preserved(self):
        image = Image.new("RGBA", (256, 256), "white")
        ImageDraw.Draw(image).rectangle((24, 24, 231, 231), fill="#202020")
        self.assertIsNone(decorative_frame(image))

    def test_exterior_extension_preserves_enclosed_holes(self):
        image = shape("tile")
        ImageDraw.Draw(image).ellipse((95, 95, 160, 160), fill=(0, 0, 0, 0))
        output = extend_exterior_edges(image)
        self.assertEqual(output.getpixel((128, 128))[3], 0)
        self.assertEqual(output.getpixel((0, 0))[3], 255)

    def test_circle_keyline_larger_than_square(self):
        _, circle = optical_layout(shape())
        _, square = optical_layout(Image.new("RGBA", (256, 256), "red"))
        self.assertGreater(circle["scale"], square["scale"] + .05)

    def test_symmetric_shapes_stay_centered(self):
        _, layout = optical_layout(shape())
        np.testing.assert_allclose(layout["placement_center"], [128, 128], atol=.5)

    def test_asymmetric_mass_has_bounded_optical_correction(self):
        _, layout = optical_layout(shape("triangle"))
        self.assertLess(layout["placement_center"][0], 127)
        self.assertGreaterEqual(layout["placement_center"][0], 118)
        self.assertLessEqual(layout["placement_center"][1], 138)

    def test_shadow_has_less_weight_than_main_body(self):
        image = Image.new("RGBA", (256, 256))
        draw = ImageDraw.Draw(image)
        draw.rectangle((40, 40, 200, 200), fill="red")
        draw.rectangle((201, 40, 250, 200), fill=(0, 0, 0, 12))
        _, layout = optical_layout(image)
        self.assertLess(layout["visual_centroid"][0], 128)
        self.assertLess(layout["robust_bounds"][2], 256)

    def test_meaningful_pixels_stay_inside_squircle(self):
        for image in (shape("triangle"), shape(), shape("folder")):
            output, layout = optical_layout(image)
            alpha = np.asarray(output.getchannel("A"))
            mask = np.asarray(squircle_mask())
            self.assertFalse(np.any((alpha > 8) & (mask < 250)), layout)

    def test_transparent_image_is_safe(self):
        image = Image.new("RGBA", (256, 256))
        self.assertEqual(classify(image)[0], "fit")
        output, layout = optical_layout(image)
        self.assertIsNone(output.getbbox())
        self.assertEqual(layout["method"], "empty")

    def test_trim_and_contain_preserve_aspect(self):
        original = Image.new("RGBA", (60, 120), "red")
        self.assertEqual(contain(original).getchannel("A").getbbox(), (64, 0, 192, 256))
        image = Image.new("RGBA", (100, 100))
        ImageDraw.Draw(image).rectangle((20, 20, 79, 79), fill="blue")
        self.assertEqual(trim_visible(image).size, (60, 60))

    def test_mask_applies_to_all_presentations(self):
        for presentation in ("fit", "fill", "extend"):
            image = compose_icon(Image.new("RGBA", (256, 256), "red"), "#303030", presentation)
            self.assertEqual(image.getpixel((0, 0))[3], 0)
            self.assertEqual(image.getpixel((128, 128))[3], 255)

    def test_cache_key_tracks_presentation_and_bytes(self):
        self.assertNotEqual(source_key(b"a", "", "fit"), source_key(b"a", "", "fill"))
        self.assertNotEqual(source_key(b"a", "", "fit"), source_key(b"b", "", "fit"))


class BackgroundTests(unittest.TestCase):
    def test_all_backgrounds_are_neutral_and_deterministic(self):
        for color in ("#003F20", "#21AC80", "#324F9B", "#B0B0B0", "white", "black"):
            image = shape(color=color)
            result = icon_backplates(image)
            self.assertEqual(result, icon_backplates(image))
            for background in result.values():
                channels = bytes.fromhex(background[1:])
                self.assertEqual(min(channels), max(channels))

    def test_dark_green_gets_high_luminance_separation(self):
        image = shape(color="#006331")
        for mode in ("light", "dark"):
            decision = backplate_decision([image], mode)
            self.assertGreaterEqual(decision["contrast_p10"], decision["contrast_target"])
            self.assertTrue(decision["target_met"])

    def test_white_artwork_escapes_light_mode_surface(self):
        result = backplate_decision([shape(color="white")], "light")
        self.assertGreaterEqual(result["contrast_p10"], 3)
        self.assertLess(_luminance(tuple(bytes.fromhex(result["color"][1:]))), .3)
    def test_background_cannot_disappear_on_dark_launcher(self):
        for color in ("#0040FF", "#00CCDD", "#EED020", "white", "black"):
            decision = backplate_decision([shape(color=color)], "dark")
            rgb = tuple(bytes.fromhex(decision["color"][1:]))
            self.assertGreaterEqual((_luminance(rgb) + .05) / (_luminance((32, 32, 37)) + .05), 2.2)

    def test_dark_backplates_never_escape_to_bright_white(self):
        for color in ("black", "white", "#00CCDD", "#006331", "#A05040"):
            channels = bytes.fromhex(backplate_decision([shape(color=color)], "dark")["color"][1:])
            self.assertGreaterEqual(min(channels), 88)
            self.assertLessEqual(max(channels), 160)

    def test_no_artwork_recoloring(self):
        image = shape(color="#C02030")
        output, _ = render_adaptive(image, "fit", {"accent": "#00FF00"}, False,
                                    {"hue_shift": 180, "saturation": 0})
        self.assertEqual(output.getpixel((128, 128))[:3], (192, 32, 48))


class BuilderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apps = self.root / "applications"
        self.apps.mkdir()
        self.cache = self.root / "cache"
        self.image = self.root / "source.png"
        shape().save(self.image)
        self.enterContext(patch.object(builder, "DEFAULT_CACHE", self.root / "live-cache"))
        self.enterContext(patch.object(builder, "APP_THEME", self.root / "absent-theme/64x64/apps"))
        self.enterContext(patch.object(builder, "Gtk", None))

    def desktop(self, app_id, extra="", icon=None, name="Sample"):
        path = self.apps / (app_id + ".desktop")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"[Desktop Entry]\nName={name}\nIcon={icon or self.image}\n{extra}")
        return path

    def build(self):
        return builder.build(self.cache, directories=[self.apps])
    def install_generic_sources(self):
        builder.APP_THEME.mkdir(parents=True)
        for _, name in builder.GENERIC_FALLBACKS:
            (builder.APP_THEME / (name + ".svg")).write_text(
                '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256">'
                '<circle cx="128" cy="128" r="128" fill="red"/></svg>')

    def test_missing_declared_icon_gets_generic_default(self):
        self.install_generic_sources()
        self.desktop("arbitrary", icon="").write_text("[Desktop Entry]\nName=No Icon\n")
        with patch.object(builder, "load_icon", return_value=shape()):
            entry = self.build()["arbitrary"]
        self.assertEqual(entry["source_selection"]["icon_name"], "application-default-icon")
        self.assertEqual(entry["source_selection"]["reason"], "no declared icon")
        dictionary = json.loads((self.cache / "icon_dictionary.json").read_text())
        self.assertEqual(len(dictionary["generic_fallback_shortlist"]), 9)

    def test_unresolved_icon_uses_category_not_application_identity(self):
        self.install_generic_sources()
        for app_id in ("random-first", "random-second"):
            self.desktop(app_id, icon="absent", extra="Categories=Utility;Development;\n")
        with patch.object(builder, "load_icon", return_value=shape()):
            entries = self.build()
        self.assertEqual(entries["random-first"]["source_selection"]["icon_name"], "applications-development")
        self.assertEqual(entries["random-first"]["source"], entries["random-second"]["source"])

    def test_terminal_fallback_and_missing_category_icon_use_default(self):
        self.install_generic_sources()
        self.assertEqual(builder.generic_icon({"terminal": "true"})[1]["icon_name"], "utilities-terminal")
        (builder.APP_THEME / "applications-development.svg").unlink()
        self.assertEqual(builder.generic_icon({"categories": "Development;"})[1]["icon_name"],
                         "application-default-icon")

    def test_valid_declared_source_always_beats_generic(self):
        self.install_generic_sources()
        self.desktop("arbitrary", extra="Categories=Development;\n")
        entry = self.build()["arbitrary"]
        self.assertEqual(entry["source"], str(self.image))
        self.assertEqual(entry["source_selection"]["kind"], "declared-icon")

    def test_undecodable_category_generic_falls_through_to_default(self):
        self.install_generic_sources()
        self.desktop("arbitrary", icon="absent", extra="Categories=Development;\n")
        def decode(path):
            if path.stem == "applications-development":
                raise ValueError("simulated corrupt generic")
            return shape()
        with patch.object(builder, "load_icon", side_effect=decode):
            entry = self.build()["arbitrary"]
        self.assertEqual(entry["source_selection"]["icon_name"], "application-default-icon")
        record = json.loads((self.cache / "icon_dictionary.json").read_text())["icons"]["arbitrary"]
        self.assertEqual([attempt["status"] for attempt in record["source_attempts"]],
                         ["failed", "accepted"])

    def test_undecodable_declared_source_uses_generic_and_records_attempts(self):
        self.install_generic_sources()
        self.desktop("arbitrary")
        def decode(path):
            if path == self.image:
                raise ValueError("simulated corrupt source")
            return shape()
        with patch.object(builder, "load_icon", side_effect=decode):
            entry = self.build()["arbitrary"]
        self.assertEqual(entry["source_selection"]["kind"], "generic-papirus-fallback")
        record = json.loads((self.cache / "icon_dictionary.json").read_text())["icons"]["arbitrary"]
        self.assertEqual([attempt["status"] for attempt in record["source_attempts"]],
                         ["failed", "accepted"])

    def test_identity_and_categories_cannot_change_pixels(self):
        for app_id, categories in (("virt-manager", ""), ("org.gnome.FileRoller", "Game;"),
                                    ("arbitrary-new-app", "Utility;")):
            self.desktop(app_id, "Categories=" + categories + "\n")
        entries = self.build()
        values = [entries[key] for key in ("virt-manager", "org.gnome.FileRoller", "arbitrary-new-app")]
        self.assertEqual(len({entry["path_dark"] for entry in values}), 1)
        self.assertEqual(len({entry["presentation"] for entry in values}), 1)

    def test_legacy_hints_have_no_effect(self):
        self.desktop("sample")
        plain = self.build()["sample"]
        hinted = builder.build(self.cache, None, {"sample": {"presentation": "fill",
                                                             "alternate_icon": "unrelated"}},
                               [self.apps])["sample"]
        self.assertEqual(plain, hinted)

    def test_extracted_glyph_dictionary_matches_rendered_inset(self):
        image = Image.new("RGBA", (256, 256), "#303030")
        ImageDraw.Draw(image).ellipse((80, 60, 175, 195), fill="#EEEEEE")
        image.save(self.image)
        self.desktop("sample")
        self.build()
        record = json.loads((self.cache / "icon_dictionary.json").read_text())["icons"]["sample"]
        foreground, _, _ = tile_layers(image)
        self.assertEqual(record["presentation"], "extend")
        self.assertEqual(record["placement"], fit_layout(foreground)[1])
        self.assertEqual(record["placement"]["padding_scale"], .95)

    def test_dictionary_has_one_entry_per_app_and_explicit_failure(self):
        self.desktop("sample")
        self.desktop("missing", icon="/nonexistent/icon.png")
        meta = self.build()
        dictionary = json.loads((self.cache / "icon_dictionary.json").read_text())
        self.assertEqual(set(dictionary["icons"]), {"sample", "missing"})
        record = dictionary["icons"]["sample"]
        for field in ("measurements", "backgrounds", "placement", "reason", "outputs", "source_hash",
                      "foreground_analysis"):
            self.assertIn(field, record)
        self.assertEqual(dictionary["icons"]["missing"]["status"], "failed")
        self.assertEqual(meta["sample"]["name"], "Sample")
        self.assertTrue(Path(record["outputs"]["dark"]).is_file())

    def test_repeat_build_is_byte_stable(self):
        self.desktop("sample")
        self.build()
        before = (self.cache / "icon_dictionary.json").read_bytes()
        self.build()
        self.assertEqual(before, (self.cache / "icon_dictionary.json").read_bytes())

    def test_staging_recovers_live_managed_original(self):
        path = self.desktop("sample")
        original = path.read_text()
        live = builder.DEFAULT_CACHE
        live.mkdir()
        (live / "global-icons.json").write_text(json.dumps({"sample": {
            "original": original, "source": str(path)}}))
        path.write_text(builder.MANAGED_MARKER + "\n[Desktop Entry]\nName=Sample\nIcon=quickshell-generated-sample\n")
        self.assertEqual(self.build()["sample"]["source"], str(self.image))

    def test_unrecoverable_managed_entry_cannot_recurse(self):
        self.desktop("sample", icon="quickshell-generated-sample").write_text(
            builder.MANAGED_MARKER + "\n[Desktop Entry]\nName=Sample\nIcon=quickshell-generated-sample\n")
        self.assertEqual(self.build(), {})

    def test_generated_source_symlink_is_rejected(self):
        generated = self.root / "quickshell-generated-test.png"
        shape().save(generated)
        link = self.root / "innocent.png"
        link.symlink_to(generated)
        self.assertIsNone(builder.resolve_icon(str(link)))

    def test_shared_alias_does_not_override_canonical_identity(self):
        self.desktop("sample", name="shared")
        self.desktop("other", name="sample")
        self.desktop("third", name="shared")
        meta = self.build()
        self.assertEqual(meta["sample"]["app_id"], "sample")
        self.assertNotIn("shared", meta)
        self.assertNotIn(str(self.image), meta)

    def test_flatpak_style_xdg_icon_and_desktop_discovery(self):
        root = self.root / "exports/share"
        apps = root / "applications"
        apps.mkdir(parents=True)
        (apps / "org.test.App.desktop").write_text("[Desktop Entry]\nName=App\nIcon=org.test.App\n")
        icons = root / "icons/hicolor/256x256/apps"
        icons.mkdir(parents=True)
        shape().save(icons / "org.test.App.png")
        with patch.dict(os.environ, {"XDG_DATA_DIRS": str(root),
                                      "XDG_DATA_HOME": str(self.root / "home-share")}):
            self.assertIn(apps, builder.application_directories())
            self.assertEqual(builder.resolve_icon("org.test.App"), icons / "org.test.App.png")
            self.assertIn("org.test.App", builder.build(self.cache))

    def test_nested_desktop_id_and_hidden_precedence(self):
        self.desktop("nested/app")
        self.desktop("hidden", extra="Hidden=true\n")
        meta = self.build()
        self.assertIn("nested-app", meta)
        self.assertNotIn("hidden", meta)

    def test_legacy_null_paths_do_not_abort(self):
        self.cache.mkdir()
        (self.cache / "app_icons_meta.json").write_text(json.dumps({"missing": {"path": None}}))
        self.desktop("missing", icon="/not-an-icon.png")
        self.assertEqual(self.build(), {})

    def test_resolution_rejects_path_traversal(self):
        self.assertIsNone(builder.resolve_icon("../../private"))
        self.assertIsNone(builder.themed_icon(("../../private",)))
    def test_unrelated_theme_identity_cannot_override_declared_icon(self):
        theme = builder.APP_THEME
        theme.mkdir(parents=True)
        (theme / "identity-special.svg").write_text("<svg/>")
        with patch.object(builder, "resolve_icon", return_value=self.image):
            first = builder.metadata_for("identity-special", {"icon": "declared"}, {}, "",
                                         self.cache, {})
            second = builder.metadata_for("random-identity", {"icon": "declared"}, {}, "",
                                          self.cache, {})
        self.assertEqual(first["source"], second["source"])
        self.assertEqual(first["path_dark"], second["path_dark"])

    def test_failed_canonical_id_is_not_a_descriptive_alias(self):
        self.desktop("broken", icon="/absent.png")
        self.desktop("success", name="broken")
        self.assertNotIn("broken", self.build())

    def test_lowercase_alias_cannot_steal_failed_case_distinct_identity(self):
        self.desktop("App")
        self.desktop("app", icon="/absent.png")
        meta = self.build()
        self.assertIn("App", meta)
        self.assertNotIn("app", meta)
        self.assertNotIn("app.desktop", meta)

    def test_duplicate_flatpak_root_retains_xdg_precedence(self):
        flatpak = Path("/var/lib/flatpak/exports/share")
        with patch.dict(os.environ, {"XDG_DATA_DIRS": str(flatpak) + ":/usr/share"}):
            roots = builder.data_roots()
            self.assertGreater(roots.index(flatpak), roots.index(Path("/usr/share")))
            self.assertEqual(roots.count(flatpak), 1)

    def test_current_staging_artwork_is_never_a_source(self):
        adaptive = self.cache / "adaptive"
        adaptive.mkdir(parents=True)
        generated = adaptive / "cached.png"
        shape().save(generated)
        self.desktop("bad", icon=str(generated))
        self.assertNotIn("bad", self.build())

    def test_user_edited_managed_icon_is_respected(self):
        path = self.desktop("sample")
        original = path.read_text()
        rendered = builder.MANAGED_MARKER + "\n" + original
        live = builder.DEFAULT_CACHE
        live.mkdir()
        (live / "global-icons.json").write_text(json.dumps({"sample": {
            "original": original, "source": str(path), "rendered": rendered}}))
        alternate = self.root / "custom.png"
        shape(color="red").save(alternate)
        path.write_text(rendered.replace(str(self.image), str(alternate)))
        self.assertEqual(self.build()["sample"]["source"], str(alternate))


if __name__ == "__main__":
    unittest.main()
