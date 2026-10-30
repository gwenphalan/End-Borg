import QtQuick
import qs.modules.common

// Short, interruptible motion for small visual changes.
NumberAnimation {
    duration: Appearance.animation.elementMoveFast.duration
    easing.type: Appearance.animation.elementMoveFast.type
    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
}
