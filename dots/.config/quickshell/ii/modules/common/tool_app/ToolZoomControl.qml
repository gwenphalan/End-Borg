import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

RowLayout {
    id: root
    property real percent: 100
    property bool atReset: true
    property bool resetBeforeInput: false
    layoutDirection:resetBeforeInput ? Qt.RightToLeft : Qt.LeftToRight
    readonly property bool inputFocused: zoomInput.inputFocused
    signal zoomEdited(real percent)
    signal resetRequested()
    spacing: 8
    NumberInput {
        id: zoomInput
        objectName: "zoomPercentInput"
        number: root.percent
        minimum: 2; maximum: 3200; increment: 10; unit: "%"
        Accessible.name: "Zoom"
        onEdited: value => root.zoomEdited(value)
    }
    Item {
        implicitWidth:36; implicitHeight:36
        Layout.fillHeight:false
        IconToolbarButton {
        anchors.fill:parent
        activeFocusOnTab:false
        focusPolicy:Qt.ClickFocus
        objectName: "resetViewButton"
        implicitWidth: 36; implicitHeight: 36
        Layout.fillHeight: false
        buttonRadius: height/2
        text: "undo"
        Accessible.name: "Reset view · F"
        enabled: !root.atReset
        opacity: enabled ? 1 : 0.4
        onClicked: root.resetRequested()
        StyledToolTip {text: parent.Accessible.name}
        }
    }
}
