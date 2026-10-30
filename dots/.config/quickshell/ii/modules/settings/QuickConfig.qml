import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.settings.desktop
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root
    forceWidth: true
    topContentPadding: 0
    readonly property string wallpaperPath: {
        const revision = SettingsCatalog.revision;
        return SettingsCatalog.get("background.wallpaperPath") || "";
    }
    property string randomError: ""

    function selectWallpaper(path) {
        if (!path || !path.startsWith("/"))
            return;
        randomError = "";
        SettingsCatalog.write("background.wallpaperPath", path);
    }

    FileDialog {
        id: wallpaperDialog
        title: Translation.tr("Choose wallpaper")
        fileMode: FileDialog.OpenFile
        nameFilters: [Translation.tr(
                "Images and videos (*.png *.jpg *.jpeg *.webp *.avif *.gif *.bmp *.svg *.mp4 *.webm *.mkv *.mov)"),
            Translation.tr("All files (*)")]
        onAccepted: root.selectWallpaper(decodeURIComponent(String(selectedFile).replace(/^file:\/\//, "")))
    }

    Connections {
        target: SettingsCatalog
        function onDismissPopups() {
            wallpaperDialog.close();
        }
    }
    readonly property real wallpaperContentWidth: Math.max(0, Math.min(root.width - 40, root.baseWidth))

    Process {
        id: randomWallProc
        property string downloadedPath: ""
        property string scriptPath: `${Directories.scriptPath}/colors/random/random_konachan_wall.sh`
        command: ["bash", FileUtils.trimFileProtocol(scriptPath), "--download-only"]
        onStarted: {
            downloadedPath = "";
            root.randomError = "";
        }
        stdout: SplitParser {
            onRead: data => {
                if (data.startsWith("WALLPAPER_PATH="))
                    randomWallProc.downloadedPath = data.slice(15).trim();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && downloadedPath.startsWith("/"))
                root.selectWallpaper(downloadedPath);
            else
                root.randomError = Translation.tr("Could not download a wallpaper. Try again.");
        }
    }

    component SmallLightDarkPreferenceButton: RippleButton {
        id: smallLightDarkPreferenceButton
        required property bool dark
        property color colText: dark ? "#f7f4fa" : "#211d27"
        padding: 5
        Layout.fillWidth: true
        Layout.minimumHeight: 68
        buttonRadius: Appearance.rounding.normal
        toggled: SettingsCatalog.appearanceMode === (dark ? "dark" : "light")
        colBackground: dark ? "#3b3444" : "#eeeaf2"
        colBackgroundHover: dark ? "#494153" : "#f7f4fa"
        colBackgroundToggled: dark ? "#2d2636" : "#ffffff"
        colBackgroundToggledHover: dark ? "#393044" : "#ffffff"
        pointingHandCursor: true
        Accessible.role: Accessible.RadioButton
        Accessible.checked: toggled
        Accessible.name: dark ? Translation.tr("Dark") : Translation.tr("Light")
        onClicked: SettingsCatalog.setAppearanceMode(dark ? "dark" : "light")
        Rectangle {
            anchors.fill: parent
            radius: smallLightDarkPreferenceButton.buttonRadius
            color: "transparent"
            border.width: smallLightDarkPreferenceButton.toggled ? 2 : 0
            border.color: Appearance.m3colors.m3primary
            z: 10
        }
        contentItem: Item {
            anchors.centerIn: parent
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 30
                    text: dark ? "dark_mode" : "light_mode"
                    color: smallLightDarkPreferenceButton.colText
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: dark ? Translation.tr("Dark") : Translation.tr("Light")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: smallLightDarkPreferenceButton.colText
                }
            }
        }
    }

    // Wallpaper selection
    ColumnLayout {
        Layout.fillWidth: true
        spacing:8

        Item {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.preferredHeight: wallpaperControls.implicitHeight

            RowLayout {
                id: wallpaperControls
                anchors.centerIn: parent
                width: Math.min(parent.width, wallpaperCard.naturalWidth + 8 + 128)
                spacing: 8

            Item {
                id: wallpaperCard
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.maximumWidth: naturalWidth
                Layout.preferredWidth: naturalWidth
                Layout.alignment: Qt.AlignVCenter
                readonly property real sourceAspectRatio:wallpaperPreview.status===Image.Ready && wallpaperPreview.paintedWidth>0 && wallpaperPreview.paintedHeight>0 ? wallpaperPreview.paintedWidth/wallpaperPreview.paintedHeight : 16/9
                readonly property real naturalWidth:Math.min(250,144*sourceAspectRatio)
                implicitHeight:width/sourceAspectRatio
                Layout.preferredHeight:implicitHeight
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: Translation.tr("Choose wallpaper")
                Accessible.description: root.wallpaperPath ? root.wallpaperPath.split("/").pop() : Translation.tr("No wallpaper selected")
                Accessible.onPressAction: wallpaperDialog.open()
                Keys.onReturnPressed: event => { wallpaperDialog.open(); event.accepted = true; }
                Keys.onSpacePressed: event => { wallpaperDialog.open(); event.accepted = true; }
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: wallpaperCard.width
                        height: wallpaperCard.height
                        radius: Appearance.rounding.normal
                    }
                }

                Rectangle { anchors.fill:parent;color:Appearance.colors.colLayer2 }
                StyledImage {
                    id: wallpaperPreview
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    source: Qt.resolvedUrl(root.wallpaperPath)
                    // A stable decode request avoids reloading while the card adjusts to the image ratio.
                    sourceSize: Qt.size(250, 0)
                    Accessible.ignored: true
                    cache: false
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: wallpaperPreview.status !== Image.Ready
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: /\.(mp4|webm|mkv|mov)$/i.test(root.wallpaperPath) ? "videocam" : "wallpaper"
                        iconSize: 32
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.maximumWidth: wallpaperPreview.width - 24
                        Layout.alignment: Qt.AlignHCenter
                        text: root.wallpaperPath ? root.wallpaperPath.split("/").pop() : Translation.tr(
                                                       "Choose a wallpaper")
                        elide: Text.ElideMiddle
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    color: "#000000"
                    opacity: wallpaperMouse.containsMouse || wallpaperCard.activeFocus ? 0.45 : 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: wallpaperMouse.containsMouse || wallpaperCard.activeFocus
                    spacing: 5
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "add_photo_alternate"
                        iconSize: 30
                        color: "white"
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Choose file")
                        color: "white"
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Math.max(0, Appearance.rounding.normal - 2)
                    color: "transparent"
                    visible: wallpaperCard.activeFocus
                    border.width: 2
                    border.color: Appearance.m3colors.m3primary
                }
                MouseArea {
                    id: wallpaperMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: wallpaperDialog.open()
                }
            }

            ColumnLayout {
                Layout.preferredWidth: Math.min(128, Math.max(80, wallpaperControls.width - 88))
                Layout.minimumWidth: 80
                Layout.alignment: Qt.AlignVCenter
                spacing: 8
                SmallLightDarkPreferenceButton {
                    Layout.preferredHeight: 68
                    dark: false
                }
                SmallLightDarkPreferenceButton {
                    Layout.preferredHeight: 68
                    dark: true
                }
            }
        }
        }
        RowLayout {
            visible: {
                const revision = SettingsCatalog.revision;
                return SettingsCatalog.get("policies.weeb") === 1;
            }
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(386, root.wallpaperContentWidth - 32)
            spacing: 8
            RippleButtonWithIcon {
                enabled: !randomWallProc.running
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.small
                materialIcon: "ifl"
                mainText: randomWallProc.running ? Translation.tr("Be patient...") : Translation.tr("Random: Konachan")
                onClicked: {
                    randomWallProc.scriptPath = `${Directories.scriptPath}/colors/random/random_konachan_wall.sh`;
                    randomWallProc.running = true;
                }
                StyledToolTip {
                    text: Translation.tr("Random SFW Anime wallpaper from Konachan\nDownloaded wallpaper is applied when you save")
                }
            }
            RippleButtonWithIcon {
                enabled: !randomWallProc.running
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.small
                materialIcon: "ifl"
                mainText: randomWallProc.running ? Translation.tr("Be patient...") : Translation.tr("Random: osu! seasonal")
                onClicked: {
                    randomWallProc.scriptPath = `${Directories.scriptPath}/colors/random/random_osu_wall.sh`;
                    randomWallProc.running = true;
                }
                StyledToolTip {
                    text: Translation.tr("Random osu! seasonal background\nDownloaded wallpaper is applied when you save")
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.randomError !== ""
            text: root.randomError
            wrapMode: Text.WordWrap
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.small
            Accessible.role: Accessible.AlertMessage
        }
    }
}
