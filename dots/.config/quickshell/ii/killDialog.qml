//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

AppWindow {
    id:root
    appTitle:Translation.tr("Service conflicts")
    width:680; height:600
    minimumWidth:580; minimumHeight:450
    property int checkedGroups:0
    property int conflictCount:0
    readonly property var programs:[
        {names:["kded6"],title:"System tray service",description:"Another tray service is running. Stopping it lets the shell manage tray icons.",preference:"conflictKiller.autoKillTrays"},
        {names:["mako","dunst"],title:"Notification service",description:"Another notification daemon is running. Stopping it lets the shell receive notifications.",preference:"conflictKiller.autoKillNotificationDaemons"}
    ]
    StyledFlickable {
        anchors.fill:parent; anchors.margins:20
        clip:true
        contentHeight:content.implicitHeight+20
        ColumnLayout {
            id:content
            width:parent.width
            spacing:14
            RowLayout {
                MaterialSymbol { text:"notifications_active"; iconSize:36; color:Appearance.colors.colPrimary }
                ColumnLayout {
                    Layout.fillWidth:true; spacing:6
                    StyledText { text:Translation.tr("Choose which service to use"); font.pixelSize:Appearance.font.pixelSize.larger; font.weight:Font.Medium; wrapMode:Text.Wrap; Layout.fillWidth:true }
                    StyledText { Layout.fillWidth:true; text:Translation.tr("The shell provides its own tray and notification service. Resolve conflicts here, or keep your existing services running."); color:Appearance.colors.colSubtext; wrapMode:Text.Wrap }
                }
            }
            Repeater {
                id:groups
                model:root.programs
                delegate:Rectangle {
                    id:group
                    required property var modelData
                    property bool checked:false
                    property bool found:false
                    property string result:""
                    property bool always:false
                    property string error:""
                    onFoundChanged:root.conflictCount+=found ? 1 : -1
                    Layout.fillWidth:true
                    implicitHeight:groupContent.implicitHeight+28
                    color:Appearance.colors.colLayer1; radius:Appearance.rounding.normal
                    Behavior on implicitHeight { animation:Appearance.animation.elementResize.numberAnimation.createObject(this) }
                    Process {
                        id:probe
                        command:["pidof",...group.modelData.names]
                        running:true
                        onExited:(exitCode,exitStatus) => { group.found=exitCode===0; group.checked=true; root.checkedGroups++; if (exitCode>1) group.error=Translation.tr("Could not check this service. Try again."); }
                    }
                    Process {
                        id:stopProcess
                        command:["killall",...group.modelData.names]
                        onExited:(exitCode,exitStatus) => {
                            if (exitCode===0) {
                                group.result=Translation.tr("Stopped. The shell can now manage this service."); group.found=false; group.error="";
                                if (group.always) Config.setNestedValue(group.modelData.preference,true);
                            } else group.error=Translation.tr("Could not stop the service. It may have exited already, or require different permissions.");
                        }
                    }
                    ColumnLayout {
                        id:groupContent
                        anchors { left:parent.left; right:parent.right; top:parent.top; margins:14 }
                        spacing:10
                        StyledText { text:Translation.tr(group.modelData.title); font.weight:Font.Medium }
                        StyledText { Layout.fillWidth:true; text:group.error || (!group.checked ? Translation.tr("Checking…") : group.result || (group.found ? Translation.tr(group.modelData.description) : Translation.tr("No conflicting service found."))); color:group.error ? Appearance.colors.colError : Appearance.colors.colSubtext; wrapMode:Text.Wrap }
                        StyledText { visible:group.found; text:group.modelData.names.join(", "); font.family:Appearance.font.family.monospace; font.pixelSize:Appearance.font.pixelSize.smaller; color:Appearance.colors.colSubtext }
                        RowLayout {
                            visible:group.found
                            Layout.fillWidth:true
                            StyledSwitch { checked:group.always; onClicked:group.always=checked; enabled:!stopProcess.running; Accessible.name:Translation.tr("Resolve automatically next time") }
                            StyledText { Layout.fillWidth:true; text:Translation.tr("Resolve automatically next time"); wrapMode:Text.Wrap; color:Appearance.colors.colSubtext }
                        }
                        RowLayout {
                            visible:group.found || !!group.error
                            Layout.fillWidth:true
                            DialogButton { buttonText:Translation.tr("Keep running"); visible:group.found; enabled:!stopProcess.running; onClicked:{ group.result=Translation.tr("Kept running. Some shell features may be unavailable."); group.found=false; } }
                            Item { Layout.fillWidth:true }
                            DialogButton { visible:!!group.error; buttonText:Translation.tr("Check again"); onClicked:{ group.error=""; group.checked=false; root.checkedGroups--; probe.running=true; } }
                            RippleButtonWithIcon { visible:group.found; materialIcon:stopProcess.running ? "hourglass_top" : "stop_circle"; mainText:stopProcess.running ? Translation.tr("Stopping…") : Translation.tr("Stop service"); enabled:!stopProcess.running; onClicked:stopProcess.running=true }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth:true
                StyledText { Layout.fillWidth:true; text:root.checkedGroups<root.programs.length ? Translation.tr("Checking desktop services…") : root.conflictCount ? Translation.tr("%1 conflicts found").arg(root.conflictCount) : Translation.tr("No unresolved conflicts"); color:Appearance.colors.colSubtext }
                RippleButtonWithIcon { materialIcon:"check"; mainText:Translation.tr("Done"); onClicked:root.close() }
            }
        }
    }
}
