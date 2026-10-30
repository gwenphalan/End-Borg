"""Approved V3 dependency extracted from structure-aware/candidate.py."""


import numpy as np
from scipy.ndimage import binary_dilation, binary_propagation, gaussian_filter, label, sobel

from .lab_support import luminance, oklab


def _components(mask, minimum=16):
    regions, _ = label(mask)
    sizes = np.bincount(regions.ravel())
    return int(np.count_nonzero(sizes[1:] >= minimum))

def structural_layers(image, substrate):
    """Retain a topology map instead of interpreting all closed rings as rims."""
    rgba = np.asarray(image.convert("RGBA"))
    rgb = rgba[:, :, :3].astype(float)
    visible = rgba[:, :, 3] > 128
    distance = np.max(np.abs(rgb - np.asarray(substrate)), axis=2)
    native = visible & (distance <= 20)
    boundary = visible & binary_dilation(
        ~np.pad(visible, 1, constant_values=False), iterations=2)[1:-1, 1:-1]
    exterior = binary_propagation(native & boundary, mask=native)
    glyph = visible & ~native
    holes = native & ~exterior
    dark = visible & (luminance(rgb) < min(.20, float(luminance(substrate)) * .65))
    outline = dark & binary_dilation(native, iterations=2)
    softened = gaussian_filter(glyph.astype(float), .7)
    gx, gy = sobel(softened, axis=1), sobel(softened, axis=0)
    edges = np.hypot(gx, gy) > .6
    axis_ratio = np.minimum(np.abs(gx), np.abs(gy)) / np.maximum(
        np.maximum(np.abs(gx), np.abs(gy)), 1e-6)
    axis_fraction = float(np.mean(axis_ratio[edges] < .1)) if edges.any() else 0.
    labs = oklab(rgb)
    chromatic = np.hypot(labs[:, :, 1], labs[:, :, 2]) > .09
    hole_boundary = binary_dilation(holes, iterations=2) & glyph
    neutral_dark_boundary = hole_boundary & dark & ~chromatic
    boundary_fraction = float(neutral_dark_boundary.sum() / max(hole_boundary.sum(), 1))
    return {
        "transparent_exterior": ~visible,
        "substrate_exterior": exterior,
        "substrate_holes": holes,
        "glyph": glyph,
        "outline": outline,
    }, {
        "transparent_fraction": float((~visible).mean()),
        "exterior_native_fraction": float(exterior.mean()),
        "enclosed_native_fraction": float(holes.mean()),
        "enclosed_native_components": _components(holes),
        "glyph_components": _components(glyph),
        "outline_fraction": float(outline.mean()),
        "axis_aligned_edge_fraction": axis_fraction,
        "neutral_dark_enclosure_fraction": boundary_fraction,
        "chromatic_ink_fraction": float((chromatic & glyph).mean()),
        "topology_policy": "retain-outline-and-enclosed-substrate; no erosion",
    }
