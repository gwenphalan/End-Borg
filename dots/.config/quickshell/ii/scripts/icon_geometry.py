"""Image-only geometry measurements; identities never enter rendering decisions."""
import math

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import (binary_dilation, binary_fill_holes, distance_transform_edt,
                           gaussian_filter, label)
from scipy.spatial import ConvexHull

ANALYSIS_SIZE = 256


def visible_bounds(image, threshold=8):
    return image.convert("RGBA").getchannel("A").point(
        lambda alpha: 255 if alpha > threshold else 0).getbbox()


def normalized(image, size=ANALYSIS_SIZE):
    image = image.convert("RGBA")
    bounds = visible_bounds(image)
    if bounds:
        image = image.crop(bounds)
    scale = size / max(image.size)
    image = image.resize((max(1, round(image.width * scale)),
                          max(1, round(image.height * scale))), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size))
    canvas.alpha_composite(image, ((size - image.width) // 2, (size - image.height) // 2))
    return canvas


def analyze_geometry(image):
    """Separate broad, solid tiles from badges, outlines, and floating glyphs."""
    bounds = visible_bounds(image)
    tile_bounds = visible_bounds(image, 128) or bounds
    cropped = image.crop(tile_bounds) if tile_bounds else image
    rgba = np.asarray(normalized(cropped))
    solid = rgba[:, :, 3] > 220
    supported = rgba[:, :, 3] > 128
    coverage = float(solid.mean())
    support_coverage = float(supported.mean())
    core = float(supported[32:224, 32:224].mean())
    aspect = max(cropped.size) / max(1, min(cropped.size))
    supports = [bool(supported[y, x]) for y, x in
                ((32, 32), (32, 223), (223, 32), (223, 223),
                 (16, 128), (128, 16), (239, 128), (128, 239))]
    tile = aspect <= 1.12 and support_coverage >= .81 and core >= .995 and all(supports)
    concavity = 0.
    if tile:
        filled = binary_fill_holes(supported)
        border = filled & binary_dilation(~np.pad(filled, 1, constant_values=False))[1:-1, 1:-1]
        ys, xs = np.nonzero(border)
        points = np.column_stack((xs, ys))
        hull = ConvexHull(points)
        envelope = Image.new("1", (256, 256))
        ImageDraw.Draw(envelope).polygon([tuple(point) for point in points[hull.vertices]], fill=1)
        convex = np.asarray(envelope, dtype=bool)
        concavity = float(np.count_nonzero(convex & ~filled) / max(np.count_nonzero(convex), 1))
        tile = concavity <= .01
    axis = (np.arange(256) + .5 - 128) / 128
    squircle = np.abs(axis[:, None]) ** 4 + np.abs(axis[None, :]) ** 4 <= 1
    missing = float(np.mean(~solid[squircle]))
    return {"visible_bounds": list(bounds) if bounds else None,
            "tile_bounds": list(tile_bounds) if tile_bounds else None,
            "source_size": list(image.size), "aspect_ratio": float(aspect),
            "opaque_coverage": coverage, "supported_coverage": support_coverage,
            "interior_solidity": core,
            "square_support": supports, "is_tile": bool(tile),
            "convexity_deficit": concavity,
            "uncovered_squircle_fraction": missing}


def decorative_frame(image):
    """Find a thin, contrasting closed rim, never a glyph's meaningful outline.

    All four sides must have a similar narrow color peak, a uniform interior
    substrate, and near-complete opaque support. Only the detected rim is cropped.
    """
    geometry = analyze_geometry(image)
    if not geometry["is_tile"]:
        return None
    cropped = image.crop(geometry["tile_bounds"]).convert("RGBA")
    # Sample the rectangular tile itself, not contain()'s transparent padding.
    rgba = np.asarray(cropped.resize((256, 256), Image.Resampling.LANCZOS))
    rgb = rgba[:, :, :3].astype(float)
    profiles = [np.median(rgb[:, 64:192], axis=1),
                np.median(rgb[:, 64:192], axis=1)[::-1],
                np.median(rgb[64:192, :], axis=0),
                np.median(rgb[64:192, :], axis=0)[::-1]]
    widths, colors, substrates = [], [], []
    for profile in profiles:
        inner = profile[12:32]
        distances = np.max(np.abs(inner[:, None] - inner[None, :]), axis=2)
        anchor = int(np.argmax((distances <= 22).sum(axis=1)))
        cluster = inner[distances[anchor] <= 22]
        if len(cluster) < 8:
            return None
        substrate = np.median(cluster, axis=0)
        distance = np.max(np.abs(profile[:18] - substrate), axis=1)
        rim = np.flatnonzero(distance > 55)
        if not len(rim) or rim[0] > 9 or rim[-1] > 14 or len(rim) > 10:
            return None
        widths.append(int(rim[-1] + 4))
        colors.append(np.median(profile[rim], axis=0))
        substrates.append(substrate)
    if max(widths) - min(widths) > 5:
        return None
    if np.max(np.abs(np.array(colors) - np.median(colors, axis=0))) > 32:
        return None
    if np.max(np.abs(np.array(substrates) - np.median(substrates, axis=0))) > 28:
        return None
    top, bottom, left, right = widths
    return {"crop_normalized": [left, top, 256 - right, 256 - bottom],
            "rim_widths": widths,
            "substrate_rgb": np.median(substrates, axis=0).astype(int).tolist(),
            "reason": "thin closed contrasting rim over solid tile"}


def prepare_geometry(image):
    geometry = analyze_geometry(image)
    frame = decorative_frame(image) if geometry["is_tile"] else None
    tile = image.crop(geometry["tile_bounds"]) if geometry["is_tile"] else image
    prepared = normalized(tile)
    if frame:
        left, top, right, bottom = frame["crop_normalized"]
        cropped = tile.crop((round(left * tile.width / 256), round(top * tile.height / 256),
                             round(right * tile.width / 256), round(bottom * tile.height / 256)))
        # The detector verified a uniform substrate beneath this translucent rim.
        substrate = Image.new("RGBA", cropped.size, tuple(frame["substrate_rgb"]) + (255,))
        substrate.alpha_composite(cropped.convert("RGBA"))
        prepared = normalized(substrate)
        geometry = analyze_geometry(prepared)
    return prepared, geometry, frame


def extend_edges(image):
    """Nearest opaque-edge colors fill exterior only; enclosed holes survive."""
    rgba = np.array(normalized(image))
    solid = rgba[:, :, 3] > 128
    if not solid.any():
        return Image.fromarray(rgba)
    exterior = ~binary_fill_holes(solid)
    nearest = distance_transform_edt(~solid, return_distances=False, return_indices=True)
    rgba[exterior, :3] = rgba[nearest[0][exterior], nearest[1][exterior], :3]
    rgba[exterior, 3] = 255
    return Image.fromarray(rgba)


def tile_layers(image, diagnostics=None):
    """Separate simple marks only when a dominant, uniform substrate is proven."""
    detail = diagnostics if diagnostics is not None else {}
    detail.update(decision="preserve-tile", reason="insufficient supported perimeter samples")
    rgba = np.array(normalized(image))
    rgb = rgba[:, :, :3].astype(float)
    candidates = []
    for start in (8, 4):
        end = start + 8
        strips = np.concatenate((rgba[start:end, 48:208].reshape(-1, 4),
                                 rgba[256-end:256-start, 48:208].reshape(-1, 4),
                                 rgba[48:208, start:end].reshape(-1, 4),
                                 rgba[48:208, 256-end:256-start].reshape(-1, 4)))
        strips = strips[strips[:, 3] > 128, :3].astype(float)
        if len(strips) >= 2000:
            substrate = np.median(strips, axis=0)
            uniformity = float(np.mean(np.max(np.abs(strips - substrate), axis=1) <= 18))
            candidates.append((uniformity, substrate))
    if not candidates:
        return None
    uniformity, substrate = max(candidates, key=lambda candidate: candidate[0])
    distance = np.max(np.abs(rgb - substrate), axis=2)
    visible = rgba[:, :, 3] > 128
    background_fraction = float(np.mean(distance[visible] <= 18)) if visible.any() else 0
    quantized = (rgba[:, :, :3][visible] // 32).astype(int)
    _, counts = np.unique(quantized, axis=0, return_counts=True)
    probabilities = counts / max(counts.sum(), 1)
    entropy = float(-np.sum(probabilities * np.log2(probabilities)))
    detail.update(border_uniformity=uniformity, substrate_rgb=substrate.astype(int).tolist(),
                  background_fraction=background_fraction, palette_entropy_bits=entropy)
    if uniformity < .9 or background_fraction < .45 or entropy > 3.2:
        detail["reason"] = "nonuniform perimeter, nondominant substrate, or detailed palette"
        return None
    # Closed tile highlights, shadows and antialiased corners are not the mark.
    background = visible & (distance <= 18)
    flat_substrate = float(np.mean(distance[background] <= 2)) >= .98 if background.any() else False
    seed = (distance > (2 if flat_substrate else 24)) & visible
    components, _ = label(seed)
    inner_distance = distance_transform_edt(np.pad(visible, 1))[1:-1, 1:-1]
    boundary_ids = np.unique(components[inner_distance <= 4])
    boundary_ids = boundary_ids[boundary_ids != 0]
    boundary = np.isin(components, boundary_ids) if len(boundary_ids) else np.zeros_like(visible)
    detail.update(flat_substrate=flat_substrate, excluded_boundary_fraction=float(boundary.mean()))
    # Never delete a meaningful mark merely because one stroke meets an edge.
    if (float(boundary.mean()) > .15
            or (boundary.any() and float(inner_distance[boundary].max()) > 12)):
        detail["reason"] = "edge-connected artwork cannot safely be separated from a rim"
        return None
    mask = seed & ~boundary
    if not flat_substrate:
        # Native texture flecks are not isolated glyph accents. Only make this
        # distinction on textured substrates; flat tiles keep even tiny marks.
        component_sizes = np.bincount(components.ravel())
        mask &= component_sizes[components] >= 64
        mask = binary_dilation(mask, iterations=2) & (distance > 2) & visible & ~boundary
    # Palette size is not detail: a two-color pixel-art cover can be very busy.
    edge_density = float((np.count_nonzero(mask[1:] != mask[:-1])
                          + np.count_nonzero(mask[:, 1:] != mask[:, :-1]))
                         / max(np.count_nonzero(mask), 1))
    if edge_density > .5:
        detail.update(foreground_edge_density=edge_density,
                      reason="high spatial complexity; preserve detailed artwork")
        return None
    # Unmix against the proven native substrate, rather than attenuating already
    # antialiased RGB a second time. Recomposition reproduces source colors.
    differences = rgb - substrate
    capacity = np.where(differences >= 0, 255 - substrate, substrate)
    coverage = np.maximum(.1, np.max(np.abs(differences) / np.maximum(capacity, 1), axis=2))
    coverage *= mask
    foreground = rgba.copy()
    foreground[:, :, :3] = np.clip(np.rint(
        substrate + differences / np.maximum(coverage[:, :, None], 1e-9)), 0, 255).astype(np.uint8)
    foreground[:, :, 3] = np.rint(rgba[:, :, 3] * coverage).astype(np.uint8)
    bounds = visible_bounds(Image.fromarray(foreground))
    fraction = float(mask.mean())
    detail.update(foreground_fraction=fraction, foreground_edge_density=edge_density)
    if not bounds or fraction < .025 or fraction > .55:
        detail["reason"] = "no confidently isolated mark of suitable area"
        return None
    detail.update(decision="separate-glyph", reason="dominant native substrate with a simple isolated mark")
    return (Image.fromarray(foreground), tuple(substrate.astype(int)),
            {"method": "uniform-native-substrate-and-low-spatial-complexity",
             "substrate_rgb": substrate.astype(int).tolist(),
             "border_uniformity": uniformity, "background_fraction": background_fraction,
             "palette_entropy_bits": entropy, "foreground_fraction": fraction,
             "foreground_edge_density": edge_density,
             "excluded_boundary_fraction": float(boundary.mean()),
             "flat_substrate": flat_substrate,
             "foreground_bounds": list(bounds)})


def _mass_quantile(weights, fraction):
    cumulative = np.cumsum(weights)
    return int(np.searchsorted(cumulative, cumulative[-1] * fraction))


def optical_layout(image, size=256, scale_factor=1.):
    """Approximate perceived bounds without ever discarding the source artwork.

    Filled silhouette area supplies shape-dependent keylines. Soft shadows have
    little mass. Robust bounds and a capped centroid correction prevent isolated
    accents from displacing the main object. Every visible pixel still constrains
    the final squircle-safe envelope.
    """
    artwork = normalized(image)
    rgba = np.asarray(artwork)
    alpha = rgba[:, :, 3].astype(float) / 255
    if not (alpha > 8 / 255).any():
        return Image.new("RGBA", (size, size)), {"method": "empty", "scale": 0}
    silhouette = binary_fill_holes(alpha > .35).astype(float)
    blurred = gaussian_filter(alpha, sigma=2)
    # Modest local-detail weighting, not brightness: dark artwork carries mass too.
    luma = rgba[:, :, :3].astype(float) @ np.array([.2126, .7152, .0722]) / 255
    detail = np.abs(luma - gaussian_filter(luma, sigma=4))
    mass = (.65 * silhouette + .35 * blurred) * (.9 + np.minimum(detail, .3))
    rows, columns = mass.sum(axis=1), mass.sum(axis=0)
    robust = [_mass_quantile(columns, .005), _mass_quantile(rows, .005),
              _mass_quantile(columns, .995) + 1, _mass_quantile(rows, .995) + 1]
    centroid = [float(np.dot(np.arange(256) + .5, columns) / mass.sum()),
                float(np.dot(np.arange(256) + .5, rows) / mass.sum())]
    robust_center = [(robust[0] + robust[2]) / 2, (robust[1] + robust[3]) / 2]
    center = np.clip(.6 * np.array(robust_center) + .4 * np.array(centroid), 118, 138)
    area = float((.7 * silhouette + .3 * alpha).sum())
    scale = min(math.sqrt(.50 * size * size / max(area, 1)), size * .88 / 256)
    # Bound visible pixels using the same exponent as the final squircle, inset 8%.
    ys, xs = np.nonzero(alpha > 8 / 255)
    radius = (np.abs(xs + .5 - center[0]) ** 4
              + np.abs(ys + .5 - center[1]) ** 4) ** .25
    scale = min(scale, size * .42 / max(float(radius.max()), 1))
    extent = max(1, round(256 * scale * scale_factor))
    resized = artwork.resize((extent, extent), Image.Resampling.LANCZOS)
    position = (round(size / 2 - center[0] * extent / 256),
                round(size / 2 - center[1] * extent / 256))
    output = Image.new("RGBA", (size, size))
    output.alpha_composite(resized, position)
    return output, {"method": "silhouette-area-and-bounded-visual-mass",
                    "analysis_size": 256, "robust_bounds": robust,
                    "alpha_bounds": list(visible_bounds(artwork)),
                    "visual_centroid": centroid, "placement_center": center.tolist(),
                    "silhouette_area": area, "scale": extent / 256,
                    "offset": list(position), "rendered_bounds": list(visible_bounds(output)),
                    "target_area_fraction": .50 * scale_factor ** 2,
                    "safe_radius_fraction": .42 * scale_factor,
                    "padding_scale": scale_factor}


def fit_layout(image, size=256):
    """The same extra inset for floating artwork and extracted native tile marks."""
    return optical_layout(image, size, scale_factor=.95)
