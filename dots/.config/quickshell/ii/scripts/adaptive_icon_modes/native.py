"""Approved V3 dependency extracted from synthesis-v3/native.py."""


import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, label

from .lab_support import baseline_variant, fit_layout, luminance, oklab, prepare_geometry, tile_layers
from . import _native_v2, _palette, _structure


SIZES = (16, 24, 32, 48, 64)

def clean(value):
    if isinstance(value, dict):
        return {str(k): clean(v) for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [clean(v) for v in value]
    if isinstance(value, (np.floating, float)):
        return round(float(value), 6)
    if isinstance(value, np.integer):
        return int(value)
    if isinstance(value, np.bool_):
        return bool(value)
    return value

def contrast(rgb, background):
    a, b = luminance(rgb), luminance(background)
    return (np.maximum(a, b) + .05) / (np.minimum(a, b) + .05)

def glyph_small_sizes(artwork, coverage, substrate):
    """Absolute glyph/native-substrate distance, not an old-polarity edge ratio."""
    report = {}
    for size in SIZES:
        pixels = np.asarray(artwork.resize((size, size), Image.Resampling.LANCZOS))[:, :, :3]
        mask = np.asarray(Image.fromarray(np.rint(coverage * 255).astype("uint8")).resize(
            (size, size), Image.Resampling.LANCZOS)).astype(float) / 255
        supported = mask > .55
        distance = np.linalg.norm(oklab(pixels) - oklab(substrate), axis=2)
        report[str(size)] = float(np.percentile(distance[supported], 10)) if supported.any() else 0.
    return report

def render_variant(image, mode):
    if mode != "light":
        return _native_v2.render_variant(image, mode)
    base = baseline_variant(image, mode)
    detail = {
        "system": "native-dark-container-light-v3", "decision": "preserve",
        "chosen_method": "unchanged-policy31", "reason": "", "features": {}, "trials": [],
        "policy": "light surface requires a dark proven-neutral native container, not barely separated pale gray",
        "geometry": "baseline alpha/presentation/optical layout unchanged; no refit of transformed artwork",
    }
    base["diagnostics"] = detail

    def preserve(reason):
        detail["reason"] = reason
        base["diagnostics"] = clean(detail)
        return base

    prepared, geometry, frame = prepare_geometry(image)
    detail["features"].update(is_native_tile=bool(geometry["is_tile"]), baseline_frame=bool(frame))
    if not geometry["is_tile"] or base["presentation"] == "fit":
        return preserve("not native extend/fill artwork; generated fit container is a separate policy")
    if min(image.size) < 96:
        return preserve("low-resolution / potential pixel artwork; unresolved native policy")
    segmentation = {}
    layers = tile_layers(prepared, segmentation)
    detail["features"]["segmentation"] = segmentation
    if layers is None:
        return preserve("uncertain native substrate/gradient/detailed artwork; not claimed satisfactory for light")
    foreground, substrate, meta = layers
    substrate = np.asarray(substrate, dtype=float)
    substrate_chroma = float(np.linalg.norm(oklab(substrate)[1:]))
    detail["features"].update(substrate_rgb=substrate.tolist(), substrate_chroma=substrate_chroma)
    if substrate_chroma > .025:
        return preserve("chromatic native substrate meaningful; preserve native palette")
    if float(np.max(substrate)) <= 112:
        return preserve("original native substrate already dark enough for light surface")
    if (meta["border_uniformity"] < .975 or meta["foreground_edge_density"] > .22
            or meta["palette_entropy_bits"] > 2.4):
        return preserve("detailed/textured or uncertain neutral native tile; light target unresolved")
    _, topology = _structure.structural_layers(prepared, substrate)
    detail["features"]["topology"] = topology
    if topology["axis_aligned_edge_fraction"] > .86:
        return preserve("axis-aligned potential block/pixel artwork; preserve")
    if (topology["enclosed_native_fraction"] > .005
            and topology["neutral_dark_enclosure_fraction"] > .50
            and topology["chromatic_ink_fraction"] > .02):
        return preserve("outlined chromatic badge has semantic enclosed native-color panel; preserve")
    if topology["enclosed_native_components"] > 10 or topology["glyph_components"] > 12:
        return preserve("ambiguous nested/disconnected structure; preserve")

    before = base["artwork"]
    original = np.asarray(before)
    rgb = original[:, :, :3].astype(float)
    placed = np.asarray(fit_layout(foreground)[0])
    support = placed[:, :, 3] > 8
    delta = rgb - substrate
    distance = np.max(np.abs(delta), axis=2)
    if not support.any():
        return preserve("no native glyph support")
    strong = max(40., float(np.percentile(distance[support], 75)) * .55)
    strong_core = support & (distance >= strong)
    # Low-contrast interior fill is semantic ink even when a darker outline
    # dominates the strong threshold. Erode observed ink, not the strong core:
    # otherwise solid gray letters become bright outlines around dark holes.
    deep_ink = distance_transform_edt(support & (distance >= 35)) > 1.5
    core = strong_core | deep_ink
    observed_lab = oklab(rgb)
    neutral_body = (deep_ink & (np.linalg.norm(observed_lab[:, :, 1:], axis=2) < .055)
                    & (observed_lab[:, :, 0] > .30) & (observed_lab[:, :, 0] < .75))
    if core.sum() < 200 or np.percentile(distance_transform_edt(core)[core], 50) < 1.5:
        return preserve("no robust native mark core / fine-stroke ambiguity")
    radius, nearest = distance_transform_edt(~core, return_indices=True)
    line = rgb[nearest[0], nearest[1]] - substrate
    coverage = np.clip(np.sum(delta * line, axis=2)
                       / np.maximum(np.sum(line * line, axis=2), 1), 0, 1)
    coverage[core] = 1
    glyph_region = support & (radius <= 2)
    coverage[~glyph_region] = 0
    shadow_region = support & ~glyph_region
    # A disconnected accent must either have a modeled core or trigger abstention.
    native_ink, count = label(support & (distance > 30))
    unmodeled = []
    for index in range(1, count + 1):
        region = native_ink == index
        if region.sum() >= 6 and not np.any(core & region):
            native_contrast = float(np.percentile(contrast(rgb[region], substrate), 50))
            if native_contrast >= 1.5:
                unmodeled.append(int(region.sum()))
    if unmodeled:
        detail["features"]["unmodeled_accent_pixels"] = unmodeled
        return preserve("meaningful disconnected accent has no robust matte core; preserve")
    recovered = np.clip(substrate + delta / np.maximum(coverage[:, :, None], 1e-9), 0, 255)
    labs = oklab(recovered)
    core_labs = labs[core]
    chroma = np.linalg.norm(core_labs[:, 1:], axis=1)
    neutral_core = core.copy()
    neutral_core[core] = chroma < .055
    chromatic_core = core & ~neutral_core
    neutral_fraction = float(neutral_core.sum() / core.sum())
    detail["features"].update(
        core_pixels=int(core.sum()), neutral_core_fraction=neutral_fraction,
        chromatic_core_fraction=1 - neutral_fraction, matte_threshold=strong,
        matte_edge_pixels=int((glyph_region & ~core).sum()), shadow_pixels=int(shadow_region.sum()),
        deep_fill_added_core_pixels=int((deep_ink & ~strong_core).sum()),
        neutral_body_pixels=int(neutral_body.sum()),
    )
    nearest_neutral = neutral_core[nearest[0], nearest[1]]
    # Nearest opaque color determines the role in the antialias band, rather
    # than misclassifying desaturated edge blends as independent gray ink.
    neutral_role = glyph_region & nearest_neutral
    chromatic_role = glyph_region & ~neutral_role
    nearest_core_lab = labs[nearest[0], nearest[1]]
    if neutral_core.any():
        center = float(np.median(labs[:, :, 0][neutral_core]))
    else:
        center = 0.
    detail["features"]["neutral_original_lightness_center"] = center
    palette = _palette
    components, component_count = label(core)
    regions = [components == index for index in range(1, component_count + 1)
               if np.count_nonzero(components == index) >= 6]
    if not regions:
        return preserve("no robust semantic components")

    # Dark substrate is the explicit target. Prefer preserving chromatic RGB;
    # darker substrate is tried first because ruby/coral glyphs need separation.
    attempts = [(channel, neutral_center, chromatic_shift)
                for channel in (48, 64, 80, 96, 112)
                for chromatic_shift in ((0., .02, .04, .06) if chromatic_core.any() else (0.,))
                for neutral_center in (.80, .77, .74)]
    for target_channel, neutral_center, chromatic_shift in attempts:
        target = np.repeat(float(target_channel), 3)
        mapped = recovered.copy()
        changed_lab = labs.copy()
        if neutral_core.any():
            # Strictly increasing bounded transfer: shadows remain below
            # highlights even while changing the neutral role's polarity.
            changed_lab[:, :, 0][neutral_role] = (neutral_center + .13 * np.tanh(
                (labs[:, :, 0] - center) / .20))[neutral_role]
            # Faint AA extrapolation is chromatically ill-conditioned. Its
            # local strong-core chroma is the proven color-line endpoint.
            changed_lab[:, :, 1:][neutral_role] = nearest_core_lab[:, :, 1:][neutral_role]
        changed_lab[:, :, 0][chromatic_role] += chromatic_shift
        linear = palette.lab_to_linear(changed_lab)
        transformed = palette.linear_to_rgb(linear)
        mapped[neutral_role] = transformed[neutral_role]
        if chromatic_shift:
            mapped[chromatic_role] = transformed[chromatic_role]
        gamut_weight = coverage * glyph_region
        clipping = palette.gamut_fraction(linear, gamut_weight) if gamut_weight.any() else 0.
        adapted = target + coverage[:, :, None] * (mapped - target)
        if shadow_region.any():
            native_gray = rgb @ np.array([.2126, .7152, .0722])
            strength = np.clip((float(substrate.mean()) - native_gray) / 255, 0, .15)
            adapted[shadow_region] = target * (1 - strength[shadow_region, None])
        output = original.copy()
        output[:, :, :3] = np.clip(np.rint(adapted), 0, 255).astype("uint8")
        artwork = Image.fromarray(output, "RGBA")
        component_contrasts = [float(np.percentile(contrast(output[region, :3], target), 10))
                               for region in regions]
        tiny_min = min(component_contrasts)
        core_p10 = float(np.percentile(contrast(output[core, :3], target), 10))
        small = glyph_small_sizes(artwork, coverage, target)
        chromatic_drift = (float(np.max(np.abs(
            output[chromatic_core, :3].astype(float) - rgb[chromatic_core])))
            if chromatic_core.any() else 0.)
        chromatic_chroma_error = (float(np.max(np.linalg.norm(
            oklab(output[chromatic_core, :3])[:, 1:] - labs[chromatic_core, 1:], axis=1)))
            if chromatic_core.any() else 0.)
        order = 1.
        relief = 1.
        output_lab = oklab(output[:, :, :3])
        body_retained = (float(np.mean(np.linalg.norm(
            output_lab[neutral_body] - oklab(target), axis=1) >= .10))
            if neutral_body.any() else 1.)
        if neutral_core.any():
            a = labs[:, :, 0][neutral_core]
            b = output_lab[:, :, 0][neutral_core]
            if np.std(a) > .015:
                order = float(np.corrcoef(a, b)[0, 1]) if np.std(b) > 1e-9 else 0.
                relief = float(np.std(b) / np.std(a))
        reasons = []
        if clipping > 1e-8:
            reasons.append("role-aware gamut safeguard")
        if core_p10 < 2.2 or tiny_min < 1.8:
            reasons.append("semantic glyph/tiny-component contrast")
        if min(small.values()) < .08:
            reasons.append("absolute launcher-scale glyph/substrate separation")
        if (not chromatic_shift and chromatic_drift > 1) or chromatic_chroma_error > .003:
            reasons.append("chromatic opaque core hue/chroma preservation")
        if order < .94 or relief < .25:
            reasons.append("positive-order neutral relief safeguard")
        if body_retained < .90:
            reasons.append("deep neutral semantic fill retention")
        trial = {
            "substrate_rgb": target.tolist(), "neutral_target_lightness_center": neutral_center,
            "chromatic_shared_lightness_shift": chromatic_shift,
            "core_contrast_p10": core_p10, "component_contrast_min": tiny_min,
            "glyph_small_size_distance_p10": small, "neutral_gamut_weight_fraction": clipping,
            "chromatic_core_rgb_max_error": chromatic_drift,
            "chromatic_core_ab_max_error": chromatic_chroma_error,
            "neutral_shading_order_correlation": order, "neutral_relief_std_ratio": relief,
            "deep_neutral_body_retained_fraction": body_retained,
            "rejections": reasons,
        }
        detail["trials"].append(trial)
        if reasons:
            continue
        detail.update(
            decision="adapt-dark-native-container", chosen_method="role-aware-dark-native",
            reason="explicit dark light-surface container; neutral roles lifted monotonically, chromatic hue/chroma retained",
            selected_substrate_rgb=target.tolist(),
            neutral_transfer="L'=center+0.13*tanh((L-native_center)/0.20); a,b retained",
            selected_neutral_lightness_center=neutral_center,
            selected_chromatic_lightness_shift=chromatic_shift,
            chromatic_transfer="native RGB exact when safe; otherwise one shared OKLab L translation, a,b unchanged",
            shadow_policy="outside glyph remains subtractive, never a bright halo",
            uncertainty="heuristic segmentation/matte and role inference, not semantic recognition",
        )
        base["artwork"] = artwork
        base["diagnostics"] = clean(detail)
        return base
    return preserve("no dark native palette passes role/contrast/relief/gamut safeguards; light target unresolved")
