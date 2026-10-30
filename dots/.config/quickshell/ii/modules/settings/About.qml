pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.ii.overview
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    clip: true
    contentHeight: content.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: SpotlightScrollBar { scrolling: root.moving }

    readonly property real identityWidth: Math.min(640, Math.max(0, root.width - 48))
    readonly property var distroLinks: [
        {title: Translation.tr("Website"), icon: "language", url: SystemInfo.homeUrl},
        {title: Translation.tr("Documentation"), icon: "menu_book", url: SystemInfo.documentationUrl},
        {title: Translation.tr("Help & support"), icon: "help", url: SystemInfo.supportUrl},
        {title: Translation.tr("Report a bug"), icon: "bug_report", url: SystemInfo.bugReportUrl},
        {title: Translation.tr("Privacy policy"), icon: "policy", url: SystemInfo.privacyPolicyUrl}
    ].filter(link => /^https?:\/\//.test(link.url))
    readonly property var shellLinks: [
        {title: Translation.tr("Documentation"), icon: "menu_book", url: "https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/"},
        {title: Translation.tr("Source code"), icon: "code", url: "https://github.com/end-4/dots-hyprland"},
        {title: Translation.tr("Issues"), icon: "bug_report", url: "https://github.com/end-4/dots-hyprland/issues"},
        {title: Translation.tr("Discussions"), icon: "forum", url: "https://github.com/end-4/dots-hyprland/discussions"},
        {title: Translation.tr("Support the project"), icon: "favorite", url: "https://github.com/sponsors/end-4"}
    ]

    component IdentityBlock: ColumnLayout {
        id: block
        required property string identityName
        required property string subtitle
        required property string logoSource
        required property string fallbackIcon
        required property var links
        Layout.preferredWidth: root.identityWidth
        Layout.alignment: Qt.AlignHCenter
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 24
            Image {
                id: logo
                Layout.preferredWidth: 96
                Layout.preferredHeight: 96
                Layout.alignment: Qt.AlignVCenter
                source: block.logoSource
                sourceSize.width: 192
                sourceSize.height: 192
                fillMode: Image.PreserveAspectFit
                Accessible.ignored: true
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: logo.status === Image.Error
                    text: block.fallbackIcon
                    iconSize: 72
                    color: Appearance.colors.colPrimary
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                StyledText {
                    Layout.fillWidth: true
                    text: block.identityName
                    font.pixelSize: Appearance.font.pixelSize.title
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignLeft
                }
                StyledText {
                    Layout.fillWidth: true
                    text: block.subtitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.normal
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignLeft
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            spacing: 8
            visible: block.links.length > 0
            Repeater {
                model: block.links
                delegate: RippleButton {
                    id: linkButton
                    required property var modelData
                    implicitHeight: 38
                    implicitWidth: linkContent.implicitWidth + 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.m3colors.m3surfaceContainer
                    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHighest
                    Accessible.name: modelData.title
                    onClicked: Qt.openUrlExternally(modelData.url)
                    contentItem: RowLayout {
                        id: linkContent
                        spacing: 7
                        MaterialSymbol {
                            text: linkButton.modelData.icon
                            iconSize: 17
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: linkButton.modelData.title
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                    StyledToolTip { text: linkButton.modelData.url }
                }
            }
        }
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: 44

        IdentityBlock {
            Layout.topMargin: 28
            identityName: SystemInfo.distroName
            subtitle: [SystemInfo.desktopEnvironment, SystemInfo.windowingSystem].filter(Boolean).join(" • ")
            logoSource: Quickshell.shellPath(SystemInfo.distroId === "cachyos" ? "assets/icons/cachyos-logo.svg" : "assets/icons/" + SystemInfo.distroIcon + ".svg")
            fallbackIcon: "desktop_windows"
            links: root.distroLinks
        }
        IdentityBlock {
            Layout.bottomMargin: 28
            identityName: "illogical-impulse"
            subtitle: Translation.tr("end-4 dotfiles • Quickshell")
            logoSource: Quickshell.shellPath("assets/icons/illogical-impulse-logo.svg")
            fallbackIcon: "folder_managed"
            links: root.shellLinks
        }
    }
}
