pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id: root
    readonly property bool settingsPreview: Quickshell.env("QS_SETTINGS_PREVIEW") === "1"
    property string result: ""
    property string selectedLocale: {
        const revision = SettingsCatalog.revision;
        const language = SettingsCatalog.get("language.ui");
        return language === "auto" ? Qt.locale().name : String(language || Qt.locale().name);
    }
    spacing: 14

    Process {
        id: translation
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, locale]
        onExited: (exitCode, exitStatus) => root.result = exitCode === 0
            ? Translation.tr("Translation generated. It is now available in the language selector.")
            : Translation.tr("Translation generation failed. Check your Gemini key and connection, then try again.")
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Requires a Gemini API key in the AI sidebar.")
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Target language")
        }
        SettingsLocalePicker {
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            enabled: !translation.running
            value: root.selectedLocale
            label: Translation.tr("language")
            onChosen: value => root.selectedLocale = value
        }
    }
    RowLayout {
        Layout.fillWidth: true
        RippleButtonWithIcon {
            materialIcon: translation.running ? "hourglass_top" : "translate"
            mainText: translation.running ? Translation.tr("Generating…") : Translation.tr("Generate translation")
            enabled: !root.settingsPreview && !translation.running && /^[a-z]{2,3}(?:[_-][A-Za-z]{2,4}){0,2}$/.test(root.selectedLocale)
            onClicked: {
                root.result = "";
                translation.locale = root.selectedLocale;
                translation.running = true;
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: translation.running ? Translation.tr("This may take a few minutes. Keep this window open.") : root.result
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
        }
    }
}
