#!/usr/bin/env python3
"""One JSON request on stdin, one JSON envelope on stdout; never print credentials."""
import json
from pathlib import Path
import subprocess
import sys

from borg_intelligence.client import ClientError, MAX_INPUT, run


def main():
    try:
        if len(sys.argv) != 2:
            raise ClientError("operation", "Specify exactly one operation")
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            raise ClientError("input_limit", "Input exceeds limit")
        payload = json.loads(raw or b"{}")
        if sys.argv[1] == "refresh_launcher":
            helper = Path(__file__).with_name("borg_launcher.py")
            worker = Path.home() / ".local/state/quickshell/.venv/bin/python"
            response = subprocess.run([str(worker), str(helper)], input=json.dumps(payload),
                                      capture_output=True, text=True, timeout=900)
            result = json.loads(response.stdout)
            if response.returncode or result.get("error"):
                raise ClientError("launcher", "Launcher update failed; existing cache retained")
        else:
            result = run(sys.argv[1], payload)
        envelope = {"ok": True, "result": result, "error": None}
    except ClientError as exc:
        envelope = {"ok": False, "result": None, "error": {"code": exc.code, "message": exc.message}}
    except Exception:
        envelope = {"ok": False, "result": None, "error": {"code": "unavailable", "message": "Client unavailable"}}
    print(json.dumps(envelope, ensure_ascii=False))


if __name__ == "__main__":
    main()
