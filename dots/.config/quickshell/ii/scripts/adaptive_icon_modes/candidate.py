"""Approved V3 dependency extracted from synthesis-v3/candidate.py."""


import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion

from adaptive_icon_policy import compose_icon
from .lab_support import fit_layout, luminance, oklab
from . import _badge, _v2, native as _native


TONES = (80, 72, 88, 64, 96, 56, 104, 48, 112, 40, 32, 24)

def render_variant(image, mode):
    old = _v2
    if mode == "dark":
        return old.render_variant(image, mode)
    if mode != "light":
        raise ValueError("Invalid mode")
    badge = _badge
    extracted, _ = badge.extract_outlined_badge(image)
    if extracted is not None:
        return old.render_variant(image, mode)
    native = _native.render_variant(image, mode)
    detail = native["diagnostics"]
    native["diagnostics"] = {
        "system": "dark-on-light-v3",
        "chosen_method": detail.get("chosen_method", "native"),
        "reason": detail.get("reason", ""),
        "native": detail, "geometry_changed": False,
    }
    return native

def boundary_quality(placed, tone):
    """Measure mark against its container independently of launcher separation."""
    arr = np.asarray(placed)
    alpha = arr[:, :, 3].astype(float) / 255
    solid = alpha > .85
    boundary = solid & ~binary_erosion(solid, iterations=2)
    if not boundary.any():
        boundary = alpha > .15
    if not boundary.any():
        return {"eligible": True, "empty": True, "contrast_p10": 99., "distance_p10": 1.}
    colors = arr[:, :, :3][boundary]
    bg = np.repeat(float(tone), 3)
    y, b = luminance(colors), luminance(bg)
    contrast = (np.maximum(y, b) + .05) / (np.minimum(y, b) + .05)
    distance = np.linalg.norm(oklab(colors) - oklab(bg), axis=1)
    c, d = float(np.percentile(contrast, 10)), float(np.percentile(distance, 10))
    whole = arr[:, :, :3][solid]
    if not len(whole):
        whole = colors
    y = luminance(whole)
    ratios = (np.maximum(y, b) + .05) / (np.minimum(y, b) + .05)
    deltas = np.linalg.norm(oklab(whole) - oklab(bg), axis=1)
    whole_c = float(np.percentile(ratios, 35))
    whole_d = float(np.percentile(deltas, 35))
    contour_pass = c >= 1.8 and d >= .09
    whole_pass = whole_c >= 2.2 and whole_d >= .12
    return {
        "eligible": bool(contour_pass or whole_pass),
        "criterion": "contour" if contour_pass else "whole-mark" if whole_pass else "neither",
        "contrast_p10": c, "distance_p10": d,
        "whole_mark_contrast_p35": whole_c, "whole_mark_distance_p35": whole_d,
    }

def neutral_lift(artwork):
    """Optional positive-slope neutral lift, never an RGB or chromatic inversion."""
    arr = np.array(artwork)
    support = arr[:, :, 3] > 32
    core = arr[:, :, 3] > 220
    if core.sum() < 200:
        return None, {"reason": "no robust neutral core"}
    labs = oklab(arr[:, :, :3])
    chroma = np.linalg.norm(labs[:, :, 1:], axis=2)
    if float(np.mean(chroma[core] > .035)) > .025:
        return None, {"reason": "chromatic or mixed-role artwork is not inverted"}
    # Complex grayscale photos/pixel grids are not assumed to be single marks.
    quantized = arr[:, :, :3][core] // 32
    _, counts = np.unique(quantized, axis=0, return_counts=True)
    p = counts / counts.sum()
    entropy = float(-np.sum(p * np.log2(p)))
    edges = np.count_nonzero(support[1:] != support[:-1]) + np.count_nonzero(support[:, 1:] != support[:, :-1])
    density = float(edges / max(support.sum(), 1))
    if entropy > 2.5 or density > .45:
        return None, {"reason": "detailed neutral image; do not reinterpret its tones"}
    center = float(np.median(labs[:, :, 0][core]))
    if center >= .65:
        return None, {"reason": "neutral mark already light"}
    # Positive slope preserves highlight/shadow ordering and holes/alpha.
    original = arr[:, :, :3].astype(float)
    gray = original @ np.array([.2126, .7152, .0722])
    median = float(np.median(gray[core]))
    mapped = np.clip(205 + .65 * (gray - median), 135, 246)
    arr[support, :3] = np.rint(mapped[support, None]).astype("uint8")
    return Image.fromarray(arr), {
        "reason": "neutral-mark polarity lift with positive-slope shading",
        "original_gray_median": median, "target_gray_median": 205,
        "shading_slope": .65, "alpha_unchanged": True,
    }

def resolve_container(variant, composed, mode):
    old = _v2
    if mode == "dark":
        return old.resolve_container(variant, composed, mode)
    result = dict(variant, diagnostics=dict(variant["diagnostics"]))
    if result["presentation"] != "fit":
        return result
    pixels = np.asarray(composed)
    solid = pixels[:, :, 3] >= 250
    contour = solid & ~binary_erosion(solid, iterations=3)
    samples = pixels[:, :, :3][contour].astype(float)
    original = np.median(samples, axis=0)
    uniformity = float(np.mean(np.max(np.abs(samples - original), axis=1) <= 2))
    detail = {
        "source": "actual composed contour pixels",
        "original_rgb": original.tolist(), "uniformity": uniformity,
        "dark_target_max_channel": 112, "artwork_bytes_preserved": True,
    }
    result["diagnostics"]["container"] = detail
    if uniformity < .995 or np.ptp(original) > 3:
        detail.update(decision="preserve-unresolved", reason="not a proven generated neutral plate")
        return result
    if original.max() <= 112:
        detail.update(decision="preserve", reason="existing generated container already dark")
        return result
    placed = fit_layout(variant["artwork"])[0]
    trials = []
    for tone in TONES:
        quality = boundary_quality(placed, tone)
        trials.append({"tone": tone, "glyph_quality": quality, "artwork_changed": False})
        if not quality["eligible"]:
            continue
        selected = "#" + f"{tone:02X}" * 3
        actual = old.composed_quality(compose_icon(variant["artwork"], selected, "fit"), mode)
        if not actual["adequate"]:
            continue
        result["backplate"] = selected
        detail.update(
            decision="dark-generated-backplate",
            reason="genuinely dark container; source artwork retained exactly",
            selected_rgb=[tone] * 3, glyph_quality=quality, outer_quality=actual,
            rejected_count=len(trials) - 1,
        )
        result["diagnostics"]["chosen_method"] = "dark-generated-backplate"
        return result
    lifted, lift_detail = neutral_lift(variant["artwork"])
    if lifted is not None:
        placed_lifted = fit_layout(lifted)[0]
        # Do not allow optical mass changes to produce a second/different fit.
        if not np.array_equal(np.asarray(placed)[:, :, 3], np.asarray(placed_lifted)[:, :, 3]):
            lifted = None
            lift_detail = {"reason": "neutral lift would change brightness-weighted placement"}
    if lifted is not None:
        for tone in TONES:
            quality = boundary_quality(placed_lifted, tone)
            trials.append({"tone": tone, "glyph_quality": quality, "artwork_changed": True})
            if not quality["eligible"]:
                continue
            selected = "#" + f"{tone:02X}" * 3
            actual = old.composed_quality(compose_icon(lifted, selected, "fit"), mode)
            if not actual["adequate"]:
                continue
            result.update(artwork=lifted, backplate=selected)
            detail.update(
                decision="dark-generated-neutral-polarity",
                reason="dark neutral mark requires controlled polarity on dark container",
                selected_rgb=[tone] * 3, glyph_quality=quality, outer_quality=actual,
                artwork_bytes_preserved=False, neutral_lift=lift_detail,
            )
            result["diagnostics"]["chosen_method"] = "dark-generated-neutral-polarity"
            return result
    detail.update(
        decision="preserve-unresolved",
        reason="no dark plate preserves mark; unsafe polarity change is not automatic",
        neutral_lift=lift_detail, trials=trials,
    )
    fallback = old.resolve_container(variant, composed, mode)
    fallback["diagnostics"] = dict(fallback["diagnostics"], container=detail)
    return fallback
