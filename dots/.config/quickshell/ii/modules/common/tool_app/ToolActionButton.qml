import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id:root
    required property string actionId
    required property var controller
    property bool labeled:false
    property real buttonSize:40
    readonly property var actionDefinition:(controller && controller.definition && controller.definition.actions || {})[actionId] || ({})
    visible:controller.visibleFor(actionId)
    enabled:controller.enabledFor(actionId)
    toggled:controller.checkedFor(actionId)
    implicitHeight:buttonSize
    implicitWidth:labeled ? content.implicitWidth+24 : buttonSize
    Layout.fillWidth:false
    Layout.fillHeight:false
    buttonRadius:height/2
    opacity:enabled ? 1 : 0.4
    Accessible.name:actionDefinition.label || actionId
    Accessible.checked:toggled
    background:Rectangle {
        color:"transparent"
        radius:root.height/2
        border.width:root.enabled && root.visualFocus ? 2 : 0
        border.color:Appearance.colors.colPrimary
    }
    contentItem:RowLayout {
        id:content
        spacing:8
        MaterialSymbol {
            Layout.alignment:Qt.AlignVCenter
            text:root.actionDefinition.icon || ""
            iconSize:root.labeled ? 18 : 22
            color:root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
        }
        ToolActionLabel {
            visible:root.labeled
            label:root.actionDefinition.label || ""
            dirty:root.controller.dirtyFor(root.actionId)
            reserveDirtySpace:root.actionDefinition.dirtyWhen !== undefined && root.actionDefinition.dirtyWhen !== false
            color:root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            font.pixelSize:root.labeled ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
        }
    }
    onClicked:controller.invoke(actionId)
    StyledToolTip {text:root.actionDefinition.tooltip || ((root.actionDefinition.label || root.actionId)+(root.actionDefinition.shortcut ? " · "+root.actionDefinition.shortcut : ""))}
}
