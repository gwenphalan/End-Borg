import QtQuick
import QtQuick.Controls
import qs.modules.common

Popup {
    parent:Overlay.overlay
    z:1000
    padding:6
    focus:true
    closePolicy:Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background:Rectangle {
        color:Appearance.colors.colLayer1Base
        radius:Appearance.rounding.small
        border.width:1
        border.color:Appearance.colors.colOutlineVariant
    }
}
