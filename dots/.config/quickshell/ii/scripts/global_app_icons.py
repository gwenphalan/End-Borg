"""Publish generated icons for all desktop consumers without changing vendor files."""
import argparse
import configparser
import json
from pathlib import Path

from process_all_icons import DEFAULT_CACHE, atomic_bytes

HOME = Path.home()
APPLICATIONS = HOME / ".local/share/applications"
ICONS = HOME / ".local/share/icons/hicolor/256x256/apps"
THEME_INDEX = Path("/usr/share/icons/hicolor/index.theme")
MANIFEST = DEFAULT_CACHE / "global-icons.json"
MARKER = "# Managed by global_app_icons.py; source is preserved in the icon manifest."


def original_desktop(app_id):
    local = APPLICATIONS / (app_id + ".desktop")
    if local.is_file():
        text = local.read_text()
        if not text.startswith(MARKER):
            return text, str(local)
    system = Path("/usr/share/applications") / (app_id + ".desktop")
    if system.is_file():
        return system.read_text(), str(system)
    return None, None


def export(meta, mode, manifest=MANIFEST, applications=APPLICATIONS, icons=ICONS):
    """Install only managed overrides; never overwrite an unowned local entry."""
    if mode not in ("light", "dark"):
        raise ValueError("mode must be light or dark")
    try:
        records = json.loads(manifest.read_text())
    except (OSError, ValueError):
        records = {}
    applications.mkdir(parents=True, exist_ok=True)
    icons.mkdir(parents=True, exist_ok=True)
    index = icons.parent.parent / "index.theme"
    if not index.exists() and THEME_INDEX.is_file():
        index.symlink_to(THEME_INDEX)
    entries = {entry["app_id"]: entry for entry in meta.values() if entry.get("path_" + mode)}
    for app_id, entry in entries.items():
        icon_name = "quickshell-generated-" + app_id.replace("/", "-")
        target = applications / (app_id + ".desktop")
        record = records.get(app_id)
        if record:
            if not target.is_file() or not target.read_text().startswith(MARKER):
                continue
            original = record["original"]
        else:
            if target.is_file() and target.read_text().startswith(MARKER):
                continue
            if target.is_file():
                original, source = target.read_text(), str(target)
            else:
                original, source = original_desktop(app_id)
            if original is None:
                continue
            record = {"original": original, "source": source}
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            parser.read_string(original)
            if not parser.has_section("Desktop Entry"):
                continue
        except configparser.Error:
            continue
        icon_file = icons / (icon_name + ".png")
        source_image = Path(entry["path_" + mode])
        if not source_image.is_file():
            continue
        if not icon_file.is_file() or icon_file.read_bytes() != source_image.read_bytes():
            atomic_bytes(icon_file, source_image.read_bytes())
        # Preserve all original keys, translations, actions, and comments.
        lines = original.splitlines(keepends=True)
        in_entry = False
        changed = False
        output = [MARKER + "\n"]
        for line in lines:
            if line.startswith("["):
                if in_entry and not changed:
                    output.append("Icon=" + icon_name + "\n")
                    changed = True
                in_entry = line.strip() == "[Desktop Entry]"
            if in_entry and line.startswith("Icon="):
                line = "Icon=" + icon_name + "\n"
                changed = True
            output.append(line)
        if in_entry and not changed:
            output.append("Icon=" + icon_name + "\n")
        rendered = "".join(output)
        records[app_id] = record
        if target.is_file() and target.read_text().startswith(MARKER):
            previous_render = record.get("rendered")
            if target.read_text() != (previous_render or rendered):
                continue
        record["rendered"] = rendered
        atomic_bytes(manifest, json.dumps(records, indent=2).encode())
        if not target.is_file() or target.read_text() != rendered:
            permissions = target.stat().st_mode if target.is_file() else None
            atomic_bytes(target, rendered.encode())
            if permissions is not None:
                target.chmod(permissions)
    atomic_bytes(manifest.parent / "appearance-mode", mode.encode())
    return len(records)


def restore(manifest=MANIFEST, applications=APPLICATIONS, icons=ICONS):
    """Restore only our untouched managed entries; keep user modifications."""
    records = json.loads(manifest.read_text())
    retained = {}
    for app_id, record in records.items():
        target = applications / (app_id + ".desktop")
        if not target.is_file() or target.read_text() != record.get("rendered"):
            retained[app_id] = record
            continue
        if record["source"] == str(target):
            atomic_bytes(target, record["original"].encode())
        else:
            target.unlink()
        icon = icons / ("quickshell-generated-" + app_id.replace("/", "-") + ".png")
        if icon.is_file():
            icon.unlink()
    if retained:
        atomic_bytes(manifest, json.dumps(retained, indent=2).encode())
    else:
        manifest.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("light", "dark"))
    parser.add_argument("--restore", action="store_true")
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE)
    args = parser.parse_args()
    if args.restore:
        restore(args.cache_dir / "global-icons.json")
    else:
        if not args.mode:
            parser.error("--mode is required")
        meta = json.loads((args.cache_dir / "app_icons_meta.json").read_text())
        print(f"Published {export(meta, args.mode, args.cache_dir / 'global-icons.json')} global icons")


if __name__ == "__main__":
    main()
