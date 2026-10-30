import QtQuick
import qs.modules.common

Item {
    id: root
    required property var controller
    required property bool shown
    property real widthProgress: shown ? 1 : 0
    property real heightProgress: shown ? 1 : 0
    property real travelProgress: shown ? 1 : 0
    property real contentOpacity: shown ? 1 : 0
    readonly property bool presented: shown || widthProgress !== 0 || heightProgress !== 0 || travelProgress !== 0
    readonly property real edgeOpacity: Math.max(0, Math.min(1, heightProgress / 0.06))

    // Spatial channels may overshoot; opacity and clipping must not flatten that settle.
    Behavior on widthProgress {
        id: widthBehavior
        NumberAnimation {
            duration: root.controller.reducedMotion ? 0 : widthBehavior.targetValue === 1 ? Appearance.animation.elementMoveSmall.duration : root.controller.exitDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: widthBehavior.targetValue === 1 ? Appearance.animation.elementMoveSmall.bezierCurve : root.controller.exitCurve
        }
    }
    Behavior on heightProgress {
        id: heightBehavior
        NumberAnimation {
            duration: heightBehavior.targetValue === 1 ? root.controller.panelEntranceDuration : root.controller.exitDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: heightBehavior.targetValue === 1 ? Appearance.animation.clickBounce.bezierCurve : root.controller.exitCurve
        }
    }
    Behavior on travelProgress {
        id: travelBehavior
        NumberAnimation {
            duration: travelBehavior.targetValue === 1 ? root.controller.searchEntranceDuration : root.controller.exitDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: travelBehavior.targetValue === 1 ? Appearance.animation.elementMove.bezierCurve : root.controller.exitCurve
        }
    }
    Behavior on contentOpacity {
        NumberAnimation {
            duration: root.controller.reducedMotion ? 0 : Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
}
