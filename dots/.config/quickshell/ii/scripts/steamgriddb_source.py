"""Offline SteamGridDB source lookup. This module never accesses the network."""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex

CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell/game_icons/steamgriddb"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "illogical-impulse/config.json"


def steam_app_id(desktop):
    """Accept actual Steam launch commands, never display names or fuzzy IDs."""
    try:
        command = shlex.split(desktop.get("exec", ""))
    except ValueError:
        return None
    if command and Path(command[0]).name == "env":
        command = command[1:]
        while command and (re.match(r"^[A-Za-z_][A-Za-z_0-9]*=", command[0]) or command[0] == "--"):
            command.pop(0)
    if not command:
        return None
    program = Path(command[0]).name
    if program == "flatpak":
        if len(command) < 3 or command[1] != "run":
            return None
        index = 2
        while index < len(command) and command[index].startswith("-"):
            option, separator, value = command[index].partition("=")
            if option == "--":
                index += 1
                break
            if option in ("--user", "--system", "--file-forwarding"):
                if separator:
                    return None
                index += 1
                continue
            if option not in ("--branch", "--arch", "--installation", "--command"):
                return None
            if not separator:
                index += 1
                if index >= len(command):
                    return None
                value = command[index]
            if not value or (option == "--command" and value not in ("steam", "steam-runtime", "steam-native")):
                return None
            index += 1
        if index >= len(command) or command[index] != "com.valvesoftware.Steam":
            return None
        arguments = command[index + 1:]
    elif program in ("steam", "steam-runtime", "steam-native"):
        arguments = command[1:]
    else:
        return None
    ids = set()
    for index, argument in enumerate(arguments):
        match = re.fullmatch(r"steam://(?:run|rungameid)/([1-9][0-9]{0,9})(?:/[^?#]*)?", argument)
        value = match[1] if match else (
            arguments[index + 1] if argument == "-applaunch" and index + 1 < len(arguments) else "")
        if re.fullmatch(r"[1-9][0-9]{0,9}", value) and int(value) <= 0xFFFFFFFF:
            ids.add(value)
    return next(iter(ids)) if len(ids) == 1 else None


def enabled(config=None):
    try:
        settings = json.loads((config or CONFIG).read_text())
        return settings.get("appearance", {}).get("steamGridDb", {}).get("enabled") is True
    except (OSError, ValueError, AttributeError):
        return False


def read_manifest(cache=None):
    try:
        path = (cache or CACHE) / "manifest.json"
        with path.open("rb") as stream:
            raw = stream.read(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024:
            return {}
        data = json.loads(raw)
        return data["icons"] if data.get("schema_version") == 1 and isinstance(data.get("icons"), dict) else {}
    except (OSError, ValueError, AttributeError, KeyError):
        return {}


def cached_sources(cache=None):
    """Reject stale/corrupt entries and paths escaping the dedicated asset cache."""
    cache = cache or CACHE
    sources = {}
    for app_id, entry in read_manifest(cache).items():
        if (not isinstance(entry, dict) or not re.fullmatch(r"[1-9][0-9]{0,9}", app_id)
                or int(app_id) > 0xFFFFFFFF):
            continue
        digest = entry.get("sha256", "")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            continue
        path = cache / "assets" / f"{app_id}-{digest}.png"
        try:
            if ((cache / "assets").is_symlink() or path.is_symlink()
                    or not path.resolve().is_relative_to((cache / "assets").resolve())):
                continue
            with path.open("rb") as stream:
                data = stream.read(8 * 1024 * 1024 + 1)
            if len(data) > 8 * 1024 * 1024:
                continue
            if hashlib.sha256(data).hexdigest() != digest:
                continue
        except OSError:
            continue
        sources[app_id] = (path, {
            "kind": "steamgriddb-icon", "steam_app_id": app_id,
            "asset_id": entry.get("asset_id"), "style": entry.get("style", ""),
            "reason": "cached dedicated game icon matched by Steam app ID",
        })
    return sources
