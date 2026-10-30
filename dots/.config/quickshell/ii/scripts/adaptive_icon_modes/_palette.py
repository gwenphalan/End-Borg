"""Approved V3 dependency extracted from perceptual-palette/candidate.py."""


import numpy as np
from PIL import Image
from scipy.ndimage import minimum_filter

from .lab_support import oklab


SIZES = (16, 24, 32, 48, 64)

def lab_to_linear(lab):
    lab = np.asarray(lab, dtype=float)
    l, a, b = np.moveaxis(lab, -1, 0)
    lm = (l + .3963377774 * a + .2158037573 * b) ** 3
    mm = (l - .1055613458 * a - .0638541728 * b) ** 3
    sm = (l - .0894841775 * a - 1.2914855480 * b) ** 3
    return np.stack((4.0767416621 * lm - 3.3077115913 * mm + .2309699292 * sm,
                     -1.2684380046 * lm + 2.6097574011 * mm - .3413193965 * sm,
                     -.0041960863 * lm - .7034186147 * mm + 1.7076147010 * sm), axis=-1)

def linear_to_rgb(linear):
    linear = np.asarray(linear, dtype=float)
    encoded = np.where(linear <= .0031308, 12.92 * linear,
                       1.055 * np.maximum(linear, 0) ** (1 / 2.4) - .055)
    return np.clip(encoded * 255, 0, 255)

def gamut_fraction(linear, weights):
    outside = np.any((linear < -.00015) | (linear > 1.00015), axis=-1)
    return float(np.sum(weights * outside) / max(np.sum(weights), 1e-9))

def effective_foreground(base, placed, substrate):
    """Reparameterize layer coverage, not its shape/placement.

    Policy31 unmixed colors can be much brighter than the visible mark. A robust
    coverage anchor restores the actual mark palette before perceptual analysis.
    The original composed RGB remains exactly reconstructible; output alpha is
    never replaced by this photometric coverage.
    """
    rgb = np.asarray(base)[:, :, :3].astype(float)
    alpha = np.asarray(placed)[:, :, 3].astype(float) / 255
    core = alpha[alpha > .12]
    if core.size < 300:
        return None
    reference = max(.12, float(np.percentile(core, 85)))
    coverage = np.clip(alpha / reference, 0, 1)
    differences = rgb - substrate
    capacity = np.where(differences >= 0, 255 - substrate, substrate)
    required = np.max(np.abs(differences) / np.maximum(capacity, 1), axis=-1)
    coverage = np.maximum(coverage, np.clip(required, 0, 1))
    foreground = substrate + differences / np.maximum(coverage[:, :, None], 1e-9)
    foreground = np.clip(foreground, 0, 255)
    return foreground, coverage, reference

def small_structure(before, after, coverage):
    """Check boundary readability separately from intra-glyph shading."""
    ratios, internal_ratios = {}, {}
    for size in SIZES:
        x = np.asarray(before.resize((size, size), Image.Resampling.LANCZOS))[:, :, :3]
        y = np.asarray(after.resize((size, size), Image.Resampling.LANCZOS))[:, :, :3]
        c = np.asarray(Image.fromarray(np.rint(coverage * 255).astype("uint8")).resize(
            (size, size), Image.Resampling.LANCZOS)).astype(float) / 255
        a, b = oklab(x), oklab(y)
        ex = np.hypot(*np.gradient(a[:, :, 0]))
        ey = np.hypot(*np.gradient(b[:, :, 0]))
        boundary = (c > .08) & (ex > .035)
        internal = (minimum_filter(c, size=3) > .98) & (ex > .008)
        ratios[str(size)] = float(np.mean(ey[boundary]) / np.mean(ex[boundary])) if boundary.any() else 1.
        internal_ratios[str(size)] = (
            float(np.mean(ey[internal]) / np.mean(ex[internal])) if internal.any() else 1.)
    return ratios, internal_ratios
