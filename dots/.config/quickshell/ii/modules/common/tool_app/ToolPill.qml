import QtQuick
import QtQuick.Layouts
import qs.modules.common

Rectangle {
    id:root
    property real buttonSize:40
    property real contentPadding:8
    property int orientation:Qt.Vertical
    default property alias buttons:column.data
    implicitWidth:(orientation===Qt.Horizontal ? column.implicitWidth : buttonSize)+contentPadding*2
    implicitHeight:column.implicitHeight+contentPadding*2
    width:implicitWidth
    height:implicitHeight
    radius:Math.min(width,height)/2
    color:Appearance.colors.colLayer0Base
    z:2
    property Item hoverGroup:ToolHoverGroup {parent:root;container:root}
    property Item contentLayout:GridLayout {
        id:column
        parent:root
        z:1
        anchors.centerIn:parent
        columns:root.orientation===Qt.Horizontal ? Math.max(1,children.length) : 1
        rowSpacing:4
        columnSpacing:4
    }
}
