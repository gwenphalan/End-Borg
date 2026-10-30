#!/usr/bin/python3
"""Resolve a launcher entry and request an authenticated package uninstall.

--resolve prints the target without prompting or changing anything.
"""
import argparse
import configparser
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HELPER = '/usr/local/libexec/ii-uninstall-app'
DIALOG = str(Path(__file__).resolve().parents[1] / 'appUninstallDialog.qml')
DECISION_PREFIX = 'II_UNINSTALL_DIALOG_RESULT:'


def run(args):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def desktop_path(desktop_id):
    if not desktop_id or '/' in desktop_id or '\x00' in desktop_id or desktop_id.startswith('.'):
        raise ValueError('Invalid application launcher ID.')
    filename = desktop_id if desktop_id.endswith('.desktop') else desktop_id + '.desktop'
    home_data = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
    data_dirs = [home_data] + [Path(p) for p in os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':') if p]
    data_dirs += [home_data / 'flatpak/exports/share', Path('/var/lib/flatpak/exports/share')]
    # Desktop entry IDs flatten nested application directories with hyphens.
    for data in dict.fromkeys(data_dirs):
        base = data / 'applications'
        direct = base / filename
        if direct.is_file():
            return direct
        if base.is_dir():
            for candidate in base.rglob('*.desktop'):
                if str(candidate.relative_to(base)).replace('/', '-') == filename:
                    return candidate
    raise ValueError('This application launcher no longer exists.')


def resolve(desktop_id):
    path = desktop_path(desktop_id)
    data = configparser.ConfigParser(interpolation=None, strict=False)
    data.read(path, encoding='utf-8')
    name = data.get('Desktop Entry', 'Name', fallback=desktop_id)
    flatpak_id = data.get('Desktop Entry', 'X-Flatpak', fallback='')
    if flatpak_id and re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*', flatpak_id):
        # Match the exported entry's deployment to its installation. A user
        # override is resolved against installed applications, user first.
        resolved_path = path.resolve()
        preferred = ['system', 'user'] if str(resolved_path).startswith('/var/lib/flatpak/') else ['user', 'system']
        for scope in preferred:
            info = run(['/usr/bin/flatpak', 'info', '--' + scope, '--show-ref', flatpak_id])
            if info.returncode == 0 and info.stdout.strip().startswith('app/'):
                return {'name': name, 'kind': 'flatpak-' + scope, 'target': info.stdout.strip(), 'desktop': str(path)}
    owner = run(['/usr/bin/pacman', '-Qqo', '--', str(path)])
    packages = owner.stdout.splitlines()
    if owner.returncode == 0 and len(packages) == 1:
        return {'name': name, 'kind': 'pacman', 'target': packages[0], 'desktop': str(path)}
    # Generated icon overrides are unowned copies of packaged launchers. Match
    # the desktop ID AND Exec field before selecting the system package.
    filename = desktop_id if desktop_id.endswith('.desktop') else desktop_id + '.desktop'
    original_exec = data.get('Desktop Entry', 'Exec', fallback='')
    for base in (Path('/usr/local/share/applications'), Path('/usr/share/applications')):
        candidates = [base / filename]
        if base.is_dir():
            candidates += [p for p in base.rglob('*.desktop') if str(p.relative_to(base)).replace('/', '-') == filename]
        for candidate in dict.fromkeys(candidates):
            if not candidate.is_file() or candidate == path:
                continue
            system_data = configparser.ConfigParser(interpolation=None, strict=False)
            system_data.read(candidate, encoding='utf-8')
            if not original_exec or system_data.get('Desktop Entry', 'Exec', fallback='') != original_exec:
                continue
            owner = run(['/usr/bin/pacman', '-Qqo', '--', str(candidate)])
            packages = owner.stdout.splitlines()
            if owner.returncode == 0 and len(packages) == 1:
                return {'name': name, 'kind': 'pacman', 'target': packages[0], 'desktop': str(path)}
    raise ValueError('This launcher is not owned by an installed Pacman or Flatpak application. Use its own uninstaller (for example Steam) instead.')


def dialog(kind, title, message):
    """A separate Quickshell window returns a decision; failures cancel safely."""
    environment = os.environ.copy()
    environment.update({
        'II_UNINSTALL_DIALOG_MODE': kind,
        'II_UNINSTALL_DIALOG_TITLE': title,
        'II_UNINSTALL_DIALOG_MESSAGE': message,
    })
    try:
        result = subprocess.run(['/usr/bin/qs', '-p', DIALOG], env=environment,
                                text=True, capture_output=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired):
        return False
    if result.returncode != 0:
        return False
    output = result.stdout + '\n' + result.stderr
    answer = next((line.split(DECISION_PREFIX, 1)[1].strip()
                   for line in output.splitlines() if DECISION_PREFIX in line), '')
    return answer == ('confirm' if kind == 'question' else 'acknowledge')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resolve', action='store_true')
    parser.add_argument('desktop_id')
    parser.add_argument('display_name', nargs='?')
    args = parser.parse_args()
    try:
        target = resolve(args.desktop_id)
    except (ValueError, OSError, configparser.Error) as error:
        if args.resolve:
            print(str(error), file=sys.stderr)
        else:
            dialog('error', 'Cannot uninstall application', str(error))
        return 1
    if args.resolve:
        print(json.dumps(target))
        return 0
    label = 'package' if target['kind'] == 'pacman' else target['kind'].replace('-', ' ')
    detail = ('Other launchers supplied by this package will also be removed.\nDependent packages will not be removed automatically.'
              if target['kind'] == 'pacman' else 'Application data will be kept.')
    if not dialog('question', f"Uninstall {target['name']}?",
                  f"{label}: {target['target']}\n\n{detail}\n\nAn administrator password is required."):
        return 0
    result = run(['/usr/bin/pkexec', HELPER, target['kind'], target['target']])
    if result.returncode:
        if result.returncode == 126:  # User dismissed the authentication dialog.
            return 0
        text = (result.stderr.strip() or result.stdout.strip() or 'Authentication failed or the uninstall was refused.')
        dialog('error', f"Could not uninstall {target['name']}", text[-5000:])
        return result.returncode
    # Remove this generated icon override, which otherwise leaves a dead app
    # in the launcher after its packaged desktop entry has disappeared.
    selected = Path(target['desktop'])
    local_apps = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'applications'
    if selected.parent == local_apps and selected.is_file():
        try:
            if selected.read_text(encoding='utf-8').startswith('# Managed by global_app_icons.py;'):
                selected.unlink()
        except OSError:
            pass
    dialog('info', 'Application uninstalled', f"{target['name']} was uninstalled.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
