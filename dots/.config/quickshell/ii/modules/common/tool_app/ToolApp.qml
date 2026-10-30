import QtQuick
import QtQuick.Layouts

Item {
    id:root
    default property alias canvasContent:canvasContents.data
    property alias toolbar:topBar.buttons
    property alias operationsLeft:operationsBar.leftContent
    property alias operationsRight:operationsBar.rightContent
    property alias operationsSecondLeft:operationsBar.secondLeft
    property alias operationsSecondRight:operationsBar.secondRight
    property alias operationsContent:operationsBar.customContent
    property bool operationsEnabled:controlsEnabled
    property alias tools:toolsPill.buttons
    property alias utilities:utilitiesPill.buttons
    property alias contextActions:contextPill.buttons
    property alias status:statusBar.data
    property alias canvasArea:canvasSurface
    property bool controlsEnabled:true
    property bool toolbarEnabled:controlsEnabled
    property bool toolsEnabled:controlsEnabled
    property bool utilitiesEnabled:controlsEnabled
    property bool contextActionsEnabled:controlsEnabled
    property bool contextActionsVisible:true
    property bool utilitiesTopRight:false
    property bool contextBelowTools:false
    property real pillMargin:18

    property Item chromeLayout:ColumnLayout {
        parent:root
        anchors.fill:parent
        spacing:0
        ToolTopBar {
            id:topBar
            enabled:root.toolbarEnabled
            visible:contentLayout.children.length>0
        }
        ToolOperationsBar {
            id:operationsBar
            enabled:root.operationsEnabled
            visible:hasControls
        }
        ToolCanvasArea {
            id:canvasSurface
            Item {id:canvasContents;anchors.fill:parent}
            ToolPill {
                id:toolsPill
                anchors.left:parent.left;anchors.leftMargin:root.pillMargin
                anchors.top:parent.top;anchors.topMargin:root.pillMargin
                enabled:root.toolsEnabled
                visible:contentLayout.children.length>0
            }
            ToolPill {
                id:contextPill
                orientation:Qt.Horizontal
                anchors.right:root.contextBelowTools ? undefined : parent.right
                anchors.rightMargin:root.pillMargin+(root.utilitiesTopRight && utilitiesPill.visible ? utilitiesPill.width+12 : 0)
                anchors.left:root.contextBelowTools ? parent.left : undefined
                anchors.leftMargin:root.pillMargin
                anchors.top:root.contextBelowTools ? toolsPill.bottom : parent.top
                anchors.topMargin:root.contextBelowTools ? 12 : root.pillMargin
                enabled:root.contextActionsEnabled
                visible:root.contextActionsVisible && contentLayout.children.length>0
            }
            ToolPill {
                id:utilitiesPill
                buttonSize:32
                anchors.left:root.utilitiesTopRight ? undefined : parent.left
                anchors.leftMargin:root.pillMargin
                anchors.right:root.utilitiesTopRight ? parent.right : undefined
                anchors.rightMargin:root.pillMargin
                anchors.top:root.utilitiesTopRight ? parent.top : undefined
                anchors.topMargin:root.pillMargin
                anchors.bottom:root.utilitiesTopRight ? undefined : parent.bottom
                anchors.bottomMargin:root.pillMargin
                enabled:root.utilitiesEnabled
                visible:contentLayout.children.length>0
            }
        }
        ToolStatusBar {
            id:statusBar
            visible:children.length>0
        }
    }
}
