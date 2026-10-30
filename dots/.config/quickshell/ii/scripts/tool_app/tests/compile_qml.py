"""Compile tool_app QML with Quickshell offscreen. Creates no Window objects.

The only instantiated object is ShellRoot. UI component definitions are compiled,
never created. Temporary import links are isolated from the running desktop.
"""
from pathlib import Path
import argparse
import json
import os
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[3]
NAMES=['ToolIconButton','ToolHoverGroup','ToolTopBar','ToolOperationsBar','ToolApp','ToolBarButton','ToolStartupDialog','ToolCanvasFooter','ToolPointCoordinates','ToolOperationFeedback','ToolSaveButton','ToolActionLabel','ToolActionController','ToolActionButton','ToolActionStrip','ToolActionBar','ToolActionPill','ToolBackendProcess','ToolConfiguredApp','ToolDefinitionLoader','ToolSettingsStore','ToolSettingsForm','ToolProjectSettingsDialog','ToolProfilePicker','ToolShortcutHints','ToolToast']


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform",choices=("offscreen","wayland"),default="offscreen")
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tool-app-compile-') as directory:
        folder=Path(directory)
        for name in ('modules','services','GlobalStates.qml'):
            if (ROOT/name).exists():(folder/name).symlink_to(ROOT/name)
        paths=[str(ROOT/'modules/common/tool_app'/f'{name}.qml') for name in NAMES]
        paths.append(str(ROOT/'modules/lensCalibration/CalibrationWorkspace.qml'))
        source='''import QtQuick
import Quickshell
import qs.modules.common.tool_app
ShellRoot {
    Component.onCompleted: {
        Quickshell.watchFiles=false;
        Qt.callLater(checkComponents);
    }
    function checkComponents() {
        let failures=0;
        for (const path of PATHS) {
            const component=Qt.createComponent("file://"+path,Component.PreferSynchronous);
            if(component.status!==Component.Ready) {console.error("COMPILE FAIL",path,component.errorString());failures++;}
        }
        console.log("TOOL COMPILE RESULT",failures);
        Qt.callLater(Qt.quit);
    }
}
'''.replace('PATHS',json.dumps(paths))
        (folder/'shell.qml').write_text(source)
        runtime=folder/'runtime';runtime.mkdir(mode=0o700)
        env=dict(os.environ,QT_QPA_PLATFORM=args.platform,QS_NO_RELOAD_POPUP='1')
        if args.platform=='offscreen':env.update(XDG_RUNTIME_DIR=str(runtime),DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent')
        try:
            result=subprocess.run(['qs','-p',str(folder/'shell.qml'),'--no-color'],env=env,capture_output=True,text=True,timeout=45)
        except subprocess.TimeoutExpired as error:
            for output in (error.stdout,error.stderr):
                if output:print(output.decode(errors='replace') if isinstance(output,bytes) else output)
            print('COMPILE TIMEOUT: no Window objects were instantiated')
            return 1
        output=result.stdout+result.stderr
        print(output)
        return 0 if 'TOOL COMPILE RESULT 0' in output else 1

if __name__=='__main__':raise SystemExit(main())
