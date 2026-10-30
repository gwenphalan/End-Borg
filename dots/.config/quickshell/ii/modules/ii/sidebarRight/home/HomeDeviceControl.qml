pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id: root
    required property var entity
    readonly property string domain: HomeAssistant.domain(entity)
    readonly property var attrs: entity?.attributes || {}
    readonly property bool usable: HomeAssistant.available(entity) && !HomeAssistant.busy[entity?.entity_id]
    signal requestColorPicker(var entity)
    readonly property bool supportsCustomColor:(attrs.supported_color_modes || []).some(m => ["hs","xy","rgb","rgbw","rgbww"].includes(m))
    readonly property var swatches:(supportsCustomColor ? [{custom:true}] : []).concat(HomeAssistant.favoriteColors(entity).map(color => ({custom:false,color:color})))
    function supports(service) { return !!HomeAssistant.services[domain]?.[service]; }
    function label(key) { return key.replace(/_/g," ").replace(/^./,c=>c.toUpperCase()); }
    spacing: 16
    RowLayout {
        Layout.fillWidth:true;Layout.topMargin:12;Layout.bottomMargin:8;spacing:16
        Rectangle {
            implicitWidth:64;implicitHeight:64;radius:32
            color:["on","playing","heat","cool"].includes(root.entity.state) ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
            MaterialSymbol { anchors.centerIn:parent;text:HomeAssistant.icon(root.entity);iconSize:32;color:Appearance.colors.colPrimary }
            Behavior on color { animation:Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }
        ColumnLayout {
            Layout.fillWidth:true;spacing:4
            StyledText { Layout.fillWidth:true;text:HomeAssistant.status(root.entity);font.pixelSize:Appearance.font.pixelSize.larger;font.weight:Font.Medium;wrapMode:Text.Wrap }
            StyledText { visible:root.attrs.current_temperature!==undefined; text:Translation.tr("Currently %1°").arg(root.attrs.current_temperature ?? "");color:Appearance.colors.colSubtext }
            StyledText { visible:root.attrs.battery_level!==undefined;text:Translation.tr("Battery %1%").arg(root.attrs.battery_level ?? "");color:Appearance.colors.colSubtext }
        }
        StyledSwitch {
            visible:["light","switch","input_boolean","fan","automation","humidifier"].includes(root.domain)
            checked:root.entity.state==="on";enabled:root.usable;Accessible.name:Translation.tr("Power")
            onClicked:HomeAssistant.activate(root.entity)
        }
    }
    RippleButtonWithIcon {
        visible:["scene","script","button","input_button"].includes(root.domain)
        Layout.fillWidth:true;materialIcon:"play_arrow";mainText:root.domain==="scene" ? Translation.tr("Activate scene") : Translation.tr("Run")
        enabled:root.usable;onClicked:HomeAssistant.activate(root.entity)
    }
    StyledText {
        visible: root.domain === "light" && root.attrs.brightness !== undefined
        text: Translation.tr("Brightness") + " · " + Math.round((root.attrs.brightness || 0) / 255 * 100) + "%"
        color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small
    }
    CommittedSlider {
        Layout.fillWidth:true
        visible: root.domain === "light" && (root.attrs.supported_color_modes || []).some(m => m !== "onoff")
        enabled: root.usable
        Accessible.name: Translation.tr("Brightness")
        configuration: StyledSlider.Configuration.L
        value: (root.attrs.brightness || 0) / 255
        onCommitted: value => HomeAssistant.callService(root.entity,value === 0 ? "turn_off" : "turn_on",value === 0 ? {} : {brightness_pct:Math.round(value*100)})
    }
    StyledText { visible: temperature.visible; text: Translation.tr("Warmth"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small }
    CommittedSlider {
        Layout.fillWidth:true
        Accessible.name: Translation.tr("Color temperature")
        id: temperature
        visible: root.domain === "light" && (root.attrs.supported_color_modes || []).includes("color_temp")
        enabled: root.usable
        from: root.attrs.min_color_temp_kelvin || 2000
        to: root.attrs.max_color_temp_kelvin || 6500
        value: root.attrs.color_temp_kelvin || from
        usePercentTooltip: false; tooltipContent: Math.round(value) + " K"
        onCommitted: value => HomeAssistant.callService(root.entity,"turn_on",{color_temp_kelvin:Math.round(value)})
    }
    ColumnLayout {
        Layout.fillWidth:true
        spacing:8
        visible:root.domain==="light" && (root.attrs.supported_color_modes || []).some(m => ["color_temp","hs","xy","rgb","rgbw","rgbww"].includes(m))
        StyledText { text:Translation.tr("Favorite colors"); color:Appearance.colors.colSubtext; font.pixelSize:Appearance.font.pixelSize.small }
        GridLayout {
            id:swatchGrid
            objectName:"homeColorSwatches"
            Layout.fillWidth:true
            readonly property int balancedColumns: {
                const count=root.swatches.length;
                const max=Math.max(1,Math.floor((width+columnSpacing)/(40+columnSpacing)));
                return Math.max(1,Math.ceil(count/Math.ceil(Math.max(1,count)/max)));
            }
            columns:balancedColumns
            columnSpacing:8; rowSpacing:8
            Repeater {
                model:root.swatches
                delegate:RippleButton {
                    required property var modelData
                    Layout.fillWidth:true
                    Layout.preferredWidth:1
                    implicitHeight:36
                    buttonRadius:Appearance.rounding.full
                    colBackground:modelData.custom ? ((root.attrs.rgb_color || root.attrs.hs_color || root.attrs.color_temp_kelvin) ? HomeAssistant.colorPreview(root.attrs,root.entity) : Appearance.colors.colLayer3) : HomeAssistant.colorPreview(modelData.color,root.entity)
                    colBackgroundHover:colBackground
                    enabled:root.usable
                    Accessible.name:modelData.custom ? Translation.tr("Custom color") : modelData.color.color_temp_kelvin ? Translation.tr("Color temperature")+" "+modelData.color.color_temp_kelvin+" K" : Translation.tr("Set light color")+" "+String(colBackground)
                    onClicked:if (modelData.custom) root.requestColorPicker(root.entity); else HomeAssistant.applyLightColor(root.entity,modelData.color)
                    contentItem:Item { MaterialSymbol { anchors.centerIn:parent; visible:parent.parent.modelData.custom; text:"colorize"; iconSize:18; color:parent.parent.colBackground.hslLightness>.5 ? "#171c19" : "white" } }
                    StyledToolTip { text:parent.Accessible.name }
                }
            }
        }
    }
    Loader {
        Layout.fillWidth: true
        active: root.domain === "media_player"
        sourceComponent: HomeMediaControl { entity: root.entity }
    }
    StyledText { visible: thermostat.visible; text: Translation.tr("Target temperature"); color: Appearance.colors.colSubtext }
    CommittedSlider {
        Layout.fillWidth:true
        Accessible.name: Translation.tr("Target temperature")
        id: thermostat
        visible: ["climate","water_heater"].includes(root.domain) && root.attrs.temperature !== undefined
        enabled: root.usable
        from: root.attrs.min_temp ?? 7; to: root.attrs.max_temp ?? 35; stepSize: root.attrs.target_temp_step || 0.5
        value: root.attrs.temperature ?? from
        usePercentTooltip: false; tooltipContent: value.toFixed(1) + "°"
        onCommitted: value => HomeAssistant.callService(root.entity,"set_temperature",{temperature:value})
    }
    StyledComboBox {
        buttonIcon: root.domain === "climate" ? "thermostat" : "list"
        visible: root.domain === "climate" && (root.attrs.hvac_modes || []).length > 0
        enabled: root.usable; textRole: "name"
        model: (root.attrs.hvac_modes || []).map(v => ({name:v}))
        currentIndex: (root.attrs.hvac_modes || []).indexOf(root.entity?.state)
        onActivated: HomeAssistant.callService(root.entity,"set_hvac_mode",{hvac_mode:root.attrs.hvac_modes[currentIndex]})
    }
    CommittedSlider {
        Layout.fillWidth:true
        visible: root.domain === "fan" && HomeAssistant.hasFeature(root.entity,1)
        enabled: root.usable; from: 0; to: 100; stepSize: root.attrs.percentage_step || 1
        value: root.attrs.percentage || 0
        onCommitted: value => HomeAssistant.callService(root.entity,"set_percentage",{percentage:Math.round(value)})
    }
    RowLayout {
        visible: root.domain === "cover"
        HomeAction { symbol:"arrow_upward"; label:Translation.tr("Open"); enabled:root.usable && HomeAssistant.hasFeature(root.entity,1); onClicked:HomeAssistant.callService(root.entity,"open_cover") }
        HomeAction { symbol:"stop"; label:Translation.tr("Stop"); enabled:root.usable && HomeAssistant.hasFeature(root.entity,8); onClicked:HomeAssistant.callService(root.entity,"stop_cover") }
        HomeAction { symbol:"arrow_downward"; label:Translation.tr("Close"); enabled:root.usable && HomeAssistant.hasFeature(root.entity,2); onClicked:HomeAssistant.callService(root.entity,"close_cover") }
    }
    CommittedSlider {
        Layout.fillWidth:true
        visible: root.domain === "cover" && HomeAssistant.hasFeature(root.entity,4)
        enabled: root.usable; from:0; to:100; value:root.attrs.current_position || 0
        onCommitted: value => HomeAssistant.callService(root.entity,"set_cover_position",{position:Math.round(value)})
    }
    RowLayout {
        visible: root.domain === "automation"
        HomeAction { symbol:"play_arrow"; label:Translation.tr("Run automation"); enabled:root.usable; onClicked:HomeAssistant.callService(root.entity,"trigger") }
        StyledText { text:Translation.tr("Run now"); color:Appearance.colors.colSubtext }
    }
    RowLayout {
        visible: root.domain === "lock"
        HomeAction { symbol:"lock"; label:Translation.tr("Lock"); enabled:root.usable; onClicked:HomeAssistant.callService(root.entity,"lock") }
        HomeAction { symbol:"lock_open"; label:Translation.tr("Unlock"); enabled:root.usable; onClicked:HomeAssistant.callService(root.entity,"unlock") }
    }
    RowLayout {
        visible: root.domain === "vacuum"
        HomeAction { symbol:"play_arrow"; label:Translation.tr("Start"); enabled:root.usable && HomeAssistant.hasFeature(root.entity,8192); onClicked:HomeAssistant.callService(root.entity,"start") }
        HomeAction { symbol:"pause"; label:Translation.tr("Pause"); enabled:root.usable && HomeAssistant.hasFeature(root.entity,4); onClicked:HomeAssistant.callService(root.entity,"pause") }
        HomeAction { symbol:"home"; label:Translation.tr("Return to dock"); enabled:root.usable && HomeAssistant.hasFeature(root.entity,16); onClicked:HomeAssistant.callService(root.entity,"return_to_base") }
    }
    StyledComboBox {
        buttonIcon: root.domain === "climate" ? "thermostat" : "list"
        visible: ["select","input_select"].includes(root.domain)
        enabled:root.usable; textRole:"name"
        model:(root.attrs.options || []).map(v=>({name:v}))
        currentIndex:(root.attrs.options || []).indexOf(root.entity?.state)
        onActivated:HomeAssistant.callService(root.entity,"select_option",{option:root.attrs.options[currentIndex]})
    }
    CommittedSlider {
        Layout.fillWidth:true
        visible:["number","input_number"].includes(root.domain)
        enabled:root.usable; from:root.attrs.min ?? 0; to:root.attrs.max ?? 100; stepSize:root.attrs.step || 1
        value:Number(root.entity?.state) || 0; usePercentTooltip:false
        onCommitted: value => HomeAssistant.callService(root.entity,"set_value",{value:value})
    }
    Repeater {
        model:[
            {domain:"light",attribute:"effect",list:"effect_list",service:"turn_on",key:"effect",label:Translation.tr("Effect")},
            {domain:"climate",attribute:"preset_mode",list:"preset_modes",service:"set_preset_mode",key:"preset_mode",label:Translation.tr("Preset")},
            {domain:"climate",attribute:"fan_mode",list:"fan_modes",service:"set_fan_mode",key:"fan_mode",label:Translation.tr("Fan mode")},
            {domain:"climate",attribute:"swing_mode",list:"swing_modes",service:"set_swing_mode",key:"swing_mode",label:Translation.tr("Swing")},
            {domain:"fan",attribute:"preset_mode",list:"preset_modes",service:"set_preset_mode",key:"preset_mode",label:Translation.tr("Preset")},
            {domain:"humidifier",attribute:"mode",list:"available_modes",service:"set_mode",key:"mode",label:Translation.tr("Mode")},
            {domain:"water_heater",attribute:"operation_mode",list:"operation_list",service:"set_operation_mode",key:"operation_mode",label:Translation.tr("Operation")},
            {domain:"vacuum",attribute:"fan_speed",list:"fan_speed_list",service:"set_fan_speed",key:"fan_speed",label:Translation.tr("Cleaning power")}
        ].filter(m => m.domain===root.domain && (root.attrs[m.list] || []).length && root.supports(m.service))
        delegate:HomeModeSelector {
            required property var modelData
            label:modelData.label;values:root.attrs[modelData.list] || [];current:root.attrs[modelData.attribute] || "";enabled:root.usable
            onSelected:value => {const data={};data[modelData.key]=value;HomeAssistant.callService(root.entity,modelData.service,data);}
        }
    }
    RowLayout {
        visible:root.domain==="fan" && HomeAssistant.hasFeature(root.entity,2) && root.supports("oscillate")
        StyledText { Layout.fillWidth:true;text:Translation.tr("Oscillation") }
        StyledSwitch { checked:!!root.attrs.oscillating;enabled:root.usable;onClicked:HomeAssistant.callService(root.entity,"oscillate",{oscillating:!root.attrs.oscillating}) }
    }
    HomeModeSelector {
        visible:root.domain==="fan" && HomeAssistant.hasFeature(root.entity,4) && root.supports("set_direction")
        label:Translation.tr("Direction");values:["forward","reverse"];current:root.attrs.direction || "forward";enabled:root.usable
        onSelected:value => HomeAssistant.callService(root.entity,"set_direction",{direction:value})
    }
    StyledText { visible:humidity.visible;text:Translation.tr("Target humidity");color:Appearance.colors.colSubtext }
    CommittedSlider {
        id:humidity;Layout.fillWidth:true
        visible:["climate","humidifier"].includes(root.domain) && root.supports("set_humidity") && root.attrs.humidity!==undefined
        enabled:root.usable;from:root.attrs.min_humidity ?? 0;to:root.attrs.max_humidity ?? 100;stepSize:1;value:root.attrs.humidity || 0
        usePercentTooltip:false;tooltipContent:Math.round(value)+"%";Accessible.name:Translation.tr("Humidity")
        onCommitted:value => HomeAssistant.callService(root.entity,"set_humidity",{humidity:Math.round(value)})
    }
    ColumnLayout {
        Layout.fillWidth:true;visible:root.domain==="climate" && root.attrs.target_temp_low!==undefined && root.attrs.target_temp_high!==undefined
        StyledText { text:Translation.tr("Temperature range");color:Appearance.colors.colSubtext }
        Repeater {
            model:["target_temp_low","target_temp_high"]
            delegate:ColumnLayout {
                required property string modelData
                Layout.fillWidth:true
                StyledText { text:(modelData==="target_temp_low" ? Translation.tr("Minimum") : Translation.tr("Maximum"))+" · "+root.attrs[modelData]+"°" }
                CommittedSlider {
                    Layout.fillWidth:true;enabled:root.usable;from:root.attrs.min_temp ?? 7;to:root.attrs.max_temp ?? 35;stepSize:root.attrs.target_temp_step || 0.5;value:root.attrs[parent.modelData] ?? from;usePercentTooltip:false;tooltipContent:value.toFixed(1)+"°"
                    onCommitted:value => { const data={target_temp_low:root.attrs.target_temp_low,target_temp_high:root.attrs.target_temp_high};data[parent.modelData]=value;if(data.target_temp_low<=data.target_temp_high)HomeAssistant.callService(root.entity,"set_temperature",data); }
                }
            }
        }
    }
    ColumnLayout {
        Layout.fillWidth:true;visible:["text","input_text"].includes(root.domain)
        MaterialTextArea { id:textValue;Layout.fillWidth:true;placeholderText:Translation.tr("Value");text:root.entity.state;Accessible.name:Translation.tr("Text value") }
        RippleButtonWithIcon { materialIcon:"check";mainText:Translation.tr("Save");enabled:root.usable;onClicked:HomeAssistant.callService(root.entity,"set_value",{value:textValue.text}) }
    }
    HomeServiceActions { Layout.fillWidth:true;entity:root.entity }
    RippleButtonWithIcon {
        Layout.fillWidth:true;materialIcon:attributesView.visible ? "expand_less" : "info";mainText:Translation.tr("Device information")
        onClicked:attributesView.visible=!attributesView.visible
    }
    ColumnLayout {
        id:attributesView;visible:false;Layout.fillWidth:true;spacing:12
        Repeater {
            model:Object.keys(root.attrs).filter(k => !["entity_picture","access_token","supported_features","friendly_name"].includes(k) && !/token|password|secret/i.test(k))
            delegate:ColumnLayout {
                required property string modelData
                Layout.fillWidth:true;spacing:2
                StyledText { text:root.label(parent.modelData);color:Appearance.colors.colSubtext;font.pixelSize:Appearance.font.pixelSize.smaller }
                StyledText { Layout.fillWidth:true;text:typeof root.attrs[parent.modelData]==="object" ? JSON.stringify(root.attrs[parent.modelData]) : String(root.attrs[parent.modelData]);textFormat:Text.PlainText;wrapMode:Text.WrapAnywhere }
            }
        }
    }
}
