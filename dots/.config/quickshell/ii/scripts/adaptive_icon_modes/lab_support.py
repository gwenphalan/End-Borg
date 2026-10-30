"""Approved V3 dependency extracted from common/lab_support.py."""


import numpy as np

from adaptive_icon_policy import classify, render_adaptive
from icon_geometry import fit_layout, prepare_geometry, tile_layers


def baseline_variant(image, mode):
    if mode not in ("dark", "light"):
        raise ValueError("Invalid mode")
    presentation = classify(image)[0]
    artwork, presentation = render_adaptive(image, presentation)
    return {"artwork": artwork, "presentation": presentation, "backplate": None,
            "diagnostics": {"decision": "preserve", "reason": "policy31 baseline"}}

def luminance(rgb):
    rgb = np.asarray(rgb, dtype=float) / 255
    linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
    return linear @ np.array([.2126, .7152, .0722])

def oklab(rgb):
    rgb = np.asarray(rgb, dtype=float) / 255
    linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
    lms = np.cbrt(linear @ np.array([[.4122214708, .5363325363, .0514459929],
                                    [.2119034982, .6806995451, .1073969566],
                                    [.0883024619, .2817188376, .6299787005]]).T)
    return lms @ np.array([[.2104542553, .7936177850, -.0040720468],
                           [1.9779984951, -2.4285922050, .4505937099],
                           [.0259040371, .7827717662, -.8086757660]]).T
