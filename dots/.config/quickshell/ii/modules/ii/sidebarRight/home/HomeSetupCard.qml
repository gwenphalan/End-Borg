pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    implicitHeight: content.implicitHeight + 36
    ColumnLayout {
        id: content
        anchors { left:parent.left; right:parent.right; top:parent.top; margins:18 }
        spacing: 14
        Rectangle {
            implicitWidth:52; implicitHeight:52; radius:Appearance.rounding.normal
            color:Appearance.colors.colSecondaryContainer
            MaterialSymbol { anchors.centerIn:parent; text:"home"; fill:1; iconSize:Appearance.font.pixelSize.huge; color:Appearance.colors.colOnSecondaryContainer }
        }
        ColumnLayout {
            Layout.fillWidth:true; spacing:8
            StyledText {
                Layout.fillWidth:true; wrapMode:Text.Wrap
                text: HomeAssistant.settings.enabled && HomeAssistant.configured ? Translation.tr("Home Assistant is offline") : Translation.tr("Connect Home Assistant")
                font.pixelSize:Appearance.font.pixelSize.larger; font.weight:Font.Medium
                color:Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth:true; wrapMode:Text.Wrap
                text:HomeAssistant.settings.enabled && HomeAssistant.configured ? (HomeAssistant.error || Translation.tr("Waiting for Home Assistant. Your controls will return when the connection is restored.")) : Translation.tr("Add your server and access token in Home settings to control your devices.")
                font.pixelSize:Appearance.font.pixelSize.small
                color:Appearance.colors.colSubtext
                lineHeight:1.2
            }
        }
        RippleButtonWithIcon {
            Layout.fillWidth:true
            implicitHeight:42
            materialIcon:"settings"
            mainText:HomeAssistant.configured ? Translation.tr("Connection settings") : Translation.tr("Set up Home Assistant")
            onClicked:HomeAssistant.openSettings()
        }
        DialogButton {
            visible:HomeAssistant.settings.enabled && HomeAssistant.configured
            Layout.fillWidth:true; implicitHeight:36
            buttonText:Translation.tr("Try again")
            onClicked:HomeAssistant.reconnect()
        }
    }
}
