import QtQuick
import qs.modules.common

Item {
    id: root
    property bool shown: false
    property bool reducedMotion: false
    property real distance: 24
    property bool initialized: false
    property real progress: initialized && shown ? 1 : 0
    readonly property real offset: reducedMotion ? 0 : distance * (1 - progress)
    Component.onCompleted: initialized = true
    Behavior on progress {
        id: progressBehavior
        NumberAnimation {
            duration: root.reducedMotion ? 0 : progressBehavior.targetValue === 1
                ? Appearance.animation.elementMoveSmall.duration : Appearance.animation.elementMoveExit.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: progressBehavior.targetValue === 1
                ? Appearance.animation.elementMoveSmall.bezierCurve : Appearance.animation.elementMoveExit.bezierCurve
        }
    }
}
