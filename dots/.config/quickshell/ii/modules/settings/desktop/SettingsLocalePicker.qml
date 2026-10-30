pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import "LocaleChoices.js" as Locales

// Shared searchable locale control. Translation files use underscores; calendar locales use hyphens.
Item {
    id: root
    required property string value
    property string label: Translation.tr("language")
    property string separator: "_"
    property bool allowSystemDefault: false
    property var extraLocales: []
    readonly property var choices: {
        const locales = Locales.buildChoices(code => Qt.locale(code),
            Translation.allAvailableLanguages.concat(extraLocales, [value, Qt.locale().name]), separator);
        return allowSystemDefault ? [{name:Translation.tr("System default"), value:"auto"}].concat(locales) : locales;
    }
    signal chosen(string value)
    function open() { picker.open(); }
    implicitWidth: picker.implicitWidth
    implicitHeight: picker.implicitHeight

    SettingsChoicePicker {
        id: picker
        anchors.fill: parent
        choices: root.choices
        value: root.allowSystemDefault && (!root.value || root.value === "auto") ? "auto" : Locales.normalizedCode(root.value, root.separator)
        label: root.label
        displayText: {
            if (root.allowSystemDefault && (!root.value || root.value === "auto")) return Translation.tr("System default");
            const locale=Qt.locale(root.value);
            return locale.name!=="C" ? locale.nativeLanguageName : root.value;
        }
        onChosen: value => root.chosen(String(value))
    }
}
