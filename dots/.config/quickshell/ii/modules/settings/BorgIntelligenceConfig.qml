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
    baseWidth: 760
    horizontalContentPadding: 0
    readonly property bool settingsPreview: Quickshell.env("QS_SETTINGS_PREVIEW") === "1"
    readonly property bool connectionDirty: {
        const revision = SettingsCatalog.revision;
        return ["enabled", "endpoint", "textModel", "visionModel", "timeoutSeconds", "iconAssistance"].some(
                    key => SettingsCatalog.drafts["borgIntelligence." + key] !== undefined || JSON.stringify(
                               SettingsCatalog.get("borgIntelligence." + key)) !== JSON.stringify(
                               SettingsCatalog.get("borgIntelligence." + key, Config.options)));
    }
    property var models: []
    property bool modelsChecked: false
    property string credentialState: "Not checked"
    Connections {
        target: BorgIntelligence
        function onFinished(operation, succeeded, result, error) {
            if (operation === "status" && succeeded)
                root.credentialState = result.credential;
            if (operation === "models" && succeeded) {
                root.models = result.models;
                root.modelsChecked = true;
            }
            if (operation === "set_key" && succeeded) {
                keyField.clear();
                root.credentialState = "available";
            }
        }
    }
    Component.onCompleted: BorgIntelligence.status()

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 20
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            SettingsGroup {
                section: ({
                              title: Translation.tr("Connection"),
                              resetEnabled: false,
                              items: ["enabled", "endpoint", "textModel", "visionModel", "timeoutSeconds",
                                  "iconAssistance"].map(key => ({
                                      kind: "preference",
                                      setting: SettingsCatalog.entry("borgIntelligence." + key)
                                  }))
            })
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: credentials.implicitHeight + 40
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.normal
            ColumnLayout {
                id: credentials
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 12
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
                        text: Translation.tr("API key")
                    }
                    StyledText {
                        text: root.credentialState === "available" ? Translation.tr("Saved") : Translation.tr(root.credentialState)
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    CompactTextField {
                        id: keyField
                        Layout.fillWidth: true
                        enabled: !BorgIntelligence.busy
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        placeholderText: Translation.tr("Paste key")
                        Accessible.name: Translation.tr("Gateway API key")
                    }
                    RippleButtonWithIcon {
                        implicitHeight: 40
                        materialIcon: "save"
                        mainText: Translation.tr("Save key")
                        enabled: !root.settingsPreview && !!keyField.text && !BorgIntelligence.busy
                        onClicked: {
                            if (BorgIntelligence.storeKey(keyField.text))
                                keyField.clear();
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    DialogButton {
                        buttonText: Translation.tr("Check credential")
                        onClicked: BorgIntelligence.status()
                    }
                    DialogButton {
                        buttonText: Translation.tr("Discover models")
                        enabled: !root.settingsPreview && !root.connectionDirty && !BorgIntelligence.busy
                        onClicked: BorgIntelligence.models()
                    }
                    DialogButton {
                        buttonText: Translation.tr("Improve launcher")
                        enabled: !root.settingsPreview && !root.connectionDirty
                                 && Config.options.borgIntelligence.enabled && !BorgIntelligence.busy
                        onClicked: BorgIntelligence.improveLauncher()
                    }
                    DialogButton {
                        buttonText: Translation.tr("Clear icon cache")
                        enabled: !root.settingsPreview
                        onClicked: BorgIntelligence.clearCache()
                    }
                }
                StyledText {
                    visible: root.connectionDirty
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("Save connection settings before discovering models.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                StyledText {
                    visible: root.modelsChecked
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.models.length ? Translation.tr("Available models: %1").arg(root.models.join(
                                                                                              ", ")) : Translation.tr("No models found")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                StyledText {
                    visible: !!BorgIntelligence.message && BorgIntelligence.message !== "Request completed"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: BorgIntelligence.message
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }
}
}
