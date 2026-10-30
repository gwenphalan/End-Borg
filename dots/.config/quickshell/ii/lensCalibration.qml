//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import Quickshell
import qs.modules.common.tool_app
import qs.modules.lensCalibration

ShellRoot {
    property alias appWindow: appLoader.item
    // Keep this entry cheap when the desktop discovers root QML types.
    // The tool is a separate process; desktop reloads must not rebuild its work.
    LazyLoader {
        id: appLoader
        objectName: "lensCapLoader"
        active: false
        source: Qt.resolvedUrl("apps/lensCap/LensCapWindow.qml")
    }
    Component.onCompleted: {
        Quickshell.watchFiles = false;
        appLoader.active = true;
    }
}
