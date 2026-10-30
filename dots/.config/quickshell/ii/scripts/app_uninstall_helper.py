#!/usr/bin/python3 -I
"""Root-owned pkexec target; never evaluates launcher content or user code as root."""
import os
import pwd
import re
import subprocess
import sys

ENV = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'HOME': '/root'}


def command(kind, target, caller_uid):
    if kind == 'pacman':
        if not re.fullmatch(r'[a-zA-Z0-9@_+][a-zA-Z0-9@._+:-]*', target):
            raise ValueError('Invalid package name.')
        check = subprocess.run(['/usr/bin/pacman', '-Qq', '--', target], env=ENV, text=True, capture_output=True)
        if check.returncode or check.stdout.strip() != target:
            raise ValueError('The selected package is not installed.')
        return ['/usr/bin/pacman', '-R', '--noconfirm', '--', target]
    if kind not in ('flatpak-user', 'flatpak-system'):
        raise ValueError('Unsupported package manager.')
    if not re.fullmatch(r'app/[A-Za-z0-9_][A-Za-z0-9_.-]*/[A-Za-z0-9_]+/[A-Za-z0-9_.-]+', target):
        raise ValueError('Invalid Flatpak application reference.')
    prefix = []
    scope = kind.split('-')[1]
    if scope == 'user':
        if caller_uid <= 0:
            raise ValueError('A non-root requesting user is required.')
        user = pwd.getpwuid(caller_uid)
        prefix = ['/usr/bin/runuser', '-u', user.pw_name, '--', '/usr/bin/env', '-i',
                  'PATH=/usr/bin:/bin', 'LANG=C.UTF-8', 'HOME=' + user.pw_dir,
                  'USER=' + user.pw_name, 'LOGNAME=' + user.pw_name,
                  'XDG_DATA_HOME=' + user.pw_dir + '/.local/share',
                  'XDG_RUNTIME_DIR=/run/user/' + str(caller_uid)]
    check = subprocess.run(prefix + ['/usr/bin/flatpak', 'info', '--' + scope, '--show-ref', target], env=ENV, text=True, capture_output=True)
    if check.returncode or check.stdout.strip() != target:
        raise ValueError('The selected Flatpak application is not installed in this scope.')
    return prefix + ['/usr/bin/flatpak', 'uninstall', '--' + scope, '--noninteractive', '--assumeyes', target]


def main():
    if os.geteuid() != 0 or len(sys.argv) != 3:
        raise ValueError('This helper must be run through the authenticated application uninstaller.')
    caller_uid = int(os.environ.get('PKEXEC_UID', '-1'))
    if caller_uid <= 0:
        raise ValueError('Missing authenticated requesting user.')
    args = command(sys.argv[1], sys.argv[2], caller_uid)
    return subprocess.run(args, env=ENV).returncode


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
