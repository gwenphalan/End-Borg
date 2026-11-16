"""Offline wake-policy tests: no live compositor or session bus access."""
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "dots/.config/hypr/hyprland/scripts/display_wake.py"
spec = importlib.util.spec_from_file_location("display_wake", SCRIPT)
wake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wake)


class FakeCommands:
    def __init__(self, instances=("current",), replies=()):
        self.instances = instances
        self.replies = iter(replies)
        self.calls = []

    def __call__(self, args, **kwargs):
        self.calls.append(args)
        assert kwargs["timeout"] == 3
        if args[1:] == ["instances", "-j"]:
            output = json.dumps([{"instance": instance} for instance in self.instances])
        elif "monitors" in args:
            output = '[{"name":"DP-1","dpmsStatus":true}]'
        else:
            response = next(self.replies, "ok")
            if isinstance(response, Exception):
                raise response
            if isinstance(response, tuple):
                return subprocess.CompletedProcess(args, response[0], response[1], "error")
            output = response
        return subprocess.CompletedProcess(args, 0, output, "")


class WakeTests(unittest.TestCase):
    def setUp(self):
        self.logging = patch.object(wake, "log")
        self.logging.start()
        self.addCleanup(self.logging.stop)

    def make(self, fake, environ=None):
        return wake.Wake(run=fake, sleep=lambda _: None, environ=environ or {})

    def test_inherited_instance_wins_over_other_sessions(self):
        fake = FakeCommands(("other", "mine"))
        self.make(fake, {"HYPRLAND_INSTANCE_SIGNATURE": "mine"}).execute()
        self.assertEqual(fake.calls[-1][1:3], ["-i", "mine"])

    def test_stale_signature_falls_back_to_sole_instance(self):
        fake = FakeCommands()
        self.make(fake, {"HYPRLAND_INSTANCE_SIGNATURE": "old"}).execute()
        self.assertEqual(fake.calls[-1][2], "current")

    def test_ambiguous_or_missing_instance_fails_without_dispatch(self):
        for instances in ((), ("first", "second")):
            fake = FakeCommands(instances)
            with self.assertRaises(wake.WakeError):
                self.make(fake).execute()
            self.assertEqual(len(fake.calls), 1)

    def test_standard_hook_does_not_cycle_even_if_monitors_claim_on(self):
        fake = FakeCommands()
        self.make(fake).execute()
        self.assertEqual(len(fake.calls), 2)
        self.assertIn('action = "on"', fake.calls[-1][-1])

    def test_rejected_and_timed_out_on_are_retried_bounded(self):
        fake = FakeCommands(replies=((1, ""), subprocess.TimeoutExpired("hyprctl", 3), "ok"))
        self.make(fake).execute()
        self.assertEqual(len(fake.calls), 4)
        self.assertTrue(all('action = "on"' in call[-1] for call in fake.calls[1:]))

    def test_unacknowledged_on_stops_after_three(self):
        fake = FakeCommands(replies=("unknown request",) * 3)
        with self.assertRaises(wake.WakeError):
            self.make(fake).execute()
        self.assertEqual(len(fake.calls), 4)

    def test_manual_cycle_always_restores_on_after_off_failure(self):
        fake = FakeCommands(replies=(subprocess.TimeoutExpired("hyprctl", 3), "ok"))
        self.make(fake).execute(reinitialize=True)
        self.assertIn('action = "off"', fake.calls[-2][-1])
        self.assertIn('action = "on"', fake.calls[-1][-1])

    def test_check_never_dispatches(self):
        fake = FakeCommands()
        with patch("sys.stdout", new_callable=io.StringIO) as output:
            self.make(fake).execute(check=True)
        self.assertEqual(json.loads(output.getvalue())["instance"], "current")
        self.assertFalse(any("dispatch" in call for call in fake.calls))

    def test_overlapping_invocation_is_rejected(self):
        with tempfile.TemporaryDirectory() as runtime:
            with wake.serialized({"XDG_RUNTIME_DIR": runtime}):
                with self.assertRaises(wake.WakeError):
                    with wake.serialized({"XDG_RUNTIME_DIR": runtime}):
                        self.fail("overlapping invocation acquired lock")
            with wake.serialized({"XDG_RUNTIME_DIR": runtime}):
                pass

    def test_missing_runtime_fails_closed(self):
        with self.assertRaises(wake.WakeError):
            with wake.serialized({}):
                self.fail("missing runtime acquired lock")


if __name__ == "__main__":
    unittest.main()
