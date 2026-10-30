import QtQuick
import qs.modules.common

// Quiet overlay reveal using the shared effects and spatial animation tokens.
Transition {
    id: root
    property bool entering: true
    property bool reducedMotion: Config.options.launcher.reducedMotion
    ParallelAnimation {
        NumberAnimation {
            property: "opacity"
            from: root.entering ? 0 : 1
            to: root.entering ? 1 : 0
            duration: root.reducedMotion ? 0 : Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        NumberAnimation {
            property: "scale"
            from: root.entering ? 0.97 : 1
            to: root.entering ? 1 : 0.97
            duration: root.reducedMotion ? 0 : Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }
}
