import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(shutil.which("qs"), "Quickshell runtime is not installed")
class QmlServiceTests(unittest.TestCase):
    def probe(self, missing_python, delayed_exit=False):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            # Minimal dependency stubs isolate the real service from desktop state.
            common = root / "modules/common"
            functions = common / "functions"
            functions.mkdir(parents=True)
            (root / "services").mkdir()
            (root / "services/SteamGridDb.qml").symlink_to(ROOT / "services/SteamGridDb.qml")
            (common / "Config.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property bool ready: true
    property string lastError: ""
    property bool saving: false
    property var options: ({appearance:{steamGridDb:{enabled:false}}})
}''')
            (common / "Directories.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
    property string home: %s
    property string scriptPath: %s
}''' % (repr(str(root if missing_python else Path.home())), repr(str(root))))
            (functions / "FileUtils.qml").write_text('''pragma Singleton
import QtQuick
QtObject { function trimFileProtocol(value) { return value.replace("file://", ""); } }''')
            (root / "steamgriddb_icons.py").write_text('''import json, sys, time
json.loads(sys.stdin.read())
print(json.dumps({"ok":True,"result":{"credential":"missing","cached_icons":0}}), flush=True)
time.sleep(%s)
''' % (".01" if delayed_exit else "0"))
            (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property int completed: 0
    Connections {
        target: SteamGridDb
        function onFinished(operation, succeeded, result) {
            if (succeeded === %s || SteamGridDb.pendingInput || SteamGridDb.busy) {
                console.log("PROBE_FAIL", succeeded, SteamGridDb.pendingInput.length, SteamGridDb.busy, SteamGridDb.message);
                Qt.quit();
                return;
            }
            root.completed++;
            if (root.completed === %d) {
                console.log("PROBE_PASS");
                Qt.quit();
            } else if (!SteamGridDb.status()) {
                console.log("PROBE_FAIL_RESTART");
                Qt.quit();
            }
        }
    }
    Timer { interval:1; running:true; onTriggered: %s }
    Timer { interval:10000; running:true; onTriggered:{ console.log("PROBE_TIMEOUT"); Qt.quit(); } }
}''' % ("true" if missing_python else "false", 1 if missing_python else 20,
         'SteamGridDb.storeKey("test-only")' if missing_python else "SteamGridDb.status()"))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
            env.pop("QS_CONFIG_PATH", None)
            result = subprocess.run(["qs", "-p", str(root)], env=env,
                                    capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertIn("PROBE_PASS", output)
            self.assertNotIn("PROBE_FAIL", output)
            self.assertNotIn("PROBE_TIMEOUT", output)

    def test_fast_requests_complete_once_and_restart_safely(self):
        self.probe(False)

    def test_missing_python_releases_busy_and_clears_input(self):
        self.probe(True)
    def test_stdout_before_exit_completes_once_and_restarts_safely(self):
        self.probe(False, delayed_exit=True)


if __name__ == "__main__":
    unittest.main()
