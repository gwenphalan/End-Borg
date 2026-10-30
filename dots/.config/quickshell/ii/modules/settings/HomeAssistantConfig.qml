pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.modules.settings.desktop
import qs.modules.ii.sidebarRight.home

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760
    horizontalContentPadding: 0
    readonly property bool settingsPreview: Quickshell.env("QS_SETTINGS_PREVIEW") === "1"
    Connections {
        target: HomeAssistant
        function onTokenSaveFinished(succeeded) {
            if (succeeded)
                tokenField.clear();
        }
    }
    Connections {
        target: Config.options.homeAssistant
        function onUrlChanged() {
            if (!urlField.activeFocus && SettingsCatalog.drafts["homeAssistant.url"] === undefined)
                urlField.text = Config.options.homeAssistant.url;
        }
    }
    readonly property var matchingDevices: HomeAssistant.entities.filter(e => !filter.text.trim() || (
                                                                                  HomeAssistant.name(e) + " "
                                                                                  + e.entity_id).toLowerCase(
                                                                                  ).includes(filter.text.trim(
                                                                                                 ).toLowerCase(
                                                                                                 )))
    readonly property bool connectionDirty: {
        const revision = SettingsCatalog.revision;
        return urlField.text.trim().replace(/\/+$/, "") !== String(Config.options.homeAssistant.url).trim().replace(/\/+$/,
                                                                                                                    "") || !Config.options.homeAssistant.enabled
                || SettingsCatalog.get("homeAssistant.enabled") !== Config.options.homeAssistant.enabled;
    }
    function preference(key) {
        const observed = SettingsCatalog.revision;
        return SettingsCatalog.get("homeAssistant." + key);
    }
    Connections {
        target: SettingsCatalog
        function onSaved() {
            if (!urlField.activeFocus)
                urlField.text = root.preference("url");
        }
        function onDiscarded() {
            urlField.text = root.preference("url");
        }
    }
    function togglePreference(key, id) {
        const path = "homeAssistant." + key;
        const values = Array.from(SettingsCatalog.get(path));
        SettingsCatalog.write(path, values.includes(id) ? values.filter(v => v !== id) : values.concat([id]));
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 20
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            StyledText {
                Layout.leftMargin: 20
                text: Translation.tr("Connection")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: connectionForm.implicitHeight + 40
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.normal
                ColumnLayout {
                    id: connectionForm
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        MaterialSymbol {
                            text: "link"
                            iconSize: 20
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Server address")
                        }
                    }
                    CompactTextField {
                        id: urlField
                        Layout.fillWidth: true
                        placeholderText: "https://home.example.com"
                        Component.onCompleted: text = SettingsCatalog.drafts["homeAssistant.url"]
                                               ?? root.preference("url")
                        onTextChanged: if (activeFocus) {
                                           if (text === root.preference("url"))
                                               SettingsCatalog.clearDraft("homeAssistant.url");
                                           else
                                               SettingsCatalog.saveDraft("homeAssistant.url", text);
                                       }
                        Keys.onReturnPressed: event => {
                            event.accepted = true;
                        }
                        Accessible.name: Translation.tr("Home Assistant server URL")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        MaterialSymbol {
                            text: "key"
                            iconSize: 20
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Access token")
                        }
                        IconToolbarButton {
                            text: "info"
                            implicitWidth: 28
                            implicitHeight: 28
                            Accessible.name: Translation.tr("About access tokens")
                            StyledToolTip {
                                text: Translation.tr(
                                          "Create a long-lived access token in your Home Assistant profile. It is saved in your unlocked desktop keyring.")
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        CompactTextField {
                            id: tokenField
                            Layout.fillWidth: true
                            enabled: !HomeAssistant.savingToken
                            echoMode: TextInput.Password
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                            placeholderText: HomeAssistant.token.length > 0 ? Translation.tr(
                                                                                  "Enter a replacement token") :
                                                                              Translation.tr(
                                                                                  "Long-lived access token")
                            Accessible.name: Translation.tr("Access token")
                        }
                        RippleButtonWithIcon {
                            implicitHeight: 40
                            materialIcon: "save"
                            mainText: HomeAssistant.savingToken ? Translation.tr("Saving…") : Translation.tr(
                                                                      "Save token")
                            enabled: !root.settingsPreview && !HomeAssistant.savingToken
                                     && tokenField.text.trim().length > 0
                            onClicked: HomeAssistant.saveToken(tokenField.text)
                        }
                    }
                    StyledText {
                        visible: HomeAssistant.credentialMessage.length > 0
                        text: HomeAssistant.credentialMessage
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        RippleButtonWithIcon {
                            implicitHeight: 40
                            materialIcon: "link"
                            mainText: Translation.tr("Connect")
                            enabled: !root.settingsPreview && !root.connectionDirty &&
                                     /^https?:\/\/[^\s]+$/.test(urlField.text.trim())
                            onClicked: HomeAssistant.reconnect()
                        }
                        DialogButton {
                            buttonText: Translation.tr("Refresh")
                            enabled: !root.settingsPreview && HomeAssistant.connected
                            onClicked: HomeAssistant.refresh()
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }
                    StyledText {
                        visible: root.connectionDirty
                        Layout.fillWidth: true
                        text: Translation.tr("Save settings before connecting to this server.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: HomeAssistant.connectionLabel
                        color: HomeAssistant.connected ? Appearance.colors.colPrimary :
                                                         Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        visible: HomeAssistant.connected && HomeAssistant.error.length > 0
                        Layout.fillWidth: true
                        text: HomeAssistant.error
                        color: Appearance.colors.colError
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            StyledText {
                Layout.leftMargin: 20
                text: Translation.tr("Devices")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: devices.implicitHeight + 32
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.normal
                ColumnLayout {
                    id: devices
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 12
                    SearchField {
                        id: filter
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Search devices")
                        Accessible.name: Translation.tr("Search devices")
                        Keys.onReturnPressed: event => {
                            event.accepted = true;
                        }
                    }
                    StyledText {
                        visible: !HomeAssistant.connected && HomeAssistant.entities.length === 0
                        text: Translation.tr("Connect Home Assistant to choose your devices.")
                        color: Appearance.colors.colSubtext
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        visible: HomeAssistant.connected && root.matchingDevices.length === 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: filter.text.trim() ? Translation.tr("No devices match your search.") :
                                                   Translation.tr(
                                                       "No devices were returned. Refresh to try again.")
                        color: Appearance.colors.colSubtext
                    }
                    ListView {
                        id: entityList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(360, contentHeight)
                        clip: true
                        spacing: 0
                        model: ScriptModel {
                            values: root.matchingDevices
                            objectProp: "entity_id"
                        }
                        ScrollBar.vertical: SpotlightScrollBar {
                            scrolling: entityList.moving
                        }
                        delegate: DialogListItem {
                            id: row
                            required property var modelData
                            width: ListView.view.width
                            implicitHeight: 64
                            horizontalPadding: 4
                            verticalPadding: 8
                            buttonRadius: Appearance.rounding.small
                            pointingHandCursor: false
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            contentItem: RowLayout {
                                spacing: 12
                                MaterialSymbol {
                                    Layout.preferredWidth: 24
                                    text: HomeAssistant.icon(row.modelData)
                                    iconSize: 20
                                    color: Appearance.colors.colSubtext
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: HomeAssistant.name(row.modelData)
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: row.modelData.entity_id + " • " + HomeAssistant.status(
                                                  row.modelData)
                                        textFormat: Text.PlainText
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }
                                RowLayout {
                                    spacing: 2
                                    HomeAction {
                                        symbol: root.preference("hiddenEntities").includes(
                                                    row.modelData.entity_id) ? "visibility_off" : "visibility"
                                        label: Translation.tr("Show / hide")
                                        onClicked: root.togglePreference("hiddenEntities",
                                                                         row.modelData.entity_id)
                                    }
                                    HomeAction {
                                        symbol: "star"
                                        label: Translation.tr("Favorite")
                                        accent: root.preference("favoriteEntities").includes(
                                                    row.modelData.entity_id)
                                        onClicked: root.togglePreference("favoriteEntities",
                                                                         row.modelData.entity_id)
                                    }
                                    HomeAction {
                                        symbol: "keep"
                                        label: Translation.tr("Default shortcut")
                                        enabled: HomeAssistant.canActivate(row.modelData)
                                        accent: root.preference("quickToggleEntities").includes(
                                                    row.modelData.entity_id)
                                        onClicked: root.togglePreference("quickToggleEntities",
                                                                         row.modelData.entity_id)
                                    }
                                    HomeAction {
                                        symbol: "toast"
                                        label: Translation.tr("Pin to top bar")
                                        enabled: HomeAssistant.canActivate(row.modelData)
                                        accent: root.preference("barControlEntities").includes(
                                                    row.modelData.entity_id)
                                        onClicked: root.togglePreference("barControlEntities",
                                                                         row.modelData.entity_id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            SettingsGroup {
                section: ({
                              title: Translation.tr("Shortcut order"),
                              resetEnabled: false,
                              items: ["homeAssistant.quickToggleEntities",
                                  "homeAssistant.barControlEntities"].map(path => ({
                                      kind: "preference",
                                      setting: SettingsCatalog.entry(path)
                                  }))
            })
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 16
            wrapMode: Text.Wrap
            text: Translation.tr(
                      "Pin devices above, then arrange their shortcut order. An empty top-bar list uses your default shortcuts.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
}
}
