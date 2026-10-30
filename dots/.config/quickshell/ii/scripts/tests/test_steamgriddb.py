import fcntl
import hashlib
import io
import json
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
import urllib.error
import zlib

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import process_all_icons as builder
import steamgriddb_credentials as credentials
import steamgriddb_icons as client
import steamgriddb_source as source


def png(size=(256, 256), color="red"):
    buffer = io.BytesIO()
    Image.new("RGBA", size, color).save(buffer, format="PNG")
    return buffer.getvalue()


def seed(cache, data=None):
    data = png() if data is None else data
    digest = hashlib.sha256(data).hexdigest()
    path = cache / "assets" / f"570-{digest}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    record = {"sha256": digest, "asset_id": 42, "style": "official", "fetched_at": int(time.time())}
    (cache / "manifest.json").write_text(json.dumps({"schema_version": 1, "icons": {"570": record}}))
    return path


class SourceTests(unittest.TestCase):
    def test_exact_steam_launch_identity(self):
        for command in (
            "steam steam://rungameid/570", "/usr/bin/steam -applaunch 570",
            'env STEAM_FRAME_FORCE_CLOSE=1 steam "steam://run/570//"',
            "steam-native steam://run/570", "flatpak run com.valvesoftware.Steam steam://rungameid/570",
            "flatpak run --branch=stable --arch x86_64 --command=steam com.valvesoftware.Steam -applaunch 570",
        ):
            with self.subTest(command=command):
                self.assertEqual(source.steam_app_id({"exec": command}), "570")

    def test_unrelated_or_ambiguous_launches_are_not_games(self):
        for command in (
            "printf steam://rungameid/570", "steam -applaunch 0",
            "steam steam://rungameid/10908424674384973824", 'steam "unterminated',
            "steam -applaunch 570 steam://run/730", "steam steam://store/570",
            "flatpak run org.example.Other com.valvesoftware.Steam steam://run/570",
            "flatpak run --command=printf com.valvesoftware.Steam steam://run/570",
            "flatpak run --command /bin/sh com.valvesoftware.Steam steam://run/570",
            "flatpak run --unexpected=value com.valvesoftware.Steam steam://run/570",
        ):
            with self.subTest(command=command):
                self.assertIsNone(source.steam_app_id({"exec": command, "name": "Dota 2"}))

    def test_missing_malformed_and_disabled_config(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            self.assertFalse(source.enabled(path))
            for value in ("", "[]", '{"appearance":null}', '{"appearance":{"steamGridDb":{"enabled":"true"}}}'):
                path.write_text(value)
                self.assertFalse(source.enabled(path))
            path.write_text('{"appearance":{"steamGridDb":{"enabled":true}}}')
            self.assertTrue(source.enabled(path))

    def test_content_addressed_cache_and_corruption(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder)
            path = seed(cache)
            self.assertEqual(source.cached_sources(cache)["570"][0], path)
            path.write_bytes(b"corrupted")
            self.assertEqual(source.cached_sources(cache), {})

    def test_invalid_manifests_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder)
            for data in ("[]", "null", "{", '{"schema_version":1,"icons":[]}', "x" * (2 * 1024 * 1024 + 1)):
                (cache / "manifest.json").write_text(data)
                self.assertEqual(source.cached_sources(cache), {})
            (cache / "manifest.json").write_text(json.dumps({"schema_version": 1, "icons": {
                "../570": {}, "570": {"sha256": "../escape"}, "4294967296": {}}}))
            self.assertEqual(source.cached_sources(cache), {})

    def test_cache_symlinks_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder)
            path = seed(cache)
            other = cache / "other.png"
            path.rename(other)
            path.symlink_to(other)
            self.assertEqual(source.cached_sources(cache), {})

    def test_preference_and_corrupt_preferred_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder)
            declared = cache / "declared.png"
            declared.write_bytes(png(color="blue"))
            preferred = seed(cache)
            desktop = {"name": "Sample", "icon": str(declared), "exec": "steam -applaunch 570"}
            selection = source.cached_sources(cache)["570"]
            result = builder.metadata_for("sample", desktop, {}, "", cache, {}, preferred_source=selection)
            self.assertEqual(result["source"], str(preferred))
            self.assertEqual(result["source_family"], "SteamGridDB")
            preferred.write_bytes(b"bad")
            result = builder.metadata_for("sample", desktop, {}, "", cache, {}, preferred_source=selection)
            self.assertEqual(result["source"], str(declared))
            result = builder.metadata_for("sample", desktop, {}, "", cache, {},
                                          source_override=declared, preferred_source=selection)
            self.assertEqual(result["source"], str(declared))

    def test_builder_disabled_does_not_read_cache_or_network(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(builder, "steamgriddb_enabled", return_value=False), \
                patch.object(builder, "cached_sources") as cached, patch.object(client, "fetch") as network:
            apps = Path(folder) / "apps"
            apps.mkdir()
            builder.build(Path(folder) / "cache", directories=[apps])
            cached.assert_not_called()
            network.assert_not_called()


    def test_invalid_cached_images_fall_back_without_aborting(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder)
            declared = cache / "declared.png"
            declared.write_bytes(png(color="blue"))
            desktop = {"name": "Sample", "icon": str(declared), "exec": "steam -applaunch 570"}
            header = struct.pack(">IIBBBBB", 30000, 30000, 8, 6, 0, 0, 0)
            bomb = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", len(header)) + b"IHDR" + header + struct.pack(">I", zlib.crc32(b"IHDR" + header))
            for data in (bomb, png((64, 128)), png((32, 32)), png(color=(0, 0, 0, 0))):
                seed(cache, data)
                result = builder.metadata_for("sample", desktop, {}, "", cache, {},
                                              preferred_source=source.cached_sources(cache)["570"])
                self.assertEqual(result["source"], str(declared))


class DownloadTests(unittest.TestCase):
    def test_artwork_origin_validation(self):
        self.assertTrue(client.valid_artwork_url("https://cdn2.steamgriddb.com/icon/abc.png"))
        for url in ("http://cdn2.steamgriddb.com/icon/a.png", "https://evil.example/icon/a",
                    "https://cdn2.steamgriddb.com.evil.example/icon/a",
                    "https://user@cdn2.steamgriddb.com/icon/a", "https://cdn2.steamgriddb.com:8443/icon/a",
                    "https://cdn2.steamgriddb.com/grid/a.png", "https://cdn2.steamgriddb.com/icon/a?key=x"):
            self.assertFalse(client.valid_artwork_url(url))
        with self.assertRaises(client.ServiceError):
            client.fetch("https://www.steamgriddb.com.evil.example/api/v2/icons", key="test-only")

    def test_auth_only_on_api_and_redirects_rejected(self):
        response = Mock(status=200, headers={})
        response.read1.side_effect = [b"{}", b"", b"png", b""]
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        opener = Mock()
        opener.open.return_value = response
        with patch.object(client.urllib.request, "build_opener", return_value=opener):
            client.fetch(client.API + "/test", key="test-only")
            client.fetch("https://cdn2.steamgriddb.com/icon/a.png")
        first, second = [call.args[0] for call in opener.open.call_args_list]
        self.assertEqual(first.get_header("Authorization"), "Bearer test-only")
        self.assertIsNone(second.get_header("Authorization"))
        self.assertIsNone(client.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.example"))

    def test_response_size_and_deadline(self):
        response = Mock(status=200, headers={"Content-Length": "100"})
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        opener = Mock()
        opener.open.return_value = response
        with patch.object(client.urllib.request, "build_opener", return_value=opener):
            with self.assertRaises(client.ServiceError) as error:
                client.fetch(client.API + "/test", key="test-only", maximum=10)
            self.assertEqual(error.exception.code, "size")
            response.headers = {}
            response.read1.return_value = b"x" * 11
            with self.assertRaises(client.ServiceError):
                client.fetch(client.API + "/test", key="test-only", maximum=10)
            with patch.object(client.time, "monotonic", side_effect=[0, 31]):
                with self.assertRaises(client.ServiceError) as error:
                    client.fetch(client.API + "/test", key="test-only")
                self.assertEqual(error.exception.code, "timeout")

    def test_http_errors_are_sanitized(self):
        for status, code in ((401, "auth"), (403, "auth"), (429, "rate_limit"), (404, "not_found"), (302, "http")):
            opener = Mock()
            opener.open.side_effect = urllib.error.HTTPError("https://example", status, "private-body", {}, None)
            with patch.object(client.urllib.request, "build_opener", return_value=opener):
                with self.assertRaises(client.ServiceError) as error:
                    client.fetch(client.API + "/test", key="test-only")
            self.assertEqual(error.exception.code, code)
            self.assertNotIn("test-only", str(error.exception))
            self.assertNotIn("private-body", str(error.exception))

    def test_image_bounds_transparency_and_corruption(self):
        self.assertEqual(client.decode_icon(png())[1], (256, 256))
        for data in (b"bad", png((32, 32)), png((256, 128)), png(color=(0, 0, 0, 0)), png((2049, 2049))):
            with self.assertRaises(client.ServiceError):
                client.decode_icon(data)
        buffer = io.BytesIO()
        Image.new("RGBA", (64, 64), "red").save(buffer, "PNG", save_all=True,
                                               append_images=[Image.new("RGBA", (64, 64), "blue")])
        with self.assertRaises(client.ServiceError):
            client.decode_icon(buffer.getvalue())

    def test_deterministic_official_preference_and_download_retry(self):
        entries = [
            {"id": 1, "style": "custom", "score": 1000, "url": "https://cdn2.steamgriddb.com/icon/1.png"},
            {"id": 2, "style": "official", "score": 10, "url": "https://cdn2.steamgriddb.com/icon/2.png"},
            {"id": 3, "style": "official", "score": 5, "url": "https://cdn2.steamgriddb.com/icon/3.png"},
        ]
        with patch.object(client, "api", return_value=entries), \
                patch.object(client, "fetch", side_effect=[b"bad", png()]) as fetch:
            _, record = client.select_icon("570", "test-only")
            self.assertEqual(record["asset_id"], 3)
            self.assertEqual(fetch.call_args_list[0].args[0], entries[1]["url"])
            self.assertNotIn("key", fetch.call_args_list[0].kwargs)

    def test_refresh_cache_stability_failures_and_throttling(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(client.time, "sleep"):
            cache = Path(folder)
            with patch.object(client, "select_icon", return_value=(png(), {"asset_id": 42, "style": "official"})) as select:
                self.assertEqual(client.refresh("test-only", cache, ["570"])["updated"], 1)
                first = next((cache / "assets").iterdir()).read_bytes()
                self.assertEqual(client.refresh("test-only", cache, ["570"])["cached"], 1)
                self.assertEqual(select.call_count, 1)
            before = (cache / "manifest.json").read_bytes()
            for code in ("not_found", "network"):
                with patch.object(client, "select_icon", side_effect=client.ServiceError(code, "Unavailable")):
                    client.refresh("test-only", cache, ["570"], force=True)
                self.assertEqual((cache / "manifest.json").read_bytes(), before)
                self.assertEqual(next((cache / "assets").iterdir()).read_bytes(), first)
            for code in ("auth", "rate_limit"):
                with patch.object(client, "select_icon", side_effect=client.ServiceError(code, "Unavailable")) as select:
                    with self.assertRaises(client.ServiceError):
                        client.refresh("test-only", cache, ["570", "730"], force=True)
                    self.assertEqual(select.call_count, 1)
            self.assertNotIn("test-only", (cache / "manifest.json").read_text())

    def test_refresh_serialization(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder)
            with (cache / ".refresh.lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaises(client.ServiceError) as error:
                    client.refresh("test-only", cache, [])
                self.assertEqual(error.exception.code, "busy")


    def test_same_size_corruption_is_repaired(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(client.time, "sleep"):
            cache = Path(folder)
            path = seed(cache)
            original = path.read_bytes()
            path.write_bytes(b"x" * len(original))
            with patch.object(client, "select_icon", return_value=(original, {"asset_id": 42, "style": "official"})):
                report = client.refresh("test-only", cache, ["570"], force=True)
            self.assertEqual(report["cached_icons"], 1)
            self.assertEqual(path.read_bytes(), original)

    def test_deferred_games_progress_and_partial_failure_keeps_cursor(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(client.time, "sleep"), patch.object(client, "MAX_GAMES", 2):
            cache = Path(folder)
            ids = ["570", "730", "440"]
            with patch.object(client, "select_icon", return_value=(png(), {"asset_id": 42, "style": "official"})) as select:
                self.assertEqual(client.refresh("test-only", cache, ids, force=True)["deferred"], 1)
                client.refresh("test-only", cache, ids, force=True)
                self.assertIn("440", [call.args[0] for call in select.call_args_list])
            with patch.object(client, "select_icon", side_effect=[
                    (png(), {"asset_id": 42, "style": "official"}), client.ServiceError("rate_limit", "Retry later")]):
                with self.assertRaises(client.ServiceError) as error:
                    client.refresh("test-only", cache, ids, force=True)
                self.assertEqual(error.exception.partial["updated"], 1)
                self.assertTrue((cache / ".refresh-cursor").is_file())

    def test_rebuild_waits_for_saved_preference(self):
        result = subprocess.CompletedProcess([], 0, b"", b"")
        with patch.object(client, "enabled", side_effect=[False, False, True]), \
                patch.object(client.time, "sleep"), patch.object(client.subprocess, "run", return_value=result) as rebuild:
            self.assertTrue(client.run("rebuild", {"enabled": True})["rebuilt"])
            rebuild.assert_called_once()
        with patch.object(client, "enabled", return_value=False), \
                patch.object(client.time, "monotonic", side_effect=[0, 6]), \
                patch.object(client.subprocess, "run") as rebuild:
            with self.assertRaises(client.ServiceError):
                client.run("rebuild", {"enabled": True})
            rebuild.assert_not_called()


class CredentialTests(unittest.TestCase):
    def test_key_only_through_captured_stdin(self):
        result = subprocess.CompletedProcess([], 0, "", "")
        with patch.object(client.subprocess, "run", return_value=result) as run:
            client.credential("store", "test-only")
        args, kwargs = run.call_args
        self.assertNotIn("test-only", " ".join(args[0]))
        self.assertEqual(kwargs["input"], "test-only")
        self.assertTrue(kwargs["capture_output"])

    def test_locked_missing_and_disabled_are_reported_without_network(self):
        with patch.object(client.subprocess, "run", return_value=subprocess.CompletedProcess([], 3, "", "")):
            self.assertEqual(client.run("status", {})["credential"], "locked")
        with patch.object(client, "enabled", return_value=False), patch.object(client, "credential") as key:
            with self.assertRaises(client.ServiceError):
                client.run("refresh", {})
            key.assert_not_called()
        with patch.object(client, "credential", return_value=""), patch.object(client, "api") as api:
            with self.assertRaises(client.ServiceError):
                client.run("test", {})
            api.assert_not_called()

    def test_keyring_attributes_and_connection_cleanup(self):
        storage, collection = Mock(), Mock()
        collection.is_locked.return_value = False
        with patch.object(credentials, "writable_collection", return_value=collection):
            credentials.store(storage, "test-only")
        self.assertEqual(collection.create_item.call_args.args[1], credentials.ATTRIBUTES)
        self.assertTrue(collection.create_item.call_args.kwargs["replace"])
        storage.dbus_init.return_value.close.assert_called_once()
        for invalid in ("", "a b", "a\nb", "a" * 513, "\x00"):
            with self.assertRaises(ValueError):
                credentials.store(storage, invalid)


if __name__ == "__main__":
    unittest.main()
