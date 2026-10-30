#!/usr/bin/env python3
"""Validate source without starting the desktop or writing to live configuration."""
from __future__ import annotations

import argparse
from collections import Counter
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import warnings

ROOT = Path(__file__).resolve().parents[1]
SHELL_ROOT = ROOT / "dots/.config/quickshell/ii"
SKIP_DIRS = {".git", ".venv", "venv", "__pycache__", ".pytest_cache", "node_modules", "local", "backups"}


def sources():
    for directory, dirs, files in os.walk(ROOT, followlinks=False):
        dirs[:] = sorted(name for name in dirs if name not in SKIP_DIRS)
        for name in sorted(files):
            yield Path(directory) / name
        for name in dirs:
            path = Path(directory) / name
            if path.is_symlink():
                yield path


def isolated_env(directory: Path) -> dict[str, str]:
    """Do not inherit desktop sockets, credentials, proxies, or user Python paths."""
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "LANG": "C.UTF-8",
        "HOME": str(directory / "home"),
        "PYTHONDONTWRITEBYTECODE": "1",
        "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1",
        "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent/end-borg-validation-bus",
        "QT_QPA_PLATFORM": "offscreen",
        "TZ": "UTC",
    }
    for variable, suffix in (
        ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"),
        ("XDG_STATE_HOME", "state"), ("XDG_DATA_HOME", "data"),
        ("XDG_RUNTIME_DIR", "runtime"), ("TMPDIR", "tmp"),
        ("QS_SETTINGS_PREVIEW_ROOT", "preview"),
    ):
        env[variable] = str(directory / suffix)
    for variable in ("HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME",
                     "XDG_DATA_HOME", "XDG_RUNTIME_DIR", "TMPDIR", "QS_SETTINGS_PREVIEW_ROOT"):
        Path(env[variable]).mkdir(mode=0o700, parents=True, exist_ok=True)
    return env


def run(command: list[str], env: dict[str, str], cwd: Path) -> bool:
    try:
        # Diagnostics may include source text; expose only the failing path.
        result = subprocess.run(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=180)
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def static_checks(env: dict[str, str], qmlformat: str | None) -> tuple[Counter, list[tuple[str, str]], set[str]]:
    checked = Counter()
    failed = []
    missing = set()
    for path in sources():
        relative = path.relative_to(ROOT).as_posix()
        kind = None
        valid = True
        try:
            if path.is_symlink():
                target = Path(os.readlink(path))
                # Absolute/machine-local links are not a portable source check.
                if target.is_absolute():
                    checked["external_symlink_unchecked"] += 1
                    continue
                resolved = (path.parent / target).resolve()
                if not resolved.is_relative_to(ROOT):
                    checked["external_symlink_unchecked"] += 1
                    continue
                kind = "relative_symlink"
                valid = resolved.exists()
            elif path.suffix == ".py":
                kind = "python"
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", SyntaxWarning)
                    compile(path.read_bytes(), relative, "exec", dont_inherit=True)
            elif path.suffix == ".json":
                kind = "json"
                json.loads(path.read_text(encoding="utf-8"))
            elif path.suffix == ".qml":
                kind = "qml_parse"
                tool = qmlformat
                if tool is None:
                    missing.add("qmlformat")
                    continue
                result = subprocess.run([tool, "-n", str(path)], env=env, cwd=ROOT,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
                valid = result.returncode == 0
                if not valid and relative == (
                    "dots/.config/quickshell/ii/modules/common/models/LauncherSearchResult.qml"
                ):
                    # Qt 6.12 qmlformat cannot round-trip this upstream model's id property.
                    # The semantic linter accepts it. Keep this exception exact and visible.
                    linter = Path(tool).resolve().with_name("qmllint")
                    if linter.is_file():
                        valid = run([str(linter), "--ignore-settings", str(path)], env, ROOT)
                        if valid:
                            checked["qml_qmllint_fallback"] += 1
            elif path.suffix in {".sh", ".lua"}:
                kind, executable, flag = (("shell", "bash", "-n") if path.suffix == ".sh"
                                           else ("lua", "luac", "-p"))
                tool = shutil.which(executable, path=env["PATH"])
                if tool is None:
                    missing.add(executable)
                    continue
                if relative == "dots/.config/hypr/hyprland/scripts/fuzzel-emoji.sh":
                    # Upstream appends an inert emoji database after an unconditional exit.
                    source = path.read_bytes().split(b"\n### DATA ###\n", 1)[0]
                    if not source.endswith(b"\nexit"):
                        valid = False
                    else:
                        result = subprocess.run([tool, flag], input=source + b"\n",
                                                env=env, stdout=subprocess.PIPE,
                                                stderr=subprocess.PIPE, timeout=30)
                        valid = result.returncode == 0
                else:
                    valid = run([tool, flag, str(path)], env, ROOT)
            else:
                continue
        except (OSError, ValueError, SyntaxError, subprocess.TimeoutExpired):
            valid = False
        checked[kind or "read"] += 1
        if not valid:
            failed.append((kind or "read", relative))
    return checked, failed, missing


def safe_tests(env: dict[str, str], python: str, lens_python: str | None) -> list[tuple[str, bool, str]]:
    """Explicit allowlist: pure logic, source contracts, temporary profile stores."""
    scripts = SHELL_ROOT / "scripts"
    tests = [
        ("scripts/test_bedlock_lan_status.py",
         [python, "-B", "-m", "unittest", "-q", "test_bedlock_lan_status"], scripts),
        ("scripts/tests/test_launcher_helpers.py",
         [python, "-B", "-m", "unittest", "discover", "-q", "-s", "tests",
          "-p", "test_launcher_helpers.py"], scripts),
        ("scripts/tool_app (definitions, protocol, files, history, registration)",
         [python, "-B", "-m", "pytest", "-q", "-p", "no:cacheprovider",
          "scripts/tool_app/tests/test_definition.py",
          "scripts/tool_app/tests/test_protocol_profiles.py",
          "scripts/tool_app/test_tool_app.py"], SHELL_ROOT),
    ]
    icon_tests = [
        "test_adaptive_icons.py", "test_generated_icon_names.py", "test_global_app_icons.py",
        "test_icon_families.py", "test_icon_modes.py", "test_icon_publication.py",
        "test_steamgriddb.py",
    ]
    tests.append(("scripts/tests (offline icon suites)",
                  [python, "-B", "-m", "pytest", "-q", "-p", "no:cacheprovider",
                   *[str(scripts / "tests" / name) for name in icon_tests]], SHELL_ROOT))
    tests.append(("scripts/colors/test_scheme_for_image.py",
                  [python, "-B", "-m", "unittest", "-q", "test_scheme_for_image"], scripts / "colors"))
    if lens_python:
        lens_tests = [
            "test_backend_blender.py", "test_backend_diagnostics.py",
            "test_calibration_diagnostics.py", "test_distorted_labelme_export.py",
            "test_geometry.py", "test_history.py", "test_labelme_handoff.py",
            "test_normalize_vertices.py", "test_profiles.py", "test_spatial.py",
        ]
        tests.append(("scripts/lens_calibration (offline Python suites)",
                      [lens_python, "-B", "-m", "pytest", "-q", "-p", "no:cacheprovider",
                       *lens_tests], scripts / "lens_calibration"))
    node = shutil.which("node", path=env["PATH"])
    if node:
        for relative in [
            "scripts/settings/test_sleep_schedule.mjs",
            "scripts/lens_calibration/test_context_hints.mjs",
            "scripts/lens_calibration/test_curve_diagnostics.mjs",
            "scripts/lens_calibration/test_curve_geometry.mjs",
            "scripts/lens_calibration/test_region_geometry.mjs",
            "scripts/lens_calibration/test_selection_headless.mjs",
            "scripts/tool_app/tests/test_runtime.mjs",
        ]:
            tests.append((relative, [node, str(SHELL_ROOT / relative)], SHELL_ROOT))
    else:
        tests.append(("scripts/settings/test_sleep_schedule.mjs (node missing)", [], SHELL_ROOT))
    results = []
    for name, command, cwd in tests:
        if not command:
            results.append((name, False, ""))
            continue
        try:
            result = subprocess.run(command, env=env, cwd=cwd, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=180, text=True)
            output = result.stdout + result.stderr
            counts = re.findall(r"(?m)(\d+ (?:passed|skipped|failed|errors?)\b)", output)
            unittest_count = re.search(r"Ran (\d+) tests?", output)
            summary = ", ".join(counts) if counts else (
                f"{unittest_count.group(1)} tests" if unittest_count else "")
            results.append((name, result.returncode == 0, summary))
        except (OSError, subprocess.TimeoutExpired):
            results.append((name, False, ""))
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tests", action="store_true", help="Run the reviewed, explicit test allowlist")
    parser.add_argument("--python", default=sys.executable, help="Python interpreter for optional tests")
    parser.add_argument("--lens-python", help="Opt in to offline Lens Cap tests with this dependency environment")
    parser.add_argument("--qmlformat", help="Qt 6 qmlformat executable; auto-detected by default")
    args = parser.parse_args()
    qmlformat = args.qmlformat or next((str(path) for path in (
        Path("/usr/lib/qt6/bin/qmlformat"), Path("/usr/lib64/qt6/bin/qmlformat"))
        if path.is_file()), None) or shutil.which("qmlformat6") or shutil.which("qmlformat")
    with tempfile.TemporaryDirectory(prefix="end-borg-validation-") as temporary:
        env = isolated_env(Path(temporary))
        checked, failed, missing = static_checks(env, qmlformat)
        for kind, count in sorted(checked.items()):
            print(f"CHECKED {kind}: {count}")
        for kind, path in failed:
            print(f"FAIL {kind}: {path}")
        for executable in sorted(missing):
            print(f"MISSING TOOL: {executable}")
        tests = safe_tests(env, args.python, args.lens_python) if args.tests else []
        for path, passed, summary in tests:
            suffix = f" ({summary})" if summary else ""
            print(f"{'PASS' if passed else 'FAIL'} test: {path}{suffix}")
        failures = len(failed) + len(missing) + sum(not passed for _, passed, _ in tests)
        print(f"RESULT: {failures} failure(s); desktop and QML runtime not exercised")
        return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
