import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

Dialog {
    id:root
    property real preferredWidth:620
    parent:Overlay.overlay
    width:Math.min(preferredWidth,parent ? parent.width-48 : preferredWidth)
    anchors.centerIn:parent
    padding:24
    modal:true
    focus:true
    closePolicy:Popup.CloseOnEscape
    enter:OverlayTransition {}
    exit:OverlayTransition {entering:false}
    Overlay.modal:Rectangle {color:Appearance.colors.colScrim}
    background:Rectangle {
        color:Appearance.m3colors.m3surfaceContainerHigh
        radius:Appearance.rounding.normal
    }
    header:StyledText {
        visible:text!==""
        text:root.title
        leftPadding:24;rightPadding:24;topPadding:24;bottomPadding:8
        horizontalAlignment:Text.AlignHCenter
        wrapMode:Text.Wrap
        font.pixelSize:Appearance.font.pixelSize.huge
        font.weight:Font.Bold
    }
}
