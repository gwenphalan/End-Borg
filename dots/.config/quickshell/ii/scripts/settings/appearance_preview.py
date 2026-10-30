#!/usr/bin/env python3
"""Generate Settings-only Material roles without writing templates or config."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

SCHEMES = {"scheme-" + name for name in (
    "content", "expressive", "fidelity", "fruit-salad", "monochrome", "neutral",
    "rainbow", "tonal-spot",
)}
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".avi", ".mov"}


def run(command, timeout=15):
    return subprocess.run(command, check=True, capture_output=True, text=True, timeout=timeout).stdout


def mode_wallpaper(path, mode):
    """Match switchwall.sh's explicit light/dark sibling selection."""
    name = path.stem.removesuffix("-dark").removesuffix("-light")
    for candidate in (path.with_name(name + "-" + mode + path.suffix), path.with_name(name + path.suffix)):
        if candidate.is_file():
            return candidate
    return path


def generate(accent, mode, image, scheme, detector):
    original = Path(image)
    # Auto detection precedes sibling selection and video extraction in switchwall.
    if scheme not in SCHEMES:
        scheme = "scheme-tonal-spot"
        if image and original.is_file() and original.suffix.lower() not in VIDEO_EXTENSIONS:
            try:
                detected = run([sys.executable, detector, image], timeout=10).strip()
                if detected in SCHEMES:
                    scheme = detected
            except (OSError, subprocess.SubprocessError):
                pass  # switchwall uses tonal spot when its detector cannot read a source.
    if accent and not re.fullmatch(r"#[0-9a-fA-F]{6}", accent):
        raise ValueError("Accent must contain six hexadecimal digits")
    with tempfile.TemporaryDirectory(prefix="qs-settings-theme-") as temporary:
        command = ["matugen", "--dry-run", "--json", "hex", "--mode", mode, "--type", scheme]
        if accent:
            command += ["color", "hex", accent]
        else:
            source = mode_wallpaper(original, mode)
            if not image or not source.is_file():
                raise FileNotFoundError("Wallpaper source is unavailable")
            if source.suffix.lower() in VIDEO_EXTENSIONS:
                frame = Path(temporary) / "frame.jpg"
                run(["ffmpeg", "-y", "-i", str(source), "-vframes", "1", str(frame)])
                source = frame
            command += ["image", str(source)]
        colors = json.loads(run(command))["colors"][mode]
        if not all(re.fullmatch(r"#[0-9a-fA-F]{6}", colors.get(role, ""))
                   for role in ("background", "on_background", "primary", "on_primary")):
            raise ValueError("The color engine returned incomplete Material roles")
        return {"colors": colors, "scheme": scheme, "mode": mode}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("accent")
    parser.add_argument("mode", choices=("light", "dark"))
    parser.add_argument("image")
    parser.add_argument("scheme")
    parser.add_argument("detector")
    args = parser.parse_args()
    try:
        result = generate(args.accent, args.mode, args.image, args.scheme, args.detector)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as error:
        print(json.dumps({"error": str(error)}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
