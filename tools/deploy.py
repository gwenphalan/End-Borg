#!/usr/bin/env python3
"""Plan scoped desktop copies; applying and rollback are explicit, drift checked actions."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile
from datetime import datetime, timezone

SCOPES = ("quickshell/ii", "hypr")
GENERATED = {"hypr/hyprlock.conf", "hypr/hyprlock/colors.conf", "hypr/hyprland/colors.lua"}


def managed(relative):
    p = Path(relative)
    if p.is_absolute() or ".." in p.parts or not any(
        relative == s or relative.startswith(s + "/") for s in SCOPES
    ):
        return False
    if relative in GENERATED or relative.startswith("hypr/hyprlock/current-wallpaper."):
        return False
    return not any(
        part in {".git", "__pycache__", ".pytest_cache", ".qmlls.ini"}
        or part.endswith((".pyc", ".pyo", ".old", ".new", "~"))
        or any(marker in part for marker in (".bak", ".backup", ".before-", ".codex-before-", ".t3-capture-backup-"))
        for part in p.parts
    )


def safe_path(root, relative):
    if not managed(relative):
        raise ValueError(f"Unmanaged path: {relative}")
    root = Path(root)
    if root.is_symlink():
        raise ValueError(f"Root must not be a symlink: {root}")
    current = root
    for part in Path(relative).parts[:-1]:
        current /= part
        if current.is_symlink() or (current.exists() and not current.is_dir()):
            raise ValueError(f"Unsafe path ancestor: {current}")
    return root / relative


def fingerprint(path):
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    mode = stat.S_IMODE(info.st_mode)
    if stat.S_ISLNK(info.st_mode):
        return {"kind": "symlink", "target": os.readlink(path), "mode": mode}
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f"Expected file or symlink: {path}")
    return {"kind": "file", "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "mode": mode}


def inventory(root):
    root = Path(root)
    result = {}
    for scope in SCOPES:
        base = root / scope
        safe_path(root, scope + "/.sentinel")
        if not base.exists():
            continue
        for folder, dirs, files in os.walk(base, followlinks=False):
            # Directory symlinks are treated as entries, never traversed.
            links = [name for name in dirs if (Path(folder) / name).is_symlink()]
            dirs[:] = [name for name in dirs if name not in links and managed(str((Path(folder) / name).relative_to(root)))]
            for name in files + links:
                path = Path(folder) / name
                rel = str(path.relative_to(root))
                if managed(rel):
                    result[rel] = fingerprint(safe_path(root, rel))
    return result


def digest(files):
    return hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".end-borg-")
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(data, output, indent=2, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def snapshot(target, baseline):
    target = Path(target).absolute()
    data = {"version": 1, "target": str(target), "files": inventory(target)}
    write_json(baseline, data)
    return data


def plan(source, target, baseline):
    source, target = Path(source).absolute(), Path(target).absolute()
    saved = json.loads(Path(baseline).read_text())
    if saved.get("version") != 1 or saved.get("target") != str(target):
        raise ValueError("Baseline target/version mismatch")
    source_files = inventory(source)
    changes, drift = [], []
    for rel, after in sorted(source_files.items()):
        before = fingerprint(safe_path(target, rel))
        if before != saved["files"].get(rel):
            drift.append(rel)
        if before != after:
            changes.append({"path": rel, "before": before, "after": after})
    return {"version": 1, "source": str(source), "target": str(target),
            "source_manifest_sha256": digest(source_files), "changes": changes, "drift": drift}


def atomic_copy(source, destination, expected):
    if fingerprint(source) != expected:
        raise ValueError(f"Source changed: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=destination.parent, prefix=".end-borg-")
    os.close(fd)
    temp = Path(temporary)
    try:
        if expected["kind"] == "symlink":
            temp.unlink()
            temp.symlink_to(expected["target"])
        else:
            shutil.copyfile(source, temp)
            temp.chmod(expected["mode"])
            with temp.open("rb") as stream:
                os.fsync(stream.fileno())
        if fingerprint(temp) != expected:
            raise ValueError(f"Copy verification failed: {source}")
        os.replace(temp, destination)
    finally:
        if temp.exists() or temp.is_symlink():
            temp.unlink()


def apply(source, target, baseline, report, backup):
    proposed = plan(source, target, baseline)
    validation = json.loads(Path(report).read_text())
    if not (validation.get("passed") is True and validation.get("runtime_validated") is True
            and validation.get("source_manifest_sha256") == proposed["source_manifest_sha256"]):
        raise ValueError("Validation must pass static and runtime checks for this exact source digest")
    if proposed["drift"]:
        raise ValueError("Live drift: " + ", ".join(proposed["drift"]))
    backup = Path(backup).resolve()
    for protected in (Path(source).absolute(), Path(target).absolute()):
        protected = protected.resolve()
        if backup == protected or protected in backup.parents:
            raise ValueError("Backup must be outside source and target")
    backup.mkdir(parents=True, exist_ok=False)
    transaction = dict(proposed, status="backing-up")
    journal = backup / "transaction.json"
    write_json(journal, transaction)
    for change in proposed["changes"]:
        rel = change["path"]
        if change["before"] is not None:
            atomic_copy(safe_path(target, rel), backup / "files" / rel, change["before"])
    # Recheck the entire plan after backup, immediately before any live writes.
    if plan(source, target, baseline) != proposed:
        raise ValueError("Source or live files changed during backup; nothing applied")
    transaction["status"] = "applying"
    write_json(journal, transaction)
    for change in proposed["changes"]:
        rel = change["path"]
        destination = safe_path(target, rel)
        if fingerprint(destination) != change["before"]:
            raise ValueError(f"Live drift before write: {rel}; rollback journal: {journal}")
        atomic_copy(safe_path(source, rel), destination, change["after"])
    transaction["status"] = "applied"
    write_json(journal, transaction)
    return transaction


def rollback(backup, perform=False):
    backup = Path(backup).absolute()
    transaction = json.loads((backup / "transaction.json").read_text())
    target = Path(transaction["target"])
    pending = []
    for change in transaction["changes"]:
        rel = change["path"]
        current = fingerprint(safe_path(target, rel))
        if current == change["before"]:
            continue  # Already restored or not reached during a partial apply.
        if current != change["after"]:
            raise ValueError(f"Rollback would overwrite live drift: {rel}")
        if change["before"] is not None and fingerprint(backup / "files" / rel) != change["before"]:
            raise ValueError(f"Backup verification failed: {rel}")
        pending.append(change)
    if perform:
        for change in pending:
            rel = change["path"]
            destination = safe_path(target, rel)
            if fingerprint(destination) != change["after"]:
                raise ValueError(f"Live drift immediately before rollback: {rel}")
            if change["before"] is None:
                destination.unlink()
            else:
                atomic_copy(backup / "files" / rel, destination, change["before"])
        transaction["status"] = "rolled-back"
        write_json(backup / "transaction.json", transaction)
    return {"target": str(target), "rollback_changes": pending, "applied": perform}


def main():
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("snapshot", "plan", "deploy", "rollback"), nargs="?", default="plan")
    parser.add_argument("--source", type=Path, default=repo / "dots/.config")
    parser.add_argument("--target", type=Path, default=Path.home() / ".config")
    parser.add_argument("--baseline", type=Path, default=repo / "local/live-baseline.json")
    parser.add_argument("--backup", type=Path)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--validated", type=Path, help="JSON report for the exact source digest; static and runtime checks must pass")
    args = parser.parse_args()
    try:
        if args.action == "snapshot":
            if args.baseline.exists():
                raise ValueError("Baseline already exists; archive it deliberately before taking another")
            result = snapshot(args.target, args.baseline)
            print(json.dumps({"baseline": str(args.baseline), "file_count": len(result["files"])}))
            return
        if args.action == "rollback":
            if args.backup is None:
                raise ValueError("Rollback requires --backup DIRECTORY")
            result = rollback(args.backup, args.apply)
        elif args.apply:
            if args.action != "deploy" or args.validated is None:
                raise ValueError("Applying requires deploy --apply --validated REPORT")
            backup = args.backup or Path.home() / ".local/state/end-borg/backups" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
            result = apply(args.source, args.target, args.baseline, args.validated, backup)
            result["backup"] = str(backup)
        else:
            result = plan(args.source, args.target, args.baseline)
        print(json.dumps(result, indent=2, sort_keys=True))
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, f"deploy: {error}\n")


if __name__ == "__main__":
    main()
