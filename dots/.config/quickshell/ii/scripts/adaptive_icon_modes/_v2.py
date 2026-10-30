"""Approved V3 dependency extracted from synthesis-v2/candidate.py."""


from functools import lru_cache

import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion

from adaptive_icon_policy import compose_icon, squircle_mask
from .lab_support import fit_layout, luminance, oklab
from . import _badge, _native_v2


SIZES = (16, 24, 32, 48, 64)

SURFACES = {
    "light": ("#FFFFFF", "#F2F1F5", "#E6E5EB", "#E8EEF4"),
    "dark": ("#121216", "#202025", "#303038", "#242B35"),
}

def rgb(color):
    return np.array([int(color[i:i + 2], 16) for i in (1, 3, 5)], dtype=float)

@lru_cache(maxsize=1024)
def outer_quality(color, mode):
    tile = Image.new("RGBA", (256, 256), tuple(int(x) for x in color) + (255,))
    tile.putalpha(squircle_mask(256))
    return composed_quality(tile, mode)

def composed_quality(tile, mode):
    """Same mask-before-RGBA-resize path as the independently audited PNG."""
    if mode not in SURFACES:
        raise ValueError("Invalid mode")
    distances, contrasts = [], []
    for size in SIZES:
        pixels = np.asarray(tile.resize((size, size), Image.Resampling.LANCZOS))
        alpha = pixels[:, :, 3].astype(float) / 255
        solid = alpha >= .98
        contour = solid & ~binary_erosion(solid)
        for value in SURFACES[mode]:
            surface = rgb(value)
            displayed = pixels[:, :, :3] * alpha[:, :, None] + surface * (1 - alpha[:, :, None])
            delta = np.linalg.norm(oklab(displayed) - oklab(surface), axis=2)[contour]
            y, bg = luminance(displayed)[contour], luminance(surface)
            ratios = (np.maximum(y, bg) + .05) / (np.minimum(y, bg) + .05)
            distances.append(float(np.percentile(delta, 10)))
            contrasts.append(float(np.percentile(ratios, 10)))
    distance, contrast = min(distances), min(contrasts)
    return {
        "minimum_oklab_distance": distance,
        "minimum_luminance_contrast": contrast,
        "adequate": bool(distance >= .06 and contrast >= 1.20),
        "measurement": "actual mask-before-resize RGBA contour, 16/24/32/48/64",
    }

def render_variant(image, mode):
    badge_renderer = _badge
    extracted, _ = badge_renderer.extract_outlined_badge(image)
    if extracted is not None:
        badge = badge_renderer.render_variant(image, mode)
        badge["diagnostics"] = {
            "system": "visibility-first-v2", "chosen_method": "extract-fit-edge-fill",
            "reason": "proven outlined badge; corrected structural pipeline",
            "badge": badge["diagnostics"], "geometry_changed": True,
        }
        return badge
    native = _native_v2.render_variant(image, mode)
    native["diagnostics"] = {
        "system": "visibility-first-v2",
        "chosen_method": native["diagnostics"].get("chosen_method", "native"),
        "reason": native["diagnostics"].get("reason", ""),
        "native": native["diagnostics"], "geometry_changed": False,
    }
    return native

def glyph_quality(placed, before, after):
    """Separate glyph-boundary readability from the outer container boundary."""
    pixels = np.asarray(placed)
    alpha = pixels[:, :, 3].astype(float) / 255
    solid = alpha > .8
    boundary = solid & ~binary_erosion(solid, iterations=2)
    if not boundary.any():
        boundary = alpha > .15
    if not boundary.any():
        return {"eligible": True, "empty": True}
    colors = pixels[:, :, :3][boundary]
    old = np.linalg.norm(oklab(colors) - oklab(before), axis=1)
    new = np.linalg.norm(oklab(colors) - oklab(after), axis=1)
    old_p10, new_p10 = np.percentile(old, 10), np.percentile(new, 10)
    old_mean, new_mean = old.mean(), new.mean()
    retention = []
    for size in SIZES:
        small = np.asarray(placed.resize((size, size), Image.Resampling.LANCZOS))
        a = small[:, :, 3].astype(float) / 255
        x = small[:, :, :3] * a[:, :, None] + before * (1 - a[:, :, None])
        y = small[:, :, :3] * a[:, :, None] + after * (1 - a[:, :, None])
        lx, ly = oklab(x)[:, :, 0], oklab(y)[:, :, 0]
        gx, gy = np.hypot(*np.gradient(lx)), np.hypot(*np.gradient(ly))
        edge = (a > .03) & (a < .99) & (gx > .008)
        retention.append(float(gy[edge].mean() / gx[edge].mean()) if edge.any() else 1.)
    eligible = bool(
        new_p10 >= min(.08, old_p10)
        and (new_p10 >= old_p10 * .55 or new_p10 >= .14)
        and new_mean >= old_mean * .60 and min(retention) >= .60)
    return {
        "eligible": eligible,
        "boundary_distance_p10_before": float(old_p10),
        "boundary_distance_p10_after": float(new_p10),
        "boundary_distance_mean_retention": float(new_mean / max(old_mean, 1e-9)),
        "small_boundary_retention": dict(zip(map(str, SIZES), retention)),
    }

def resolve_container(variant, composed, mode):
    """Inspect actual rendered plate pixels; leave all artwork bytes untouched."""
    result = dict(variant, diagnostics=dict(variant["diagnostics"]))
    if result["presentation"] != "fit":
        return result
    pixels = np.asarray(composed)
    solid = pixels[:, :, 3] >= 250
    contour = solid & ~binary_erosion(solid, iterations=3)
    samples = pixels[:, :, :3][contour].astype(float)
    old = np.median(samples, axis=0)
    uniformity = float(np.mean(np.max(np.abs(samples - old), axis=1) <= 2))
    detail = {
        "source": "actual composed contour pixels; no family or identity inputs",
        "original_rgb": old.tolist(), "uniformity": uniformity,
        "artwork_bytes_preserved": True,
        "original_outer_quality": composed_quality(composed, mode),
    }
    result["diagnostics"]["container"] = detail
    if uniformity < .995 or np.ptp(old) > 3:
        detail.update(decision="preserve", reason="not a proven generated neutral backplate")
        return result
    if detail["original_outer_quality"]["adequate"]:
        detail.update(decision="preserve", reason="existing container already distinguishable")
        return result
    placed = fit_layout(variant["artwork"])[0]
    original = float(old.mean())
    # Closest passing tone wins. Equal original family plates receive the same
    # least-change cap unless a particular mark needs stronger inner contrast.
    trials = []
    for value in sorted(range(64, 233), key=lambda x: (abs(x - original), -x)):
        color = (value,) * 3
        outer = outer_quality(color, mode)
        if not outer["adequate"]:
            continue
        quality = glyph_quality(placed, old, np.array(color, dtype=float))
        trials.append({"rgb": color, "glyph": quality})
        if quality["eligible"]:
            selected = "#" + f"{value:02X}" * 3
            actual = composed_quality(compose_icon(variant["artwork"], selected, "fit"), mode)
            if not actual["adequate"]:
                trials[-1]["rendered_contour_rejected"] = actual
                continue
            result["backplate"] = selected
            detail.update(
                decision="adjust-generated-backplate",
                reason="nearest visible neutral tone passing glyph-boundary retention",
                selected_rgb=color, outer_quality=actual, glyph_quality=quality,
                rejected_count=len(trials) - 1,
            )
            result["diagnostics"]["chosen_method"] = "generated-backplate-only"
            return result
    detail.update(
        decision="preserve-unresolved",
        reason="no tone passes both outer visibility and glyph-boundary safeguards",
        trials=trials,
    )
    return result
