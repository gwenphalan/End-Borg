pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: root
    readonly property var entries: HomeAssistant.quickControls
    implicitHeight: content.implicitHeight + 16
    Behavior on implicitHeight { animation:Appearance.animation.elementResize.numberAnimation.createObject(this) }
    color: Appearance.colors.colLayer1; radius: Appearance.rounding.normal
    ColumnLayout {
        id: content
        anchors { left:parent.left; right:parent.right; top:parent.top; margins:8 }
        spacing: 4
        RowLayout {
            MaterialSymbol { text:"home"; iconSize:18; color:Appearance.colors.colPrimary }
            StyledText { Layout.fillWidth:true; text:Translation.tr("Home"); font.weight:Font.Medium }
            HomeAction { implicitHeight:28; symbol:"arrow_forward"; label:Translation.tr("Open Home controls"); onClicked:{ Persistent.states.sidebar.bottomGroup.tab = 0; Persistent.states.sidebar.bottomGroup.collapsed = false; GlobalStates.sidebarRightOpen = true; } }
        }
        RippleButton {
            visible: root.entries.length === 0
            Layout.fillWidth: true; implicitHeight: 36; buttonRadius: Appearance.rounding.full
            buttonText: HomeAssistant.connected ? Translation.tr("Choose quick controls in Home") : Translation.tr("Connect Home Assistant")
            onClicked: {
                if (!HomeAssistant.connected) HomeAssistant.openSettings();
                else { Persistent.states.sidebar.bottomGroup.tab = 0; Persistent.states.sidebar.bottomGroup.collapsed = false; GlobalStates.sidebarRightOpen = true; }
            }
        }
        Flow {
            Layout.fillWidth:true; Layout.preferredHeight:childrenRect.height; spacing:4
            Repeater {
                model:ScriptModel { values:root.entries; objectProp:"entity_id" }
                delegate:RippleButton {
                    required property var modelData
                    implicitWidth:Math.min(150,Math.max(90,toggleContent.implicitWidth+20)); implicitHeight:36
                    buttonRadius:Appearance.rounding.full
                    enabled:HomeAssistant.available(modelData) && !HomeAssistant.busy[modelData.entity_id]
                    toggled:["on","playing"].includes(modelData.state)
                    colBackground:Appearance.colors.colLayer2
                    colBackgroundHover:Appearance.colors.colLayer2Hover
                    colRipple:Appearance.colors.colLayer2Active
                    colBackgroundToggled:Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover:Appearance.colors.colSecondaryContainerHover
                    colRippleToggled:Appearance.colors.colSecondaryContainerActive
                    onClicked:HomeAssistant.activate(modelData)
                    contentItem:RowLayout {
                        id:toggleContent; spacing:6
                        MaterialSymbol { text:HomeAssistant.icon(parent.parent.modelData); iconSize:18; color:parent.parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2 }
                        StyledText { Layout.fillWidth:true; text:HomeAssistant.name(parent.parent.modelData); textFormat:Text.PlainText; color:parent.parent.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2; elide:Text.ElideRight; font.pixelSize:Appearance.font.pixelSize.small }
                    }
                    StyledToolTip { text:HomeAssistant.status(parent.modelData) }
                }
            }
        }
    }
}
