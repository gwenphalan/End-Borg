pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Dialog {
    id: root
    property bool busy: false
    property string message: Translation.tr("Changes that are not saved will be lost.")
    signal discardRequested()
    signal saveRequested()
    parent: Overlay.overlay
    implicitWidth: 440
    width: Math.min(implicitWidth, parent ? parent.width - 32 : implicitWidth)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    z: 1000
    padding: 24
    modal: true
    focus: true
    title: Translation.tr("Save Changes?")
    enter: OverlayTransition {}
    exit: OverlayTransition { entering: false }
    Overlay.modal: Rectangle { color: Appearance.colors.colScrim }
    background: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerHigh
    }
    header: StyledText {
        text: root.title
        leftPadding: 24; rightPadding: 24; topPadding: 24
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.huge
        font.weight: Font.Bold
        wrapMode: Text.Wrap
    }
    contentItem: ColumnLayout {
        spacing: 24
        StyledText {
            Layout.fillWidth: true
            text: root.message
            font.family: "Noto Sans"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            DialogButton {
                Layout.minimumWidth: 96
                textFontFamily: "Noto Sans"
                implicitHeight: 44
                buttonText: Translation.tr("Cancel")
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colText: Appearance.colors.colOnLayer2
                onClicked: root.close()
            }
            Item { Layout.fillWidth: true }
            DialogButton {
                Layout.minimumWidth: 96
                textFontFamily: "Noto Sans"
                implicitHeight: 44
                enabled: !root.busy
                buttonText: Translation.tr("Discard")
                colBackground: ColorUtils.mix(Appearance.m3colors.m3surfaceContainerHigh, Appearance.colors.colError, 0.82)
                colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3surfaceContainerHigh, Appearance.colors.colError, 0.74)
                colRipple: Appearance.colors.colErrorContainerActive
                colEnabled: Appearance.colors.colError
                onClicked: root.discardRequested()
            }
            DialogButton {
                Layout.minimumWidth: 96
                textFontFamily: "Noto Sans"
                implicitHeight: 44
                enabled: !root.busy
                buttonText: Translation.tr("Save")
                colBackground: Appearance.m3colors.m3primary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colText: Appearance.m3colors.m3onPrimary
                onClicked: root.saveRequested()
            }
        }
    }
}
