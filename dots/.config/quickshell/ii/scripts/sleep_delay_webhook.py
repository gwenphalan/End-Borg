#!/usr/bin/env python3
"""Sync an absolute bedtime delay count without opening the desktop keyring."""
import json, pathlib, sys
WEBHOOK_ID = 'ivNHRHkUD0XbwNAPq9j-8XBZrekNGPuRgp2SDRwJ4cs'
def send(used, night):
    # The webhook is local-only inside HA. SSH provides the access control.
    if not 0 < used <= 3 or night <= 0:
        return False
    import subprocess, shlex
    remote = """import json,sys,urllib.request
body=sys.stdin.buffer.read()
req=urllib.request.Request('http://127.0.0.1:8123/api/webhook/"""+WEBHOOK_ID+"""',body,{'Content-Type':'application/json'},method='POST')
with urllib.request.urlopen(req,timeout=8) as response: print(response.status)
"""
    # Resolve the current Compose container rather than pinning an ephemeral
    # deployment name. Refuse an ambiguous match instead of posting elsewhere.
    remote_command=(
        "set -- $(sudo -n docker ps --filter label=com.docker.compose.service=homeassistant "
        "--format '{{.ID}}'); [ \"$#\" -eq 1 ] || exit 3; "
        "sudo -n docker exec -i \"$1\" python3 -c " + shlex.quote(remote)
    )
    command=['ssh','-F',str(pathlib.Path.home()/'.ssh/config'),'-o','BatchMode=yes',
        '-o','ConnectTimeout=5','unimatrix-03',remote_command]
    try:
        result=subprocess.run(command,input=json.dumps({'used':used,'night_start':night}).encode(),
            capture_output=True,timeout=15)
        return result.returncode == 0 and result.stdout.strip() == b'200'
    except (OSError,subprocess.TimeoutExpired):
        return False

if __name__=='__main__':
    try:
        success = len(sys.argv) == 3 and send(int(sys.argv[1]), float(sys.argv[2]))
    except ValueError:
        success = False
    sys.exit(0 if success else 1)
