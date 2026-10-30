import QtQuick
import QtQuick.Layouts
import qs.modules.common

Item {
    Layout.fillWidth:true
    Layout.fillHeight:true
    clip:true
    Rectangle {
        anchors.fill:parent
        anchors.margins:6
        color:Appearance.colors.colLayer1
        radius:Appearance.rounding.normal
    }
}
