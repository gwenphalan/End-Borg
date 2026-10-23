#!/usr/bin/env python3
"""One-shot local backend for the Quickshell icon review window."""
from io import BytesIO
import hashlib
import json
import os
from pathlib import Path
from subprocess import SubprocessError
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from adaptive_icon_policy import render_adaptive, theme_colors
from process_all_icons import DEFAULT_CACHE, DEFAULT_THEME, atomic_bytes, load_icon, trim_visible

STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "quickshell"
REVIEWS = STATE / "icon-review/reviews.json"
LABELS = STATE / "borg-intelligence/launcher-labels.json"
ALTERNATIVES = REVIEWS.parent / "alternatives"
PREVIEWS = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "quickshell/icon-review/previews"
FIELDS = {"flag", "note", "presentation", "bg_color", "hue_shift", "saturation", "strength", "alternate_icon"}
PRESENTATIONS = {"fit", "fill", "extend", "bleed", "remove-background"}
IMAGE_SUFFIXES = {".png", ".svg", ".webp", ".jpg", ".jpeg", ".xpm"}


def records():
    with (DEFAULT_CACHE / "app_icons_meta.json").open() as source:
        data = json.load(source)
    return {entry["app_id"]: entry for entry in data.values()
            if isinstance(entry, dict) and entry.get("app_id") and entry.get("path") and entry.get("source")}


def reviews():
    try:
        data = json.loads(REVIEWS.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}

def launcher_labels():
    try:
        return json.loads(LABELS.read_text()).get("labels", {})
    except (OSError, ValueError):
        return {}


def validate(data):
    if not isinstance(data, dict) or set(data) - FIELDS:
        raise ValueError("Unknown review field")
    result = {}
    for field in ("flag", "note", "presentation", "bg_color"):
        value = data.get(field, "")
        if not isinstance(value, str):
            raise ValueError("Invalid " + field)
        if field == "flag" and value not in ("", "looks good", "needs work"):
            raise ValueError("Invalid review flag")
        if field == "note" and len(value) > 500:
            raise ValueError("Note exceeds 500 characters")
        if field == "presentation" and value not in PRESENTATIONS | {""}:
            raise ValueError("Invalid icon presentation")
        if field == "bg_color" and value and (len(value) != 7 or value[0] != "#" or
                                                any(c not in "0123456789abcdefABCDEF" for c in value[1:])):
            raise ValueError("Invalid hex color")
        if value:
            result[field] = value.upper() if field == "bg_color" else value
    for field, low, high, default in (("hue_shift", -90, 90, 0),
                                     ("saturation", .5, 1.5, 1), ("strength", 0, 1, 1)):
        if field not in data:
            continue
        value = data[field]
        if isinstance(value, bool) or not isinstance(value, (float, int)) or not low <= value <= high:
            raise ValueError("Invalid " + field)
        if value != default:
            result[field] = round(value, 2)
    if "alternate_icon" in data:
        selected = data["alternate_icon"]
        if not isinstance(selected, str) or len(selected) > 1024:
            raise ValueError("Invalid alternative icon")
        if selected:
            source = Path(selected)
            if (not source.is_absolute() or source.suffix.lower() not in IMAGE_SUFFIXES
                    or not source.is_file() or not 0 < source.stat().st_size <= 15 * 1024 * 1024):
                raise ValueError("Alternative icon must be a local image file under 15 MB")
            resolved = source.resolve()
            if resolved.suffix.lower() not in IMAGE_SUFFIXES:
                raise ValueError("Alternative icon must be an image file")
            result["alternate_icon"] = str(resolved)
    return result


def handle(request):
    if not isinstance(request, dict):
        raise ValueError("Invalid request")
    operation = request.get("operation")
    if operation == "catalog":
        return {"apps": sorted(records().values(), key=lambda app: app["name"].casefold()),
                "reviews": reviews(), "labels": launcher_labels(), "theme": theme_colors(DEFAULT_THEME)}
    if operation not in ("preview", "save"):
        raise ValueError("Unknown operation")
    app_id = request.get("id")
    entry = records().get(app_id) if isinstance(app_id, str) else None
    if entry is None:
        raise ValueError("Unknown application")
    review = validate(request.get("review"))
    if operation == "save":
        all_reviews = reviews()
        existing = all_reviews.get(app_id)
        existing = dict(existing) if isinstance(existing, dict) else {}
        for field in FIELDS:
            existing.pop(field, None)
        if review.get("alternate_icon"):
            chosen = Path(review["alternate_icon"])
            image = load_icon(chosen)
            if image.getchannel("A").getbbox() is None:
                raise ValueError("Alternative icon has no visible pixels")
            content = chosen.read_bytes()
            name = hashlib.sha256(content).hexdigest() + chosen.suffix.lower()
            destination = ALTERNATIVES / name
            if not destination.exists():
                atomic_bytes(destination, content)
            review["alternate_icon"] = str(destination)
        existing.update(review)
        if existing:
            all_reviews[app_id] = existing
        else:
            all_reviews.pop(app_id, None)
        atomic_bytes(REVIEWS, json.dumps(all_reviews, indent=2).encode())
        return {"saved": existing}
    source = Path(review.get("alternate_icon") or entry["source"])
    image = trim_visible(load_icon(source))
    presentation = review.get("presentation") or entry["presentation"]
    rendered, _ = render_adaptive(image, presentation, theme_colors(DEFAULT_THEME),
                                  entry.get("is_game", False), review)
    output = BytesIO()
    rendered.save(output, "PNG")
    content = output.getvalue()
    key = hashlib.sha256(content).hexdigest()
    destination = PREVIEWS / (key + ".png")
    if not destination.is_file():
        atomic_bytes(destination, content)
    return {"path": str(destination)}


def main():
    try:
        request = json.loads(sys.stdin.read(4096))
        print(json.dumps({"ok": True, "result": handle(request)}))
    except (ValueError, KeyError, OSError, TimeoutError, RuntimeError, SubprocessError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
