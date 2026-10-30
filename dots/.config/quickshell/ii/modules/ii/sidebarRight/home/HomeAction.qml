import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

IconToolbarButton {
    id: root

    property string symbol: ""
    property string label: ""
    property bool accent: false

    text: symbol
    toggled: accent
    implicitWidth: 40
    implicitHeight: 40
    Layout.fillHeight: false
    Accessible.name: label

    StyledToolTip {
        text: root.label
        extraVisibleCondition: false
        alternativeVisibleCondition: root.isHovered || root.activeFocus
    }

}
