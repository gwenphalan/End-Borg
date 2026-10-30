#!/usr/bin/env python3
"""One JSON request/response; network access happens only for explicit actions."""
import fcntl
import hashlib
import io
import json
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from PIL import Image

from process_all_icons import application_directories, atomic_bytes, desktop_entries
from steamgriddb_source import CACHE, cached_sources, enabled, read_manifest, steam_app_id

API = "https://www.steamgriddb.com/api/v2"
MAX_IMAGE = 8 * 1024 * 1024
MAX_JSON = 1024 * 1024
MAX_GAMES = 100
MAX_SECONDS = 300


class ServiceError(Exception):
    def __init__(self, code, message):
        self.code, self.message = code, message
        super().__init__(message)


class OperationTimeout(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        return None


def credential(operation="read", value=""):
    """Use the system Python's Secret Service support, not the image venv."""
    try:
        result = subprocess.run(
            ["/usr/bin/python3", str(Path(__file__).with_name("steamgriddb_credentials.py")), "--" + operation],
            input=value, capture_output=True, text=True, timeout=12)
    except (OSError, subprocess.SubprocessError):
        raise ServiceError("keyring", "Could not access the desktop keyring") from None
    if result.returncode == 3:
        raise ServiceError("locked", "Unlock your desktop keyring, then retry")
    if result.returncode not in (0, 1):
        raise ServiceError("keyring", "Could not access the desktop keyring")
    if operation == "store" and result.returncode != 0:
        raise ServiceError("keyring", "The API key could not be saved")
    return result.stdout.strip() if operation == "read" else ""


def valid_artwork_url(url):
    if not isinstance(url, str) or len(url) > 2048:
        return False
    try:
        parsed = urllib.parse.urlsplit(url)
        return (parsed.scheme == "https" and parsed.port in (None, 443)
                and not parsed.username and not parsed.password and not parsed.query and not parsed.fragment
                and bool(re.fullmatch(r"cdn[0-9]*\.steamgriddb\.com", parsed.hostname or ""))
                and parsed.path.startswith("/icon/"))
    except ValueError:
        return False


def fetch(url, key=None, maximum=MAX_JSON):
    # Artwork requests never inherit an API Authorization header.
    if key is not None:
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme != "https" or parsed.netloc != "www.steamgriddb.com"
                or not parsed.path.startswith("/api/v2/") or parsed.fragment):
            raise ServiceError("origin", "Invalid API origin")
    elif not valid_artwork_url(url):
        raise ServiceError("origin", "Invalid artwork URL")
    headers = {"User-Agent": "Quickshell-Adaptive-Icons/1.0"}
    if key is not None:
        headers["Authorization"] = "Bearer " + key
    request = urllib.request.Request(url, headers=headers)
    try:
        started = time.monotonic()
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=10) as response:
            if response.status != 200:
                raise ServiceError("http", "SteamGridDB returned an unexpected response")
            size = response.headers.get("Content-Length")
            if size and int(size) > maximum:
                raise ServiceError("size", "SteamGridDB response exceeded the size limit")
            chunks, received = [], 0
            while received <= maximum:
                if time.monotonic() - started > 30:
                    raise ServiceError("timeout", "SteamGridDB request timed out")
                chunk = response.read1(min(65536, maximum + 1 - received))
                if not chunk:
                    break
                chunks.append(chunk)
                received += len(chunk)
            data = b"".join(chunks)
            if len(data) > maximum:
                raise ServiceError("size", "SteamGridDB response exceeded the size limit")
            return data
    except urllib.error.HTTPError as error:
        code = error.code
        error.close()
        if code in (401, 403):
            raise ServiceError("auth", "SteamGridDB rejected the API key") from None
        if code == 429:
            raise ServiceError("rate_limit", "SteamGridDB rate limit reached; retry later") from None
        if code == 404:
            raise ServiceError("not_found", "No SteamGridDB icon found") from None
        raise ServiceError("http", "SteamGridDB request failed") from None
    except (OSError, ValueError):
        raise ServiceError("network", "SteamGridDB could not be reached") from None


def api(path, key):
    try:
        response = json.loads(fetch(API + path, key))
    except (ValueError, UnicodeError):
        raise ServiceError("response", "Invalid SteamGridDB response") from None
    if not isinstance(response, dict) or response.get("success") is not True:
        raise ServiceError("response", "SteamGridDB did not return a successful result")
    return response.get("data")


def decode_icon(data):
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.format not in ("ICO", "PNG", "WEBP"):
                raise ValueError()
            if image.width > 2048 or image.height > 2048 or getattr(image, "n_frames", 1) != 1:
                raise ValueError()
            image = image.convert("RGBA")
            if image.width != image.height or image.width < 64 or image.getchannel("A").getextrema()[1] < 9:
                raise ValueError()
            image.thumbnail((512, 512), Image.Resampling.LANCZOS)
            buffer = io.BytesIO()
            image.save(buffer, format="PNG")
            return buffer.getvalue(), image.size
    except (OSError, ValueError, Image.DecompressionBombError):
        raise ServiceError("image", "Artwork is not a usable static square icon") from None


def select_icon(app_id, key):
    results = api("/icons/steam/" + app_id + "?types=static&nsfw=false&humor=false&limit=20", key)
    if not isinstance(results, list):
        raise ServiceError("response", "Invalid SteamGridDB icon list")
    candidates = [item for item in results[:20] if isinstance(item, dict)
                  and isinstance(item.get("id"), int) and not isinstance(item["id"], bool)
                  and item["id"] > 0 and valid_artwork_url(item.get("url"))
                  and not item.get("nsfw") and not item.get("humor")
                  and not item.get("epilepsy") and item.get("style") in ("official", "custom")]
    def rank(item):
        score = item.get("score", 0)
        score = score if isinstance(score, (int, float)) else 0
        width = item.get("width", 0)
        width = width if isinstance(width, int) else 0
        return (item["style"] != "official", width != 0 and width < 256, -score, item["id"])
    for item in sorted(candidates, key=rank)[:3]:
        try:
            data, size = decode_icon(fetch(item["url"], maximum=MAX_IMAGE))
        except ServiceError as error:
            if error.code == "rate_limit":
                raise
            continue
        return data, {"asset_id": item["id"], "style": item["style"],
                      "url": item["url"], "width": size[0], "height": size[1]}
    raise ServiceError("not_found", "No usable SteamGridDB icon found")


def installed_games():
    entries = desktop_entries(application_directories())
    return sorted({app_id for entry in entries.values()
                   if entry.get("hidden", "").lower() != "true" and (app_id := steam_app_id(entry))},
                  key=int)


def refresh(key, cache=CACHE, app_ids=None, force=False):
    cache.mkdir(parents=True, exist_ok=True)
    if (cache / "assets").is_symlink():
        raise ServiceError("cache", "Invalid SteamGridDB cache directory")
    with (cache / ".refresh.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ServiceError("busy", "A SteamGridDB refresh is already running") from None
        records = read_manifest(cache)
        valid = cached_sources(cache)
        ids = installed_games() if app_ids is None else app_ids
        try:
            with (cache / ".refresh-cursor").open() as stream:
                offset = int(stream.read(32)) % len(ids) if ids else 0
        except (OSError, ValueError):
            offset = 0
        ids = ids[offset:] + ids[:offset]
        report = {"updated": 0, "cached": 0, "missing": 0, "failed": 0, "deferred": 0}
        started = time.monotonic()
        attempted, visited = 0, 0
        for index, app_id in enumerate(ids):
            if attempted >= MAX_GAMES or time.monotonic() - started > MAX_SECONDS:
                report["deferred"] = len(ids) - index
                break
            visited += 1
            previous = records.get(app_id, {})
            fetched = previous.get("fetched_at", 0) if isinstance(previous, dict) else 0
            if (not force and app_id in valid and isinstance(fetched, (int, float))
                    and 0 <= time.time() - fetched < 86400):
                report["cached"] += 1
                continue
            attempted += 1
            try:
                data, record = select_icon(app_id, key)
                digest = hashlib.sha256(data).hexdigest()
                target = cache / "assets" / f"{app_id}-{digest}.png"
                try:
                    with target.open("rb") as stream:
                        unchanged = not target.is_symlink() and stream.read(len(data) + 1) == data
                except OSError:
                    unchanged = False
                if not unchanged:
                    atomic_bytes(target, data)
                records[app_id] = dict(record, sha256=digest, fetched_at=int(time.time()))
                report["updated"] += 1
                atomic_bytes(cache / "manifest.json", json.dumps(
                    {"schema_version": 1, "icons": records}, sort_keys=True, indent=2).encode())
            except ServiceError as error:
                if error.code in ("auth", "rate_limit"):
                    atomic_bytes(cache / ".refresh-cursor", str((offset + visited) % len(ids)).encode())
                    error.partial = dict(report, deferred=len(ids) - index - 1,
                                         cached_icons=len(cached_sources(cache)))
                    raise
                report["missing" if error.code == "not_found" else "failed"] += 1
            time.sleep(.3)
        if ids:
            atomic_bytes(cache / ".refresh-cursor", str((offset + visited) % len(ids)).encode())
        return dict(report, cached_icons=len(cached_sources(cache)))


def run(operation, payload):
    if operation == "rebuild":
        expected = payload.get("enabled")
        if not isinstance(expected, bool):
            raise ServiceError("input", "Invalid icon preference")
        # Config.saving covers debounce, not necessarily asynchronous disk I/O.
        # Wait for the actual persisted flag, then build under the normal lock.
        deadline = time.monotonic() + 5
        while enabled() != expected:
            if time.monotonic() > deadline:
                raise ServiceError("settings", "The icon preference has not been saved; retry after saving")
            time.sleep(.05)
        try:
            result = subprocess.run(
                [sys.executable, str(Path(__file__).with_name("process_all_icons.py"))],
                capture_output=True, timeout=180)
            if result.returncode:
                raise ServiceError("rebuild", "Application icon rebuild failed")
        except (OSError, subprocess.SubprocessError):
            raise ServiceError("rebuild", "Application icon rebuild failed") from None
        return {"rebuilt": True}
    if operation == "status":
        try:
            state = "available" if credential() else "missing"
        except ServiceError as error:
            state = error.code
        return {"credential": state, "cached_icons": len(cached_sources())}
    if operation == "set_key":
        key = payload.get("key", "")
        if (not isinstance(key, str) or not key.strip() or len(key) > 512
                or any(not 33 <= ord(character) <= 126 for character in key.strip())):
            raise ServiceError("input", "Enter a valid API key")
        credential("store", key)
        return {"credential": "available"}
    if operation not in ("test", "refresh"):
        raise ServiceError("operation", "Unknown operation")
    if operation == "refresh" and not enabled():
        raise ServiceError("disabled", "Enable SteamGridDB icons before refreshing")
    key = credential()
    if not key:
        raise ServiceError("missing", "Save a SteamGridDB API key first")
    if operation == "test":
        api("/search/autocomplete/Steam", key)
        return {"connected": True}
    return refresh(key, force=payload.get("force") is True)


def main():
    def timed_out(signum, frame):
        raise OperationTimeout()
    try:
        signal.signal(signal.SIGALRM, timed_out)
        signal.alarm(MAX_SECONDS + 45)
        if len(sys.argv) != 2:
            raise ServiceError("operation", "Specify one operation")
        raw = sys.stdin.buffer.read(2049)
        if len(raw) > 2048:
            raise ServiceError("input", "Request exceeded the size limit")
        payload = json.loads(raw or b"{}")
        if not isinstance(payload, dict):
            raise ServiceError("input", "Invalid request")
        result = run(sys.argv[1], payload)
        response = {"ok": True, "result": result}
    except ServiceError as error:
        response = {"ok": False, "error": {"code": error.code, "message": error.message}}
        if hasattr(error, "partial"):
            response["partial"] = error.partial
    except OperationTimeout:
        response = {"ok": False, "error": {"code": "timeout", "message": "SteamGridDB operation timed out; cached artwork retained"}}
    except Exception:
        response = {"ok": False, "error": {"code": "unavailable", "message": "SteamGridDB operation failed"}}
    finally:
        signal.alarm(0)
    print(json.dumps(response, allow_nan=False))


if __name__ == "__main__":
    main()
