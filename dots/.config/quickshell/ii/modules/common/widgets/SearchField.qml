pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic
import qs.services
import qs.modules.common

// One stable search control for sidebar and picker searches. Basic supplies the
// native TextField editing/context-menu API and exactly one resting placeholder.
Basic.TextField {
    id: root
    property bool showClearButton: true
    implicitWidth: 240
    implicitHeight: 48
    leftPadding: 14
    rightPadding: showClearButton && text.length ? 40 : 14
    topPadding: 8
    bottomPadding: 8
    verticalAlignment: TextInput.AlignVCenter
    wrapMode: TextInput.NoWrap
    selectByMouse: true
    clip: true
    renderType: Text.QtRendering
    color: Appearance.colors.colOnLayer2
    placeholderTextColor: Appearance.colors.colSubtext
    selectionColor: Appearance.colors.colSecondaryContainer
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    opacity: enabled ? 1 : 0.5
    Accessible.name: placeholderText
    Accessible.searchEdit: true

    background: Rectangle {
        implicitWidth: 240
        implicitHeight: 48
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Appearance.m3colors.m3secondary : Appearance.colors.colLayer0Border
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    IconToolbarButton {
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 36
        implicitWidth: 36
        implicitHeight: 36
        visible: root.showClearButton && root.text.length > 0
        text: "close"
        Accessible.name: Translation.tr("Clear search")
        onClicked: {
            root.clear();
            root.forceActiveFocus();
        }
    }
}
