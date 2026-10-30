//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets

ShellRoot {
    id: root
    readonly property string mode: Quickshell.env("II_UNINSTALL_DIALOG_MODE") || "info"
    readonly property string title: Quickshell.env("II_UNINSTALL_DIALOG_TITLE") || "Uninstall application"
    readonly property string message: Quickshell.env("II_UNINSTALL_DIALOG_MESSAGE") || ""

    function finish(answer) {
        console.log("II_UNINSTALL_DIALOG_RESULT:" + answer);
        Qt.quit();
    }

    PanelWindow {
        id: window
        screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name)
            ?? Quickshell.screens[0]
        visible: true
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        WlrLayershell.namespace: "quickshell:uninstall-dialog"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore

        Item {
            id: dialogFocus
            anchors.fill: parent
            focus: true
            Component.onCompleted: Qt.callLater(() => forceActiveFocus())
            Keys.onEscapePressed: event => {
                root.finish("cancel");
                event.accepted = true;
            }
            Keys.onReturnPressed: event => {
                root.finish(root.mode === "question" ? "confirm" : "acknowledge");
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                root.finish(root.mode === "question" ? "confirm" : "acknowledge");
                event.accepted = true;
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colScrim
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.finish("cancel")
                }
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: Math.min(450, parent.width - 48)
                height: contents.implicitHeight + 48
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainerHigh
                MouseArea { anchors.fill: parent; onClicked: {} }

                ColumnLayout {
                    id: contents
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 24 }
                    spacing: 16

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        iconSize: 26
                        text: root.mode === "error" ? "error" : root.mode === "question" ? "delete" : "check_circle"
                        color: root.mode === "error" ? Appearance.colors.colError : Appearance.colors.colSecondary
                    }
                    WindowDialogTitle {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.title
                    }
                    WindowDialogParagraph {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignLeft
                        text: root.message
                        textFormat: Text.PlainText
                    }
                    WindowDialogButtonRow {
                        Layout.margins: 0
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        DialogButton {
                            visible: root.mode === "question"
                            buttonText: "Cancel"
                            onClicked: root.finish("cancel")
                        }
                        DialogButton {
                            buttonText: root.mode === "question" ? "Uninstall" : "OK"
                            colBackground: Appearance.m3colors.m3primary
                            colText: Appearance.m3colors.m3onPrimary
                            onClicked: root.finish(root.mode === "question" ? "confirm" : "acknowledge")
                        }
                    }
                }
            }
        }
    }
}
