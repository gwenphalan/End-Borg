import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Popup {
    id: root

    property string message: ""
    property bool failed: false
    property int duration: failed || actionText !== "" ? 7000 : 3500

    property string actionText: ""
    property bool actionEnabled: true
    signal actionTriggered()

    function show(text, isError, action) {
        actionText = action || "";
        message = text;
        failed = !!isError;
        if (!text)
            return ;

        open();
        expiry.restart();
    }

    parent: Overlay.overlay
    x: parent ? Math.max(16, (parent.width - width) / 2) : 16
    y: parent ? parent.height - height - 64 : 0
    width: Math.min(560, parent ? parent.width - 32 : 560)
    padding: 14
    z: 3000
    modal: false
    focus: false
    closePolicy: Popup.NoAutoClose

    Timer {
        id: expiry

        interval: root.duration
        onTriggered: root.close()
    }

    enter: OverlayTransition {
    }

    exit: OverlayTransition {
        entering: false
    }

    background: Rectangle {
        color: Appearance.m3colors.m3surfaceContainerHigh
        radius: Appearance.rounding.normal
    }

    contentItem: RowLayout {
        spacing: 12

        MaterialSymbol {
            text: root.failed ? "error" : "info"
            iconSize: 22
            color: root.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            text: root.message
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
        }

        DialogButton {
            visible: root.actionText !== ""
            enabled: root.actionEnabled
            buttonText: root.actionText
            onClicked: { root.close(); root.actionTriggered(); }
        }

        IconToolbarButton {
            implicitWidth: 28
            implicitHeight: 28
            Layout.fillHeight: false
            text: "close"
            Accessible.name: "Dismiss notification"
            onClicked: root.close()
        }

    }

}
