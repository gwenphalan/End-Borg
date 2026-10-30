pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
ColumnLayout {
    id:root
    required property var entity
    property bool editing:false
    readonly property string domain:HomeAssistant.domain(entity)
    readonly property bool isOn:["on","playing","open","heat","cool"].includes(entity.state)
    readonly property bool usable:HomeAssistant.available(entity) && !HomeAssistant.busy[entity.entity_id]
    readonly property bool toggle:["light","switch","input_boolean","fan","automation","humidifier"].includes(domain)
    signal openDevice(string entityId)
    spacing:0
    opacity:Config.options.homeAssistant.hiddenEntities.includes(entity.entity_id) ? 0.45 : HomeAssistant.available(entity) ? 1 : 0.6
    RippleButton {
        Layout.fillWidth:true;implicitHeight:72;padding:12
        buttonRadius:Appearance.rounding.normal
        colBackground:"transparent";colBackgroundHover:Appearance.colors.colLayer2Hover
        Accessible.name:HomeAssistant.name(root.entity)+", "+HomeAssistant.status(root.entity)
        onClicked:root.openDevice(root.entity.entity_id)
        contentItem:RowLayout {
            spacing:12
            Rectangle {
                implicitWidth:40;implicitHeight:40;radius:20
                color:root.isOn ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                MaterialSymbol { anchors.centerIn:parent;text:HomeAssistant.icon(root.entity);iconSize:22;color:root.isOn ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext }
                Behavior on color { animation:Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
            ColumnLayout {
                Layout.fillWidth:true;spacing:3
                StyledText { Layout.fillWidth:true;text:HomeAssistant.name(root.entity);font.weight:Font.Medium;textFormat:Text.PlainText;elide:Text.ElideRight }
                StyledText { Layout.fillWidth:true;text:HomeAssistant.busy[root.entity.entity_id] ? Translation.tr("Updating…") : root.domain==="media_player" && root.entity.attributes.media_title ? root.entity.attributes.media_title : HomeAssistant.status(root.entity);textFormat:Text.PlainText;elide:Text.ElideRight;color:Appearance.colors.colSubtext;font.pixelSize:Appearance.font.pixelSize.smaller }
            }
            StyledSwitch { visible:root.toggle && !root.editing;checked:root.entity.state==="on";enabled:root.usable;Accessible.name:HomeAssistant.name(root.entity);onClicked:HomeAssistant.activate(root.entity) }
            HomeAction { visible:!root.toggle && HomeAssistant.canActivate(root.entity) && !root.editing;symbol:root.entity.state==="playing" ? "pause" : "play_arrow";label:Translation.tr("Run");enabled:root.usable;onClicked:HomeAssistant.activate(root.entity) }
            MaterialSymbol { text:"chevron_right";iconSize:18;color:Appearance.colors.colSubtext }
        }
    }
    CommittedSlider {
        Layout.fillWidth:true;Layout.leftMargin:64;Layout.rightMargin:16;Layout.bottomMargin:8
        visible:root.domain==="light" && root.entity.state==="on" && root.entity.attributes.brightness!==undefined && !root.editing
        enabled:root.usable;value:(root.entity.attributes.brightness || 0)/255
        Accessible.name:HomeAssistant.name(root.entity)+" "+Translation.tr("Brightness")
        onCommitted:value => HomeAssistant.callService(root.entity,value===0 ? "turn_off" : "turn_on",value===0 ? {} : {brightness_pct:Math.round(value*100)})
    }
    RowLayout {
        visible:root.editing;Layout.leftMargin:56;Layout.bottomMargin:8
        HomeAction { symbol:Config.options.homeAssistant.hiddenEntities.includes(root.entity.entity_id) ? "visibility_off" : "visibility";label:Translation.tr("Show / hide");onClicked:HomeAssistant.changeList("hiddenEntities",root.entity.entity_id) }
        HomeAction { symbol:"star";label:Translation.tr("Favorite");accent:Config.options.homeAssistant.favoriteEntities.includes(root.entity.entity_id);onClicked:HomeAssistant.changeList("favoriteEntities",root.entity.entity_id) }
        HomeAction { symbol:"keep";label:Translation.tr("Quick control");accent:Config.options.homeAssistant.quickToggleEntities.includes(root.entity.entity_id);enabled:HomeAssistant.canActivate(root.entity);onClicked:HomeAssistant.changeList("quickToggleEntities",root.entity.entity_id) }
        HomeAction { symbol:"toolbar";label:Translation.tr("Top bar control");accent:Config.options.homeAssistant.barControlEntities.includes(root.entity.entity_id);enabled:HomeAssistant.canActivate(root.entity);onClicked:HomeAssistant.changeList("barControlEntities",root.entity.entity_id) }
    }
}
