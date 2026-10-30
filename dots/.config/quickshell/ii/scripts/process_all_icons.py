#!/usr/bin/env python3
"""Offline image-driven icon cache builder; use --cache-dir for safe staging."""
import argparse
import configparser
from contextlib import contextmanager
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import Image

from adaptive_icon_policy import (POLICY_VERSION, backplate_decision, classify,
                                  compose_icon, render_adaptive, source_key)
from icon_geometry import analyze_geometry, fit_layout, prepare_geometry, tile_layers, visible_bounds
from icon_families import infer_families
from adaptive_icon_modes import render_variant, resolve_container
from steamgriddb_source import cached_sources, enabled as steamgriddb_enabled, steam_app_id

try:
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
except (ImportError, ValueError):
    Gtk = None

DEFAULT_CACHE = Path.home() / ".cache/quickshell/game_icons"
DEFAULT_THEME = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "quickshell/user/generated/colors.json"
APP_THEME = Path("/usr/share/icons/Papirus/64x64/apps")
MANAGED_MARKER = "# Managed by global_app_icons.py;"
GENERIC_FALLBACKS = (
    (("Terminal",), "utilities-terminal"),
    (("Development",), "applications-development"),
    (("Graphics",), "applications-graphics"),
    (("AudioVideo", "Audio", "Video"), "applications-multimedia"),
    (("Office",), "applications-office"),
    (("Network",), "applications-internet"),
    (("Game",), "applications-games"),
    (("Utility",), "applications-utilities"),
    ((), "application-default-icon"),
)


def data_roots():
    """Low-to-high precedence XDG roots, including exported Flatpak resources."""
    system = [Path(value) for value in os.environ.get(
        "XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if value]
    home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    roots = [Path("/var/lib/flatpak/exports/share"), *reversed(system),
             home / "flatpak/exports/share", home]
    return list(reversed(dict.fromkeys(path for path in reversed(roots) if path.is_absolute())))


def application_directories():
    return [root / "applications" for root in data_roots()]


@contextmanager
def cache_lock(cache):
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / ".adaptive.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


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


def read_object(path):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def desktop_entries(directories, manifest=None):
    entries = {}
    originals = read_object(DEFAULT_CACHE / "global-icons.json")
    if manifest:
        originals.update(read_object(manifest))
    for folder in directories:
        for filename in sorted(folder.rglob("*.desktop")) if folder.is_dir() else ():
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            app_id = str(filename.relative_to(folder)).removesuffix(".desktop").replace("/", "-")
            try:
                text = filename.read_text(encoding="utf-8")
                source = str(filename)
                if text.startswith(MANAGED_MARKER):
                    record = originals.get(app_id, {})
                    # Never feed our generated icon back into the next generation.
                    if not isinstance(record, dict) or not isinstance(record.get("original"), str):
                        if app_id in entries:
                            continue
                    elif (record.get("rendered") is None and "pending_rendered" not in record) or text in (
                            record.get("rendered"), record.get("pending_rendered")):
                        text = record["original"]
                        source = record.get("source", source)
                        upstream = Path(source)
                        if upstream != filename and not upstream.is_file():
                            # The package was removed; a generated override is not an app.
                            continue
                        if upstream != filename and upstream.is_file():
                            current = upstream.read_text(encoding="utf-8")
                            if not current.startswith(MANAGED_MARKER):
                                text = current
                parser.read_string(text)
                if parser.has_section("Desktop Entry"):
                    entries[app_id] = dict(parser["Desktop Entry"], _desktop_file=source)
            except (OSError, UnicodeError, configparser.Error):
                continue
    return entries


def generated_source(path):
    resolved = path.resolve()
    return (path.name.startswith("quickshell-generated-")
            or resolved.name.startswith("quickshell-generated-")
            or resolved.is_relative_to((DEFAULT_CACHE / "adaptive").resolve()))


def resolve_icon(name):
    if not isinstance(name, str) or not name:
        return None
    if Path(name).is_absolute():
        path = Path(name)
        return path if path.is_file() and not generated_source(path) else None
    if "/" in name or "\\" in name or name.startswith("."):
        return None
    if Gtk:
        try:
            theme = Gtk.IconTheme.get_default()
            info = theme.lookup_icon(name, 256, 0) if theme else None
            path = Path(info.get_filename()) if info and info.get_filename() else None
            if path and path.is_file() and not generated_source(path):
                return path
        except (TypeError, RuntimeError):
            pass
    for root in reversed(data_roots()):
        for size in ("scalable", "256x256", "512x512", "128x128", "64x64", "48x48", "32x32"):
            for suffix in ("", ".svg", ".png", ".xpm"):
                candidate = root / "icons/hicolor" / size / "apps" / (name + suffix)
                if candidate.is_file() and not generated_source(candidate):
                    return candidate
        for suffix in ("", ".svg", ".png", ".xpm"):
            candidate = root / "pixmaps" / (name + suffix)
            if candidate.is_file() and not generated_source(candidate):
                return candidate
    return None


def load_icon(path):
    if path.suffix.lower() == ".svg":
        result = subprocess.run(["rsvg-convert", "-w", "256", path],
                                capture_output=True, check=True, timeout=8)
        with Image.open(io.BytesIO(result.stdout)) as image:
            return image.convert("RGBA")
    with Image.open(path) as image:
        image.thumbnail((512, 512))
        return image.convert("RGBA")


def themed_icon(names):
    """Exact source lookup within the configured theme, not app-specific rules."""
    for name in names:
        if not isinstance(name, str) or not name or "/" in name or "\\" in name or name.startswith("."):
            continue
        for candidate in (name, name.lower()):
            path = APP_THEME / (candidate + ".svg")
            if path.is_file() and path.resolve().is_relative_to(APP_THEME.parent.parent):
                return path
    return None



def generic_candidates(desktop):
    """Use only standard desktop metadata, never app identity or executable names."""
    categories = set(desktop.get("categories", "").split(";"))
    if desktop.get("terminal", "").lower() == "true":
        categories.add("Terminal")
    for matches, name in GENERIC_FALLBACKS:
        if not matches or categories.intersection(matches):
            path = themed_icon((name,))
            if path:
                yield path, {"kind": "generic-papirus-fallback", "icon_name": name,
                             "matched_category": next((value for value in matches if value in categories), None),
                             "reason": "no usable declared icon"}


def generic_icon(desktop):
    return next(generic_candidates(desktop), (None, None))


def save_png(path, image):
    if not path.is_file():
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")
        atomic_bytes(path, buffer.getvalue())


def metadata_for(app_id, desktop, colors, theme_hash, cache, overrides,
                 source_override=None, diagnostics=None, preferred_source=None):
    """Compatibility arguments cannot alter presentation, colors, or source choice."""
    detail = diagnostics if diagnostics is not None else {}
    icon_name = desktop.get("icon", "")
    detail.update({"app_id": app_id, "name": desktop.get("name", app_id),
                   "desktop_file": desktop.get("_desktop_file"),
                   "requested_icon": icon_name, "policy_version": POLICY_VERSION})
    source = (resolve_icon(icon_name) if Path(icon_name).is_absolute()
              else themed_icon((icon_name,)) or resolve_icon(icon_name))
    chosen = Path(source_override) if source_override is not None else source
    if chosen and (generated_source(chosen)
                   or chosen.resolve().is_relative_to((cache / "adaptive").resolve())):
        detail.update(status="failed", reason="generated artwork cannot be an original source")
        return None
    fallbacks = list(generic_candidates(desktop))
    for _, fallback_selection in fallbacks:
        fallback_selection["reason"] = (
            "no declared icon" if not icon_name else
            "declared icon could not be resolved" if not chosen else
            "declared icon could not be decoded")
    selection = {"kind": "declared-icon", "reason": "desktop entry declares an original icon"}
    attempts = ([(chosen, selection)] if chosen else []) + [
        (fallback, fallback_selection) for fallback, fallback_selection in fallbacks if fallback != chosen]
    if preferred_source and source_override is None:
        attempts.insert(0, preferred_source)
    if not attempts:
        detail.update(status="failed", reason="no original source could be resolved")
        return None
    detail["source_attempts"] = []
    for chosen, selection in attempts:
        detail["source"] = str(chosen)
        try:
            if (generated_source(chosen)
                    or chosen.resolve().is_relative_to((cache / "adaptive").resolve())):
                raise ValueError("generated artwork cannot be an original source")
            before = chosen.stat()
            original = chosen.read_bytes()
            if selection["kind"] == "steamgriddb-icon":
                with Image.open(io.BytesIO(original)) as cached:
                    if (cached.format != "PNG" or cached.width != cached.height
                            or not 64 <= cached.width <= 512 or getattr(cached, "n_frames", 1) != 1):
                        raise ValueError("invalid cached game icon")
                    image = cached.convert("RGBA")
                    if image.getchannel("A").getextrema()[1] < 9:
                        raise ValueError("transparent cached game icon")
            else:
                image = load_icon(chosen)
            if not visible_bounds(image):
                raise ValueError("transparent source artwork")
            after = chosen.stat()
            if (before.st_mtime_ns, before.st_size) != (after.st_mtime_ns, after.st_size):
                raise ValueError("source changed during read")
            detail["source_attempts"].append({"source": str(chosen), "status": "accepted"})
            break
        except (OSError, ValueError, SyntaxError, Image.DecompressionBombError, subprocess.SubprocessError) as error:
            detail["source_attempts"].append({"source": str(chosen), "status": "failed",
                                              "error_type": type(error).__name__})
    else:
        detail.update(status="failed", reason="declared and generic sources could not be decoded")
        return None
    detail["source_selection"] = selection
    source_hash = hashlib.sha256(original).hexdigest()
    detail["source_hash"] = source_hash
    detail["measurements"] = analyze_geometry(image)
    prepared, prepared_geometry, frame = prepare_geometry(image)
    foreground_analysis = {"decision": "fit-original", "reason": "not a square or squircle tile"}
    layers = tile_layers(prepared, foreground_analysis) if prepared_geometry["is_tile"] else None
    presentation, confidence, reason = classify(image)
    adapted, final = render_adaptive(image, presentation)
    if final != presentation:
        confidence, reason = .25, "unsafe tile operation; original retained with optical fit"
    presentation = final
    processed = cache / "adaptive" / (source_key(original, "", presentation) + ".png")
    save_png(processed, adapted)
    source_pixels = cache / "adaptive" / (
        source_key(image.tobytes() + str(image.size).encode(), "source-rgba", "decoded") + ".png")
    save_png(source_pixels, image)
    background_details = {mode: backplate_decision([adapted], mode) for mode in ("light", "dark")}
    variants = {}
    for mode, decision in background_details.items():
        target = cache / "adaptive" / (source_key(original, decision["color"], presentation) + "-" + mode + ".png")
        save_png(target, compose_icon(adapted, decision["color"], presentation))
        variants[mode] = str(target)
    detail.update(status="generated", presentation=presentation, confidence=confidence,
                  reason=reason, prepared_measurements=prepared_geometry, frame=frame,
                  backgrounds=background_details, foreground=layers[2] if layers else None,
                  foreground_analysis=foreground_analysis,
                  placement=fit_layout(layers[0] if layers else adapted)[1]
                  if layers or presentation == "fit" else {"method": "edge-to-edge-tile"},
                  outputs={"artwork": str(processed), **variants})
    return {"path": str(processed), "source": str(chosen), "source_hash": source_hash,
            "source_pixels": str(source_pixels), "baseline_presentation": presentation,
            "source_selection": selection,
            "desktop_file": desktop.get("_desktop_file"),
            "source_family": "SteamGridDB" if selection["kind"] == "steamgriddb-icon"
                             else "Papirus" if chosen.is_relative_to(APP_THEME) else "original",
            "fill": presentation in ("fill", "extend"), "presentation": presentation,
            "bg_light": background_details["light"]["color"], "bg_dark": background_details["dark"]["color"],
            "path_light": variants["light"], "path_dark": variants["dark"],
            "confidence": confidence, "reason": reason,
            "is_game": "Game" in desktop.get("categories", "").split(";"),
            "policy_version": POLICY_VERSION, "app_id": app_id, "name": desktop.get("name", app_id)}


def harmonize_family_backgrounds(rendered, records, desktops, cache, affected=None):
    """Share only synthesized backplates; never recolor native tile artwork."""
    eligible = {app_id: desktops[app_id] for app_id, entry in rendered.items()
                if entry.get("baseline_presentation", entry["presentation"]) == "fit"}
    families = infer_families(eligible)
    groups = {}
    for app_id, family in families.items():
        groups.setdefault(family["key"], []).append(app_id)
    for key, members in sorted(groups.items()):
        if affected is not None and not affected.intersection(members):
            continue
        members.sort()
        artworks = [load_icon(Path(rendered[app_id]["path"])) for app_id in members]
        decisions = {mode: backplate_decision(artworks, mode) for mode in ("light", "dark")}
        for app_id, artwork in zip(members, artworks):
            entry, record = rendered[app_id], records[app_id]
            family = dict(families[app_id], scope="synthesized-backplates-only")
            entry["background_family"] = key
            record["background_family"] = family
            record["individual_backgrounds"] = record.get("backgrounds") or {
                mode: backplate_decision([artwork], mode) for mode in ("light", "dark")}
            record["backgrounds"] = decisions
            for mode, decision in decisions.items():
                target = cache / "adaptive" / (
                    source_key(artwork.tobytes(), decision["color"], "fit-family") + "-" + mode + ".png")
                save_png(target, compose_icon(artwork, decision["color"], "fit"))
                entry["bg_" + mode] = decision["color"]
                entry["path_" + mode] = str(target)
                record["outputs"][mode] = str(target)


def finish_mode_variants(rendered, records, cache):
    """Finish mode variants after family composition, without identity inputs.

    Baseline artwork remains available for family inference. Decoded source
    pixels permit same-policy recovery when an upstream icon disappears.
    """
    raw_variants, finished = {}, {}
    for app_id, entry in rendered.items():
        record = records[app_id]
        record["baseline"] = {
            "presentation": entry["baseline_presentation"],
            "backgrounds": record["backgrounds"],
            "outputs": dict(record["outputs"]),
        }
        mode_records = {}
        for mode in ("light", "dark"):
            key = (entry["source_pixels"], mode)
            if key not in raw_variants:
                with Image.open(entry["source_pixels"]) as source:
                    raw_variants[key] = render_variant(source.convert("RGBA"), mode)
            raw = raw_variants[key]
            plate = entry["bg_" + mode]
            final_key = (*key, plate)
            if final_key not in finished:
                preview = compose_icon(raw["artwork"], raw.get("backplate") or plate,
                                       raw["presentation"])
                variant = resolve_container(raw, preview, mode)
                background = variant.get("backplate") or plate
                artwork, presentation = variant["artwork"], variant["presentation"]
                if artwork.mode != "RGBA" or artwork.size != (256, 256):
                    raise ValueError("mode artwork must be 256x256 RGBA")
                composed = compose_icon(artwork, background, presentation)
                art_path = cache / "adaptive" / (
                    source_key(artwork.tobytes(), mode, presentation + "-mode-artwork") + ".png")
                target = cache / "adaptive" / (
                    source_key(composed.tobytes(), mode, presentation + "-composed") + ".png")
                save_png(art_path, artwork)
                save_png(target, composed)
                finished[final_key] = {
                    "artwork": str(art_path), "path": str(target),
                    "presentation": presentation, "backplate": background,
                    "diagnostics": variant["diagnostics"],
                }
            result = finished[final_key]
            mode_records[mode] = result
            entry["path_" + mode] = result["path"]
            entry["artwork_" + mode] = result["artwork"]
            entry["bg_" + mode] = result["backplate"]
            entry["presentation_" + mode] = result["presentation"]
            record["outputs"][mode] = result["path"]
        presentations = {result["presentation"] for result in mode_records.values()}
        if len(presentations) != 1:
            raise ValueError("mode-dependent geometry is not supported by the launcher")
        entry["presentation"] = record["presentation"] = presentations.pop()
        entry["fill"] = entry["presentation"] in ("fill", "extend")
        record["mode_variants"] = mode_records
        record["backgrounds"] = {
            mode: {"color": result["backplate"], "method": "approved-v3-mode-finishing",
                   "baseline": record["baseline"]["backgrounds"][mode]}
            for mode, result in mode_records.items()
        }


ASSET_FIELDS = ("path", "path_light", "path_dark", "source_pixels",
                "artwork_light", "artwork_dark")


def input_stamp(desktop, preferred_source):
    """Stat original inputs, never decode artwork to decide whether it is cached."""
    icon = desktop.get("icon", "")
    source = (resolve_icon(icon) if Path(icon).is_absolute()
              else themed_icon((icon,)) or resolve_icon(icon))
    candidates = ([preferred_source[0]] if preferred_source else []) + (
        [source] if source else []) + [path for path, _ in generic_candidates(desktop)]
    stats = []
    for candidate in dict.fromkeys(str(path) for path in candidates):
        try:
            value = Path(candidate).stat()
            stats.append((candidate, value.st_mtime_ns, value.st_size, value.st_ino))
        except OSError:
            stats.append((candidate, None))
    payload = {"schema": 1, "policy": POLICY_VERSION, "desktop": desktop,
               "sources": stats,
               "preferred": str(preferred_source[0]) if preferred_source else None}
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def valid_cached_entry(entry, record):
    return (isinstance(entry, dict) and entry.get("policy_version") == POLICY_VERSION
            and all(isinstance(entry.get(field), str) and Path(entry[field]).is_file()
                    for field in ASSET_FIELDS)
            and isinstance(record, dict) and isinstance(record.get("baseline"), dict)
            and isinstance(record.get("mode_variants"), dict)
            and isinstance(record["baseline"].get("outputs"), dict)
            and all(isinstance(record["baseline"]["outputs"].get(key), str)
                    and Path(record["baseline"]["outputs"][key]).is_file()
                    for key in ("artwork", "light", "dark"))
            and all(mode in record["mode_variants"] for mode in ("light", "dark")))


def adopt_cached_entry(entry, record, desktop, preferred_source):
    """Migrate the existing cache without a one-time full-library regeneration."""
    if not valid_cached_entry(entry, record):
        return False
    if (record.get("requested_icon") != desktop.get("icon", "")
            or entry.get("name") != desktop.get("name")
            or entry.get("is_game") != ("Game" in desktop.get("categories", "").split(";"))):
        return False
    selected = entry.get("source_selection", {})
    if preferred_source:
        if entry.get("source") != str(preferred_source[0]):
            return False
    elif selected.get("kind") == "steamgriddb-icon":
        return False
    icon = desktop.get("icon", "")
    current = (resolve_icon(icon) if Path(icon).is_absolute()
               else themed_icon((icon,)) or resolve_icon(icon))
    if current is not None and selected.get("kind") == "declared-icon" and str(current) != entry.get("source"):
        return False
    try:
        return hashlib.sha256(Path(entry["source"]).read_bytes()).hexdigest() == entry.get("source_hash")
    except (OSError, KeyError):
        return False


def restore_baseline(entry, record):
    """Only affected family members return to their cached pre-finishing artwork."""
    baseline = record["baseline"]
    entry["presentation"] = entry["baseline_presentation"]
    record["presentation"] = entry["baseline_presentation"]
    record["outputs"] = dict(baseline["outputs"])
    record["backgrounds"] = dict(baseline["backgrounds"])
    record.pop("background_family", None)
    entry.pop("background_family", None)
    for mode in ("light", "dark"):
        entry["path_" + mode] = baseline["outputs"][mode]
        entry["bg_" + mode] = baseline["backgrounds"][mode]["color"]


def build(cache, theme=None, overrides=None, directories=None, force=False):
    """Build under a shared publication lock; diagnostic records include failures."""
    with cache_lock(cache):
        entries = desktop_entries(directories if directories is not None else application_directories(),
                                  cache / "global-icons.json")
        previous = read_object(cache / "app_icons_meta.json")
        previous_records = read_object(cache / "icon_dictionary.json").get("icons", {})
        preferred_sources = cached_sources() if steamgriddb_enabled() else {}
        if not isinstance(previous_records, dict):
            previous_records = {}
        records, rendered, changed = {}, {}, set()
        for app_id, desktop in entries.items():
            detail = {}
            if desktop.get("hidden", "").lower() == "true":
                records[app_id] = {"status": "skipped", "reason": "desktop entry is hidden",
                                   "desktop_file": desktop.get("_desktop_file")}
                continue
            preferred = preferred_sources.get(steam_app_id(desktop))
            stamp = input_stamp(desktop, preferred)
            old = previous.get(app_id)
            old_record = previous_records.get(app_id)
            if not force and valid_cached_entry(old, old_record):
                if (old_record.get("input_stamp") == stamp
                        or ("input_stamp" not in old_record
                            and adopt_cached_entry(old, old_record, desktop, preferred))):
                    rendered[app_id] = dict(old)
                    records[app_id] = dict(old_record, input_stamp=stamp)
                    continue
            if (not force and isinstance(old_record, dict)
                    and old_record.get("status") == "failed"
                    and old_record.get("input_stamp") == stamp):
                records[app_id] = old_record
                continue
            changed.add(app_id)
            entry = metadata_for(app_id, desktop, {}, "", cache, {}, diagnostics=detail,
                                 preferred_source=preferred)
            if not entry:
                old = previous.get(app_id)
                if (isinstance(old, dict) and old.get("policy_version") == POLICY_VERSION
                        and all(isinstance(old.get(field), str) and Path(old[field]).is_file()
                                for field in ("path", "path_light", "path_dark", "source_pixels"))):
                    entry = dict(old, name=desktop.get("name", app_id))
                    entry.pop("background_family", None)
                    failure = detail
                    prior_record = previous_records.get(app_id)
                    detail = dict(prior_record if isinstance(prior_record, dict) else {}, status="fallback",
                                  failure_reason=failure.get("reason"), source_failure=failure,
                                  reason="retained last valid output of current policy",
                                  outputs={"artwork": entry["path"], "light": entry["path_light"],
                                           "dark": entry["path_dark"]})
                    detail.pop("background_family", None)
                    detail.pop("individual_backgrounds", None)
                    baseline = detail.get("baseline")
                    baseline = baseline if isinstance(baseline, dict) else {}
                    entry["presentation"] = entry["baseline_presentation"]
                    detail["presentation"] = entry["baseline_presentation"]
                    backgrounds = baseline.get("backgrounds")
                    outputs = baseline.get("outputs")
                    if not (isinstance(backgrounds, dict) and isinstance(outputs, dict)
                            and all(isinstance(backgrounds.get(mode), dict)
                                    and isinstance(backgrounds[mode].get("color"), str)
                                    and isinstance(outputs.get(mode), str)
                                    and Path(outputs[mode]).is_file()
                                    for mode in ("light", "dark"))):
                        artwork = load_icon(Path(entry["path"]))
                        backgrounds = {mode: backplate_decision([artwork], mode)
                                       for mode in ("light", "dark")}
                        outputs = {"artwork": entry["path"]}
                        for mode, decision in backgrounds.items():
                            target = cache / "adaptive" / (
                                source_key(artwork.tobytes(), decision["color"],
                                           entry["baseline_presentation"] + "-recovered-baseline") + ".png")
                            save_png(target, compose_icon(artwork, decision["color"],
                                                         entry["baseline_presentation"]))
                            outputs[mode] = str(target)
                    detail["backgrounds"] = backgrounds
                    detail["outputs"] = dict(outputs)
                    for mode in ("light", "dark"):
                        entry["bg_" + mode] = detail["backgrounds"][mode]["color"]
                        entry["path_" + mode] = detail["outputs"][mode]
            records[app_id] = dict(detail, input_stamp=stamp)
            if entry:
                rendered[app_id] = entry
        eligible = {app_id: entries[app_id] for app_id, entry in rendered.items()
                    if entry.get("baseline_presentation", entry["presentation"]) == "fit"}
        families = infer_families(eligible)
        family_groups = {}
        for app_id, family in families.items():
            family_groups.setdefault(family["key"], set()).add(app_id)
        affected = set(changed)
        for app_id, record in records.items():
            family = record.get("background_family")
            expected = families.get(app_id)
            old_members = set(family.get("members", [])) if isinstance(family, dict) else set()
            new_members = family_groups.get(expected["key"], set()) if expected else set()
            if old_members != new_members:
                affected.add(app_id)
                affected.update(old_members)
                affected.update(new_members)
        for members in family_groups.values():
            if affected.intersection(members):
                affected.update(members)
        for app_id in affected - changed:
            if app_id in rendered:
                restore_baseline(rendered[app_id], records[app_id])
        harmonize_family_backgrounds(rendered, records, entries, cache, affected)
        finish_mode_variants({app_id: entry for app_id, entry in rendered.items()
                              if app_id in affected}, records, cache)
        # Canonical desktop IDs always win; ambiguous descriptive aliases are omitted.
        meta = {}
        reserved = {key for app_id in entries for key in (app_id, app_id + ".desktop")}
        for app_id, entry in rendered.items():
            meta[app_id] = entry
            meta[app_id + ".desktop"] = entry
        owners = {}
        for app_id in rendered:
            desktop = entries[app_id]
            for alias in (app_id, app_id + ".desktop", desktop.get("name", ""),
                          desktop.get("startupwmclass", ""), desktop.get("icon", "")):
                for key in (alias, alias.lower()):
                    if key:
                        owners.setdefault(key, set()).add(app_id)
        for alias, ids in owners.items():
            owner = next(iter(ids)) if len(ids) == 1 else None
            if owner and alias not in meta and alias not in reserved:
                meta[alias] = rendered[next(iter(ids))]
        dictionary = {"schema_version": 1, "policy_version": POLICY_VERSION,
                      "generic_fallback_shortlist": [
                          {"categories": list(categories), "icon_name": name,
                           "source": str(path) if (path := themed_icon((name,))) else None}
                          for categories, name in GENERIC_FALLBACKS],
                      "summary": {status: sum(record.get("status") == status for record in records.values())
                                  for status in ("generated", "failed", "fallback", "skipped")} | {
                          "generic_fallbacks": sum(record.get("source_selection", {}).get("kind")
                                                   == "generic-papirus-fallback" for record in records.values())},
                      "icons": records}
        for filename, payload in (("icon_dictionary.json", dictionary), ("app_icons_meta.json", meta)):
            encoded = json.dumps(payload, indent=2, sort_keys=True, allow_nan=False).encode()
            destination = cache / filename
            if not destination.is_file() or destination.read_bytes() != encoded:
                atomic_bytes(destination, encoded)
        keep = {Path(entry[field]).name for entry in rendered.values()
                for field in ("path", "path_light", "path_dark", "source_pixels",
                              "artwork_light", "artwork_dark")}
        keep.update(Path(path).name for record in records.values()
                    for path in record.get("baseline", {}).get("outputs", {}).values())
        # Retain a generous rollback window and never remove recently published files.
        stale = sorted((path for path in (cache / "adaptive").glob("*.png") if path.name not in keep),
                       key=lambda path: path.stat().st_mtime)
        for path in stale[:-max(256, len(keep))]:
            if time.time() - path.stat().st_mtime > 3600:
                path.unlink()
        return meta


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--theme", type=Path, default=DEFAULT_THEME, help="legacy compatibility; artwork is theme-independent")
    parser.add_argument("--desktop-dir", type=Path, action="append")
    parser.add_argument("--force", action="store_true", help="explicitly rebuild all artwork")
    parser.add_argument("--no-publish", action="store_true", help="let the shell publish the current appearance mode")
    args = parser.parse_args()
    meta = build(args.cache_dir, directories=args.desktop_dir, force=args.force)
    if args.cache_dir == DEFAULT_CACHE and not args.no_publish:
        from global_app_icons import export
        mode_file = args.cache_dir / "appearance-mode"
        mode = mode_file.read_text().strip() if mode_file.is_file() else "dark"
        export(meta, mode if mode in ("light", "dark") else "dark")
    count = len({entry["app_id"] for entry in meta.values()})
    print(f"Indexed {len(meta)} aliases for {count} apps; decisions: {args.cache_dir / 'icon_dictionary.json'}")


if __name__ == "__main__":
    main()
