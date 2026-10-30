pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.settings.desktop as Settings

// Choices: [{name, value, icon, separatorBefore?, enabled?}]. The host owns mode semantics.
Settings.SettingsPresetDropdown {
    implicitWidth: 170
    implicitHeight: 32
    Layout.fillWidth: false
    label: "Mode"
    activeFocusOnTab: false
    focusPolicy: Qt.ClickFocus
}
