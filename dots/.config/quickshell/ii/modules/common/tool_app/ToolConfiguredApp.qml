import QtQuick
import QtQuick.Layouts
import QtQml.Models
import qs.modules.common.widgets
import "ToolDefinition.js" as Definition

Item {
    id:root
    required property var definition
    property var state:({})
    property var handlers:({})
    property bool controlsEnabled:true
    property bool shortcutsEnabled:true
    property real pillMargin:18
    property var settingsValues:({})
    default property alias canvasContent:canvasContents.data
    property alias status:statusBar.data
    property alias operationsLeft:operationsBar.leftContent
    property alias operationsRight:operationsBar.rightContent
    property alias operationsSecondLeft:operationsBar.secondLeft
    property alias operationsSecondRight:operationsBar.secondRight
    property alias operationsContent:operationsBar.customContent
    property bool operationsEnabled:controlsEnabled
    readonly property alias canvasArea:canvasSurface
    readonly property alias actionController:actionRouter
    readonly property alias settingsDialog:settingsDialog
    signal backendCompleted(string backend,string operation,var result)
    signal backendFailed(string backend,string operation,string message)
    signal settingsSubmitted(var values)
    signal actionFailed(string action,string message)
    function openSettings() {settingsDialog.open();}
    function backend(id) {
        for(let i=0;i<backendDelegates.count;i++) {const item=backendDelegates.objectAt(i);if(item && item.backendId===id) return item;}
        return null;
    }
    property QtObject router:ToolActionController {
        id:actionRouter
        definition:root.definition;state:root.state;handlers:root.handlers
        settingsValues:root.settingsValues
        enabled:root.controlsEnabled;shortcutsEnabled:root.shortcutsEnabled
        onFailed:(action,message)=>root.actionFailed(action,message)
        onBackendRequested:(id,operation,payload)=>{
            const target=root.backend(id);
            if(!target) {root.backendFailed(id,operation,"Backend not registered");return;}
            target.request(operation,payload);
        }
    }
    property Item transports:Item {
        parent:root
        visible:false
        Instantiator {
            id:backendDelegates
            model:Object.keys(root.definition.backends || {})
            ToolBackendProcess {
                required property string modelData
                readonly property string backendId:modelData
                command:root.definition.backends[modelData].command
                onCompleted:(operation,result)=>root.backendCompleted(backendId,operation,result)
                onFailed:(operation,message)=>root.backendFailed(backendId,operation,message)
            }
        }
        Repeater {
            model:Object.keys(root.definition.actions || {}).filter(id=>!!root.definition.actions[id].shortcut)
            Item {
                id:shortcutOwner
                required property string modelData
                Shortcut {
                    sequence:root.definition.actions[shortcutOwner.modelData].shortcut
                    enabled:root.shortcutsEnabled && !settingsDialog.opened && actionRouter.enabledFor(shortcutOwner.modelData)
                    onActivated:actionRouter.invokeShortcut(shortcutOwner.modelData)
                }
            }
        }
    }
    property Item chrome:ColumnLayout {
        parent:root
        anchors.fill:parent
        spacing:0
        ToolTopBar {
            ToolActionBar {
                controller:actionRouter
                groups:root.definition.toolbar || []
            }
        }
        ToolOperationsBar {
            id:operationsBar
            enabled:root.operationsEnabled
            visible:hasControls
        }
        ToolCanvasArea {
            id:canvasSurface
            Item {id:canvasContents;anchors.fill:parent}
            ToolActionPill {
                id:tools
                controller:actionRouter
                actions:root.definition.tools || []
                anchors.left:parent.left;anchors.top:parent.top;anchors.margins:root.pillMargin
            }
            ToolActionPill {
                controller:actionRouter
                actions:(root.definition.utilities || {}).actions || []
                buttonSize:32
                readonly property bool atTop:(root.definition.utilities || {}).placement!=="bottomLeft"
                anchors.left:atTop ? undefined : parent.left
                anchors.right:atTop ? parent.right : undefined
                anchors.top:atTop ? parent.top : undefined
                anchors.bottom:atTop ? undefined : parent.bottom
                anchors.margins:root.pillMargin
            }
            ToolActionPill {
                controller:actionRouter
                actions:(root.definition.contextActions || {}).actions || []
                orientation:Qt.Horizontal;buttonSize:32
                readonly property bool below:(root.definition.contextActions || {}).placement!=="topRight"
                anchors.left:below ? parent.left : undefined
                anchors.right:below ? undefined : parent.right
                anchors.top:below ? tools.bottom : parent.top
                anchors.leftMargin:root.pillMargin;anchors.rightMargin:root.pillMargin
                anchors.topMargin:below ? 12 : root.pillMargin
                visible:strip.visibleActionCount>0 && Definition.evaluate((root.definition.contextActions || {}).visibleWhen,actionRouter.effectiveState)
            }
        }
        ToolStatusBar {id:statusBar;visible:children.length>0}
    }
    property ToolProjectSettingsDialog projectSettings:ToolProjectSettingsDialog {
        id:settingsDialog
        definition:root.definition;controller:actionRouter;values:root.settingsValues
        onSubmitRequested:values=>root.settingsSubmitted(values)
    }
}
