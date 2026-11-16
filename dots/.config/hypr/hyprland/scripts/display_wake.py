#!/usr/bin/env python3
"""Bounded Hyprland wake hook; command acceptance is not physical display proof."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import time


def log(message):
    line = f"{datetime.now(timezone.utc).isoformat()} {message}"
    print(line, file=sys.stderr, flush=True)
    try:
        subprocess.run(["logger", "-t", "end-borg-display-wake", "--", line],
                       timeout=1, check=False, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        pass


class WakeError(Exception):
    pass


class Wake:
    def __init__(self, run=None, sleep=None, environ=None):
        self.run = run or subprocess.run
        self.sleep = sleep or time.sleep
        self.environ = os.environ if environ is None else environ
        self.signature = None

    def command(self, arguments):
        try:
            result = self.run(["hyprctl", *arguments], capture_output=True,
                              text=True, timeout=3, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise WakeError(f"hyprctl {arguments!r}: {error}") from error
        output = result.stdout.strip()
        error = result.stderr.strip()
        log(f"hyprctl {arguments!r}: exit={result.returncode} stdout={output!r} stderr={error!r}")
        if result.returncode != 0:
            raise WakeError(f"hyprctl rejected {arguments!r} (exit {result.returncode})")
        return output

    def resolve(self):
        try:
            instances = json.loads(self.command(["instances", "-j"]))
        except (ValueError, TypeError) as error:
            raise WakeError("Invalid instance response") from error
        if not isinstance(instances, list):
            raise WakeError("Instance response must be a list")
        signatures = [item["instance"] for item in instances
                      if isinstance(item, dict) and isinstance(item.get("instance"), str)
                      and item["instance"]]
        inherited = self.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        if inherited in signatures:
            self.signature = inherited
        elif len(signatures) == 1:
            self.signature = signatures[0]
        else:
            raise WakeError(f"Cannot safely select Hyprland instance ({len(signatures)} available)")
        log(f"selected instance {self.signature!r}")

    def dispatch(self, action):
        response = self.command(["-i", self.signature, "dispatch",
                                 f'hl.dsp.dpms({{action = "{action}"}})'])
        if response.strip().lower() != "ok":
            raise WakeError(f"DPMS {action} was not acknowledged: {response!r}")

    def enable(self):
        for attempt in range(1, 4):
            try:
                self.dispatch("on")
                log(f"DPMS on acknowledged (attempt {attempt}); physical output remains unverified")
                return
            except WakeError as error:
                log(f"DPMS on attempt {attempt}/3 failed: {error}")
                if attempt == 3:
                    raise
                self.sleep(0.5)

    def execute(self, check=False, reinitialize=False):
        self.resolve()
        if check:
            try:
                monitors = json.loads(self.command(["-i", self.signature, "-j", "monitors", "all"]))
            except ValueError as error:
                raise WakeError("Invalid monitors response") from error
            if not isinstance(monitors, list):
                raise WakeError("Monitors response must be a list")
            print(json.dumps({"instance": self.signature, "monitors": monitors}))
            return
        if reinitialize:
            try:
                self.dispatch("off")
            except WakeError as error:
                log(f"DPMS off failed; still restoring on: {error}")
            finally:
                self.sleep(0.5)
                self.enable()
        else:
            self.enable()


@contextmanager
def serialized(environ):
    runtime = environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise WakeError("XDG_RUNTIME_DIR is required for wake serialization")
    directory = Path(runtime)
    info = directory.stat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise WakeError("Unsafe XDG_RUNTIME_DIR")
    fd = os.open(directory / "end-borg-display-wake.lock",
                 os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        lock_info = os.fstat(fd)
        if not stat.S_ISREG(lock_info.st_mode) or lock_info.st_uid != os.getuid():
            raise WakeError("Unsafe wake lock")
        # Another invocation already owns this bounded recovery; never queue cycles.
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise WakeError("Another display wake invocation is active")
        yield
    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="read instance and monitors, without dispatch")
    mode.add_argument("--reinitialize", action="store_true", help="explicit manual DPMS off/on recovery")
    args = parser.parse_args()
    try:
        if args.check:
            Wake().execute(check=True)
        else:
            with serialized(os.environ):
                Wake().execute(reinitialize=args.reinitialize)
    except (WakeError, OSError) as error:
        log(f"FAILED: {error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
