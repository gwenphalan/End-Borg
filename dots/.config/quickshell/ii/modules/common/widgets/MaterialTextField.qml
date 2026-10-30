pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import qs.modules.common
import qs.modules.common.widgets

// Explicit Material outline geometry keeps search/password fields independent
// of the application's Qt Quick Controls style. The label has its own 8 px inset
// above the 48 px body; input text and the resting hint share that body's center.
T.TextField {
    id: root

    readonly property bool floatingLabel: placeholderText.length > 0 && (activeFocus || text.length > 0
                                                                         || preeditText.length > 0)
    readonly property color outlineColor: activeFocus ? Appearance.m3colors.m3secondary :
                                                        Appearance.m3colors.m3outline
    property color labelBackgroundColor: fieldColor
    readonly property color fieldColor: Appearance.colors.colLayer3

    implicitWidth: 240
    implicitHeight: 56
    leftPadding: 16
    rightPadding: 16
    topPadding: 8
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    renderType: Text.QtRendering
    wrapMode: TextInput.NoWrap
    selectByMouse: true
    clip: true
    opacity: enabled ? 1 : 0.5

    color: Appearance.m3colors.m3onSurface
    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.m3colors.m3secondaryContainer
    placeholderTextColor: Appearance.m3colors.m3onSurfaceVariant
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.small
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }

    Accessible.role: Accessible.EditableText
    Accessible.name: placeholderText

    background: Rectangle {
        x: 0
        y: 8
        width: root.width
        height: Math.max(0, root.height - 8)
        implicitWidth: 240
        implicitHeight: 48
        radius: Appearance.rounding.small
        color: root.fieldColor
        border.width: root.activeFocus ? 2 : 1
        border.color: root.outlineColor
    }

    StyledText {
        x: root.leftPadding
        y: 8
        width: Math.max(0, root.width - root.leftPadding - root.rightPadding)
        height: Math.max(0, root.height - 8)
        visible: !root.floatingLabel && !root.text && !root.preeditText
        text: root.placeholderText
        font: root.font
        color: root.placeholderTextColor
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        Accessible.ignored: true
    }

    Rectangle {
        x: root.leftPadding - 4
        y: 0
        width: Math.min(label.implicitWidth + 8, Math.max(0, root.width - root.leftPadding - root.rightPadding
                                                          + 8))
        height: 16
        visible: root.floatingLabel
        color: root.labelBackgroundColor
        z: 2

        StyledText {
            id: label
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            text: root.placeholderText
            font.family: root.font.family
            font.variableAxes: root.font.variableAxes
            font.pixelSize: 12
            color: root.activeFocus ? root.outlineColor : root.placeholderTextColor
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            Accessible.ignored: true
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
    }
}
