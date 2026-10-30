import json
import tempfile
import unittest
from unittest.mock import patch

from . import client


class Item:
    item_path = client.LOGIN_COLLECTION + "/item"
    def __init__(self, locked=False):
        self.locked = locked
    def is_locked(self):
        return self.locked
    def get_secret(self):
        return b"test-only-key"


class Storage:
    class Connection:
        def close(self):
            pass
    def __init__(self, locked=False):
        self.item = Item(locked)
    def dbus_init(self):
        return self.Connection()
    def search_items(self, connection, attributes):
        return [self.item]


class Response:
    def __init__(self, data):
        self.data = json.dumps(data).encode() if not isinstance(data, bytes) else data
        self.status_code = 200
    def __enter__(self):
        return self
    def __exit__(self, *args):
        pass
    def iter_content(self, amount):
        yield self.data


class Transport:
    def __init__(self, data):
        self.data = data
        self.calls = 0
    def request(self, method, url, **kwargs):
        self.calls += 1
        assert url.startswith(client.DEFAULT_ENDPOINT)
        assert kwargs["timeout"][0] <= 10
        assert kwargs["allow_redirects"] is False
        assert kwargs["verify"] is True
        return Response(self.data)


class ClientTests(unittest.TestCase):
    def test_alternate_icon_is_from_bounded_candidates_only(self):
        payload = {"desktop_id": "org.test.Editor", "app_name": "Editor",
                   "candidates": ["editor", "text-editor"]}
        reply = lambda name: Transport({"choices": [{"message": {"content": name}}]})
        self.assertEqual(client.run("select_icon", payload, Storage(), reply("text-editor")),
                         {"icon": "text-editor"})
        self.assertEqual(client.run("select_icon", payload, Storage(), reply("NONE")), {"icon": ""})
        with self.assertRaises(client.ClientError):
            client.run("select_icon", payload, Storage(), reply("../private"))
        with self.assertRaises(client.ClientError):
            client.run("select_icon", dict(payload, candidates=["editor", "../private"]),
                       Storage(), reply("editor"))
    def test_locked_no_unlock(self):
        self.assertEqual(client.run("status", {}, Storage(True)), {"credential": "locked"})
        with self.assertRaises(client.ClientError) as failure:
            client.run("models", {}, Storage(True))
        self.assertEqual(failure.exception.code, "locked")

    def test_endpoint_validation(self):
        for endpoint in ("http://example.com/", "https://user:pass@example.com/", "https://example.com/a",
                         "https://example.com/?token=x", "file:///etc/passwd"):
            with self.subTest(endpoint=endpoint), self.assertRaises(client.ClientError):
                client.validated_endpoint(endpoint)

    def test_models_and_malformed(self):
        self.assertEqual(client.run("models", {}, Storage(), Transport({"data": [{"id": "seven"}]})),
                         {"models": ["seven"]})
        with self.assertRaises(client.ClientError) as failure:
            client.run("complete", {"prompt": "hello"}, Storage(), Transport(b"not json"))
        self.assertEqual(failure.exception.code, "malformed")

    def test_icon_opt_in_and_cache(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict("os.environ", {"XDG_STATE_HOME": directory}):
            with self.assertRaises(client.ClientError) as failure:
                client.run("classify_icon", {"icon_name": "sample"}, Storage())
            self.assertEqual(failure.exception.code, "consent")
            transport = Transport({"choices": [{"message": {"content": json.dumps(
                {"presentation": "fit", "confidence": 0.8, "reason": "Full logo"})}}]})
            payload = {"icon_name": "sample", "allow_public_icon": True}
            self.assertEqual(client.run("classify_icon", payload, Storage(), transport)["presentation"], "fit")
            self.assertTrue(client.run("classify_icon", payload, Storage(), transport)["cached"])
            self.assertEqual(transport.calls, 1)
            self.assertEqual(client.run("clear_cache", {}, Storage()), {"cleared": True})

    def test_deadline_and_serialization(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict("os.environ", {"XDG_STATE_HOME": directory}):
            with client.serialized(client.time.monotonic() + 1):
                with patch("borg_intelligence.client.fcntl.flock", side_effect=BlockingIOError):
                    with self.assertRaises(client.ClientError) as failure:
                        with client.serialized(client.time.monotonic() + 0.01):
                            pass
                    self.assertEqual(failure.exception.code, "busy")
        with self.assertRaises(client.ClientError) as failure:
            client.post_or_get(client.DEFAULT_ENDPOINT, "test", "v1/models", None, client.time.monotonic() - 1)
        self.assertEqual(failure.exception.code, "deadline")

    def test_batch_labels_and_rejected_output(self):
        payload = {"apps": [{"id": "org.test.app", "name": "Long Application Name"}]}
        transport = Transport({"choices": [{"message": {"content": '```json\n{"org.test.app":"Test App"}\n```'}}]})
        self.assertEqual(client.run("label_apps", payload, Storage(), transport)["labels"],
                         {"org.test.app": "Test App"})
        for invalid in ({"other": "Unknown App"}, {"org.test.app": "<script>"}, {"org.test.app": "Cut..."}):
            transport = Transport({"choices": [{"message": {"content": json.dumps(invalid)}}]})
            with self.assertRaises(client.ClientError):
                client.run("label_apps", payload, Storage(), transport)

    def test_title_profile_uses_a_separate_serialized_lane(self):
        response = {"choices": [{"message": {"content": "A title"}}]}
        for model in ("seven", "drone-vision", "title-fast", "nanite"):
            with self.subTest(model=model), patch.object(client, "serialized") as lock:
                client.run("complete", {"prompt": "Test", "text_model": model}, Storage(), Transport(response))
                self.assertEqual(lock.call_count, 1)
                self.assertEqual(lock.call_args.args[1:] if model in ("title-fast", "nanite") else (),
                                 ("title",) if model in ("title-fast", "nanite") else ())

    def test_lanes_allow_one_each_but_not_two_titles(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict("os.environ", {"XDG_STATE_HOME": directory}):
            with client.serialized(client.time.monotonic() + 1, "title"):
                with client.serialized(client.time.monotonic() + 1):
                    pass
                with self.assertRaises(client.ClientError):
                    with client.serialized(client.time.monotonic() + .01, "title"):
                        pass


if __name__ == "__main__":
    unittest.main()
