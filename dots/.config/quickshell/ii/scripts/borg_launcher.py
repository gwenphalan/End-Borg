"""On-demand launcher maintenance; never invoked by opening or typing in the launcher."""
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from PIL import ImageFont
from process_all_icons import DEFAULT_CACHE, application_directories, build, desktop_entries

STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "quickshell/borg-intelligence"
CURATED = {
    "A Game About Digging A Hole": "Digging a Hole",
    "appimagelaunchersettings": "AppImage Settings",
    "cmake-gui": "CMake",
    "nm-connection-editor": "Network Connections",
    "blueman-adapters": "Bluetooth Adapters",
    "blueman-manager": "Bluetooth Manager",
    "org.gnome.FileRoller": "Archive Manager",
    "CachyOS Kernel Manager": "CachyOS Kernels",
    "virt-manager": "Virt Manager",
    "Keep Talking and Nobody Explodes": "Keep Talking",
    "The Wandering Village": "Wandering Village",
}


def atomic_json(path, value):
    fd, temporary = tempfile.mkstemp(prefix=".launcher-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(value, output, ensure_ascii=False, indent=2)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_json(path):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def fits(name, font, width=82):
    if not isinstance(name, str) or not name or len(name) > 80:
        return False
    lines, current = 1, ""
    for word in name.split():
        if font.getlength(word) > width:
            return False
        proposed = (current + " " + word).strip()
        if font.getlength(proposed) <= width:
            current = proposed
        else:
            lines += 1
            current = word
    return lines <= 2


def borg(operation, payload, options):
    request = dict(options, **payload)
    try:
        response = subprocess.run(
            ["/usr/bin/python3", str(Path(__file__).with_name("borg_intelligence.py")), operation],
            input=json.dumps(request), capture_output=True, text=True,
            timeout=min(210, options.get("timeout", 210)) + 15,
        )
    except subprocess.TimeoutExpired:
        return None
    try:
        envelope = json.loads(response.stdout)
        if not envelope.get("ok"):
            return None
        return envelope["result"]
    except (ValueError, KeyError, TypeError):
        return None



def improve(options):
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(STATE, 0o700)
    with (STATE / "launcher-refresh.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {"busy": True, "message": "A launcher update is already running"}
        return improve_locked(options)


def improve_locked(options):
    folders = application_directories()
    entries = desktop_entries(folders)
    visible = {key: value for key, value in entries.items()
               if value.get("nodisplay", "false").lower() != "true"
               and value.get("hidden", "false").lower() != "true" and value.get("name")}
    font_path = subprocess.check_output(
        ["fc-match", "-f", "%{file}", "Noto Sans:weight=medium"], text=True,
    ).strip()
    font = ImageFont.truetype(font_path, 12)
    path = STATE / "launcher-labels.json"
    previous = read_json(path).get("labels", {})
    labels, unresolved = {}, []
    for app_id, entry in visible.items():
        original = entry["name"]
        curated = CURATED.get(app_id) or CURATED.get(original)
        clean = curated or re.sub(r"[™®]", "", original).strip()
        cached = previous.get(app_id, {}) if isinstance(previous, dict) else {}
        if isinstance(cached, dict) and cached.get("name") == original and fits(cached.get("label"), font):
            clean = curated or cached["label"]
        if fits(clean, font):
            labels[app_id] = {"name": original, "label": clean}
        else:
            unresolved.append({"id": app_id, "name": original})
    # Label generation is independent of the offline, image-only icon policy.
    failures = 0
    for start in range(0, min(len(unresolved), 72), 24):
        batch = unresolved[start:start + 24]
        result = borg("label_apps", {"apps": batch}, options)
        if not result:
            failures += 1
            break
        for app in batch:
            label = result.get("labels", {}).get(app["id"], "")
            if fits(label, font):
                labels[app["id"]] = {"name": app["name"], "label": label}
    # Never introduce duplicate labels, including collisions with unchanged names.
    normalized = {}
    for app_id, entry in visible.items():
        label = labels.get(app_id, {}).get("label", entry["name"])
        normalized.setdefault(label.casefold(), []).append(app_id)
    for ids in normalized.values():
        if len(ids) > 1:
            for app_id in ids:
                labels.pop(app_id, None)
    atomic_json(path, {"version": 1, "labels": labels})
    meta = build(DEFAULT_CACHE, directories=folders)
    return {
        "labels": len(labels), "apps": len(visible), "icons": len({v["app_id"] for v in meta.values()}),
        "vision_requests": 0, "alternate_requests": 0,
        "failed_batches": failures,
        "vision_failures": 0,
        "unresolved_names": [v["name"] for k, v in visible.items() if k not in labels],
    }


if __name__ == "__main__":
    try:
        print(json.dumps(improve(json.load(sys.stdin))))
    except Exception as error:
        print(json.dumps({"error": "Launcher update failed; the last published cache is retained",
                          "code": type(error).__name__}))
        sys.exit(1)
