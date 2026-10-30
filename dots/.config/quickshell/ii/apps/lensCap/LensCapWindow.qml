//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.tool_app
import qs.modules.lensCalibration

ToolAppWindow {
    id:window
    appTitle:"Lens Cap"
    closeHandler:() => workspace.requestClose()
    CalibrationWorkspace {
        id:workspace
        anchors.fill:parent
        objectName:"lensWorkspace"
        function syncStartup() {
            if(hasImage || picking || busy || pendingLegacyPath) startup.close();
            else startup.open();
        }
        onPendingLegacyPathChanged:Qt.callLater(syncStartup)
        onPickingChanged:Qt.callLater(syncStartup)
        onBusyChanged:Qt.callLater(syncStartup)
        onHasImageChanged:syncStartup()

    }
    ToolStartupDialog {
        id:startup
        objectName:"startupChooser"
        appName:"Lens Cap"
        iconName:"camera"
        recentFiles:workspace.recentProjects
        onRecentFileRequested:path=>workspace.file("load",path)
        actionsEnabled:workspace.ready && !workspace.busy && !workspace.picking
        statusText:workspace.busy ? "Opening…" : workspace.message
        failed:workspace.error
        Component.onCompleted:open()
        DialogButton {buttonText:"Open project";onClicked:workspace.file("load")}
        DialogButton {buttonText:"New image";onClicked:workspace.file("open")}
    }
}
