#!/usr/bin/env python3
"""Read and validate the nonsecret Bed Lock status from Home Assistant's LAN endpoint."""

import datetime as dt
import json
import math
import sys
import time
import urllib.request

URL = "http://192.168.68.112:8124/bedtime"


def valid_epoch(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def parse_offset_time(value):
    if not isinstance(value, str) or not value:
        raise ValueError("missing timestamp")
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("timestamp needs UTC offset")
    return parsed.timestamp()


def validate(payload, now, previous_night=0, previous_generated=0, previous_used=0):
    if not isinstance(payload, dict):
        raise ValueError("expected object")
    required = {"nightStartEpoch", "generatedAtEpoch", "delaysRemaining", "delaysUsed", "maxDelays", "delayMinutes", "bedtime", "wakeup"}
    if not required.issubset(payload):
        raise ValueError("missing required status field")
    if not valid_epoch(now):
        raise ValueError("invalid clock")
    night = payload.get("nightStartEpoch")
    generated = payload.get("generatedAtEpoch")
    remaining = payload.get("delaysRemaining")
    used = payload.get("delaysUsed")
    maximum = payload.get("maxDelays")
    delay_minutes = payload.get("delayMinutes")
    if payload.get("phase") == "off":
        if (type(night) is not int or night != 0 or type(generated) is not int
                or not valid_epoch(generated) or generated < now - 90 or generated > now + 5
                or (valid_epoch(previous_generated) and generated <= previous_generated)):
            raise ValueError("stale or replayed disabled plan")
        if (payload.get("bedtime") is not None or payload.get("wakeup") is not None
                or type(used) is not int or used != 0 or type(remaining) is not int or remaining != 0
                or type(maximum) is not int or not 0 <= maximum <= 10
                or type(delay_minutes) is not int or not 1 <= delay_minutes <= 120):
            raise ValueError("invalid disabled plan")
        return {"phase": "off", "nightStartEpoch": 0, "generatedAtEpoch": generated,
                "delaysRemaining": 0, "delaysUsed": 0, "maxDelays": maximum,
                "delayMinutes": delay_minutes, "bedtimeEpoch": 0, "wakeEpoch": 0}
    if type(night) is not int or type(generated) is not int \
            or not valid_epoch(night) or not valid_epoch(generated):
        raise ValueError("invalid epoch")
    if valid_epoch(previous_generated) and (generated < previous_generated
            or (previous_night == 0 and generated <= previous_generated)):
        raise ValueError("snapshot predates the current plan")
    if type(used) is not int or not 0 <= used <= 10:
        raise ValueError("invalid delays used")
    if type(maximum) is not int or not 0 <= maximum <= 10:
        raise ValueError("invalid max delays")
    if type(remaining) is not int or remaining != max(0, maximum - used):
        raise ValueError("invalid delays remaining")
    if type(delay_minutes) is not int or not 1 <= delay_minutes <= 120:
        raise ValueError("invalid delay length")
    if generated < now - 90 or generated > now + 5:
        raise ValueError("stale or future response")
    if night > now + 3600 or now > night + 86400:
        raise ValueError("response is for wrong night")
    bedtime = parse_offset_time(payload.get("bedtime"))
    raw_wake = payload.get("wakeup")
    wake = parse_offset_time(raw_wake) if raw_wake is not None else 0
    if bedtime < night - 21600 or bedtime > night + 86400:
        raise ValueError("bedtime outside night")
    if wake and (wake <= bedtime or wake > night + 86400):
        raise ValueError("invalid wake time")
    if valid_epoch(previous_night):
        if night < previous_night - 60:
            raise ValueError("night moved backwards")
        if abs(night - previous_night) < 60:
            if valid_epoch(previous_generated) and generated < previous_generated:
                raise ValueError("snapshot moved backwards")
            # HA can reset the count when replacing tonight's schedule.
            # Accept that authoritative reset only in a strictly newer snapshot;
            # replayed or stale data must never restore spent delays.
            if used < previous_used and (not valid_epoch(previous_generated)
                                         or generated <= previous_generated):
                raise ValueError("delay reset needs a newer snapshot")
    return {
        "nightStartEpoch": night,
        "generatedAtEpoch": generated,
        "delaysRemaining": remaining,
        "delaysUsed": used,
        "maxDelays": maximum,
        "delayMinutes": delay_minutes,
        "bedtimeEpoch": bedtime,
        "wakeEpoch": wake,
    }


def main():
    try:
        previous_night = float(sys.argv[1]) if len(sys.argv) > 1 else 0
        previous_generated = float(sys.argv[2]) if len(sys.argv) > 2 else 0
        previous_used = int(sys.argv[3]) if len(sys.argv) > 3 else 0
        request = urllib.request.Request(URL, headers={"Cache-Control": "no-cache"})
        # Do not send the public LAN read through a desktop proxy.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=2) as response:
            if response.status != 200:
                raise ValueError("HTTP failure")
            body = response.read(4097)
        if len(body) > 4096:
            raise ValueError("oversize response")
        normalized = validate(json.loads(body), time.time(), previous_night,
                              previous_generated, previous_used)
        print(json.dumps(normalized, separators=(",", ":")))
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(f"bedlock LAN status rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
