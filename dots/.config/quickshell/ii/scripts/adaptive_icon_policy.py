"""Deterministic, image-only adaptive icon policy. Originals are never modified."""
import hashlib
from functools import lru_cache

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation

from icon_geometry import (analyze_geometry, extend_edges, fit_layout, normalized,
                           prepare_geometry, tile_layers, visible_bounds)

POLICY_VERSION = 32


def trim_visible(image):
    image = image.convert("RGBA")
    bounds = visible_bounds(image)
    return image.crop(bounds) if bounds else image


def contain(image, size=256):
    return normalized(image, size)


def classify(image):
    prepared, geometry, frame = prepare_geometry(image)
    if not geometry["is_tile"]:
        return "fit", .85, "floating silhouette; optical area and visual-mass placement"
    if tile_layers(prepared) is not None:
        return "extend", .9, "simple mark optically fitted on extended native substrate"
    if geometry["aspect_ratio"] > 1.04 and not frame:
        return "fit", .85, "rectangular object; retain silhouette with optical fit"
    if frame:
        return "extend", .9, "thin decorative frame removed from solid tile"
    if geometry["uncovered_squircle_fraction"] > .002:
        return "extend", .9, "solid square tile; native corners need exterior edge extension"
    return "fill", .95, "solid square artwork covers the squircle"


def rounded_tile(image):
    geometry = analyze_geometry(image)
    return geometry["is_tile"] and geometry["opaque_coverage"] < .995


def full_bleed_tile(image):
    return analyze_geometry(image)["is_tile"]


def extend_rounded_square(image):
    prepared, geometry, _ = prepare_geometry(image)
    return extend_edges(prepared) if geometry["is_tile"] else None


def extend_exterior_edges(image):
    return extend_edges(image)


def render_adaptive(image, presentation, colors=None, is_game=False, adjustments=None):
    """Legacy call arguments are inert: only image properties select structure."""
    prepared, geometry, _ = prepare_geometry(image)
    if presentation in ("fill", "extend") and geometry["is_tile"]:
        layers = tile_layers(prepared)
        if layers:
            foreground, substrate, _ = layers
            output = Image.new("RGBA", (256, 256), substrate + (255,))
            output.alpha_composite(fit_layout(foreground)[0])
            return output, "extend"
    if presentation == "extend" and geometry["is_tile"]:
        return extend_edges(prepared), "extend"
    if presentation == "fill" and geometry["is_tile"]:
        return prepared, "fill"
    return normalized(image), "fit"


def _oklab(rgb):
    rgb = np.asarray(rgb, dtype=np.float64) / 255
    linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
    lms = np.cbrt(linear @ np.array([[.4122214708, .5363325363, .0514459929],
                                     [.2119034982, .6806995451, .1073969566],
                                     [.0883024619, .2817188376, .6299787005]]).T)
    return lms @ np.array([[.2104542553, .7936177850, -.0040720468],
                           [1.9779984951, -2.4285922050, .4505937099],
                           [.0259040371, .7827717662, -.8086757660]]).T


def _luminance(rgb):
    rgb = np.asarray(rgb, dtype=np.float64) / 255
    linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
    return linear @ np.array([.2126, .7152, .0722])


def _artwork_regions(image):
    """Opaque boundary pixels matter more than large, unrelated interior areas."""
    rgba = np.asarray(normalized(image, 64))
    alpha = rgba[:, :, 3] > 200
    if not alpha.any():
        return np.empty((0, 3), dtype=np.uint8)
    boundary = alpha & binary_dilation(~alpha, iterations=2)
    boundary[0] |= alpha[0]
    boundary[-1] |= alpha[-1]
    boundary[:, 0] |= alpha[:, 0]
    boundary[:, -1] |= alpha[:, -1]
    pixels = rgba[:, :, :3]
    return np.concatenate((np.repeat(pixels[boundary], 3, axis=0), pixels[alpha][::8]))


def backplate_score(luminances, color):
    background = _luminance(color)
    scores = []
    for foreground in luminances:
        contrast = (np.maximum(foreground, background) + .05) / (
            np.minimum(foreground, background) + .05)
        scores.append(float(np.percentile(contrast, 10)))
    return min(scores) if scores else 0


def backplate_decision(images, mode):
    """Neutral substrates, ranked by low-percentile contrast then surface tone."""
    if mode not in ("light", "dark"):
        raise ValueError("mode must be light or dark")
    regions = [_artwork_regions(image) for image in images]
    regions = [region for region in regions if len(region)]
    luminances = [_luminance(region) for region in regions]
    labs = [_oklab(region) for region in regions]
    candidates = []
    minimum, maximum, preferred, target = (88, 160, 96, 2.2) if mode == "dark" else (104, 249, 232, 3)
    for channel in range(minimum, maximum + 1, 4 if mode == "dark" else 5):
        color = (channel,) * 3
        contrast = backplate_score(luminances, color)
        separation = min((float(np.percentile(
            np.linalg.norm(region - _oklab(color), axis=1), 10)) for region in labs), default=1)
        surface_distance = abs(channel - preferred) / 255
        if mode == "dark":
            score = (.65 * min(contrast / target, 1) + .20 * min(separation / .18, 1)
                     + .15 * (1 - abs(channel - preferred) / (maximum - minimum)),
                     -surface_distance, contrast)
        else:
            score = (min(contrast / target, 1), min(separation / .18, 1),
                     -surface_distance, contrast)
        candidates.append((score, color, contrast, separation))
    _, color, contrast, separation = max(candidates)
    return {"color": "#" + "".join(f"{channel:02X}" for channel in color),
            "method": "neutral-low-percentile-boundary-contrast",
            "contrast_p10": contrast, "perceptual_distance_p10": separation,
            "contrast_target": target, "target_met": contrast >= target,
            "candidate_count": len(candidates),
            "minimum_surface_channel": minimum, "maximum_surface_channel": maximum,
            "preferred_surface_channel": preferred,
            "reason": "contrast target met; prefer mode surface" if contrast >= target
                      else "mixed artwork; bounded neutral surface balances contrast and mode tone"}


def choose_backplate(images, mode):
    return backplate_decision(images, mode)["color"]


def icon_backplates(image):
    return {mode: choose_backplate([image], mode) for mode in ("light", "dark")}


@lru_cache(maxsize=8)
def squircle_mask(size=256, supersample=4):
    """Supersampled exponent-4 superellipse shared with the fit safety envelope."""
    extent = size * supersample
    axis = (np.arange(extent, dtype=np.float32) + .5 - extent / 2) / (extent / 2)
    inside = np.abs(axis[:, None]) ** 4 + np.abs(axis[None, :]) ** 4 <= 1
    return Image.fromarray((inside * 255).astype("uint8"), "L").resize(
        (size, size), Image.Resampling.LANCZOS)


def compose_icon(artwork, backplate, presentation):
    tile = Image.new("RGBA", artwork.size, backplate)
    foreground = fit_layout(artwork, artwork.width)[0] if presentation == "fit" else artwork
    tile.alpha_composite(foreground)
    tile.putalpha(squircle_mask(artwork.width))
    return tile


def source_key(source, theme, presentation):
    return hashlib.sha256(source + theme.encode() + presentation.encode()
                          + str(POLICY_VERSION).encode()).hexdigest()
