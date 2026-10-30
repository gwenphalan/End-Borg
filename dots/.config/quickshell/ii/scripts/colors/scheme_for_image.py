#!/usr/bin/env python3
import sys
import numpy as np
from PIL import Image, UnidentifiedImageError

# Allowed scheme types
SCHEMES = [
    "scheme-content",
    "scheme-expressive",
    "scheme-fidelity",
    "scheme-fruit-salad",
    "scheme-monochrome",
    "scheme-neutral",
    "scheme-rainbow",
    "scheme-tonal-spot"
]

def image_colorfulness(image):
    """Retain the numeric diagnostic exposed by --colorfulness (RGB input)."""
    red, green, blue = np.moveaxis(image.astype(np.float64), -1, 0)
    rg = np.abs(red - green)
    yb = np.abs((red + green) / 2 - blue)
    return float(np.hypot(np.std(rg), np.std(yb)) +
                 0.3 * np.hypot(np.mean(rg), np.mean(yb)))

def pick_scheme(image):
    pixels = image.reshape(-1, 3).astype(np.float32) / 255
    highest = pixels.max(axis=1)
    lowest = pixels.min(axis=1)
    chroma = highest - lowest
    saturation = chroma / np.maximum(highest, 1 / 255)
    colorful = (saturation >= 0.18) & (chroma >= 0.07)

    # A dark but strongly tinted image is not grayscale: compare channel
    # separation relative to brightness, not only absolute colorfulness.
    if np.mean(saturation >= 0.08) < 0.05:
        return "scheme-monochrome"
    if np.mean(colorful) < 0.12:
        return "scheme-neutral"

    # Content can amplify saturation. Reserve it for moderately colored,
    # predominantly single-hue images; mixed or vivid images keep tonal spot.
    if np.mean(colorful) >= 0.35 and np.median(saturation[colorful]) < 0.55:
        selected = pixels[colorful]
        weights = chroma[colorful]
        red, green, blue = selected.T
        hue_x = 2 * red - green - blue
        hue_y = np.sqrt(3) * (green - blue)
        coherence = np.hypot(np.sum(hue_x * weights), np.sum(hue_y * weights))
        total = np.sum(np.hypot(hue_x, hue_y) * weights)
        if total > 0 and coherence / total >= 0.8:
            return "scheme-content"
    return "scheme-tonal-spot"

def load_and_resize_image(img_path, max_dim=128):
    try:
        with Image.open(img_path) as source:
            source.thumbnail((max_dim, max_dim), Image.Resampling.BOX)
            return np.asarray(source.convert("RGB"))
    except (OSError, ValueError, UnidentifiedImageError):
        return None

def main():
    colorfulness_mode = False
    args = sys.argv[1:]
    if '--colorfulness' in args:
        colorfulness_mode = True
        args.remove('--colorfulness')
    if len(args) < 1:
        print("scheme-tonal-spot")
        sys.exit(1)
    img_path = args[0]
    img = load_and_resize_image(img_path)
    if img is None:
        print("scheme-tonal-spot")
        sys.exit(1)
    colorfulness = image_colorfulness(img)
    if colorfulness_mode:
        print(f"{colorfulness}")
    else:
        scheme = pick_scheme(img)
        print(scheme)

if __name__ == "__main__":
    main()
