"""Pure, offline adaptive icon policy. Originals are never modified."""
import colorsys
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

POLICY_VERSION = 16
NEUTRAL = "#40404A"


def theme_colors(path):
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {"neutral": NEUTRAL}
    colors = {}
    for role, keys in {
        "accent": ("primary",),
        "drawer": ("surface_container", "surfaceContainer", "surface"),
        "primary": ("primary_container", "primaryContainer"),
        "secondary": ("secondary_container", "secondaryContainer"),
        "tertiary": ("tertiary_container", "tertiaryContainer"),
        "neutral": ("surface_container_high", "surfaceContainerHigh", "surface"),
    }.items():
        color = next((data[k] for k in keys if k in data), None)
        if isinstance(color, str) and len(color) == 7 and color[0] == "#":
            try:
                bytes.fromhex(color[1:])
                colors[role] = color.upper()
            except ValueError:
                pass
    colors.setdefault("neutral", NEUTRAL)
    return colors


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
        return "fill", .98, "opaque square illustration"
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


def choose_background(image, colors):
    arr = np.asarray(image.convert("RGBA").resize((64, 64)), dtype=np.float32)
    pixels = arr[:, :, :3][arr[:, :, 3] > 100]
    if len(pixels) < 10:
        return colors["neutral"], "neutral"
    pixels = pixels[::max(1, len(pixels) // 900)]
    anchor = np.array(list(bytes.fromhex(colors.get("primary", colors["neutral"])[1:])), dtype=np.float32)
    candidates = {role: value for role, value in colors.items()
                  if role in ("primary", "secondary", "tertiary", "neutral")}
    light = .28 * anchor + .72 * np.array([201, 196, 186])
    candidates["light"] = "#" + "".join(f"{round(v):02X}" for v in light)
    for role in ("primary", "tertiary"):
        if role in colors:
            base = np.array(list(bytes.fromhex(colors[role][1:])), dtype=np.float32)
            neutral = np.array(list(bytes.fromhex(colors["neutral"][1:])), dtype=np.float32)
            mixed = .48 * base + .52 * neutral
            candidates[role + "-muted"] = "#" + "".join(f"{round(v):02X}" for v in mixed)
    if "accent" in colors:
        accent_rgb = [channel / 255 for channel in bytes.fromhex(colors["accent"][1:])]
        accent_hue = colorsys.rgb_to_hsv(*accent_rgb)[0]
        for label, offset in (("analogous-cool", -.12), ("analogous-warm", .12),
                              ("complement", .5), ("split-cool", .38), ("split-warm", -.38)):
            rgb = colorsys.hsv_to_rgb((accent_hue + offset) % 1, .40, .41)
            candidates[label] = "#" + "".join(f"{round(v * 255):02X}" for v in rgb)

    def linear(rgb):
        normalized = rgb / 255
        return np.where(normalized <= .04045, normalized / 12.92,
                        ((normalized + .055) / 1.055) ** 2.4)

    foreground = linear(pixels) @ np.array([.2126, .7152, .0722])
    drawer_rgb = np.array(list(bytes.fromhex(colors.get("drawer", colors["neutral"])[1:])), dtype=np.float32)
    drawer_luminance = float(linear(drawer_rgb) @ np.array([.2126, .7152, .0722]))
    # Prioritize the least contrasted fifth of the visible artwork.
    def score(item):
        role, value = item
        rgb = np.array(list(bytes.fromhex(value[1:])), dtype=np.float32)
        luminance = float(linear(rgb) @ np.array([.2126, .7152, .0722]))
        contrast = (np.maximum(foreground, luminance) + .05) / (np.minimum(foreground, luminance) + .05)
        legibility = float(np.percentile(contrast, 20))
        drawer_contrast = ((max(luminance, drawer_luminance) + .05)
                           / (min(luminance, drawer_luminance) + .05))
        # Once a glyph is clearly readable, additional raw contrast should
        # not force every bright icon onto the same darkest neutral surface.
        return (min(legibility, 3.2) - 2 * max(0, 3.3 - legibility)
                + .55 * min(drawer_contrast, 2.2)
                - 3 * max(0, 1.7 - drawer_contrast)
                - (.45 if role == "light" else 0)
                - (.30 if role == "neutral" else 0)
                + (.20 if role in ("primary", "secondary", "tertiary") else 0)
                + (.08 if role.endswith("-muted") else 0))
    role, color = max(candidates.items(), key=score)
    return color, role
def contrast_surface(base, drawer, accent):
    """Lighten or darken a theme backplate just enough to separate from its drawer."""
    def channels(hex_color):
        return np.array(list(bytes.fromhex(hex_color[1:])), dtype=np.float32)
    def luminance(rgb):
        scaled = rgb / 255
        linear = np.where(scaled <= .04045, scaled / 12.92, ((scaled + .055) / 1.055) ** 2.4)
        return float(linear @ np.array([.2126, .7152, .0722]))
    backdrop = luminance(channels(drawer))
    start = channels(base)
    target = channels(accent) if backdrop < .25 else np.zeros(3, dtype=np.float32)
    for mix in np.linspace(0, 1, 21):
        candidate = np.round(start * (1 - mix) + target * mix)
        level = luminance(candidate)
        if (max(level, backdrop) + .05) / (min(level, backdrop) + .05) >= 3.0:
            return "#" + "".join(f"{int(value):02X}" for value in candidate)
    return "#" + "".join(f"{int(value):02X}" for value in target)


def harmonize_fit(image, colors):
    """Tint neutral glyphs toward the theme; preserve artwork, alpha and dark outlines."""
    if "primary" not in colors:
        return image
    rgba = np.array(image.convert("RGBA"))
    opaque = rgba[:, :, 3] > 180
    coverage = opaque.mean()
    if not (16 < opaque.sum() and .02 < coverage < .78):
        return image
    sample = rgba[:, :, :3][opaque].astype(np.float32)
    saturation = (sample.max(axis=1) - sample.min(axis=1)) / np.maximum(32, sample.max(axis=1))
    if np.percentile(saturation, 85) > .13:
        return image
    target = np.array(list(bytes.fromhex(colors.get("accent", colors["primary"])[1:])), dtype=np.float32)
    brightness = sample.mean(axis=1)
    strength = np.clip((brightness - 28) / 135, 0, .82) * np.clip((.20 - saturation) / .20, 0, 1)
    rgba[:, :, :3][opaque] = np.clip(sample * (1 - strength[:, None])
                                    + target * strength[:, None], 0, 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def harmonize_color(image, colors):
    """Rotate branded hues together, retaining each icon's relative hue and alpha."""
    if "accent" not in colors:
        return image
    original = image.convert("RGBA")
    rgba = np.array(original)
    hsv = np.array(original.convert("RGB").convert("HSV"))
    visible = rgba[:, :, 3] > 180
    colorful = visible & (hsv[:, :, 1] > 52) & (hsv[:, :, 2] > 65)
    if colorful.sum() < 40 or colorful.sum() < visible.sum() * .15:
        return image
    histogram = np.bincount((hsv[:, :, 0][colorful] // 16).astype(np.int32), minlength=16)
    occupied = histogram >= max(20, int(colorful.sum() * .035))
    # Adjacent hue bins form one gradient. Up to five separate solid hues
    # retain their relative spacing under the same bounded rotation.
    hue_groups = sum(bool(occupied[i] and not occupied[(i - 1) % 16]) for i in range(16))
    if occupied.sum() > 12 or hue_groups > 5:
        return image
    accent = Image.new("RGB", (1, 1), colors["accent"]).convert("HSV").getpixel((0, 0))[0]
    # Rotate the full wheel toward the theme, then gently bias neighboring
    # hues toward its analogous/complementary spokes. The mapping is shared by
    # every icon, so red/green/blue distinctions and family identities remain.
    rotation = int(np.clip(((accent - 155 + 128) % 256 - 128) * .23, -18, 18))
    hue = hsv[:, :, 0][colorful].astype(np.float32)
    warp = 4 * np.sin(2 * np.pi * (hue - accent) / 256)
    hsv[:, :, 0][colorful] = np.mod(hue + rotation + warp, 256).astype(np.uint8)
    hsv[:, :, 1][colorful] = np.clip(hsv[:, :, 1][colorful].astype(np.float32) * .91, 0, 255).astype(np.uint8)
    rgb = np.asarray(Image.fromarray(hsv, "HSV").convert("RGB"))
    rgba[:, :, :3][colorful] = rgb[colorful]
    return Image.fromarray(rgba, "RGBA")


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
    """Render both generated artwork and instant editor previews identically."""
    adjustments = adjustments or {}
    transformed = (extend_rounded_square(image) if presentation == "extend" else
                   remove_border_background(image) if presentation == "remove-background" else None)
    if presentation in ("extend", "remove-background") and transformed is None:
        presentation = "fit"
    adapted = (contain(transformed) if presentation == "remove-background" else
               transformed if presentation == "extend" else contain(image))
    if presentation == "fill" and adapted.getchannel("A").getextrema()[0] < 255:
        adapted = extend_exterior_edges(adapted)
    if not is_game:
        original = adapted
        if presentation == "fit":
            adapted = harmonize_fit(adapted, colors)
        adapted = harmonize_color(adapted, colors)
        strength = max(0, min(1, float(adjustments.get("strength", 1))))
        if strength != 1:
            adapted = Image.blend(original, adapted, strength)
    hue_shift = int(adjustments.get("hue_shift", 0))
    saturation = float(adjustments.get("saturation", 1))
    if hue_shift or saturation != 1:
        rgba = np.array(adapted)
        hsv = np.array(adapted.convert("RGB").convert("HSV"))
        colored = (rgba[:, :, 3] > 8) & (hsv[:, :, 1] > 28)
        hsv[:, :, 0][colored] = (hsv[:, :, 0][colored].astype(np.int16) + round(hue_shift * 256 / 360)) % 256
        hsv[:, :, 1][colored] = np.clip(hsv[:, :, 1][colored].astype(np.float32) * saturation, 0, 255).astype(np.uint8)
        rgba[:, :, :3][colored] = np.asarray(Image.fromarray(hsv, "HSV").convert("RGB"))[colored]
        adapted = Image.fromarray(rgba, "RGBA")
    return adapted, presentation


def source_key(source, theme, presentation):
    return hashlib.sha256(source + theme.encode() + presentation.encode()
                          + str(POLICY_VERSION).encode()).hexdigest()
