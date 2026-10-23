"""Pure, offline adaptive icon policy. Originals are never modified."""
import hashlib
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

POLICY_VERSION = 18


def trim_visible(image):
    image = image.convert("RGBA")
    bounds = image.getchannel("A").point(lambda alpha: 255 if alpha > 8 else 0).getbbox()
    return image.crop(bounds) if bounds else image


def contain(image, size=256):
    image = image.convert("RGBA")
    image = trim_visible(image)
    scale = min(size / image.width, size / image.height)
    image = image.resize((max(1, round(image.width * scale)),
                          max(1, round(image.height * scale))), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size))
    canvas.alpha_composite(image, ((size - image.width) // 2, (size - image.height) // 2))
    return canvas


def classify(image, override=None):
    """Only true edge-to-edge square illustrations fill automatically."""
    if override in ("fit", "fill", "extend", "bleed", "remove-background"):
        return override, 1.0, "explicit per-app override"
    image = image.convert("RGBA")
    w, h = image.size
    if max(w, h) / max(1, min(w, h)) > 1.12:
        return "fit", .99, "non-square original"
    alpha = np.asarray(image.getchannel("A").resize((64, 64))) > 245
    edge = np.concatenate((alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]))
    if edge.mean() > .98 and alpha.mean() > .995:
        return "fit", .65, "opaque square; meaningful edge content may be clipped"
    if rounded_tile(image):
        return "fill", .9, "rounded square artwork clipped to outer squircle"
    return "fit", .65, "transparent or uncertain silhouette"

def rounded_tile(image):
    """Distinguish broad square tiles from circular badges and floating logos."""
    if max(image.size) / max(1, min(image.size)) > 1.08:
        return False
    alpha = np.asarray(contain(image).getchannel("A")) > 245
    if alpha.mean() < .80:
        return False
    pixels = np.asarray(contain(image))
    rim = np.concatenate((pixels[16:24, 64:192].reshape(-1, 4),
                          pixels[232:240, 64:192].reshape(-1, 4),
                          pixels[64:192, 16:24].reshape(-1, 4),
                          pixels[64:192, 232:240].reshape(-1, 4)))
    solid = rim[rim[:, 3] > 245, :3].astype(np.float32)
    if len(solid) < .85 * len(rim):
        return False
    if np.percentile(np.max(np.abs(solid - np.median(solid, axis=0)), axis=1), 90) > 25:
        return False
    return (all(alpha[y, x] for y, x in
                ((32, 32), (32, 223), (223, 32), (223, 223),
                 (16, 128), (128, 16), (239, 128), (128, 239)))
            and not all(alpha[y, x] for y, x in ((0, 0), (0, 255), (255, 0), (255, 255))))


def full_bleed_tile(image):
    """Recognize near-full square tiles, excluding round logos and folders."""
    image = image.convert("RGBA")
    if max(image.size) / max(1, min(image.size)) > 1.08:
        return False
    alpha = np.asarray(contain(image).getchannel("A")) > 245
    if alpha.mean() < .90 or not all(alpha[y, x] for y, x in
                                     ((32, 32), (32, 223), (223, 32), (223, 223))):
        return False
    edge = np.concatenate((alpha[8, 32:224], alpha[-9, 32:224],
                           alpha[32:224, 8], alpha[32:224, -9]))
    return edge.mean() > .85


def remove_border_background(image):
    """Remove only a nearly uniform border-connected region, preserving inner holes."""
    from PIL import ImageDraw
    image = image.convert("RGBA")
    rgb = np.asarray(image)
    edges = np.concatenate((rgb[0, :, :3], rgb[-1, :, :3],
                            rgb[:, 0, :3], rgb[:, -1, :3]))
    background = np.median(edges, axis=0)
    if np.mean(np.max(np.abs(edges.astype(int) - background), axis=1) <= 8) < .98:
        return None
    if np.mean(rgb[:, :, 3]) < 250:
        return None
    mask = np.max(np.abs(rgb[:, :, :3].astype(int) - background), axis=2) <= 8
    marker = Image.fromarray(np.where(mask, 0, 255).astype("uint8"), "L").copy()
    ImageDraw.floodfill(marker, (0, 0), 128, thresh=0)
    connected = np.asarray(marker) == 128
    if connected.mean() < .04 or connected.mean() > .85:
        return None
    output = np.array(image)
    output[:, :, 3][connected] = 0
    return Image.fromarray(output, "RGBA")


def extend_rounded_square(image):
    """Fill small transparent rounded corners of an otherwise opaque square."""
    image = contain(image)
    arr = np.array(image)
    alpha = arr[:, :, 3] > 245
    band = 36
    if not (.72 < alpha.mean() < .995 and
            alpha[band:-band, band:-band].mean() > .99 and
            alpha[:12, :12].mean() < .25 and
            alpha[:12, -12:].mean() < .25 and
            alpha[-12:, :12].mean() < .25 and
            alpha[-12:, -12:].mean() < .25):
        return None
    # Floating glyphs have gaps across their midlines; only extrapolate
    # a filled tile with a solid interior.
    for y in (band, 64, 128, 192, 255 - band):
        if len(np.flatnonzero(alpha[y])) < 160:
            return None
    if not all(alpha[128, x] for x in (8, 247)):
        return None
    if not all(alpha[y, x] for y, x in ((32, 32), (32, 223), (223, 32), (223, 223))):
        return None
    border = np.concatenate((
        arr[16:36, 72:184].reshape(-1, 4),
        arr[220:240, 72:184].reshape(-1, 4),
        arr[72:184, 16:36].reshape(-1, 4),
        arr[72:184, 220:240].reshape(-1, 4),
    ))
    solid = border[border[:, 3] > 245, :3].astype(np.float32)
    if len(solid) < 250 or np.percentile(np.max(np.abs(solid - np.median(solid, axis=0)), axis=1), 90) > 12:
        return None
    color = tuple(np.median(solid, axis=0).astype(np.uint8)) + (255,)
    filled = Image.new("RGBA", (256, 256), color)
    filled.alpha_composite(image)
    return filled


def extend_exterior_edges(image):
    """Extend only border-connected transparency, retaining holes inside logos."""
    image = contain(image)
    pixels = np.array(image)
    mask = Image.fromarray(np.where(pixels[:, :, 3] > 8, 255, 0).astype("uint8"), "L").copy()
    for point in ((0, 0), (255, 0), (0, 255), (255, 255)):
        if mask.getpixel(point) == 0:
            ImageDraw.floodfill(mask, point, 128, thresh=0)
    exterior = np.asarray(mask) == 128
    known = pixels[:, :, 3] > 8
    rgb = pixels[:, :, :3].copy()
    for _ in range(256):
        missing = exterior & ~known
        if not missing.any():
            break
        updated = known.copy()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            neighbors = np.roll(known, (dy, dx), axis=(0, 1))
            if dy == -1: neighbors[-1, :] = False
            if dy == 1: neighbors[0, :] = False
            if dx == -1: neighbors[:, -1] = False
            if dx == 1: neighbors[:, 0] = False
            take = missing & neighbors & ~updated
            rgb[take] = np.roll(rgb, (dy, dx), axis=(0, 1))[take]
            updated[take] = True
        if np.array_equal(updated, known):
            break
        known = updated
    pixels[:, :, :3][exterior] = rgb[exterior]
    pixels[:, :, 3][exterior] = 255
    return Image.fromarray(pixels, "RGBA")


def render_adaptive(image, presentation, colors, is_game=False, adjustments=None):
    """Preserve source colors while applying only structural presentation rules."""
    transformed = (extend_rounded_square(image) if presentation == "extend" else
                   remove_border_background(image) if presentation == "remove-background" else None)
    if presentation in ("extend", "remove-background") and transformed is None:
        presentation = "fit"
    adapted = (contain(transformed) if presentation == "remove-background" else
               transformed if presentation == "extend" else contain(image))
    if presentation == "fill" and adapted.getchannel("A").getextrema()[0] < 255:
        adapted = extend_exterior_edges(adapted)
    return adapted, presentation


def icon_backplates(image):
    return {mode: choose_backplate([image], mode) for mode in ("light", "dark")}


def _oklab(rgb):
    rgb = np.asarray(rgb, dtype=np.float64) / 255
    linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
    lms = np.cbrt(linear @ np.array([[.4122214708, .5363325363, .0514459929],
                                     [.2119034982, .6806995451, .1073969566],
                                     [.0883024619, .2817188376, .6299787005]]).T)
    return lms @ np.array([[.2104542553, .7936177850, -.0040720468],
                           [1.9779984951, -2.4285922050, .4505937099],
                           [.0259040371, .7827717662, -.8086757660]]).T


def _srgb(lab):
    lms = np.asarray(lab) @ np.linalg.inv(np.array(
        [[.2104542553, .7936177850, -.0040720468],
         [1.9779984951, -2.4285922050, .4505937099],
         [.0259040371, .7827717662, -.8086757660]])).T
    linear = lms ** 3 @ np.linalg.inv(np.array(
        [[.4122214708, .5363325363, .0514459929],
         [.2119034982, .6806995451, .1073969566],
         [.0883024619, .2817188376, .6299787005]])).T
    rgb = np.where(linear <= .0031308, 12.92 * linear,
                   1.055 * np.maximum(linear, 0) ** (1 / 2.4) - .055)
    return np.clip(np.rint(rgb * 255), 0, 255).astype(np.uint8)


def _luminance(rgb):
    rgb = np.asarray(rgb, dtype=np.float64) / 255
    linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
    return linear @ np.array([.2126, .7152, .0722])


def _artwork_regions(image):
    """Collect opaque colors adjoining the exterior, plus salient small areas."""
    from scipy.ndimage import binary_dilation
    rgba = np.asarray(image.convert("RGBA").resize((64, 64), Image.Resampling.LANCZOS))
    alpha = rgba[:, :, 3] > 200
    if not alpha.any():
        return np.empty((0, 3), dtype=np.uint8)
    boundary = alpha & binary_dilation(~alpha, iterations=2)
    boundary[0] |= alpha[0]
    boundary[-1] |= alpha[-1]
    boundary[:, 0] |= alpha[:, 0]
    boundary[:, -1] |= alpha[:, -1]
    pixels = rgba[:, :, :3]
    return np.concatenate((pixels[boundary][::2], pixels[alpha][::12]))


def backplate_candidates(images, mode):
    regions = [_artwork_regions(image) for image in images]
    if not any(len(region) for region in regions):
        return regions, [(245, 245, 245) if mode == "light" else (20, 20, 20)]
    colors = np.concatenate([region for region in regions if len(region)])
    labs = _oklab(colors)
    # Anchor hue and chroma exclusively to visible artwork; achromatic art stays neutral.
    chromatic = labs[np.linalg.norm(labs[:, 1:], axis=1) > .025]
    anchors = chromatic if len(chromatic) else labs
    vectors = [np.median(anchors, axis=0)]
    for index in np.linspace(0, len(anchors) - 1, min(12, len(anchors)), dtype=int):
        vectors.append(anchors[index])
    candidates = set()
    for anchor in vectors:
        for lightness in (np.linspace(.73, .97, 9) if mode == "light"
                          else np.linspace(.10, .36, 9)):
            for factor in (0, .25, .5, .8):
                lab = (lightness, anchor[1] * factor, anchor[2] * factor)
                rgb = tuple(int(x) for x in _srgb(lab))
                candidates.add(rgb)
    return regions, sorted(candidates)


def choose_backplate(images, mode):
    regions, candidates = backplate_candidates(images, mode)
    luminances = [_luminance(region) for region in regions if len(region)]
    def score(candidate):
        background = _luminance(candidate)
        contrasts = []
        for foreground in luminances:
            contrast = (np.maximum(foreground, background) + .05) / (
                np.minimum(foreground, background) + .05)
            contrasts.append(float(np.percentile(contrast, 10)))
        return min(contrasts) if contrasts else 0
    chosen = max(candidates, key=lambda color: (score(color), color))
    return "#" + "".join(f"{channel:02X}" for channel in chosen)


@lru_cache(maxsize=8)
def squircle_mask(size=256, supersample=4):
    """Superellipse exponent 4: zero curvature at the side junctions (G2)."""
    extent = size * supersample
    axis = (np.arange(extent, dtype=np.float32) + .5 - extent / 2) / (extent / 2)
    inside = np.abs(axis[:, None]) ** 4 + np.abs(axis[None, :]) ** 4 <= 1
    return Image.fromarray((inside * 255).astype("uint8"), "L").resize(
        (size, size), Image.Resampling.LANCZOS)


def compose_icon(artwork, backplate, presentation):
    tile = Image.new("RGBA", artwork.size, backplate)
    foreground = artwork
    if presentation in ("fit", "remove-background"):
        foreground = contain(artwork, round(artwork.width * .80))
        padded = Image.new("RGBA", artwork.size)
        padded.alpha_composite(foreground, ((artwork.width - foreground.width) // 2,
                                            (artwork.height - foreground.height) // 2))
        foreground = padded
    tile.alpha_composite(foreground)
    alpha = squircle_mask(artwork.width)
    tile.putalpha(alpha)
    return tile


def source_key(source, theme, presentation):
    return hashlib.sha256(source + theme.encode() + presentation.encode()
                          + str(POLICY_VERSION).encode()).hexdigest()
