#!/usr/bin/env python3
"""Offline launcher icon cache builder; --cache-dir permits safe staging and previews."""
import argparse
import configparser
from collections import defaultdict
import fcntl
import glob
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

from PIL import Image

from adaptive_icon_policy import (POLICY_VERSION, choose_background, classify, contrast_surface,
                                  extend_rounded_square, full_bleed_tile, render_adaptive,
                                  source_key, theme_colors, trim_visible)

try:
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
except (ImportError, ValueError):
    Gtk = None

DEFAULT_CACHE = Path.home() / ".cache/quickshell/game_icons"
DEFAULT_THEME = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "quickshell/user/generated/colors.json"
APP_THEME = Path("/usr/share/icons/Papirus/64x64/apps")
FIT_IDS = {"org.kde.dolphin", "org.gnome.Nautilus", "org.gnome.FileRoller",
           "btop", "virt-manager", "nwg-displays", "nm-connection-editor",
           "avahi-discover", "bssh", "bvnc", "gtk-lshw", "systemsettings",
           "kdesystemsettings", "org.telegram.desktop", "io.gitlab.adhami3310.Converter"}
ICON_OVERRIDES = {
    "Alacritty": "/usr/share/pixmaps/Alacritty.svg",
    "avahi-discover": "network-workgroup", "bssh": "network-server",
    "bvnc": "video-display", "btop": "/usr/share/icons/hicolor/scalable/apps/btop.svg",
    "nm-connection-editor": "preferences-system-network",
    "nwg-displays": "nwg-displays", "org.telegram.desktop": "org.telegram.desktop",
    "systemsettings": "preferences-system", "kdesystemsettings": "preferences-system",
    "io.gitlab.adhami3310.Converter": "io.gitlab.adhami3310.Converter",
    "gtk-lshw": "gtk-lshw", "unityhub-unity-editor-6000.3.1f1": "unityhub",
}
for component in ("base", "calc", "draw", "impress", "math", "writer"):
    ICON_OVERRIDES["libreoffice-" + component] = "libreoffice-" + component


def atomic_bytes(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(dir=path.parent, prefix=".icon-")
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def desktop_entries(directories):
    entries = {}
    for folder in directories:
        for filename in sorted(glob.glob(str(folder / "*.desktop"))):
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                parser.read(filename, encoding="utf-8")
                if parser.has_section("Desktop Entry"):
                    entries[Path(filename).stem] = dict(parser["Desktop Entry"])
            except (OSError, configparser.Error):
                continue
    return entries


def resolve_icon(name):
    if not name:
        return None
    if Path(name).is_absolute():
        return Path(name) if Path(name).is_file() else None
    if Gtk:
        try:
            info = Gtk.IconTheme.get_default().lookup_icon(name, 48, 0)
            if info and info.get_filename():
                return Path(info.get_filename())
        except Exception:
            pass
    for base in (Path.home() / ".local/share/icons/hicolor/256x256/apps",
                 Path("/usr/share/pixmaps")):
        for suffix in ("", ".png", ".svg", ".xpm"):
            candidate = base / (name + suffix)
            if candidate.is_file():
                return candidate
    return None


def load_icon(path):
    if path.suffix.lower() == ".svg":
        result = subprocess.run(["rsvg-convert", "-w", "256", path],
                                capture_output=True, check=True, timeout=8)
        return Image.open(io.BytesIO(result.stdout)).convert("RGBA")
    with Image.open(path) as image:
        image.thumbnail((512, 512))
        return image.convert("RGBA")
def themed_icon(names):
    """Resolve only exact application-icon identities within the chosen family."""
    for name in names:
        if not isinstance(name, str) or not name or "/" in name or "\\" in name or name.startswith("."):
            continue
        for candidate in (name, name.lower()):
            path = APP_THEME / (candidate + ".svg")
            if path.is_file() and path.resolve().is_relative_to(APP_THEME.parent.parent):
                return path
    return None


def identity_icon(app_id, desktop):
    label = re.sub(r"[^a-z0-9]+", "-", desktop.get("name", "").lower()).strip("-")
    suffix = app_id.rsplit(".", 1)[-1]
    return themed_icon((app_id, desktop.get("icon", ""), desktop.get("startupwmclass", ""),
                        label, suffix))


def metadata_for(app_id, desktop, colors, theme_hash, cache, overrides, source_override=None):
    icon_name = ICON_OVERRIDES.get(app_id, desktop.get("icon", ""))
    source = resolve_icon(icon_name)
    is_game = "Game" in desktop.get("categories", "").split(";")
    policy = overrides.get(app_id, {})
    if not isinstance(policy, dict):
        policy = {}
    replacement = policy.get("alternate_icon")
    if not is_game:
        source = themed_icon((replacement,)) or identity_icon(app_id, desktop) or source
    game_tile = None
    if is_game:
        import re
        match = re.search(r"(?:rungameid/|steam_icon_)(\d+)",
                          desktop.get("exec", "") + " " + icon_name)
        if match:
            candidate = DEFAULT_CACHE / (match[1] + ".png")
            if candidate.is_file():
                game_tile = candidate
    chosen = Path(source_override) if source_override is not None else game_tile or source
    if not chosen:
        return None
    try:
        before = chosen.stat()
        original = chosen.read_bytes()
        image = load_icon(chosen)
        if image.getchannel("A").getbbox() is None:
            return None
        image = trim_visible(image)
        after = chosen.stat()
        if (before.st_mtime_ns, before.st_size) != (after.st_mtime_ns, after.st_size):
            return None
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    requested = policy.get("presentation")
    if requested and requested not in ("fit", "fill", "extend", "bleed", "remove-background"):
        requested = None
    presentation, confidence, reason = classify(image, requested)
    if app_id in FIT_IDS and not requested:
        presentation, confidence, reason = "fit", 1, "reviewed shaped icon"
    if not requested and presentation in ("fit", "fill") and not is_game and app_id not in FIT_IDS:
        if extend_rounded_square(image) is not None:
            presentation, confidence, reason = "extend", .9, "uniform rounded tile with safe corner extension"
        elif full_bleed_tile(image) and app_id not in {"org.kde.dolphin", "org.gnome.Nautilus"}:
            presentation, confidence, reason = "bleed", .9, "near-full square tile clipped by outer squircle"
    if is_game and not requested:
        if (max(image.size) / max(1, min(image.size)) <= 1.08
                and (chosen.is_relative_to(DEFAULT_CACHE) or presentation == "fill")):
            presentation, confidence, reason = "fill", 1, "square game icon clipped to squircle"
        else:
            presentation, confidence, reason = "fit", 1, "shaped game launcher icon"
    adapted, final_presentation = render_adaptive(image, presentation, colors, is_game, policy)
    if final_presentation != presentation:
        confidence, reason = .25, "unsafe border operation; retained original"
        presentation = final_presentation
    key = source_key(original, theme_hash + json.dumps(
        {k: policy.get(k) for k in ("hue_shift", "saturation", "strength")}, sort_keys=True), presentation)
    processed = cache / "adaptive" / (key + ".png")
    if adapted.getchannel("A").getbbox() is None:
        return None
    bg, role = choose_background(adapted, colors)
    if policy.get("bg_color"):
        supplied = policy["bg_color"]
        if isinstance(supplied, str) and len(supplied) == 7:
            try:
                bytes.fromhex(supplied[1:]) if supplied[0] == "#" else 1 / 0
                bg, role = supplied.upper(), "override"
            except (ValueError, ZeroDivisionError):
                pass
    if not processed.exists():
        buffer = io.BytesIO()
        adapted.save(buffer, format="PNG")
        atomic_bytes(processed, buffer.getvalue())
    return {"path": str(processed), "source": str(chosen), "source_hash": hashlib.sha256(original).hexdigest(),
            "source_family": "Papirus" if chosen.is_relative_to(APP_THEME) else "original",
            "fill": presentation in ("fill", "extend", "bleed"), "presentation": presentation, "bg_color": bg, "bg_role": role,
            "confidence": confidence, "reason": reason, "is_game": is_game, "policy_version": POLICY_VERSION,
            "app_id": app_id, "name": desktop.get("name", app_id)}


def harmonize_families(meta, colors):
    """Use one theme backplate per identifiable software suite."""
    entries = {entry["app_id"]: entry for entry in meta.values()}
    ignored = {"desktop", "application", "system", "manager", "gnome", "plasma",
               "kde", "quickshell", "settings", "freedesktop", "handler", "portal", "mobile"}
    members = defaultdict(list)
    for app_id, entry in entries.items():
        if entry["is_game"] or entry["bg_role"] == "override":
            continue
        for token in set(re.findall(r"[a-z]{6,}", app_id.lower())) - ignored:
            members[token].append(entry)
    for family, group in members.items():
        if len(group) < 3:
            continue
        color = contrast_surface(colors.get("secondary", colors["neutral"]),
                                 colors.get("drawer", colors["neutral"]),
                                 colors.get("accent", colors["neutral"]))
        for entry in group:
            if entry["bg_role"] != "override":
                entry["bg_color"], entry["bg_role"] = color, "family-" + family


def build(cache, theme, overrides, directories):
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / ".adaptive.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        colors = theme_colors(theme)
        theme_hash = hashlib.sha256(json.dumps(colors, sort_keys=True).encode()).hexdigest()
        entries = desktop_entries(directories)
        destination = cache / "app_icons_meta.json"
        try:
            previous = json.loads(destination.read_text())
        except (OSError, ValueError):
            previous = {}
        icon_counts = {}
        for app in entries.values():
            name = app.get("icon", "")
            icon_counts[name] = icon_counts.get(name, 0) + 1
        meta = {}
        for app_id, desktop in entries.items():
            entry = metadata_for(app_id, desktop, colors, theme_hash, cache, overrides)
            if not entry:
                old = previous.get(app_id + ".desktop") or previous.get(app_id)
                if isinstance(old, dict) and isinstance(old.get("path"), str) and old["path"] and Path(old["path"]).is_file():
                    entry = dict(old, app_id=app_id, name=desktop.get("name", app_id))
                    entry.setdefault("source", old["path"])
                    entry.setdefault("confidence", 0)
                    entry.setdefault("is_game", "Game" in desktop.get("categories", "").split(";"))
                else:
                    continue
            keys = (app_id + ".desktop", app_id, app_id.lower(), desktop.get("name", ""),
                    desktop.get("startupwmclass", ""))
            for key in keys:
                if key:
                    meta[key] = entry
                    meta[key.lower()] = entry
            icon_name = desktop.get("icon", "")
            if icon_name and icon_counts[icon_name] == 1 and icon_name not in (
                    "steam", "network-wired", "document-new", "application-exit",
                    "window-new", "preferences-system"):
                meta[icon_name] = entry
        harmonize_families(meta, colors)
        encoded = json.dumps(meta, indent=2).encode()
        if not destination.exists() or destination.read_bytes() != encoded:
            atomic_bytes(destination, encoded)
        keep = {Path(e["path"]).name for e in meta.values()}
        stale = sorted((image for image in (cache / "adaptive").glob("*.png")
                        if image.name not in keep), key=lambda image: image.stat().st_mtime)
        max_stale = max(256, len(keep))
        for index, image in enumerate(stale):
            if len(stale) - index > max_stale + 256 or (
                    len(stale) - index > max_stale and time.time() - image.stat().st_mtime > 3600):
                image.unlink()
        return meta


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--theme", type=Path, default=DEFAULT_THEME)
    parser.add_argument("--overrides", type=Path)
    parser.add_argument("--desktop-dir", type=Path, action="append")
    args = parser.parse_args()
    if args.overrides is None:
        hints = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "quickshell/borg-intelligence/icon-hints.json"
        if hints.is_file():
            args.overrides = hints
    try:
        overrides = json.loads(args.overrides.read_text()) if args.overrides else {}
        if not isinstance(overrides, dict):
            raise ValueError("overrides must be an object")
    except (OSError, ValueError) as error:
        parser.error(str(error))
    folders = args.desktop_dir or [Path("/usr/share/applications"),
                                  Path.home() / ".local/share/applications"]
    meta = build(args.cache_dir, args.theme, overrides, folders)
    print(f"Indexed {len(meta)} aliases for {len({entry['app_id'] for entry in meta.values()})} apps")


if __name__ == "__main__":
    main()
