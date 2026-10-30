import QtQuick
import qs.modules.common

// Keep an editor alive during collapse, then unload it after its last visible frame.
Item {
    id: root
    property bool expanded: false
    property bool reducedMotion: Config.options.launcher.reducedMotion
    readonly property bool active: body.active
    readonly property var item: body.item
    property alias sourceComponent: body.sourceComponent
    visible: expanded || implicitHeight > 0
    enabled: expanded
    clip: true
    implicitHeight: expanded && item ? item.implicitHeight : 0
    opacity: expanded ? 1 : 0
    Loader {
        id: body
        width: root.width
        active: root.expanded || root.implicitHeight > 0
        // Let the editor keep its natural height while the wrapper clips the reveal.
    }
    Behavior on implicitHeight {
        enabled: !root.reducedMotion
        NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }
    Behavior on opacity {
        enabled: !root.reducedMotion
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
}
