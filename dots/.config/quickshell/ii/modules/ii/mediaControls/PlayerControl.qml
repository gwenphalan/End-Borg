pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland

Item { // Player instance
    id: root
    property MprisPlayer player: null
    property var homeEntity: null
    readonly property bool isHome: homeEntity !== null
    readonly property var attrs: homeEntity?.attributes || {}
    readonly property bool homeNotPlaying: isHome && (!attrs.media_title || ["idle", "off", "standby", "unavailable", "unknown"].includes(homeEntity.state))
    readonly property var sourceDesktopEntry: player?.desktopEntry ? DesktopEntries.byId(player.desktopEntry) : null
    readonly property var sourceIcon: isHome ? null : AppSearch.resolveAdaptiveIcon(player?.desktopEntry || "", sourceDesktopEntry?.icon || "audio-x-generic", sourceDesktopEntry?.name || player?.identity || "")
    readonly property bool isHomePod: isHome && /homepod/i.test(HomeAssistant.name(homeEntity) + " " + homeEntity.entity_id)
    readonly property string sourceName: isHome ? HomeAssistant.name(homeEntity) : (sourceDesktopEntry?.name || player?.identity || Translation.tr("Local player"))
    readonly property var sourceToplevel: {
        if (isHome || !player) return null;
        const appId = (sourceDesktopEntry?.id || player.desktopEntry || "").replace(/\.desktop$/, "").toLowerCase();
        if (!appId) return null;
        const windows = ToplevelManager.toplevels.values.filter(window => {
            const id = (DesktopEntries.heuristicLookup(window.appId)?.id || window.appId || "").replace(/\.desktop$/, "").toLowerCase();
            return id === appId;
        });
        const title = normalized(player.trackTitle);
        return windows.find(window => title && normalized(window.title).includes(title))
            || windows.find(window => window.activated) || windows[0] || null;
    }
    readonly property bool canFocusSource: !isHome && ((player?.canRaise ?? false) || sourceToplevel !== null)
    readonly property bool playing: isHome ? homeEntity.state === "playing" : (player?.isPlaying ?? false)
    readonly property bool usable: isHome ? HomeAssistant.available(homeEntity) && !HomeAssistant.busy[homeEntity.entity_id] : player !== null
    readonly property real duration: isHome ? (attrs.media_duration || 0) : (player?.length || 0)
    property var timeline: null
    readonly property real position: isHome ? HomeAssistant.mediaTimelinePosition(timeline) : (player?.position || 0)
    readonly property bool canSeek: isHome ? HomeAssistant.hasFeature(homeEntity, 2) && duration > 0 : (player?.canSeek ?? false)
    readonly property bool showLibrary: isHome && MusicAssistant.connected && Config.options.musicAssistant.showLibraryButton
    readonly property var audioNode: findAudioNode()
    readonly property bool hasVolume: isHome ? HomeAssistant.hasFeature(homeEntity, 4) : audioNode !== null || (player?.volumeSupported ?? false)
    readonly property bool hasMute: isHome ? HomeAssistant.hasFeature(homeEntity, 8) : hasVolume
    readonly property bool hasRepeat: isHome ? HomeAssistant.hasFeature(homeEntity, 262144) : (player?.loopSupported ?? false)
    readonly property bool hasShuffle: isHome ? HomeAssistant.hasFeature(homeEntity, 32768) : (player?.shuffleSupported ?? false)
    readonly property real sourceVolume: isHome ? (attrs.volume_level || 0) : audioNode ? audioNode.audio.volume : (player?.volume || 0)
    readonly property bool sourceMuted: isHome ? !!attrs.is_volume_muted : audioNode ? audioNode.audio.muted : sourceVolume === 0
    readonly property string repeatMode: isHome ? (attrs.repeat || "off") : player?.loopState === MprisLoopState.Track ? "one" : player?.loopState === MprisLoopState.Playlist ? "all" : "off"
    readonly property bool sourceShuffle: isHome ? !!attrs.shuffle : (player?.shuffle ?? false)
    readonly property bool showExtras: showLibrary || hasVolume || hasMute || hasRepeat || hasShuffle
    property real volumeBeforeMute: 1
    signal libraryRequested()
    onHomeEntityChanged: timeline = HomeAssistant.reconcileMediaTimeline(timeline, homeEntity)
    Component.onCompleted: if (isHome) timeline = HomeAssistant.reconcileMediaTimeline(timeline, homeEntity)

    function service(name, data) {
        DesktopMedia.select({entityId: homeEntity.entity_id});
        HomeAssistant.callService(homeEntity, name, data);
    }
    function selectLocal() {
        DesktopMedia.select({player: player});
    }
    function focusSource() {
        if (!canFocusSource) return;
        const sourcePlayer = player;
        const window = sourceToplevel;
        const useRaise = sourcePlayer.canRaise;
        GlobalStates.mediaControlsOpen = false;
        if (useRaise) sourcePlayer.raise();
        else window.activate();
    }
    function normalized(value) {
        return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
    }
    function findAudioNode() {
        if (isHome || !player) return null;
        const appWords = normalized(player.identity + " " + player.desktopEntry).split(" ").filter(word => word.length > 2 && !["org", "com", "mozilla", "browser", "desktop"].includes(word));
        const candidates = Audio.outputAppNodes.filter(node => {
            const props = node.properties;
            const words = normalized([props["application.name"], props["application.id"], props["application.process.binary"], props["node.name"]].join(" ")).split(" ");
            return appWords.some(word => words.includes(word));
        });
        const title = normalized(player.trackTitle);
        const trackMatches = title.length > 3 ? candidates.filter(node => {
            const media = normalized(node.properties["media.name"]);
            return media === title || media.startsWith(title + " ") || title.startsWith(media + " ");
        }) : [];
        if (trackMatches.length === 1) return trackMatches[0];
        return candidates.length === 1 ? candidates[0] : null;
    }
    function setSourceVolume(value) {
        if (isHome) service("volume_set", {volume_level: value});
        else if (audioNode) audioNode.audio.volume = value;
        else if (player?.volumeSupported) player.volume = value;
    }
    function toggleSourceMute() {
        if (isHome) service("volume_mute", {is_volume_muted: !sourceMuted});
        else if (audioNode) audioNode.audio.muted = !audioNode.audio.muted;
        else {
            if (sourceMuted) setSourceVolume(volumeBeforeMute);
            else { volumeBeforeMute = sourceVolume; setSourceVolume(0); }
        }
    }
    function cycleRepeat() {
        if (isHome) service("repeat_set", {repeat: repeatMode === "off" ? "all" : repeatMode === "all" ? "one" : "off"});
        else if (player?.loopSupported) {
            selectLocal();
            player.loopState = repeatMode === "off" ? MprisLoopState.Playlist : repeatMode === "all" ? MprisLoopState.Track : MprisLoopState.None;
        }
    }
    function toggleShuffle() {
        if (isHome) service("shuffle_set", {shuffle: !sourceShuffle});
        else if (player?.shuffleSupported) { selectLocal(); player.shuffle = !player.shuffle; }
    }
    PwObjectTracker {
        objects: root.isHome ? [] : Audio.outputAppNodes
    }

    property string artUrl: {
        if (!isHome) return player?.trackArtUrl || "";
        const url = attrs.entity_picture || "";
        if (/^https?:\/\//.test(url)) return url;
        return url.startsWith("/") ? HomeAssistant.settings.url.replace(/\/+$/, "") + url : "";
    }
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property color artDominantColor: ColorUtils.mix((colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary), Appearance.colors.colPrimaryContainer, 0.8) || Appearance.m3colors.m3secondaryContainer
    property bool downloaded: false
    property list<real> visualizerPoints: []
    property real maxVisualizerValue: 1000 // Max value in the data points
    property int visualizerSmoothing: 2 // Number of points to average for smoothing
    property real radius
    implicitHeight: Appearance.sizes.mediaControlsHeight + (showExtras ? 46 : 0)

    property string displayedArtFilePath: isHome ? artUrl : root.downloaded ? Qt.resolvedUrl(artFilePath) : ""

    component TrackChangeButton: RippleButton {
        id: control
        implicitWidth: 24
        implicitHeight: 24

        property var iconName
        property string label: ""
        Accessible.name: label
        opacity: enabled ? 1 : 0.4
        StyledToolTip { text: control.label }
        colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 1)
        colBackgroundHover: blendedColors.colSecondaryContainerHover
        colRipple: blendedColors.colSecondaryContainerActive

        contentItem: MaterialSymbol {
            iconSize: Appearance.font.pixelSize.huge
            fill: 1
            horizontalAlignment: Text.AlignHCenter
            color: blendedColors.colOnSecondaryContainer
            text: iconName

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    Timer { // Force update for revision
        running: !root.isHome && root.playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: {
            root.player.positionChanged()
        }
    }

    onArtFilePathChanged: {
        if (root.isHome) return;
        if (root.artUrl.length == 0) {
            root.downloaded = false
            return;
        }

        // Binding does not work in Process
        coverArtDownloader.targetFile = root.artUrl
        coverArtDownloader.artFilePath = root.artFilePath
        // Download
        root.downloaded = false
        coverArtDownloader.running = true
    }

    Process { // Cover art downloader
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: [ "bash", "-c", `[ -f ${artFilePath} ] || curl -4 -sSL '${targetFile}' -o '${artFilePath}'` ]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0 // 2^0 = 1 color
        rescaleSize: 1 // Rescale to 1x1 pixel for faster processing
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: artDominantColor
    }

    StyledRectangularShadow {
        target: background
    }
    Rectangle { // Background
        id: background
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        color: ColorUtils.applyAlpha(blendedColors.colLayer0, 1)
        radius: root.radius

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: background.width
                height: background.height
                radius: background.radius
            }
        }

        StyledImage {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true

            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(blendedColors.colLayer0, 0.3)
                radius: root.radius
            }
        }

        WaveVisualizer {
            id: visualizerCanvas
            anchors.fill: parent
            live: !root.isHome && root.playing
            points: root.visualizerPoints
            maxVisualizerValue: root.maxVisualizerValue
            smoothing: root.visualizerSmoothing
            color: blendedColors.colPrimary
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.canFocusSource
            cursorShape: Qt.PointingHandCursor
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: Translation.tr("Show %1").arg(root.sourceName)
            onClicked: root.focusSource()
            Keys.onReturnPressed: root.focusSource()
            Keys.onEnterPressed: root.focusSource()
            Keys.onSpacePressed: root.focusSource()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Appearance.sizes.mediaControlsHeight - Appearance.sizes.elevationMargin * 2 - 26
                spacing: 15

                Rectangle { // Art background
                    id: artBackground
                    readonly property bool hasArtwork: mediaArt.status === Image.Ready && root.displayedArtFilePath.length > 0
                    readonly property bool revealSource: !hasArtwork || artHover.hovered
                    Layout.fillHeight: true
                    implicitWidth: height
                    radius: Appearance.rounding.verysmall
                    color: ColorUtils.transparentize(blendedColors.colLayer1, 0.5)

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: artBackground.width
                            height: artBackground.height
                            radius: artBackground.radius
                        }
                    }

                    StyledImage { // Art image
                        id: mediaArt
                        property int size: parent.height
                        anchors.fill: parent

                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        antialiasing: true

                        width: size
                        height: size
                        layer.enabled: artBackground.hasArtwork && artHover.hovered
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blurMax: 16
                            blur: 0.35
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "#55000000"
                        opacity: artBackground.hasArtwork && artHover.hovered ? 1 : 0
                        Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    }
                    Item {
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        opacity: artBackground.revealSource ? 1 : 0
                        Accessible.role: Accessible.Graphic
                        Accessible.name: root.sourceName
                        Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

                        StyledImage {
                            anchors.fill: parent
                            visible: !root.isHome
                            source: root.sourceIcon?.source || ""
                            fillMode: Image.PreserveAspectFit
                        }
                        Image {
                            id: homePodIcon
                            anchors.fill: parent
                            visible: root.isHomePod
                            source: root.isHomePod ? Quickshell.shellPath("assets/icons/homepod.svg") : ""
                            sourceSize: Qt.size(60, 60)
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: artBackground.hasArtwork ? "white" : blendedColors.colPrimary
                            }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: root.isHome && !root.isHomePod
                            text: "speaker"
                            iconSize: 30
                            color: artBackground.hasArtwork ? "white" : blendedColors.colPrimary
                        }
                    }
                    HoverHandler {
                        id: artHover
                        cursorShape: root.canFocusSource ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                    StyledToolTip {
                        text: root.sourceName
                        extraVisibleCondition: false
                        alternativeVisibleCondition: artHover.hovered
                    }
                }

                ColumnLayout { // Info & controls
                    Layout.fillHeight: true
                    spacing: 2

                    StyledText {
                        id: trackTitle
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: blendedColors.colOnLayer0
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: root.homeNotPlaying ? Translation.tr("Not Playing") : StringUtils.cleanMusicTitle(root.isHome ? root.attrs.media_title : root.player?.trackTitle) || Translation.tr("Untitled")
                        animateChange: true
                        animationDistanceX: 6
                        animationDistanceY: 0
                    }
                    StyledText {
                        id: trackArtist
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: blendedColors.colSubtext
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: root.homeNotPlaying ? "" : root.isHome ? (root.attrs.media_artist || root.attrs.media_album_name || "") : (root.player?.trackArtist || "")
                        animateChange: true
                        animationDistanceX: 6
                        animationDistanceY: 0
                    }
                    Item { Layout.fillHeight: true }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: trackTime.implicitHeight + sliderRow.implicitHeight

                        StyledText {
                            id: trackTime
                            anchors.bottom: sliderRow.top
                            anchors.bottomMargin: 5
                            anchors.left: parent.left
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: blendedColors.colSubtext
                            elide: Text.ElideRight
                            text: root.homeNotPlaying ? "" : root.duration > 0 ? `${StringUtils.friendlyTimeForSeconds(root.position)} / ${StringUtils.friendlyTimeForSeconds(root.duration)}` : root.isHome ? HomeAssistant.status(root.homeEntity) : ""
                        }
                        RowLayout {
                            id: sliderRow
                            anchors {
                                bottom: parent.bottom
                                left: parent.left
                                right: parent.right
                            }
                            TrackChangeButton {
                                iconName: "skip_previous"
                                label: Translation.tr("Previous")
                                enabled: root.usable && (root.isHome ? HomeAssistant.hasFeature(root.homeEntity, 16) : (root.player?.canGoPrevious ?? false))
                                downAction: () => {
                                    if (root.isHome) root.service("media_previous_track");
                                    else { root.selectLocal(); root.player.previous(); }
                                }
                            }
                            Item {
                                id: progressBarContainer
                                Layout.fillWidth: true
                                opacity: root.duration > 0 ? 1 : 0.3
                                implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                                Loader {
                                    id: sliderLoader
                                    anchors.fill: parent
                                    active: root.canSeek
                                    sourceComponent: CommittedSlider {
                                        Accessible.name: Translation.tr("Playback position")
                                        enabled: root.usable
                                        configuration: StyledSlider.Configuration.Wavy
                                        animateWave: root.playing
                                        highlightColor: blendedColors.colPrimary
                                        trackColor: blendedColors.colSecondaryContainer
                                        handleColor: blendedColors.colPrimary
                                        value: root.duration > 0 ? root.position / root.duration : 0
                                        usePercentTooltip: false
                                        tooltipContent: StringUtils.friendlyTimeForSeconds(value * root.duration)
                                        onCommitted: value => {
                                            if (root.isHome) {
                                                root.timeline = Object.assign({}, root.timeline, {position: value * root.duration, time: Date.now()});
                                                root.service("media_seek", {seek_position: value * root.duration});
                                            } else {
                                                root.selectLocal();
                                                root.player.position = value * root.duration;
                                            }
                                        }
                                    }
                                }

                                Loader {
                                    id: progressBarLoader
                                    anchors {
                                        verticalCenter: parent.verticalCenter
                                        left: parent.left
                                        right: parent.right
                                    }
                                    active: !root.canSeek
                                    sourceComponent: StyledProgressBar {
                                        wavy: root.playing && root.duration > 0
                                        highlightColor: blendedColors.colPrimary
                                        trackColor: blendedColors.colSecondaryContainer
                                        value: root.duration > 0 ? root.position / root.duration : 0
                                    }
                                }


                            }
                            TrackChangeButton {
                                iconName: "skip_next"
                                label: Translation.tr("Next")
                                enabled: root.usable && (root.isHome ? HomeAssistant.hasFeature(root.homeEntity, 32) : (root.player?.canGoNext ?? false))
                                downAction: () => {
                                    if (root.isHome) root.service("media_next_track");
                                    else { root.selectLocal(); root.player.next(); }
                                }
                            }
                        }

                        RippleButton {
                            id: playPauseButton
                            anchors.right: parent.right
                            anchors.bottom: sliderRow.top
                            anchors.bottomMargin: 5
                            property real size: 44
                            implicitWidth: size
                            implicitHeight: size
                            Accessible.name: root.playing ? Translation.tr("Pause") : Translation.tr("Play")
                            enabled: root.usable && (root.isHome ? HomeAssistant.hasFeature(root.homeEntity, root.playing ? 1 : 16384) : (root.player?.canTogglePlaying ?? false))
                            opacity: enabled ? 1 : 0.4
                            StyledToolTip { text: playPauseButton.Accessible.name }
                            downAction: () => {
                                if (root.isHome) root.service(root.playing ? "media_pause" : "media_play");
                                else { root.selectLocal(); root.player.togglePlaying(); }
                            }

                            buttonRadius: root.playing ? Appearance.rounding.normal : size / 2
                            colBackground: root.playing ? blendedColors.colPrimary : blendedColors.colSecondaryContainer
                            colBackgroundHover: root.playing ? blendedColors.colPrimaryHover : blendedColors.colSecondaryContainerHover
                            colRipple: root.playing ? blendedColors.colPrimaryActive : blendedColors.colSecondaryContainerActive

                            contentItem: MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.huge
                                fill: 1
                                horizontalAlignment: Text.AlignHCenter
                                color: root.playing ? blendedColors.colOnPrimary : blendedColors.colOnSecondaryContainer
                                text: root.playing ? "pause" : "play_arrow"

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.showExtras
                spacing: 8

                TrackChangeButton {
                    visible: root.hasMute
                    iconName: root.sourceMuted ? "volume_off" : "volume_up"
                    label: root.sourceMuted ? Translation.tr("Unmute") : Translation.tr("Mute")
                    enabled: root.usable
                    downAction: () => root.toggleSourceMute()
                }
                CommittedSlider {
                    Layout.fillWidth: true
                    visible: root.hasVolume
                    Accessible.name: Translation.tr("Volume")
                    configuration: StyledSlider.Configuration.XS
                    enabled: root.usable
                    highlightColor: blendedColors.colPrimary
                    trackColor: blendedColors.colSecondaryContainer
                    handleColor: blendedColors.colPrimary
                    value: root.sourceVolume
                    onCommitted: value => root.setSourceVolume(value)
                }
                StyledText {
                    visible: root.hasVolume
                    Layout.preferredWidth: 34
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.sourceVolume * 100) + "%"
                    color: blendedColors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                Item { Layout.fillWidth: true; visible: !root.hasVolume }
                TrackChangeButton {
                    visible: root.hasRepeat
                    iconName: root.repeatMode === "one" ? "repeat_one" : "repeat"
                    label: Translation.tr("Repeat") + " · " + root.repeatMode
                    enabled: root.usable && (root.isHome || (root.player?.canControl ?? false))
                    opacity: !enabled ? 0.4 : root.repeatMode !== "off" ? 1 : 0.55
                    downAction: () => root.cycleRepeat()
                }
                TrackChangeButton {
                    visible: root.hasShuffle
                    iconName: "shuffle"
                    label: Translation.tr("Shuffle")
                    enabled: root.usable && (root.isHome || (root.player?.canControl ?? false))
                    opacity: !enabled ? 0.4 : root.sourceShuffle ? 1 : 0.55
                    downAction: () => root.toggleShuffle()
                }
                TrackChangeButton {
                    visible: root.showLibrary
                    iconName: "library_music"
                    label: Translation.tr("Music library")
                    downAction: () => root.libraryRequested()
                }
            }
        }
    }
}
