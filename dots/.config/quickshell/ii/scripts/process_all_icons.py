#!/usr/bin/env python3
"""Offline launcher icon cache builder; --cache-dir permits safe staging and previews."""
import argparse
import configparser
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
import numpy as np

from adaptive_icon_policy import (POLICY_VERSION, classify, compose_icon,
                                  choose_backplate, extend_rounded_square, full_bleed_tile, icon_backplates,
                                  render_adaptive, source_key, trim_visible)

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


def desktop_entries(directories, manifest=None):
    entries = {}
    try:
        originals = json.loads((manifest or DEFAULT_CACHE / "global-icons.json").read_text())
    except (OSError, ValueError):
        originals = {}
    for folder in directories:
        for filename in sorted(glob.glob(str(folder / "*.desktop"))):
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                app_id = Path(filename).stem
                text = Path(filename).read_text(encoding="utf-8")
                if text.startswith("# Managed by global_app_icons.py;") and app_id in originals:
                    text = originals[app_id]["original"]
                parser.read_string(text)
                if parser.has_section("Desktop Entry"):
                    entries[app_id] = dict(parser["Desktop Entry"])
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
    chosen = Path(source_override) if source_override is not None else source or game_tile
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
    if is_game and not requested:
        if (max(image.size) / max(1, min(image.size)) <= 1.08
                and presentation == "fill"):
            presentation, confidence, reason = "fill", 1, "square game icon clipped to squircle"
        else:
            presentation, confidence, reason = "fit", 1, "shaped game launcher icon"
    adapted, final_presentation = render_adaptive(image, presentation, {}, is_game)
    if final_presentation != presentation:
        confidence, reason = .25, "unsafe border operation; retained original"
        presentation = final_presentation
    key = source_key(original, "", presentation)
    processed = cache / "adaptive" / (key + ".png")
    if adapted.getchannel("A").getbbox() is None:
        return None
    backplates = icon_backplates(adapted)
    if not processed.exists():
        buffer = io.BytesIO()
        adapted.save(buffer, format="PNG")
        atomic_bytes(processed, buffer.getvalue())
    variants = {}
    for mode, background in backplates.items():
        target = cache / "adaptive" / (source_key(original, background, presentation) + "-" + mode + ".png")
        if not target.exists():
            buffer = io.BytesIO()
            compose_icon(adapted, background, presentation).save(buffer, format="PNG")
            atomic_bytes(target, buffer.getvalue())
        variants[mode] = str(target)
    return {"path": str(processed), "source": str(chosen), "source_hash": hashlib.sha256(original).hexdigest(),
            "source_family": "Papirus" if chosen.is_relative_to(APP_THEME) else "original",
            "fill": presentation in ("fill", "extend", "bleed"), "presentation": presentation,
            "bg_light": backplates["light"], "bg_dark": backplates["dark"],
            "path_light": variants["light"], "path_dark": variants["dark"],
            "confidence": confidence, "reason": reason, "is_game": is_game, "policy_version": POLICY_VERSION,
            "app_id": app_id, "name": desktop.get("name", app_id)}



def harmonize_families(meta, cache):
    entries = {entry["app_id"]: entry for entry in meta.values()
               if entry.get("path_light") and entry.get("path_dark")}
    groups = {}
    for entry in entries.values():
        app_id = entry["app_id"].lower()
        # Only a documented suite or an exact vendor/app prefix establishes kinship.
        family = ("libreoffice" if app_id.startswith("libreoffice-") else
                  app_id.rsplit(".", 1)[0] if app_id.count(".") >= 2 else
                  app_id.rsplit("-", 1)[0] if app_id.count("-") >= 2 else None)
        if family and family not in {"org.gnome", "org.kde", "com.github", "io.github"}:
            groups.setdefault(family, []).append(entry)
    assigned = set()
    for family, members in sorted(groups.items(), key=lambda pair: (-len(pair[1]), -len(pair[0]))):
        members = [entry for entry in members if entry["app_id"] not in assigned]
        if len(members) < 2:
            continue
        images = []
        for entry in members:
            with Image.open(entry["path"]) as image:
                images.append(image.convert("RGBA"))
        for mode in ("light", "dark"):
            background = choose_backplate(images, mode)
            for entry in members:
                entry["bg_" + mode] = background
                entry["bg_family"] = family
                with Image.open(entry["path"]) as image:
                    buffer = io.BytesIO()
                    compose_icon(image.convert("RGBA"), background, entry["presentation"]).save(
                        buffer, format="PNG")
                variant_key = source_key(bytes.fromhex(entry["source_hash"]), family + background,
                                         entry["presentation"] + mode)
                target = cache / "adaptive" / (variant_key + "-" + mode + ".png")
                if not target.is_file() or target.read_bytes() != buffer.getvalue():
                    atomic_bytes(target, buffer.getvalue())
                entry["path_" + mode] = str(target)
        assigned.update(entry["app_id"] for entry in members)


def build(cache, theme, overrides, directories):
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / ".adaptive.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        entries = desktop_entries(directories, cache / "global-icons.json")
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
            entry = metadata_for(app_id, desktop, {}, "", cache, overrides)
            if not entry:
                old = previous.get(app_id + ".desktop") or previous.get(app_id)
                if (isinstance(old, dict) and old.get("policy_version") == POLICY_VERSION
                        and isinstance(old.get("path"), str) and old["path"]
                        and Path(old["path"]).is_file()):
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
        harmonize_families(meta, cache)
        encoded = json.dumps(meta, indent=2).encode()
        if not destination.exists() or destination.read_bytes() != encoded:
            atomic_bytes(destination, encoded)
        keep = {Path(e[field]).name for e in meta.values()
                for field in ("path", "path_light", "path_dark") if e.get(field)}
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
    if args.cache_dir == DEFAULT_CACHE:
        from global_app_icons import export
        mode_file = args.cache_dir / "appearance-mode"
        mode = mode_file.read_text().strip() if mode_file.is_file() else "dark"
        export(meta, mode if mode in ("light", "dark") else "dark")
    print(f"Indexed {len(meta)} aliases for {len({entry['app_id'] for entry in meta.values()})} apps")


if __name__ == "__main__":
    main()
