import QtQuick
import QtQuick.Controls.Basic as Basic
import qs.modules.common

// Multiline editors use the same quiet tonal surface as other form controls.
// Basic preserves text editing, selection, wrapping and the native context menu
// without inheriting a Material underline or a second floating label.
Basic.TextArea {
    id: root
    implicitWidth: 240
    implicitHeight: Math.max(72, contentHeight + topPadding + bottomPadding)
    leftPadding: 14
    rightPadding: 14
    topPadding: 12
    bottomPadding: 12
    wrapMode: TextEdit.Wrap
    verticalAlignment: TextEdit.AlignTop
    selectByMouse: true
    clip: true
    renderType: Text.QtRendering
    color: Appearance.colors.colOnLayer2
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    placeholderTextColor: Appearance.colors.colSubtext
    opacity: enabled ? 1 : 0.5
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }

    background: Rectangle {
        implicitWidth: 240
        implicitHeight: 72
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer3
        border.width: root.activeFocus ? 2 : 0
        border.color: Appearance.m3colors.m3secondary
    }
}
