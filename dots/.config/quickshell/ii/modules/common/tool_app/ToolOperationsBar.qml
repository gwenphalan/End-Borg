import QtQuick
import QtQuick.Layouts

// Two reserved rows keep document operations/settings outside canvas tool pills.
Item {
    id:root
    objectName:"toolOperationsBar"
    default property alias leftContent:leftControls.data
    property alias rightContent:rightControls.data
    property alias secondLeft:secondLeftControls.data
    property alias secondRight:secondRightControls.data
    // A host-supplied grid can span both rows without duplicating chrome.
    // Supplying it replaces the legacy row presentation, not its public API.
    property alias customContent:customControls.data
    property real rowHeight:40
    property real rowSpacing:8
    readonly property bool hasCustomContent:customControls.children.length>0
    readonly property bool hasControls:hasCustomContent || leftControls.children.length>0 || rightControls.children.length>0 || secondLeftControls.children.length>0 || secondRightControls.children.length>0
    Layout.fillWidth:true
    Layout.leftMargin:12
    Layout.rightMargin:12
    Layout.topMargin:0
    Layout.bottomMargin:4
    Layout.preferredHeight:implicitHeight
    Layout.maximumHeight:implicitHeight
    Layout.fillHeight:false
    implicitHeight:hasCustomContent ? customControls.implicitHeight : rowHeight*2+rowSpacing
    implicitWidth:hasCustomContent ? customControls.implicitWidth : Math.max(firstRow.implicitWidth,secondRow.implicitWidth)
    property Item hoverGroup:ToolHoverGroup {parent:root;container:root}
    property Item contents:ColumnLayout {
        parent:root
        z:1
        anchors.fill:parent
        visible:!root.hasCustomContent
        spacing:root.rowSpacing
        RowLayout {
            id:firstRow
            Layout.fillWidth:true
            Layout.preferredHeight:root.rowHeight
            Layout.minimumHeight:root.rowHeight
            Layout.maximumHeight:root.rowHeight
            spacing:8
            RowLayout {id:leftControls;spacing:4;visible:children.length>0}
            Item {Layout.fillWidth:true}
            RowLayout {id:rightControls;spacing:4;visible:children.length>0}
        }
        RowLayout {
            id:secondRow
            Layout.fillWidth:true
            Layout.preferredHeight:root.rowHeight
            Layout.minimumHeight:root.rowHeight
            Layout.maximumHeight:root.rowHeight
            spacing:8
            RowLayout {id:secondLeftControls;spacing:4;visible:children.length>0}
            Item {Layout.fillWidth:true}
            RowLayout {id:secondRightControls;spacing:4;visible:children.length>0}
        }
    }
    property Item customContents:ColumnLayout {
        id:customControls
        parent:root
        z:1
        anchors.fill:parent
        spacing:0
        visible:root.hasCustomContent
    }
}
