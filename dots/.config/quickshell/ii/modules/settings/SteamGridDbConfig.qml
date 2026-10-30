pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.desktop
import qs.services

ContentPage {
    id: root
    forceWidth: true
    readonly property bool settingsPreview: Quickshell.env("QS_SETTINGS_PREVIEW") === "1"
    property string credentialState: Translation.tr("Not checked")
    readonly property bool iconSettingsDirty: {
        const revision = SettingsCatalog.revision;
        return SettingsCatalog.get("appearance.steamGridDb.enabled") !== Config.options.appearance.steamGridDb.enabled;
    }
    property int cachedIcons: 0
    Connections {
        target: SteamGridDb
        function onFinished(operation, succeeded, result) {
            if (operation === "status" && succeeded) {
                root.credentialState = result.credential;
                root.cachedIcons = result.cached_icons;
            }
            if (operation === "set_key" && succeeded) {
                keyField.clear();
                root.credentialState = "available";
            }
            if (operation === "refresh" && result) root.cachedIcons = result.cached_icons;
        }
    }
    Connections {
        target: Config.options.appearance.steamGridDb
        function onEnabledChanged() { if (Config.ready && !root.settingsPreview) SteamGridDb.queueRebuild(); }
    }
    Component.onCompleted: SteamGridDb.status()
    Component.onDestruction: keyField.clear()

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: controls.implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            clip: true
            ColumnLayout {
                id: controls
                width: parent.width
                spacing: 0
                SettingRow {
                    Layout.fillWidth: true
                    grouped: true
                    compact: true
                    setting: SettingsCatalog.entry("appearance.steamGridDb.enabled")
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.topMargin: 12
                    Layout.bottomMargin: 12
                    spacing: 12
                    MaterialSymbol { text: "vpn_key"; iconSize: 20; color: Appearance.colors.colSubtext }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("API key")
                        color: Appearance.colors.colOnLayer2
                    }
                    CompactTextField {
                        id: keyField
                        Layout.preferredWidth: Math.min(300, Math.max(130, root.width * 0.42))
                        enabled: !root.settingsPreview && !SteamGridDb.busy
                        maximumLength: 512
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        placeholderText: Translation.tr("Replacement key")
                        Accessible.name: Translation.tr("SteamGridDB API key")
                        Keys.onReturnPressed: event => {
                            if (saveKey.enabled) SteamGridDb.storeKey(text);
                            event.accepted = true;
                        }
                    }
                    IconToolbarButton {
                        id: saveKey
                        implicitWidth: 40
                        implicitHeight: 40
                        Layout.fillHeight: false
                        text: "save"
                        colBackground: Appearance.colors.colLayer3
                        enabled: !root.settingsPreview && !!keyField.text.trim() && !SteamGridDb.busy
                        Accessible.name: Translation.tr("Save API key to keyring")
                        onClicked: SteamGridDb.storeKey(keyField.text)
                        StyledToolTip { text: Translation.tr("Save key to keyring") }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.topMargin: 16
                    Layout.bottomMargin: 16
                    spacing: 12
                    MaterialSymbol { text: "lock"; iconSize: 20; color: Appearance.colors.colSubtext }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Keyring"); color: Appearance.colors.colOnLayer2 }
                    StyledText { text: Translation.tr(root.credentialState); color: Appearance.colors.colSubtext }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.topMargin: 16
                    Layout.bottomMargin: 16
                    spacing: 12
                    MaterialSymbol { text: "image"; iconSize: 20; color: Appearance.colors.colSubtext }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Cached game icons"); color: Appearance.colors.colOnLayer2 }
                    StyledText { text: root.cachedIcons; color: Appearance.colors.colSubtext }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.preferredHeight: childrenRect.height
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.bottomMargin: 16
                    spacing: 8
                    RippleButtonWithIcon {
                        buttonRadius: Appearance.rounding.full
                        materialIcon: "key"
                        mainText: Translation.tr("Check keyring")
                        colBackground: Appearance.colors.colLayer3
                        enabled: !SteamGridDb.busy
                        onClicked: SteamGridDb.status()
                    }
                    RippleButtonWithIcon {
                        buttonRadius: Appearance.rounding.full
                        materialIcon: "cloud_done"
                        mainText: Translation.tr("Test connection")
                        colBackground: Appearance.colors.colLayer3
                        enabled: !root.settingsPreview && !SteamGridDb.busy
                        onClicked: SteamGridDb.testConnection()
                    }
                    RippleButtonWithIcon {
                        buttonRadius: Appearance.rounding.full
                        materialIcon: "refresh"
                        mainText: Translation.tr("Refresh icons")
                        colBackground: Appearance.colors.colLayer3
                        enabled: !root.settingsPreview && !root.iconSettingsDirty && Config.options.appearance.steamGridDb.enabled && !SteamGridDb.busy && !Config.saving
                        onClicked: SteamGridDb.refresh()
                    }
                }
            }
        }
        StyledText {
            visible: SteamGridDb.message.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            text: SteamGridDb.message
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}
