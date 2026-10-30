import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

// Compact operation control; floating editing tools keep their larger targets.
IconToolbarButton {
    id:root
    activeFocusOnTab:false
    focusPolicy:Qt.ClickFocus
    property real iconSize:18
    implicitWidth:28
    implicitHeight:28
    Layout.fillWidth:false
    Layout.fillHeight:false
    opacity:enabled ? 1 : .4
    contentItem:MaterialSymbol {
        anchors.centerIn:parent
        horizontalAlignment:Text.AlignHCenter
        verticalAlignment:Text.AlignVCenter
        text:root.text
        iconSize:root.iconSize
        color:root.colText
        animateChange:true
    }
}
