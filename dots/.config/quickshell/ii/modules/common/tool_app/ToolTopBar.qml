import QtQuick
import QtQuick.Layouts
import qs.modules.common

Rectangle {
    id:root
    objectName:"toolTopBar"
    default property alias buttons:row.data
    readonly property alias contentLayout:row
    property real contentPadding:4
    Layout.fillWidth:true
    Layout.leftMargin:8
    Layout.rightMargin:8
    Layout.topMargin:8
    Layout.bottomMargin:8
    Layout.preferredHeight:32
    Layout.maximumHeight:32
    Layout.fillHeight:false
    implicitHeight:32
    implicitWidth:row.implicitWidth+contentPadding*2
    radius:height/2
    color:Appearance.colors.colLayer1
    property Item hoverGroup:ToolHoverGroup {parent:root;container:root}
    property Item rowContent:RowLayout {
        id:row
        parent:root
        z:1
        anchors.fill:parent
        anchors.leftMargin:root.contentPadding
        anchors.rightMargin:root.contentPadding
        spacing:4
    }
}
