import QtQuick
import qs.modules.common

// Shared effects timing for short, interruptible property transitions.
PropertyAnimation {
    duration: Appearance.animation.elementMoveFast.duration
    easing.type: Appearance.animation.elementMoveFast.type
    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
}
