pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import qs.modules.common

// Compact input beside an existing external label; no duplicated floating label.
T.TextField {
    id:root
    property bool invalid:false
    implicitWidth:240
    implicitHeight:40
    leftPadding:12
    rightPadding:12
    topPadding:8
    bottomPadding:8
    verticalAlignment:TextInput.AlignVCenter
    selectByMouse:true
    clip:true
    wrapMode:TextInput.NoWrap
    color:Appearance.colors.colOnLayer2
    selectionColor:Appearance.colors.colSecondaryContainer
    selectedTextColor:Appearance.colors.colOnSecondaryContainer
    placeholderTextColor:Appearance.colors.colSubtext
    font.family:Appearance.font.family.main
    font.pixelSize:Appearance.font.pixelSize.small
    font.variableAxes:Appearance.font.variableAxes.main
    opacity:enabled ? 1 : .5
    Accessible.role:Accessible.EditableText
    background:Rectangle {
        implicitWidth:240
        implicitHeight:40
        radius:Appearance.rounding.small
        color:Appearance.colors.colLayer3
        border.width:root.activeFocus || root.invalid ? 2 : 0
        border.color:root.invalid ? Appearance.colors.colError : Appearance.m3colors.m3secondary
    }
    StyledText {
        anchors.fill:parent
        anchors.leftMargin:root.leftPadding
        anchors.rightMargin:root.rightPadding
        visible:!root.text && !root.preeditText
        text:root.placeholderText
        font:root.font
        color:root.placeholderTextColor
        verticalAlignment:Text.AlignVCenter
        elide:Text.ElideRight
        Accessible.ignored:true
    }
    Component.onCompleted:cursorPosition=0
    onActiveFocusChanged:if (!activeFocus) cursorPosition=0
    onTextChanged:if (!activeFocus) Qt.callLater(() => { if (root && !root.activeFocus) root.cursorPosition=0; })
    MouseArea { anchors.fill:parent; acceptedButtons:Qt.NoButton; cursorShape:Qt.IBeamCursor }
}
