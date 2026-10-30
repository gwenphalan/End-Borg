pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Item {
    id:root
    property string style:"cookie"
    property color foreground:Appearance.colors.colOnLayer2
    implicitWidth:28
    implicitHeight:28
    MaterialSymbol {
        anchors.centerIn:parent
        text:root.style==="digital" ? "watch" : "cookie"
        iconSize:24
        color:root.foreground
        Accessible.ignored:true
    }
}
