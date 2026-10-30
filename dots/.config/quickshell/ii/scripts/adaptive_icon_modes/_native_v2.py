"""Approved V3 dependency extracted from synthesis-v2/native.py."""


import numpy as np
from PIL import Image, ImageColor
from scipy.ndimage import binary_erosion, label

from adaptive_icon_policy import squircle_mask
from .lab_support import baseline_variant, fit_layout, luminance, oklab, prepare_geometry, tile_layers
from . import _palette, _structure


SIZES = (16, 24, 32, 48, 64)

SURFACES = {
    "light": ("#FFFFFF", "#F2F1F5", "#E6E5EB", "#E9F0EF"),
    "dark": ("#121216", "#202025", "#303038", "#243036"),
}

OUTER_FLOOR = .055

def json_safe(value):
    if isinstance(value, dict):
        return {str(k): json_safe(v) for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [json_safe(v) for v in value]
    if isinstance(value, (np.floating, float)):
        return round(float(value), 6)
    if isinstance(value, np.integer):
        return int(value)
    if isinstance(value, np.bool_):
        return bool(value)
    return value

def contrast(rgb, substrate):
    a, b = luminance(rgb), luminance(substrate)
    return (np.maximum(a, b) + .05) / (np.minimum(a, b) + .05)

def outer_visibility(artwork, mode):
    """Actual native RGB at frozen opaque inner contour, at all five sizes.

    No artificial backdrop, refit, palette proxy or glyph-edge score replaces
    this test. For native extend/fill artwork the frozen squircle is the final
    contour; returned artwork itself is never modified or refitted here.
    """
    # Frozen compose_icon puts the 256px squircle alpha onto the native tile
    # before any launcher-scale RGBA resize. Pillow's premultiplied Lanczos RGB
    # behavior is not equivalent to resizing RGB then applying squircle(size).
    composed = artwork.copy()
    composed.putalpha(squircle_mask(artwork.width))
    results = {}
    for size in SIZES:
        arr = np.asarray(composed.resize((size, size), Image.Resampling.LANCZOS))
        alpha = arr[:, :, 3].astype(float) / 255
        solid = alpha >= .98
        contour = solid & ~binary_erosion(solid)
        per_surface = {}
        for surface in SURFACES[mode]:
            bg = np.asarray(ImageColor.getrgb(surface), dtype=float)
            rgb = arr[:, :, :3] * alpha[:, :, None] + bg * (1 - alpha[:, :, None])
            distance = np.linalg.norm(oklab(rgb) - oklab(bg), axis=2)[contour]
            ratios = contrast(rgb[contour], bg)
            per_surface[surface] = {
                "oklab_distance_p10": float(np.percentile(distance, 10)),
                "contrast_p10": float(np.percentile(ratios, 10)),
            }
        results[str(size)] = per_surface
    minimum = min(v["oklab_distance_p10"] for sizes in results.values() for v in sizes.values())
    return {"adequate": minimum >= OUTER_FLOOR,
            "minimum_contour_distance_p10": minimum, "by_size": results,
            "heuristic_floor_not_wcag": OUTER_FLOOR}

def render_variant(image, mode):
    base = baseline_variant(image, mode)
    detail = {
        "system": "visibility-first-native-v2", "decision": "preserve",
        "chosen_method": "unchanged-policy31", "reason": "",
        "policy": "mode supplies launcher-surface context; never a polarity preference",
        "features": {}, "trials": [],
        "scope": "native artwork only; generated fit backplates and badge extraction excluded",
    }
    base["diagnostics"] = detail

    def preserve(reason):
        detail["reason"] = reason
        base["diagnostics"] = json_safe(detail)
        return base

    prepared, geometry, frame = prepare_geometry(image)
    detail["features"].update(is_native_tile=bool(geometry["is_tile"]), baseline_frame=bool(frame))
    if not geometry["is_tile"] or base["presentation"] == "fit":
        return preserve("not a native extend/fill tile; generated fit presentation left to separate policy")
    original_outer = outer_visibility(base["artwork"], mode)
    detail["original_outer_visibility"] = original_outer
    # This gate precedes segmentation, native polarity or candidate selection.
    # Already-visible dark-on-light and light-on-dark tiles both keep identity.
    if original_outer["adequate"]:
        return preserve("original native artwork already distinguishable on reference surfaces; keep current regardless of polarity")
    if min(image.size) < 96:
        return preserve("native outer visibility weak but low-resolution/pixel-art risk; abstain")
    segmentation = {}
    layers = tile_layers(prepared, segmentation)
    detail["features"]["segmentation"] = segmentation
    if layers is None:
        return preserve("native outer visibility weak but substrate/structure unproven; abstain")
    foreground, substrate, meta = layers
    substrate = np.asarray(substrate, dtype=float)
    chroma = float(np.linalg.norm(oklab(substrate)[1:]))
    detail["features"].update(substrate_rgb=substrate.tolist(), substrate_chroma=chroma)
    if chroma > .025:
        return preserve("chromatic native substrate meaningful; weak visibility does not authorize recoloring")
    if (meta["border_uniformity"] < .975 or meta["foreground_edge_density"] > .22
            or meta["palette_entropy_bits"] > 2.4):
        return preserve("native outer visibility weak but detailed/textured segmentation uncertain")
    _, topology = _structure.structural_layers(prepared, substrate)
    detail["features"]["topology"] = topology
    if topology["axis_aligned_edge_fraction"] > .86:
        return preserve("potential block/pixel art; preserve")
    if (topology["enclosed_native_fraction"] > .005
            and topology["neutral_dark_enclosure_fraction"] > .50
            and topology["chromatic_ink_fraction"] > .02):
        return preserve("outlined chromatic badge with semantic native-color enclosed panel; preserve")
    if topology["enclosed_native_components"] > 10 or topology["glyph_components"] > 12:
        return preserve("ambiguous nested/disconnected detail; preserve")
    palette = _palette
    placed = fit_layout(foreground)[0]
    recovered = palette.effective_foreground(base["artwork"], placed, substrate)
    if recovered is None:
        return preserve("no robust foreground for safe native visibility correction")
    colors, coverage, reference = recovered
    core = coverage >= .90
    if core.sum() < 200:
        return preserve("insufficient robust native glyph core")
    foreground_lab = oklab(colors)
    core_chroma = np.linalg.norm(foreground_lab[core, 1:], axis=1)
    chromatic_fraction = float(np.mean(core_chroma > .055))
    detail["features"].update(chromatic_core_fraction=chromatic_fraction,
                               reconstructed_coverage_reference=reference)
    if not (chromatic_fraction < .025 or chromatic_fraction > .94):
        return preserve("mixed neutral/chromatic roles uncertain; preserve components and tiny accents")
    native_contrast = float(np.percentile(contrast(colors[core], substrate), 10))
    # A shared L shift preserves every hue/chroma and lightness ordering.
    # No per-component color bending or inversion; full-field gamut is checked.
    direction = 1 if mode == "dark" else -1
    start = int(round(float(np.mean(substrate))))
    target = None
    reference_labs = [oklab(ImageColor.getrgb(surface)) for surface in SURFACES[mode]]
    for channel in range(start + direction, start + direction * 100, direction):
        if not 16 <= channel <= 245:
            continue
        proposed_substrate = np.repeat(float(channel), 3)
        if abs(float(oklab(proposed_substrate)[0] - oklab(substrate)[0])) > .18:
            break
        if min(float(np.linalg.norm(oklab(proposed_substrate) - lab)) for lab in reference_labs) < OUTER_FLOOR:
            continue
        changed = np.asarray(base["artwork"]).copy()
        changed[:, :, :3] = np.clip(np.rint(
            colors * coverage[:, :, None] + proposed_substrate * (1 - coverage[:, :, None])
        ), 0, 255).astype("uint8")
        if outer_visibility(Image.fromarray(changed), mode)["adequate"]:
            target = proposed_substrate
            break
    if target is None:
        return preserve("no minimally bounded neutral substrate reaches contour visibility; abstain")
    # Recovered photometric coverage can call tiny near-substrate shadows
    # "opaque". They are not semantic ink; do not invent a new 1.8 contrast
    # requirement for fragments that never had it in the original artwork.
    semantic_core = core & (contrast(colors, substrate) >= 1.8)
    component_map, count = label(semantic_core)
    component_regions = [(component_map == index) for index in range(1, count + 1)
                         if np.count_nonzero(component_map == index) >= 6]
    if not component_regions:
        return preserve("no robust component regions; preserve fine strokes and accents")
    contrast_floor = max(2., min(3., native_contrast * .80))
    detail["features"].update(target_substrate_rgb=target.tolist(),
                               native_core_contrast_p10=native_contrast,
                               core_contrast_floor=contrast_floor)
    for magnitude in np.arange(0., .121, .01):
        delta = float(direction * magnitude)
        changed_lab = foreground_lab.copy()
        changed_lab[:, :, 0] += delta
        linear = palette.lab_to_linear(changed_lab)
        clipping = palette.gamut_fraction(linear, coverage)
        trial = {"shared_foreground_oklab_L_delta": delta, "gamut_weight_fraction": clipping,
                 "rejections": []}
        detail["trials"].append(trial)
        if clipping > 1e-8:
            trial["rejections"].append("full-field gamut/clipping safeguard")
            continue
        changed_rgb = palette.linear_to_rgb(linear)
        core_contrast = float(np.percentile(contrast(changed_rgb[core], target), 10))
        component_min = min(float(np.percentile(contrast(changed_rgb[region], target), 10))
                            for region in component_regions)
        output = np.asarray(base["artwork"]).copy()
        output[:, :, :3] = np.rint(np.clip(
            changed_rgb * coverage[:, :, None] + target * (1 - coverage[:, :, None]), 0, 255)).astype("uint8")
        artwork = Image.fromarray(output, "RGBA")
        boundary, internal = palette.small_structure(base["artwork"], artwork, coverage)
        actual_outer = outer_visibility(artwork, mode)
        trial.update(core_contrast_p10=core_contrast, component_contrast_min=component_min,
                     boundary_retention=boundary, internal_retention=internal,
                     outer_visibility=actual_outer)
        if core_contrast < contrast_floor or component_min < 1.8:
            trial["rejections"].append("glyph/tiny-component contrast safeguard")
        if min(boundary.values()) < .78 or min(internal.values()) < .82:
            trial["rejections"].append("native small-size boundary/internal relief safeguard")
        if not actual_outer["adequate"]:
            trial["rejections"].append("actual outer-contour visibility safeguard")
        if trial["rejections"]:
            continue
        detail.update(
            decision="adapt-native-visibility", chosen_method="bounded-native-joint-OKLab",
            reason="original contour weak; smallest bounded substrate offset and first shared glyph L shift passing semantic/outer gates",
            selected_substrate_rgb=target.tolist(), selected_foreground_oklab_L_delta=delta,
            chroma_policy="foreground OKLab a,b unchanged; no inversion; shared positive-slope L translation",
            output_outer_visibility=actual_outer,
            uncertainty="reference surfaces and heuristic gates do not establish universal aesthetic suitability",
        )
        base["artwork"] = artwork
        base["diagnostics"] = json_safe(detail)
        return base
    return preserve("original native visibility weak but no bounded joint palette preserves glyph/relief/gamut; abstain")
