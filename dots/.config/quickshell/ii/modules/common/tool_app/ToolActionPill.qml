import QtQuick
import qs.modules.common

Rectangle {
    id:root
    required property var controller
    property var actions:[]
    property int orientation:Qt.Vertical
    property real buttonSize:40
    property real padding:8
    readonly property alias strip:strip
    implicitWidth:strip.implicitWidth+padding*2
    implicitHeight:strip.implicitHeight+padding*2
    width:implicitWidth;height:implicitHeight
    radius:Math.min(width,height)/2
    color:Appearance.colors.colLayer0Base
    visible:strip.visibleActionCount>0
    z:2
    ToolActionStrip {
        id:strip
        anchors.fill:parent;anchors.margins:root.padding
        controller:root.controller
        items:root.actions.map(id=>({action:id}))
        orientation:root.orientation
        buttonSize:root.buttonSize
    }
}
