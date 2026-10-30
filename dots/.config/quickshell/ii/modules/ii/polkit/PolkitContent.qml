import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    readonly property bool usePasswordChars: !(PolkitService.flow?.responseVisible ?? false)

    Keys.onPressed: event => { // Esc to close
        if (event.key === Qt.Key_Escape) {
            PolkitService.cancel();
        }
    }

    function submit() {
        if (PolkitService.interactionAvailable) PolkitService.submit(inputField.text);
    }
    Connections {
        target: PolkitService
        function onInteractionAvailableChanged() {
            if (!PolkitService.interactionAvailable) return;
            inputField.text = "";
            inputField.forceActiveFocus();
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0
        Component.onCompleted: {
            opacity = 1
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Rectangle {
        id: dialog
        anchors.centerIn: parent
        width: Math.min(450, root.width - 48)
        height: dialogContents.implicitHeight + 48
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh

        ColumnLayout {
            id: dialogContents
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 24 }
            spacing: 16

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 26
                text: "security"
                color: Appearance.colors.colSecondary
            }

            WindowDialogTitle {
                id: titleText
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Authentication")
            }

            WindowDialogParagraph {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignLeft
                text: PolkitService.cleanMessage
            }

            MaterialTextField {
                id: inputField
                Layout.fillWidth: true
                focus: true
                enabled: PolkitService.interactionAvailable
                labelBackgroundColor: dialog.color
                placeholderText: PolkitService.cleanPrompt
                Component.onCompleted: Qt.callLater(() => forceActiveFocus())
                echoMode: root.usePasswordChars ? TextInput.Password : TextInput.Normal
                onAccepted: root.submit();

                Keys.onPressed: event => { // Esc to close
                    if (event.key === Qt.Key_Escape) {
                        PolkitService.cancel();
                    }
                }
            }

            WindowDialogButtonRow {
                Layout.margins: 0
                spacing: 8
                Item {
                    Layout.fillWidth: true
                }
                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: PolkitService.cancel();
                }
                DialogButton {
                    enabled: PolkitService.interactionAvailable
                    buttonText: Translation.tr("Authenticate")
                    colBackground: Appearance.m3colors.m3primary
                    colText: Appearance.m3colors.m3onPrimary
                    onClicked: root.submit();
                }
            }
        }
    }
}
