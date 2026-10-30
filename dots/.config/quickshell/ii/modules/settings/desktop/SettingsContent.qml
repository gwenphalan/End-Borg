pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings
import qs.modules.ii.overview

Item {
    id:root
    clip:true
    required property string categoryId
    required property string groupId
    required property string query
    property string highlightPath:""
    readonly property var category:SettingsCatalog.category(categoryId)
    readonly property var groups:SettingsCatalog.groups(categoryId)
    readonly property var preferences:SettingsCatalog.preferences(categoryId,groupId)
    readonly property var sections:SettingsCatalog.sections(categoryId,groupId,true)
    readonly property var results:SettingsCatalog.search(query)
    property alias pageHeader:pageHeader
    property alias activeTool:toolLoader.item
    signal navigate(string category,string group)
    Timer { id:highlightTimer; interval:1800; onTriggered:root.highlightPath="" }
    ColumnLayout {
        anchors.fill:parent
        anchors.topMargin:28
        anchors.leftMargin:28
        anchors.rightMargin:28
        anchors.bottomMargin:0
        spacing:20
        RowLayout {
            id:pageHeader
            Layout.fillWidth:true
            Layout.maximumWidth:760
            Layout.alignment:Qt.AlignHCenter
            Layout.fillHeight:false
            Layout.preferredHeight:implicitHeight
            Layout.maximumHeight:implicitHeight
            IconToolbarButton { visible:!!root.groupId && root.categoryId!=="about" && !root.query; text:"arrow_back"; implicitWidth:36; implicitHeight:36; Accessible.name:Translation.tr("Back to category"); onClicked:root.navigate(root.categoryId,SettingsCatalog.parentGroup(root.groupId)) }
            ColumnLayout {
                Layout.fillWidth:true; Layout.fillHeight:false; spacing:5
                StyledText { visible:!!root.groupId && root.categoryId!=="about" && !root.query; text:Translation.tr(root.category.title); color:Appearance.colors.colPrimary; font.pixelSize:Appearance.font.pixelSize.smaller }
                StyledText { visible:text.length>0; Layout.fillWidth:true; text:root.query ? Translation.tr("Search settings") : root.categoryId==="sleep" && root.groupId==="sleep.tonight" ? Translation.tr("Edit Tonight's Sleep Schedule") : root.categoryId==="sleep" && root.groupId==="sleep.schedule" ? Translation.tr(root.activeTool?.editIndex < 0 ? "Add schedule" : "Edit schedule") : root.groupId && root.categoryId!=="about" ? Translation.tr(root.groups.find(g => g.id===root.groupId)?.title || "Settings") : Translation.tr(root.category.title); font.family:Appearance.font.family.title; font.variableAxes:Appearance.font.variableAxes.title; font.pixelSize:root.groupId && root.categoryId!=="about" ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.title+4; font.weight:Font.Medium; elide:Text.ElideRight }
                StyledText { visible:text.length>0; Layout.fillWidth:true; text:root.query ? Translation.tr("%1 results for “%2”").arg(root.results.length).arg(root.query) : root.groupId ? "" : Translation.tr(root.category.description); color:Appearance.colors.colSubtext; wrapMode:Text.Wrap }
            }
        }
        Item {
            Layout.fillWidth:true; Layout.fillHeight:true
            StyledFlickable {
                id:page
                anchors.fill:parent
                visible:!root.query && root.categoryId!=="about" && root.categoryId!=="sleep" && !root.groupId.startsWith("tools.")
                clip:true
                contentHeight:rows.implicitHeight+24
                ScrollBar.vertical: SpotlightScrollBar {
                    scrolling:page.moving
                    reducedMotion:Config.options.launcher.reducedMotion
                }
                onVisibleChanged:if (visible) contentY=0
                onWidthChanged:contentX=0
                Connections { target:root; function onGroupIdChanged() { page.contentY=0; } function onCategoryIdChanged() { page.contentY=0; } }
                ColumnLayout {
                    id:rows
                    width:Math.min(Math.max(0,page.width-14),760)
                    x:(page.width-width)/2
                    spacing:20
                    Repeater {
                        id:sectionRepeater
                        model:root.sections
                        delegate:SettingsGroup { required property var modelData; section:modelData; showReset:!root.groupId.startsWith("background.widgets.clock"); onNavigate:group => root.navigate(root.categoryId,group) }
                    }
                }
            }
            StyledText {
                anchors.centerIn:parent
                width:Math.min(parent.width,420)
                visible:page.visible && !root.sections.length
                text:Translation.tr("No options are available with the current settings.")
                color:Appearance.colors.colSubtext
                horizontalAlignment:Text.AlignHCenter
                wrapMode:Text.Wrap
            }
            Loader {
                id:toolLoader
                anchors.fill:parent
                active:!root.query && (root.categoryId==="about" || root.categoryId==="sleep" || root.groupId.startsWith("tools."))
                anchors.leftMargin:Math.max(0,(parent.width-Math.min(Math.max(0,parent.width-14),760))/2)
                anchors.rightMargin:anchors.leftMargin
                onLoaded:{
                    if (item.baseWidth!==undefined) item.baseWidth=760;
                    if (item.horizontalContentPadding!==undefined) item.horizontalContentPadding=0;
                    if (item.bottomContentPadding!==undefined) item.bottomContentPadding=24;
                }
                source:root.categoryId==="sleep" ? "../SleepConfig.qml" : root.groupId==="tools.wallpaper" ? "../QuickConfig.qml" : root.groupId==="tools.home" ? "../HomeAssistantConfig.qml" : root.groupId==="tools.borg" ? "../BorgIntelligenceConfig.qml" : root.groupId==="tools.steamgriddb" ? "../SteamGridDbConfig.qml" : (root.categoryId==="about" || root.groupId==="tools.about") ? "../About.qml" : "TranslationTools.qml"
            }
            Binding { target:root.categoryId==="sleep" ? toolLoader.item : null; property:"groupId"; value:root.groupId }
            Connections {
                target:root.categoryId==="sleep" ? toolLoader.item : null
                function onNavigate(category,group) { root.navigate(category,group); }
            }

            ColumnLayout {
                anchors.centerIn:parent
                width:Math.min(parent.width,420)
                visible:toolLoader.active && toolLoader.status === Loader.Error
                MaterialSymbol { Layout.alignment:Qt.AlignHCenter; text:"error"; iconSize:36; color:Appearance.colors.colError }
                StyledText { Layout.fillWidth:true; horizontalAlignment:Text.AlignHCenter; text:Translation.tr("This settings tool could not be loaded."); wrapMode:Text.Wrap }
                DialogButton { Layout.alignment:Qt.AlignHCenter; buttonText:Translation.tr("Retry"); onClicked:{ const path=toolLoader.source; toolLoader.source=""; toolLoader.source=path; } }
            }
            ListView {
                id:searchResults
                Connections { target:root; function onQueryChanged() { searchResults.positionViewAtBeginning(); } }
                anchors.fill:parent
                visible:!!root.query
                clip:true
                spacing:10
                model:root.results
                boundsBehavior:Flickable.StopAtBounds
                delegate:Loader {
                    id:result
                    required property var modelData
                    width:ListView.view.width
                    sourceComponent:modelData.type==="action" ? actionResult : settingResult
                    Component { id:settingResult; SettingRow { width:result.width; setting:result.modelData; compact:true; showBreadcrumb:true; onNavigate:(category,group) => root.navigate(category,group) } }
                    Component {
                        id:actionResult
                        RippleButtonWithIcon { width:result.width; materialIcon:SettingsCatalog.iconFor(result.modelData) || SettingsCatalog.category(result.modelData.category).icon; mainText:Translation.tr(result.modelData.label); onClicked:root.navigate(result.modelData.category,result.modelData.group); StyledToolTip { text:Translation.tr(result.modelData.description || "") } }
                    }
                }
                StyledText { anchors.centerIn:parent; width:Math.min(parent.width,420); horizontalAlignment:Text.AlignHCenter; visible:!root.results.length; text:Translation.tr("No settings found. Try a device, feature or preference name."); color:Appearance.colors.colSubtext; wrapMode:Text.Wrap }
            }
        }
    }
}
