import QtQuick
import qs.modules.common

NumberAnimation {
    property bool reducedMotion:Config.options.launcher.reducedMotion
    duration:reducedMotion ? 0 : Appearance.animation.elementMove.duration
    easing.type:Easing.BezierSpline
    easing.bezierCurve:Appearance.animationCurves.emphasized
}
