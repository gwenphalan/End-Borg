pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id:root
    required property var entity
    property bool compact:false
    property bool popupMode:false
    property var playerChoices:[]
    property int selectedPlayer:-1
    signal playerSelected(int index)
    signal libraryRequested()
    readonly property var attrs:entity?.attributes || {}
    readonly property bool usable:HomeAssistant.available(entity) && !HomeAssistant.busy[entity?.entity_id]
    property var timeline:null
    readonly property real position:HomeAssistant.mediaTimelinePosition(timeline)
    onEntityChanged:timeline=HomeAssistant.reconcileMediaTimeline(timeline,entity)
    Component.onCompleted:timeline=HomeAssistant.reconcileMediaTimeline(timeline,entity)
    function timeLabel(seconds) { return Math.floor(seconds/60)+":"+String(Math.floor(seconds%60)).padStart(2,"0"); }
    radius:Appearance.rounding.normal
    color:Appearance.colors.colLayer1
    implicitHeight:content.implicitHeight+36
    clip:true
    Behavior on implicitHeight { animation:Appearance.animation.elementResize.numberAnimation.createObject(this) }
    ColumnLayout {
        id:content
        anchors { left:parent.left; right:parent.right; top:parent.top; margins:18 }
        spacing:14
        RowLayout {
            Layout.fillWidth:true
            spacing:14
            Rectangle {
                Layout.preferredWidth:root.compact ? 40 : 64
                Layout.preferredHeight:root.compact ? 40 : 64
                radius:Appearance.rounding.small
                color:Appearance.colors.colLayer2
                clip:true
                Image {
                    id:art
                    anchors.fill:parent
                    source: {
                        const url=root.attrs.entity_picture || "";
                        if (/^https?:\/\//.test(url)) return url;
                        if (url.startsWith("/")) return HomeAssistant.settings.url.replace(/\/+$/,"")+url;
                        return "";
                    }
                    fillMode:Image.PreserveAspectCrop
                    asynchronous:true
                }
                MaterialSymbol { anchors.centerIn:parent; visible:art.status!==Image.Ready; text:"speaker"; iconSize:root.compact ? 24 : 32; color:Appearance.colors.colPrimary }
            }
            ColumnLayout {
                Layout.fillWidth:true; spacing:4
                StyledText { Layout.fillWidth:true; text:HomeAssistant.name(root.entity); textFormat:Text.PlainText; elide:Text.ElideRight; color:Appearance.colors.colSubtext; font.pixelSize:Appearance.font.pixelSize.smaller }
                StyledText { Layout.fillWidth:true; text:root.attrs.media_title || HomeAssistant.status(root.entity); textFormat:Text.PlainText; elide:Text.ElideRight; font.weight:Font.Medium; font.pixelSize:Appearance.font.pixelSize.large }
                StyledText { visible:!!text; Layout.fillWidth:true; text:root.attrs.media_artist || root.attrs.media_album_name || ""; textFormat:Text.PlainText; color:Appearance.colors.colSubtext; elide:Text.ElideRight; font.pixelSize:Appearance.font.pixelSize.smaller }
            }
        }
        ColumnLayout {
            Layout.fillWidth:true; spacing:2
            visible:!root.compact && HomeAssistant.hasFeature(root.entity,2) && (root.attrs.media_duration || 0)>0
            CommittedSlider {
                objectName:"homeMediaSeek"
                Accessible.name:Translation.tr("Playback position")
                Layout.fillWidth:true
                configuration:StyledSlider.Configuration.XS
                enabled:root.usable
                to:root.attrs.media_duration || 1
                value:root.position
                usePercentTooltip:false
                tooltipContent:root.timeLabel(value)
                onCommitted: value => {
                    root.timeline=Object.assign({},root.timeline,{position:value,time:Date.now()});
                    HomeAssistant.callService(root.entity,"media_seek",{seek_position:value});
                }
            }
            RowLayout {
                Layout.fillWidth:true
                StyledText { text:root.timeLabel(root.position); color:Appearance.colors.colSubtext; font.pixelSize:Appearance.font.pixelSize.smaller }
                Item { Layout.fillWidth:true }
                StyledText { text:root.timeLabel(root.attrs.media_duration || 0); color:Appearance.colors.colSubtext; font.pixelSize:Appearance.font.pixelSize.smaller }
            }
        }
        RowLayout {
            Layout.alignment:Qt.AlignHCenter
            objectName:"homeMediaPlaybackRow"
            spacing:root.popupMode ? 6 : 10
            Item { visible:libraryAction.visible;implicitWidth:libraryAction.implicitWidth;implicitHeight:1 }
            HomeAction { objectName:"homeMediaRepeat";symbol:root.attrs.repeat==="one" ? "repeat_one" : "repeat";label:Translation.tr("Repeat")+" · "+(root.attrs.repeat || "off");accent:!!root.attrs.repeat && root.attrs.repeat!=="off";enabled:root.usable && HomeAssistant.hasFeature(root.entity,262144);onClicked:HomeAssistant.callService(root.entity,"repeat_set",{repeat:root.attrs.repeat==="off" || !root.attrs.repeat ? "all" : root.attrs.repeat==="all" ? "one" : "off"}) }
            HomeAction { implicitWidth:36; implicitHeight:40; symbol:"skip_previous"; label:Translation.tr("Previous"); enabled:root.usable && HomeAssistant.hasFeature(root.entity,16); onClicked:HomeAssistant.callService(root.entity,"media_previous_track") }
            HomeAction { objectName:"homeMediaPlay"; implicitWidth:root.compact ? 44 : root.popupMode ? 56 : 52; implicitHeight:implicitWidth; symbol:root.entity?.state==="playing" ? "pause" : "play_arrow"; label:root.entity?.state==="playing" ? Translation.tr("Pause") : Translation.tr("Play"); accent:true; enabled:root.usable && HomeAssistant.hasFeature(root.entity,root.entity?.state==="playing" ? 1 : 16384); onClicked:HomeAssistant.callService(root.entity,root.entity?.state==="playing" ? "media_pause" : "media_play") }
            HomeAction { implicitWidth:36; implicitHeight:40; symbol:"skip_next"; label:Translation.tr("Next"); enabled:root.usable && HomeAssistant.hasFeature(root.entity,32); onClicked:HomeAssistant.callService(root.entity,"media_next_track") }
            HomeAction { objectName:"homeMediaShuffle";symbol:"shuffle";label:Translation.tr("Shuffle");accent:root.attrs.shuffle===true;enabled:root.usable && HomeAssistant.hasFeature(root.entity,32768);onClicked:HomeAssistant.callService(root.entity,"shuffle_set",{shuffle:!root.attrs.shuffle}) }
            HomeAction { id:libraryAction; objectName:"homeMediaLibrary";visible:root.popupMode && MusicAssistant.connected && Config.options.musicAssistant.showLibraryButton;symbol:"library_music";label:Translation.tr("Music library");onClicked:root.libraryRequested() }

        }
        RowLayout {
            objectName:"homeMediaVolumeRow"
            Layout.fillWidth:true
            spacing:10
            visible:root.popupMode || HomeAssistant.hasFeature(root.entity,4) || HomeAssistant.hasFeature(root.entity,8)
            StyledComboBox {
                id:devicePicker
                objectName:"homeMediaDevicePicker"
                visible:root.popupMode
                Layout.fillWidth:false;Layout.preferredWidth:36
                implicitWidth:36;implicitHeight:40
                model:root.playerChoices;textRole:"name";currentIndex:root.selectedPlayer
                colBackground:"transparent"
                colBackgroundHover:Appearance.colors.colLayer2Hover
                indicator:Item {}
                contentItem:MaterialSymbol { text:"speaker";iconSize:20;color:Appearance.colors.colOnLayer1;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter }
                popup.width:Math.max(220,root.width-36)
                onActivated:root.playerSelected(currentIndex)
                Accessible.name:Translation.tr("Choose media player")
                StyledToolTip { text:Translation.tr("Choose media player") }
            }
            HomeAction { objectName:"homeMediaMute"; symbol:root.attrs.is_volume_muted ? "volume_off" : "volume_up"; label:Translation.tr("Mute"); enabled:root.usable && HomeAssistant.hasFeature(root.entity,8); onClicked:HomeAssistant.callService(root.entity,"volume_mute",{is_volume_muted:!root.attrs.is_volume_muted}) }
            CommittedSlider {
                objectName:"homeMediaVolume"
                Layout.fillWidth:true
                visible:HomeAssistant.hasFeature(root.entity,4)
                configuration:StyledSlider.Configuration.XS
                enabled:root.usable
                value:root.attrs.volume_level || 0
                onCommitted: value => HomeAssistant.callService(root.entity,"volume_set",{volume_level:value})
            }
            StyledText { visible:HomeAssistant.hasFeature(root.entity,4); Layout.preferredWidth:36; horizontalAlignment:Text.AlignRight; text:Math.round((root.attrs.volume_level || 0)*100)+"%"; color:Appearance.colors.colSubtext; font.pixelSize:Appearance.font.pixelSize.smaller }
        }
        StyledComboBox {
            Layout.fillWidth:true
            buttonIcon:"speaker"
            visible:!root.popupMode && !root.compact && (root.attrs.source_list || []).length>0
            enabled:root.usable
            model:(root.attrs.source_list || []).map(v => ({name:v}))
            textRole:"name"
            currentIndex:(root.attrs.source_list || []).indexOf(root.attrs.source)
            displayText:currentIndex>=0 ? root.attrs.source_list[currentIndex] : Translation.tr("Select source")
            onActivated:HomeAssistant.callService(root.entity,"select_source",{source:model[currentIndex].name})
        }
    }
}
