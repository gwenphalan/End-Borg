import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    required property var controller
    property bool shown: true
    property real targetWidth: 580
    property real targetHeight: 420
    property real layoutWidth: targetWidth
    property real layoutHeight: targetHeight
    readonly property real progress: motion.heightProgress
    property color surfaceColor: Appearance.colors.colBackgroundSurfaceContainer
    property real surfaceRadius: Appearance.rounding.large
    default property alias content: contentLayer.data
    readonly property real contentOpacity: motion.contentOpacity
    implicitWidth: layoutWidth
    implicitHeight: layoutHeight
    visible: motion.presented
    opacity: motion.edgeOpacity
    enabled: shown && progress > 0.85
    function inspect() {
        return {width: surface.width, height: surface.height,
            targetWidth, targetHeight, layoutWidth, layoutHeight,
            progress, widthProgress: motion.widthProgress,
            travelProgress: motion.travelProgress, contentOpacity};
    }
    Behavior on layoutWidth {
        enabled: root.visible && !root.controller.reducedMotion
        NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
        }
    }
    Behavior on layoutHeight {
        enabled: root.visible && !root.controller.reducedMotion
        NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
        }
    }
    SpotlightRevealMotion {
        id: motion
        controller: root.controller
        shown: root.shown
        parent: root
    }
    SpotlightMaterial {
        id: surface
        anchors.horizontalCenter: parent.horizontalCenter
        y: -64 * (1 - motion.travelProgress)
        width: root.layoutWidth * (0.28 + 0.72 * Math.max(0, motion.widthProgress))
        height: root.layoutHeight * Math.max(0, root.progress)
        radius: root.surfaceRadius
        baseColor: root.surfaceColor
        clip: true
        MouseArea { anchors.fill: parent }
        Item {
            id: contentLayer
            x: (parent.width - width) / 2
            width: root.layoutWidth
            height: root.layoutHeight
            opacity: root.contentOpacity
        }
    }
}
