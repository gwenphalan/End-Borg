import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledText {
    id: root
    property bool active: false
    property real pixelX: 0
    property real pixelY: 0
    property real reservedWidth:128
    text: active ? "x: "+Math.floor(pixelX)+"  y: "+Math.floor(pixelY) : "x: —  y: —"
    Layout.minimumWidth: reservedWidth>0 ? reservedWidth : implicitWidth
    Layout.preferredWidth: reservedWidth>0 ? reservedWidth : implicitWidth
    Layout.maximumWidth: reservedWidth>0 ? reservedWidth : implicitWidth
    elide: Text.ElideRight
    color: Appearance.colors.colOnSurfaceVariant
    font.family: Appearance.font.family.numbers
    font.pixelSize: Appearance.font.pixelSize.small
    Accessible.name: "Cursor position: "+text
    HoverHandler {id:hover}
    StyledToolTip {text:"Cursor position · displayed image pixels";visible:hover.hovered}
}
