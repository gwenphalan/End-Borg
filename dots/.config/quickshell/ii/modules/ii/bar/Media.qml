import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Hyprland

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var homePlayer: DesktopMedia.remotePlayer
    readonly property bool useHomePlayer: DesktopMedia.useRemote
    readonly property string displayTitle: useHomePlayer ? (homePlayer.attributes.media_title || HomeAssistant.name(homePlayer)) : cleanedTitle
    readonly property string displayArtist: useHomePlayer ? (homePlayer.attributes.media_artist || HomeAssistant.name(homePlayer)) : (activePlayer?.trackArtist || "")
    readonly property bool playing: useHomePlayer ? homePlayer.state === "playing" : (activePlayer?.isPlaying || false)
    function mediaAction(service, localAction) {
        if (useHomePlayer) {
            if (service === "media_play_pause") HomeAssistant.activate(homePlayer);
            else if (HomeAssistant.hasFeature(homePlayer, service === "media_previous_track" ? 16 : 32)) HomeAssistant.callService(homePlayer, service);
        }
        else if (activePlayer) activePlayer[localAction]();
    }
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    Layout.fillHeight: true
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: Appearance.sizes.barHeight

    Timer {
        running: !root.useHomePlayer && activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        // Player selection lives in the popup; wheel gestures must not
        // silently redirect transport buttons to another device.
        onWheel: event => { event.accepted=false; }
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton) {
                root.mediaAction("media_play_pause", "togglePlaying");
            } else if (event.button === Qt.BackButton) {
                root.mediaAction("media_previous_track", "previous");
            } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
                root.mediaAction("media_next_track", "next");
            } else if (event.button === Qt.LeftButton) {
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
            }
        }
    }

    RowLayout { // Real content
        id: rowLayout

        spacing: 4
        anchors.fill: parent

        ClippedFilledCircularProgress {
            id: mediaCircProg
            Layout.alignment: Qt.AlignVCenter
            lineWidth: Appearance.rounding.unsharpen
            value: root.useHomePlayer ? (HomeAssistant.mediaPosition(root.homePlayer) / (root.homePlayer.attributes.media_duration || 1)) : ((activePlayer?.position || 0) / (activePlayer?.length || 1))
            implicitSize: 20
            colPrimary: Appearance.colors.colOnSecondaryContainer
            enableAnimation: false

            Item {
                anchors.centerIn: parent
                width: mediaCircProg.implicitSize
                height: mediaCircProg.implicitSize

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: root.playing ? "pause" : root.useHomePlayer ? "speaker" : "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        StyledText {
            visible: Config.options.bar.verbose
            width: rowLayout.width - (mediaCircProg.implicitSize + rowLayout.spacing * 2)
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true // Ensures the text takes up available space
            Layout.rightMargin: rowLayout.spacing
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight // Truncates the text on the right
            color: Appearance.colors.colOnLayer1
            text: `${root.displayTitle}${root.displayArtist ? ' • ' + root.displayArtist : ''}`
        }

    }

}
