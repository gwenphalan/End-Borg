"""Publish generated icons for all desktop consumers without changing vendor files."""
import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re

from process_all_icons import DEFAULT_CACHE, application_directories, atomic_bytes, cache_lock

HOME = Path.home()
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
APPLICATIONS = DATA_HOME / "applications"
ICONS = DATA_HOME / "icons/hicolor/256x256/apps"
THEME_INDEX = Path("/usr/share/icons/hicolor/index.theme")
MANIFEST = DEFAULT_CACHE / "global-icons.json"
MARKER = "# Managed by global_app_icons.py; source is preserved in the icon manifest."

def generated_icon_name(app_id):
    """Keep safe IDs unchanged; distinguish normalized IDs with their own hash."""
    if not isinstance(app_id, str):
        raise ValueError("desktop app ID must be a string")
    if re.fullmatch(r"[A-Za-z0-9._-]+", app_id):
        return "quickshell-generated-" + app_id
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", app_id).strip("-")[:180] or "app"
    digest = hashlib.sha256(app_id.encode("utf-8")).hexdigest()[:12]
    return "quickshell-generated-" + slug + "-" + digest


def _legacy_icon_name(app_id):
    return "quickshell-generated-" + app_id.replace("/", "-")


def _desktop_icon_name(text):
    if text is None:
        return None
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read_string(text)
        return parser.get("Desktop Entry", "Icon", fallback=None)
    except configparser.Error:
        return None


def _record_icon_names(app_id, record):
    """Manifest data may authorize only this app's exact new or legacy token."""
    allowed = {generated_icon_name(app_id), _legacy_icon_name(app_id)}
    retired = record.get("retired_icon_names", [])
    names = [record.get("icon_name"), record.get("pending_icon_name")]
    if isinstance(retired, list):
        names.extend(retired)
    if "icon_name" not in record and "pending_icon_name" not in record:
        names.append(_legacy_icon_name(app_id))
    return {name for name in names if isinstance(name, str) and name in allowed}


def _remove_icon_names(names, app_id, records, applications, icons):
    """Do not remove an asset still referenced by another managed desktop ID."""
    remaining = set()
    for name in names:
        shared = False
        for other_id in records:
            if other_id == app_id:
                continue
            other = applications / (other_id + ".desktop")
            if other.is_file() and _desktop_icon_name(other.read_text()) == name:
                shared = True
                break
        if shared:
            remaining.add(name)
            continue
        path = icons / (name + ".png")
        if path.is_file() or path.is_symlink():
            path.unlink()
    return remaining


def original_desktop(app_id, origin=None):
    if origin:
        path = Path(origin)
        if path.is_absolute() and path.suffix == ".desktop" and path.is_file():
            text = path.read_text()
            if not text.startswith(MARKER):
                return text, str(path)
    local = APPLICATIONS / (app_id + ".desktop")
    if local.is_file():
        text = local.read_text()
        if not text.startswith(MARKER):
            return text, str(local)
    for folder in reversed(application_directories()):
        system = folder / (app_id + ".desktop")
        if system.is_file():
            text = system.read_text()
            if not text.startswith(MARKER):
                return text, str(system)
    return None, None


def export(meta, mode, manifest=MANIFEST, applications=APPLICATIONS, icons=ICONS):
    with cache_lock(manifest.parent):
        # A build may have completed while a theme switch waited for the lock.
        try:
            latest = json.loads((manifest.parent / "app_icons_meta.json").read_text())
        except (OSError, ValueError):
            latest = meta
        return _export(latest if isinstance(latest, dict) else meta,
                       mode, manifest, applications, icons)


def _export(meta, mode, manifest, applications, icons):
    """Install only managed overrides; never overwrite an unowned local entry."""
    if mode not in ("light", "dark"):
        raise ValueError("mode must be light or dark")
    try:
        records = json.loads(manifest.read_text())
    except (OSError, ValueError):
        records = {}
    pruned = False
    for app_id, record in list(records.items()):
        target = applications / (app_id + ".desktop")
        source = Path(record.get("source", ""))
        if source == target or source.is_file():
            continue
        existing = target.read_text() if target.is_file() else None
        if existing is not None and existing in (record.get("rendered"), record.get("pending_rendered")):
            target.unlink()
            _remove_icon_names(_record_icon_names(app_id, record), app_id, records, applications, icons)
            del records[app_id]
            pruned = True
    if pruned:
        atomic_bytes(manifest, json.dumps(records, indent=2).encode())
    entries = {entry["app_id"]: entry for entry in meta.values() if entry.get("path_" + mode)}
    icon_names = {app_id: generated_icon_name(app_id) for app_id in entries}
    if len(set(icon_names.values())) != len(icon_names):
        raise ValueError("generated icon name collision; refusing ambiguous publication")
    applications.mkdir(parents=True, exist_ok=True)
    icons.mkdir(parents=True, exist_ok=True)
    standard_layout = icons.name == "apps" and icons.parent.name == "256x256"
    index = (icons.parent.parent if standard_layout else icons) / "index.theme"
    if not index.exists() and THEME_INDEX.is_file():
        index.symlink_to(THEME_INDEX)
    for app_id, entry in entries.items():
        icon_name = icon_names[app_id]
        target = applications / (app_id + ".desktop")
        record = records.get(app_id)
        retired = set()
        if record:
            existing = target.read_text() if target.is_file() else None
            owned = existing is not None and existing in (
                record.get("rendered"), record.get("pending_rendered"))
            legacy_owned = ("pending_rendered" not in record and record.get("rendered") is None
                            and existing is not None and existing.startswith(MARKER))
            unfinished = ("pending_rendered" in record and record.get("rendered") is None
                          and (existing is None or existing == record["original"]))
            if not (owned or legacy_owned or unfinished):
                continue
            retired = _record_icon_names(app_id, record) - {icon_name}
            # An incomplete first install does not establish legacy ownership.
            if not (owned or legacy_owned):
                retired.discard(_legacy_icon_name(app_id))
            original = record["original"]
        else:
            if target.is_file() and target.read_text().startswith(MARKER):
                continue
            if target.is_file():
                original, source = target.read_text(), str(target)
            else:
                original, source = original_desktop(app_id, entry.get("desktop_file"))
            if original is None:
                continue
            record = {"original": original, "source": source}
        if target.is_file() and target.read_text().startswith(MARKER):
            previous_render = record.get("rendered")
            if previous_render is not None and target.read_text() not in (
                    previous_render, record.get("pending_rendered")):
                continue
        upstream = Path(record["source"])
        if upstream != target and upstream.is_file():
            current = upstream.read_text()
            if not current.startswith(MARKER):
                original = current
                record = dict(record, original=current)
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
        image_bytes = source_image.read_bytes()
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
        # A registry notification or shell reload is not a publication change.
        # In particular, avoid two full-manifest fsyncs per unchanged app.
        if (not retired and record.get("rendered") == rendered
                and record.get("icon_name") == icon_name
                and "pending_rendered" not in record
                and target.is_file() and target.read_text() == rendered
                and icon_file.is_file() and icon_file.read_bytes() == image_bytes):
            continue
        record = dict(record, pending_rendered=rendered, pending_icon_name=icon_name)
        if retired:
            record["retired_icon_names"] = sorted(retired)
        else:
            record.pop("retired_icon_names", None)
        records[app_id] = record
        atomic_bytes(manifest, json.dumps(records, indent=2).encode())
        if not icon_file.is_file() or icon_file.read_bytes() != image_bytes:
            atomic_bytes(icon_file, image_bytes)
        if not target.is_file() or target.read_text() != rendered:
            permissions = target.stat().st_mode if target.is_file() else None
            atomic_bytes(target, rendered.encode())
            if permissions is not None:
                target.chmod(permissions)
        record["rendered"] = rendered
        record["icon_name"] = icon_name
        record.pop("pending_rendered", None)
        record.pop("pending_icon_name", None)
        atomic_bytes(manifest, json.dumps(records, indent=2).encode())
        if retired and target.read_text() == rendered:
            remaining = _remove_icon_names(retired, app_id, records, applications, icons)
            if remaining:
                record["retired_icon_names"] = sorted(remaining)
            else:
                record.pop("retired_icon_names", None)
            atomic_bytes(manifest, json.dumps(records, indent=2).encode())
    mode_path = manifest.parent / "appearance-mode"
    if not mode_path.is_file() or mode_path.read_text() != mode:
        atomic_bytes(mode_path, mode.encode())
    return len(records)


def restore(manifest=MANIFEST, applications=APPLICATIONS, icons=ICONS):
    with cache_lock(manifest.parent):
        return _restore(manifest, applications, icons)


def _restore(manifest, applications, icons):
    """Restore only our untouched managed entries; keep user modifications."""
    records = json.loads(manifest.read_text())
    retained = {}
    for app_id, record in records.items():
        target = applications / (app_id + ".desktop")
        existing = target.read_text() if target.is_file() else None
        unfinished = ("pending_rendered" in record and record.get("rendered") is None
                      and (existing is None or existing == record["original"]))
        owned = existing is not None and existing in (
            record.get("rendered"), record.get("pending_rendered"))
        if not (owned or unfinished):
            retained[app_id] = record
            continue
        if unfinished:
            pass
        elif record["source"] == str(target):
            atomic_bytes(target, record["original"].encode())
        else:
            target.unlink()
        _remove_icon_names(_record_icon_names(app_id, record), app_id, records, applications, icons)
    if retained:
        atomic_bytes(manifest, json.dumps(retained, indent=2).encode())
    else:
        manifest.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("light", "dark"))
    parser.add_argument("--restore", action="store_true")
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--applications-dir", type=Path)
    parser.add_argument("--icons-dir", type=Path)
    args = parser.parse_args()
    if args.cache_dir != DEFAULT_CACHE and (args.applications_dir is None or args.icons_dir is None):
        parser.error("a custom cache requires --applications-dir and --icons-dir for isolated publication")
    applications = args.applications_dir or APPLICATIONS
    icons = args.icons_dir or ICONS
    if args.restore:
        restore(args.cache_dir / "global-icons.json", applications, icons)
    else:
        if not args.mode:
            parser.error("--mode is required")
        meta = json.loads((args.cache_dir / "app_icons_meta.json").read_text())
        print(f"Published {export(meta, args.mode, args.cache_dir / 'global-icons.json', applications, icons)} global icons")


if __name__ == "__main__":
    main()
