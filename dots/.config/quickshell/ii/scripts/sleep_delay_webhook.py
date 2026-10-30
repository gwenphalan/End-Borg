#!/usr/bin/env python3
"""Reconcile an absolute Sleep delay count over SSH loopback, without a keyring."""
import json
import math
import pathlib
import shlex
import subprocess
import sys

# Sleep registers this endpoint local_only=True. It is never reachable from a
# browser/LAN client; SSH is the authenticated transport into HA's loopback.
WEBHOOK_ID = "sleep_delay_sync"


def send(used, night):
    if type(used) is not int or not 0 <= used <= 10 or not math.isfinite(night) or night <= 0:
        return False
    remote = """import sys,json,urllib.request
body=sys.stdin.buffer.read()
req=urllib.request.Request('http://127.0.0.1:8123/api/webhook/sleep_delay_sync',body,{'Content-Type':'application/json'},method='POST')
with urllib.request.urlopen(req,timeout=8) as response:
 acknowledgement=json.load(response)
 if response.status!=200 or acknowledgement.get('accepted') is not True or acknowledgement.get('used')!=json.loads(body)['used']: sys.exit(4)
 print(response.status)
"""
    remote_command = (
        "set -- $(sudo -n docker ps --filter label=com.docker.compose.service=homeassistant "
        "--format '{{.ID}}'); [ \"$#\" -eq 1 ] || exit 3; "
        "sudo -n docker exec -i \"$1\" python3 -c " + shlex.quote(remote)
    )
    command = ['ssh', '-F', str(pathlib.Path.home()/'.ssh/config'), '-o', 'BatchMode=yes',
               '-o', 'ConnectTimeout=5', 'unimatrix-03', remote_command]
    try:
        result = subprocess.run(command, input=json.dumps({'used':used, 'nightStartEpoch':night}).encode(),
                                capture_output=True, timeout=15)
        return result.returncode == 0 and result.stdout.strip() == b'200'
    except (OSError, subprocess.TimeoutExpired):
        return False


if __name__ == '__main__':
    try:
        success = len(sys.argv) == 3 and send(int(sys.argv[1]), float(sys.argv[2]))
    except ValueError:
        success = False
    sys.exit(0 if success else 1)
