import unittest

from bedlock_lan_status import validate


NOW = 1793098800  # 2026-10-27 04:00 America/Phoenix
NIGHT = 1793086200


def sample(**changes):
    payload = {
        "delaysRemaining": 0,
        "delaysUsed": 3,
        "maxDelays": 3,
        "delayMinutes": 30,
        "bedtime": "2026-10-27T02:30:00-07:00",
        "wakeup": "2026-10-27T10:30:00-07:00",
        "nightStartEpoch": NIGHT,
        "generatedAtEpoch": NOW,
    }
    payload.update(changes)
    return payload


class BedLockLanStatusTest(unittest.TestCase):
    def test_current_snapshot(self):
        result = validate(sample(), NOW)
        self.assertEqual(result["bedtimeEpoch"], 1793093400)
        self.assertEqual(result["wakeEpoch"], 1793122200)
        self.assertEqual(result["delaysRemaining"], 0)
        self.assertEqual(result["delaysUsed"], 3)
        self.assertEqual(result["maxDelays"], 3)
        self.assertEqual(result["delayMinutes"], 30)

    def test_schedule_off(self):
        self.assertEqual(validate(sample(wakeup=None), NOW)["wakeEpoch"], 0)

    def test_completed_override_accepts_base_bedtime_with_no_wake(self):
        # Override expiry may restore an earlier base bedtime, but HA must
        # keep wakeup null for the completed night until nightStart advances.
        result = validate(sample(wakeup=None), NOW, NIGHT, NOW - 20, 3)
        self.assertEqual(result["wakeEpoch"], 0)
        self.assertEqual(result["nightStartEpoch"], NIGHT)

    def test_null_wake_does_not_bypass_snapshot_validation(self):
        for changes in ({"generatedAtEpoch": NOW - 91},
                        {"bedtime": "bad"}, {"delaysRemaining": -1}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate(sample(wakeup=None, **changes), NOW)
        with self.assertRaises(ValueError):
            validate(sample(wakeup=None), NOW, NIGHT + 86400, NOW - 20, 3)

    def test_changed_delay_length(self):
        self.assertEqual(validate(sample(delayMinutes=45), NOW)["delayMinutes"], 45)

    def test_rejects_bad_payloads(self):
        bad = [
            None,
            {"bedtime": "2026-10-27T02:30:00-07:00"},
            sample(delaysRemaining=-1),
            sample(delaysRemaining=True),
            sample(delaysRemaining=4),
            sample(delaysUsed=-1),
            sample(delaysUsed=11),
            sample(maxDelays=11),
            sample(maxDelays=True),
            sample(delayMinutes=0),
            sample(delayMinutes=121),
            sample(delayMinutes=True),
            sample(delayMinutes=30.5),
            sample(bedtime="not a timestamp"),
            sample(bedtime="2026-10-27T02:30:00"),
            sample(wakeup="2026-10-27T01:00:00-07:00"),
            sample(generatedAtEpoch=NOW - 91),
            sample(generatedAtEpoch=NOW + 6),
            sample(nightStartEpoch=NIGHT - 90000),
            sample(nightStartEpoch=NOW + 3601),
        ]
        for payload in bad:
            with self.subTest(payload=payload), self.assertRaises((ValueError, TypeError)):
                validate(payload, NOW)

    def test_newer_override_can_reset_delays(self):
        result = validate(sample(delaysRemaining=3, delaysUsed=0,
                                 bedtime="2026-10-27T04:30:00-07:00",
                                 wakeup="2026-10-27T09:30:00-07:00"),
                          NOW, NIGHT, NOW - 20, 3)
        self.assertEqual(result["delaysUsed"], 0)
        self.assertEqual(result["delaysRemaining"], 3)
        self.assertEqual(result["wakeEpoch"] - result["bedtimeEpoch"], 5 * 3600)

    def test_delay_reset_needs_strictly_newer_snapshot(self):
        for previous_generated in (0, NOW, NOW + 1):
            with self.subTest(previous_generated=previous_generated), self.assertRaises(ValueError):
                validate(sample(delaysRemaining=1, delaysUsed=2), NOW,
                         NIGHT, previous_generated, 3)

    def test_same_night_generation_is_monotonic(self):
        with self.assertRaises(ValueError):
            validate(sample(generatedAtEpoch=NOW - 20), NOW, NIGHT, NOW - 10, 3)
        self.assertEqual(validate(sample(), NOW, NIGHT, NOW - 20, 3)["delaysRemaining"], 0)

    def test_max_can_change_without_undoing_used_delays(self):
        result = validate(sample(maxDelays=5, delaysRemaining=2), NOW, NIGHT, NOW - 20, 3)
        self.assertEqual(result["delaysRemaining"], 2)
        self.assertEqual(result["delaysUsed"], 3)

    def test_previous_night_cannot_return(self):
        with self.assertRaises(ValueError):
            validate(sample(), NOW, NIGHT + 86400, NOW - 20, 1)


if __name__ == "__main__":
    unittest.main()
