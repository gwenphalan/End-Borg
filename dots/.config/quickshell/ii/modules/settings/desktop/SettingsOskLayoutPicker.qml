pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import "../../ii/onScreenKeyboard/layouts.js" as Layouts

// Use the keyboard's own supported-layout inventory; never offer nonexistent layouts.
Item {
    id:root
    required property string value
    property string label:Translation.tr("Keyboard layout")
    signal chosen(string value)
    readonly property var choices:Object.keys(Layouts.byName).map(name => ({name:Translation.tr(name),value:name}))
    function open() { picker.open(); }
    implicitWidth:picker.implicitWidth
    implicitHeight:picker.implicitHeight
    SettingsChoicePicker {
        id:picker
        anchors.fill:parent
        choices:root.choices
        value:Layouts.byName[root.value] ? root.value : Layouts.defaultLayout
        label:root.label
        onChosen:value => root.chosen(String(value))
    }
}
