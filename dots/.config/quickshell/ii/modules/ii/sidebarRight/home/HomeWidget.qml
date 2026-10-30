pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id: root
    property bool editing: false
    property bool favoritesOnly: false
    property bool searchOpen: false
    property string selectedId: ""
    property bool colorPickerOpen:false
    property alias colorPicker:fullColorPicker
    function openColorPicker(entity) { fullColorPicker.reset(HomeAssistant.colorPreview(entity.attributes,entity));colorPickerOpen=true; }
    onSelectedIdChanged:colorPickerOpen=false
    Behavior on selectedId {
        SequentialAnimation {
            NumberAnimation {
                target: deviceView; property: "opacity"; to: 0
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            PropertyAction {}
            NumberAnimation {
                target: deviceView; property: "opacity"; to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
    }
    readonly property var selectedEntity: HomeAssistant.states[selectedId] || null
    onSelectedEntityChanged:if (!selectedEntity) colorPickerOpen=false
    readonly property string preferredArea: Config.options.homeAssistant.rememberArea ? Persistent.states.homeAssistant.areaId : Config.options.homeAssistant.defaultAreaId
    readonly property string area: HomeAssistant.areaChoices.some(a => a.area_id === preferredArea) ? preferredArea : ""
    readonly property var entries: HomeAssistant.visibleEntities(area,editing).filter(e => (!favoritesOnly || Config.options.homeAssistant.favoriteEntities.includes(e.entity_id)) && (!search.text || (HomeAssistant.name(e) + e.entity_id).toLowerCase().includes(search.text.toLowerCase())))
    readonly property bool browsing: HomeAssistant.connected && selectedEntity === null
    onAreaChanged: rooms.syncSelection()
    spacing: 10

    RowLayout {
        Layout.fillWidth:true; Layout.topMargin:12; Layout.rightMargin:14
        spacing:8
        HomeAction {
            visible:root.selectedEntity !== null
            symbol:"arrow_back"; label:Translation.tr("Back to room")
            onClicked:{ if (root.colorPickerOpen) root.colorPickerOpen=false; else root.selectedId=""; }
        }
        ColumnLayout {
            Layout.fillWidth:true; spacing:3
            StyledText {
                Layout.fillWidth:true; elide:Text.ElideRight
                text:root.colorPickerOpen ? Translation.tr("Custom color") : root.selectedEntity ? HomeAssistant.name(root.selectedEntity) : Translation.tr("Home")
                font.pixelSize:Appearance.font.pixelSize.larger; font.weight:Font.Medium
            }
            RowLayout {
                visible:!root.colorPickerOpen
                spacing:5
                Rectangle { implicitWidth:6; implicitHeight:6; radius:3; color:HomeAssistant.connected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                StyledText {
                    text:HomeAssistant.connected ? (root.selectedEntity ? HomeAssistant.status(root.selectedEntity) : Translation.tr("%1 controls").arg(root.entries.length)) : Translation.tr("Not connected")
                    color:Appearance.colors.colSubtext; font.pixelSize:Appearance.font.pixelSize.smaller
                }
            }
        }
        HomeAction { visible:HomeAssistant.connected && !root.selectedEntity; symbol:root.editing ? "check" : "edit"; label:Translation.tr("Edit controls"); accent:root.editing; onClicked:root.editing = !root.editing }
        HomeAction { visible:!root.colorPickerOpen; symbol:"settings"; label:Translation.tr("Home Assistant settings"); onClicked:HomeAssistant.openSettings() }
    }

    RowLayout {
        visible:root.browsing && !root.colorPickerOpen
        Layout.fillWidth:true; Layout.rightMargin:14
        StyledComboBox {
            id:rooms
            function syncSelection() { currentIndex = Math.max(0,HomeAssistant.areaChoices.findIndex(a => a.area_id === root.area)); }
            onModelChanged:Qt.callLater(syncSelection)
            Layout.fillWidth:true; implicitHeight:40; buttonRadius:Appearance.rounding.full
            buttonIcon:"meeting_room"; textRole:"name"
            model:HomeAssistant.areaChoices
            currentIndex:Math.max(0,HomeAssistant.areaChoices.findIndex(a => a.area_id === root.area))
            onActivated: {
                const id = HomeAssistant.areaChoices[currentIndex].area_id;
                if (Config.options.homeAssistant.rememberArea) Persistent.states.homeAssistant.areaId = id;
                else Config.options.homeAssistant.defaultAreaId = id;
                root.selectedId = "";
            }
        }
        HomeAction {
            symbol:"search"; label:Translation.tr("Search devices"); accent:root.searchOpen
            onClicked: {
                root.searchOpen = !root.searchOpen;
                if (root.searchOpen) Qt.callLater(() => search.forceActiveFocus());
                else search.clear();
            }
        }
        HomeAction { symbol:"star"; label:Translation.tr("Favorites only"); accent:root.favoritesOnly; onClicked:root.favoritesOnly = !root.favoritesOnly }
    }
    Item {
        id: searchContainer
        Layout.fillWidth:true; Layout.rightMargin:14
        implicitHeight: root.browsing && !root.colorPickerOpen && root.searchOpen ? searchRow.implicitHeight : 0
        opacity: root.browsing && !root.colorPickerOpen && root.searchOpen ? 1 : 0
        visible: opacity > 0
        clip: true
        Behavior on implicitHeight { animation:Appearance.animation.elementResize.numberAnimation.createObject(this) }
        Behavior on opacity { animation:Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        RowLayout {
        id: searchRow
        width: parent.width
        spacing:8
        MaterialTextArea {
            id:search
            clip:true
            Layout.fillWidth:true
            wrapMode:TextEdit.NoWrap
            Keys.onReturnPressed: event => { event.accepted = true; }
            placeholderText:Translation.tr("Search devices")
            Accessible.name:Translation.tr("Search devices")
            Keys.onEscapePressed: { root.searchOpen = false; clear(); }
        }
        HomeAction {
            visible:search.text.length > 0
            symbol:"close"; label:Translation.tr("Clear search")
            onClicked:search.clear()
        }
    }
    }
    StyledFlickable {
        id: deviceView
        visible:!root.colorPickerOpen
        Layout.fillWidth:true; Layout.fillHeight:true; Layout.rightMargin:14; Layout.bottomMargin:12
        contentHeight:column.implicitHeight; clip:true
        ColumnLayout {
            id:column
            width:parent.width
            spacing:10
            HomeSetupCard {
                opacity:HomeAssistant.connected ? 0 : 1
                visible:opacity > 0
                enabled:!HomeAssistant.connected
                Layout.fillWidth:true
                Behavior on opacity { animation:Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            }
            StyledText {
                visible:HomeAssistant.connected && HomeAssistant.error.length > 0
                text:HomeAssistant.error; Layout.fillWidth:true; wrapMode:Text.Wrap
                font.pixelSize:Appearance.font.pixelSize.small; color:Appearance.colors.colError
            }
            StyledText {
                visible:HomeAssistant.connected && root.editing
                Layout.fillWidth:true; wrapMode:Text.Wrap
                text:Translation.tr("Choose what appears here. Star favorites and pin quick actions.")
                color:Appearance.colors.colSubtext; font.pixelSize:Appearance.font.pixelSize.smaller
            }
            Loader {
                Layout.fillWidth:true
                active:HomeAssistant.connected && root.selectedEntity !== null
                sourceComponent:HomeDeviceControl {
                    entity:root.selectedEntity || ({entity_id:"",state:"unknown",attributes:{}})
                    onRequestColorPicker:entity => root.openColorPicker(entity)
                }
            }
            Repeater {
                model:root.browsing ? [
                    {name:Translation.tr("Lighting"),domains:["light"]},
                    {name:Translation.tr("Climate & comfort"),domains:["climate","fan","humidifier","water_heater"]},
                    {name:Translation.tr("Media"),domains:["media_player"]},
                    {name:Translation.tr("Scenes & routines"),domains:["scene","script","automation"]},
                    {name:Translation.tr("Devices"),domains:["switch","input_boolean","cover","lock","vacuum","alarm_control_panel","button","input_button"]},
                    {name:Translation.tr("Readings & more"),domains:[]}
                ] : []
                delegate:ColumnLayout {
                    id:section
                    required property var modelData
                    property bool expanded:modelData.domains.length>0
                    readonly property var members:root.entries.filter(e => modelData.domains.length ? modelData.domains.includes(HomeAssistant.domain(e)) : !["light","climate","fan","humidifier","water_heater","media_player","scene","script","automation","switch","input_boolean","cover","lock","vacuum","alarm_control_panel","button","input_button"].includes(HomeAssistant.domain(e)))
                    visible:members.length>0
                    Layout.fillWidth:true;spacing:6
                    RippleButton {
                        Layout.fillWidth:true;implicitHeight:40;padding:12;buttonRadius:Appearance.rounding.full
                        colBackground:"transparent";colBackgroundHover:Appearance.colors.colLayer2Hover
                        onClicked:section.expanded=!section.expanded
                        Accessible.name:section.modelData.name
                        contentItem:RowLayout {
                            StyledText { Layout.fillWidth:true;text:section.modelData.name;color:Appearance.colors.colPrimary;font.weight:Font.Medium;font.pixelSize:Appearance.font.pixelSize.small }
                            StyledText { text:section.members.length;color:Appearance.colors.colSubtext;font.pixelSize:Appearance.font.pixelSize.smaller }
                            MaterialSymbol { text:section.expanded ? "expand_less" : "expand_more";iconSize:18;color:Appearance.colors.colSubtext }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth:true;implicitHeight:section.expanded ? rows.implicitHeight : 0
                        clip:true;visible:implicitHeight>0;enabled:section.expanded
                        Behavior on implicitHeight { animation:Appearance.animation.elementResize.numberAnimation.createObject(this) }
                        radius:Appearance.rounding.normal;color:Appearance.colors.colLayer1
                        ColumnLayout {
                            id:rows;width:parent.width;spacing:0
                            Repeater {
                                model:ScriptModel { values:section.members;objectProp:"entity_id" }
                                delegate:HomeEntityRow {
                                    required property var modelData
                                    Layout.fillWidth:true;entity:modelData;editing:root.editing
                                    onOpenDevice:entityId => root.selectedId=entityId
                                }
                            }
                        }
                    }
                }
            }
            StyledText { visible:root.browsing && root.entries.length === 0; text:Translation.tr("No devices match. Try another room or clear your search."); Layout.fillWidth:true; wrapMode:Text.Wrap; color:Appearance.colors.colSubtext }
        }
    }
    StyledFlickable {
        id:pickerView
        objectName:"homePickerView"
        interactive:!fullColorPicker.interacting
        Layout.fillWidth:true; Layout.fillHeight:true; Layout.rightMargin:14; Layout.bottomMargin:12
        visible:root.colorPickerOpen
        clip:true
        contentHeight:fullColorPicker.implicitHeight
        HomeColorPicker {
            id:fullColorPicker
            width:parent.width
            enabled:root.selectedEntity!==null && HomeAssistant.available(root.selectedEntity)
            spectrumHeight:Math.max(200,pickerView.height-230)
            onChosen:rgb => { if (root.selectedEntity) HomeAssistant.applyLightColor(root.selectedEntity,{rgb_color:rgb}); root.colorPickerOpen=false; }
            onCancelled:root.colorPickerOpen=false
        }
    }
}
