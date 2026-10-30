pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Popup {
    id: root
    property color initialColor: Appearance.colors.colPrimary
    signal chosen(string value)
    parent: Overlay.overlay
    width: Math.min(360, parent ? parent.width - 32 : 360)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    modal: true
    focus: true
    padding: 20
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    enter: OverlayTransition {}
    exit: OverlayTransition { entering: false }
    Overlay.modal: Rectangle { color: Appearance.colors.colScrim }
    background: Rectangle {
        color: Appearance.m3colors.m3surfaceContainerHigh
        radius: Appearance.rounding.normal
    }
    onOpened: picker.reset(initialColor)
    contentItem: ColumnLayout {
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Custom accent color")
                font.pixelSize: Appearance.font.pixelSize.large
            }
            IconToolbarButton {
                text: "close"
                Accessible.name: Translation.tr("Close color picker")
                onClicked: root.close()
            }
        }
        ColorPicker {
            id: picker
            Layout.fillWidth: true
            title: ""
            showHexInput: false
            spectrumHeight: 260
            onChosen: {
                root.chosen(picker.hex);
                root.close();
            }
            onCancelled: root.close()
        }
    }
}
