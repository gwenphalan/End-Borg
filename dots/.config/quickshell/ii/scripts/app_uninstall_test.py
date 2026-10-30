#!/usr/bin/python3
"""Non-destructive tests: all privileged command executions are mocked."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


ui = load('app_uninstall', 'app_uninstall.py')
helper = load('app_uninstall_helper', 'app_uninstall_helper.py')


class UninstallTests(unittest.TestCase):
    def test_rejects_path_and_option_ids(self):
        for value in ('../etc/passwd', '/usr/share/applications/foo.desktop', '.hidden', ''):
            with self.subTest(value=value), self.assertRaises(ValueError):
                ui.desktop_path(value)

    def test_package_command_never_recurses(self):
        with patch.object(helper.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'filelight\n', '')):
            command = helper.command('pacman', 'filelight', 1000)
        self.assertEqual(command, ['/usr/bin/pacman', '-R', '--noconfirm', '--', 'filelight'])

    def test_rejects_options_and_shell_syntax(self):
        for kind, target in [('pacman', '--root=/tmp'), ('pacman', 'a;rm -rf /'), ('flatpak-system', '--delete-data'), ('flatpak-user', 'runtime/a/b/c')]:
            with self.subTest(target=target), self.assertRaises(ValueError), patch.object(helper.subprocess, 'run') as run:
                helper.command(kind, target, 1000)
            run.assert_not_called()

    def test_missing_package_is_not_removed(self):
        with patch.object(helper.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'missing')) as run:
            with self.assertRaises(ValueError):
                helper.command('pacman', 'missing-package', 1000)
        self.assertEqual(run.call_count, 1)

    def test_user_flatpak_runs_only_as_caller(self):
        target = 'app/com.hypixel.HytaleLauncher/x86_64/master'
        with patch.object(helper.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, target + '\n', '')):
            command = helper.command('flatpak-user', target, 1000)
        self.assertEqual(command[:4], ['/usr/bin/runuser', '-u', 'gwenp', '--'])
        self.assertIn('--user', command)
        self.assertNotIn('--delete-data', command)
        self.assertEqual(command[-1], target)

    def test_resolution_never_executes_desktop_command(self):
        with tempfile.TemporaryDirectory() as temp:
            desktop = Path(temp) / 'test.desktop'
            desktop.write_text('[Desktop Entry]\nName=Test\nExec=touch /tmp/should-never-run\n')
            with patch.object(ui, 'desktop_path', return_value=desktop), patch.object(ui, 'run', return_value=subprocess.CompletedProcess([], 0, 'test-package\n', '')) as run:
                result = ui.resolve('test')
        self.assertEqual(result['target'], 'test-package')
        self.assertEqual(run.call_args.args[0][:3], ['/usr/bin/pacman', '-Qqo', '--'])


if __name__ == '__main__':
    unittest.main()
