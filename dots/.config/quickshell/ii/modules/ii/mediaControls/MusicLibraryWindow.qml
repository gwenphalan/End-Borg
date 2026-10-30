pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
PanelWindow {
    id:root
    signal dismissed()
    property alias content:library
    implicitWidth:Math.min(800,screen.width-48)
    implicitHeight:Math.min(700,screen.height-80)
    exclusiveZone:0
    WlrLayershell.namespace:"quickshell:music-library"
    WlrLayershell.keyboardFocus:WlrKeyboardFocus.Exclusive
    color:"transparent"
    Rectangle {
        opacity:0
        Component.onCompleted:opacity=1
        Behavior on opacity { animation:Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        anchors.fill:parent;color:Appearance.colors.colLayer0;radius:Appearance.rounding.normal;border.width:1;border.color:Appearance.colors.colLayer0Border
        MusicLibrary { id:library;anchors.fill:parent;anchors.margins:20;onDismissed:root.dismissed();focus:true;Keys.onEscapePressed:root.dismissed() }
    }
}
