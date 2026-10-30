"""Approved V3 dependency extracted from badge-v2/candidate.py."""


import numpy as np
from PIL import Image
from scipy.ndimage import (
    binary_dilation, binary_fill_holes, binary_propagation,
    distance_transform_edt, label,
)

from .lab_support import baseline_variant, fit_layout, luminance


def extract_outlined_badge(image):
    """Extract only a proven closed dark contour over a flat opaque exterior.

    Returns (RGBA image or None, deterministic diagnostics). All retained RGBA
    pixels equal the 256px source sample exactly; contours are never cropped.
    """
    detail = {"decision": "preserve", "reason": "no proven enclosed outlined badge"}
    if min(image.size) < 96 or abs(image.width / image.height - 1) > .03:
        return None, detail
    source = image.convert("RGBA")
    if source.size != (256, 256):
        source = source.resize((256, 256), Image.Resampling.LANCZOS)
    rgba = np.array(source)
    if np.mean(rgba[:, :, 3] > 250) < .999:
        detail["reason"] = "source is not a full opaque tile; preserve native alpha topology"
        return None, detail
    rgb = rgba[:, :, :3].astype(float)
    border = np.zeros((256, 256), dtype=bool)
    border[[0, -1], :] = True
    border[:, [0, -1]] = True
    exterior_color = np.median(rgb[border], axis=0)
    difference = np.max(np.abs(rgb - exterior_color), axis=2)
    uniformity = float(np.mean(difference[border] <= 3))
    detail.update(exterior_rgb=exterior_color.astype(int).tolist(), border_uniformity=uniformity)
    if uniformity < .995:
        detail["reason"] = "nonuniform exterior or badge touching source border"
        return None, detail
    exterior = binary_propagation(border, mask=difference <= 10)
    silhouette = ~exterior
    fraction = float(exterior.mean())
    detail["exterior_fraction"] = fraction
    components, _ = label(silhouette)
    sizes = np.bincount(components.ravel())
    if not .08 < fraction < .65 or np.count_nonzero(sizes[1:] >= 64) != 1:
        return None, detail
    if any((silhouette[:2].any(), silhouette[-2:].any(),
            silhouette[:, :2].any(), silhouette[:, -2:].any())):
        detail["reason"] = "meaningful contour touches image boundary"
        return None, detail
    dark = luminance(rgb) < min(.20, float(luminance(exterior_color)) * .65)
    enclosed = binary_fill_holes(dark) & ~dark
    detail["outline_enclosed_fraction"] = float(enclosed.mean())
    if enclosed.mean() < .20 or np.mean(enclosed & exterior) > .002:
        detail["reason"] = "no continuous meaningful closed dark outline"
        return None, detail
    ring = silhouette & binary_dilation(exterior, iterations=3)
    if float(np.mean(dark[ring])) < .70:
        detail["reason"] = "outer silhouette is not separated by dark contour"
        return None, detail
    rgba[exterior, 3] = 0
    detail.update(
        decision="extract-outlined-badge",
        reason="uniform border-connected exterior outside a closed dark contour",
        exterior_removed_pixels=int(exterior.sum()),
        retained_outline_pixels=int((dark & silhouette).sum()),
        retained_source_rgba_exact=True,
    )
    return Image.fromarray(rgba, "RGBA"), detail

def fill_canvas_exterior(fitted):
    """Extend nearest opaque colors without normalization, trimming or resizing.

    Opaque/core and enclosed interior samples remain unchanged. Exterior AA is
    composited over its nearest opaque donor instead of exposing a mode plate.
    Structural holes use alpha>128 topology, not tiny Lanczos ringing samples.
    No normalization, re-fit, synthetic rim, or invented donor color is used.
    """
    rgba = np.array(fitted.convert("RGBA"))
    alpha = rgba[:, :, 3]
    solid = alpha > 128
    opaque = alpha == 255
    structural_exterior = ~binary_fill_holes(solid)
    # Include the contour's partially covered outer AA in exterior compositing,
    # while fill_holes protects the complete enclosed interior (including holes).
    retained = binary_fill_holes(opaque)
    exterior = ~retained
    holes = ~solid & ~structural_exterior
    detail = {
        "canvas_size": list(fitted.size),
        "fill_method": "nearest-opaque-on-already-fitted-canvas",
        "normalization_calls": 0, "resize_calls": 0, "fit_calls": 0,
        "retained_support_pixels": int(retained.sum()),
        "retention_domain": "opaque core and complete enclosed interior; not exterior antialiasing",
        "enclosed_transparent_pixels": int((holes & (alpha == 0)).sum()),
        "exterior_antialias_samples": int((exterior & (alpha > 0)).sum()),
        "filled_exterior_pixels": 0,
    }
    if not opaque.any() or not exterior.any():
        detail["retained_support_equal"] = True
        return Image.fromarray(rgba, "RGBA"), detail
    nearest = distance_transform_edt(
        ~opaque, return_distances=False, return_indices=True)
    colors = rgba[nearest[0][exterior], nearest[1][exterior], :3]
    output = rgba.copy()
    coverage = alpha[exterior].astype(float)[:, None] / 255
    output[exterior, :3] = np.rint(
        rgba[exterior, :3] * coverage + colors * (1-coverage)).astype(np.uint8)
    output[exterior, 3] = 255
    detail.update(
        filled_exterior_pixels=int(exterior.sum()),
        retained_support_equal=bool(np.array_equal(output[retained], rgba[retained])),
        opaque_core_equal=bool(np.array_equal(output[opaque], rgba[opaque])),
        holes_equal=bool(np.array_equal(output[holes], rgba[holes])),
        donor_rgb_median=np.median(colors, axis=0).astype(int).tolist(),
        donor_luminance_p95=float(np.percentile(luminance(colors), 95)),
    )
    return Image.fromarray(output, "RGBA"), detail

def fit_then_extend(extracted):
    """Exactly one optical placement, then a canvas-preserving fill."""
    fitted, layout = fit_layout(extracted)
    final, fill_detail = fill_canvas_exterior(fitted)
    return fitted, final, {
        "pipeline": ["extract", "fit_layout_once", "fill_canvas_exterior"],
        "optical_fit_calls": 1,
        "fit_layout": layout,
        "canvas_fill": fill_detail,
    }

def render_variant(image, mode):
    if mode not in ("light", "dark"):
        raise ValueError("mode must be light or dark")
    extracted, detail = extract_outlined_badge(image)
    if extracted is None:
        result = baseline_variant(image, mode)
        detail.update(geometry_changed=False, optical_fit_calls=0)
        result["diagnostics"] = detail
        return result
    _, final, pipeline_detail = fit_then_extend(extracted)
    detail.update(pipeline_detail)
    detail.update(
        decision="extract-fit-once-edge-fill",
        geometry_changed=True,
        geometry_policy="explicit badge pipeline; fit once before edge-fill",
        presentation_policy="extend prevents compose-time refit",
        backplate_policy="frozen family retained; artwork supplies exterior",
    )
    return {
        "artwork": final, "presentation": "extend", "backplate": None,
        "diagnostics": detail,
    }
