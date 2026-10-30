pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id:root
    required property var section
    property bool showReset:true
    property var valueStore:null
    signal actionRequested(string action)
    readonly property bool reducedMotion:Config.options.launcher.reducedMotion
    readonly property var shownItems:{
        const observed=SettingsCatalog.revision;
        return section.items.filter(item => root.valueStore ? item.available!==false : item.kind==="preference" ? SettingsCatalog.available(item.setting) : SettingsCatalog.linkAvailable(item.category || item.setting?.category || section.category,item.group));
    }
    readonly property bool editorAvailable:section.editor!=="clockAppearance" || SettingsCatalog.available(SettingsCatalog.entry("background.widgets.clock.digital.font.family"))
    readonly property bool hasContent:!!section.tool || (!!section.editor && editorAvailable) || shownItems.length>0
    signal navigate(string group)
    Layout.fillWidth:true
    visible:hasContent || implicitHeight>0
    spacing:8
    Item {
        visible:implicitHeight>0
        Layout.leftMargin:20
        Layout.fillWidth:true
        implicitHeight:root.hasContent && !!root.section.title ? heading.implicitHeight+8 : 0
        clip:true
        Behavior on implicitHeight { enabled:!root.reducedMotion; NumberAnimation { duration:Appearance.animation.elementMoveSmall.duration; easing.type:Appearance.animation.elementMoveSmall.type; easing.bezierCurve:Appearance.animation.elementMoveSmall.bezierCurve } }
        StyledText {
            id:heading
            y:8
            text:Translation.tr(root.section.title)
            color:Appearance.colors.colSubtext
            font.pixelSize:Appearance.font.pixelSize.smaller
        }
    }
    Loader {
        active:root.section.editor==="barUtilities"
        visible:active
        Layout.fillWidth:true
        sourceComponent:SettingsBarUtilityEditor {}
    }
    Loader {
        active:root.section.editor==="clockAppearance" && root.editorAvailable
        visible:active
        Layout.fillWidth:true
        sourceComponent:SettingsClockAppearanceEditor {}
    }
    Loader {
        id:embeddedTool
        visible:active
        active:["steamgriddb","wallpaper","translation"].includes(root.section.tool)
        Layout.fillWidth:true
        Layout.preferredHeight:item ? (item.contentHeight!==undefined ? item.contentHeight+8 : item.implicitHeight) : 0
        source:root.section.tool==="steamgriddb" ? "../SteamGridDbConfig.qml" : root.section.tool==="wallpaper" ? "../QuickConfig.qml" : "TranslationTools.qml"
        onLoaded: {
            if (item.baseWidth!==undefined) item.baseWidth=760;
            if (item.horizontalContentPadding!==undefined) item.horizontalContentPadding=0;
            if (item.bottomContentPadding!==undefined) item.bottomContentPadding=24;
            if (item.interactive!==undefined) item.interactive=false;
        }
    }
    Rectangle {
        visible:implicitHeight>0
        Layout.fillWidth:true
        implicitHeight:items.implicitHeight
        color:Appearance.colors.colLayer2
        radius:Appearance.rounding.normal
        clip:true
        ColumnLayout {
            id:items
            width:parent.width
            spacing:0
            Repeater {
                model:root.section.items
                delegate:Item {
                    id:row
                    required property int index
                    required property var modelData
                    readonly property bool shown:{
                        const observed=SettingsCatalog.revision;
                        return root.valueStore ? modelData.available!==false : modelData.kind==="preference" ? SettingsCatalog.available(modelData.setting) : SettingsCatalog.linkAvailable(root.section.category,modelData.group);
                    }
                    Layout.fillWidth:true
                    implicitHeight:shown ? rowContent.implicitHeight : 0
                    visible:shown || implicitHeight>0
                    enabled:shown
                    opacity:shown ? 1 : 0
                    clip:true
                    Behavior on implicitHeight { enabled:!root.reducedMotion && row.modelData.setting?.path!=="background.widgets.clock.digital.font.size"; NumberAnimation { duration:Appearance.animation.elementMoveSmall.duration; easing.type:Appearance.animation.elementMoveSmall.type; easing.bezierCurve:Appearance.animation.elementMoveSmall.bezierCurve } }
                    Behavior on opacity { enabled:!root.reducedMotion; NumberAnimation { duration:Appearance.animation.elementMoveFast.duration; easing.type:Appearance.animation.elementMoveFast.type; easing.bezierCurve:Appearance.animation.elementMoveFast.bezierCurve } }
                    ColumnLayout {
                    id:rowContent
                    width:parent.width
                    spacing:0
                    Loader {
                        id:control
                        Layout.fillWidth:true
                        sourceComponent:row.modelData.kind === "preference" ? preference : submenu
                        Component {
                            id:preference
                            SettingRow { valueStore:root.valueStore; objectName:row.modelData.objectName || (root.valueStore ? row.modelData.setting.path : ""); width:control.width; setting:row.modelData.setting; compact:true; grouped:true }
                        }
                        Component {
                            id:submenu
                            RippleButton {
                                id:link
                                objectName:root.valueStore ? (row.modelData.objectName || "") : ""
                                enabled:!root.valueStore || row.modelData.enabled!==false
                                opacity:enabled ? 1 : 0.4
                                width:control.width
                                implicitHeight:Math.max(60,implicitContentHeight+24)
                                padding:20
                                buttonRadius:0
                                Accessible.name:Translation.tr(row.modelData.title)
                                onClicked:root.valueStore ? root.actionRequested(row.modelData.action || "") : root.navigate(row.modelData.group)
                                contentItem:RowLayout {
                                    spacing:16
                                    MaterialSymbol {
                                        visible:!!row.modelData.icon
                                        text:row.modelData.icon || ""
                                        iconSize:20
                                        color:Appearance.colors.colSubtext
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth:true; spacing:4
                                        StyledText { Layout.fillWidth:true; text:Translation.tr(row.modelData.title); elide:Text.ElideRight }
                                    }
                                    StyledText {
                                        visible:!!row.modelData.valuePath
                                        Layout.maximumWidth:link.width*.3
                                        text:(root.valueStore ? root.valueStore.get(row.modelData.valuePath || "") : SettingsCatalog.get(row.modelData.valuePath || "")) || Translation.tr(row.modelData.emptyValue || "")
                                        color:Appearance.colors.colSubtext; elide:Text.ElideMiddle
                                    }
                                    MaterialSymbol { visible:!root.valueStore || !!row.modelData.action; text:"chevron_right"; iconSize:20; color:Appearance.colors.colSubtext }
                                }
                            }
                        }
                    }
                    Rectangle {
                        visible:row.shown && root.shownItems.indexOf(row.modelData)<root.shownItems.length-1
                        Layout.fillWidth:true; Layout.leftMargin:20; Layout.rightMargin:16
                        implicitHeight:1
                        color:Appearance.colors.colLayer0Border
                    }
                    }
                }
            }
        }
    }
    RowLayout {
        visible:!root.valueStore && root.hasContent && root.showReset && root.section.resetEnabled && SettingsCatalog.sectionChanged(root.section)
        Layout.fillWidth:true
        Layout.leftMargin:20
        Layout.rightMargin:16
        DialogButton {
            buttonText:Translation.tr("Reset to default")
            implicitHeight:30
            padding:8
            Accessible.name:Translation.tr("Reset %1 to default").arg(root.section.title ? Translation.tr(root.section.title) : Translation.tr("Wallpaper & Colors"))
            onClicked:if(!root.valueStore) SettingsCatalog.resetSection(root.section)
        }
        Item { Layout.fillWidth:true }
    }
}
