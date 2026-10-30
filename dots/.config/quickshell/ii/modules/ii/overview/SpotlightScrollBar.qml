import QtQuick
import QtQuick.Controls
import qs.modules.common

ScrollBar {
    id: root
    property int motionDuration: 140
    property bool reducedMotion: false
    property bool scrolling: false
    property int hideDelay: 1000
    readonly property bool interacting: pressed || hovered || active || scrolling
    onInteractingChanged: {
        if (interacting) linger.stop();
        else linger.restart();
    }
    Timer { id:linger; interval:root.hideDelay }
    policy: ScrollBar.AsNeeded
    hoverEnabled: true
    implicitWidth: 14
    minimumSize: 0.06
    padding: 3
    contentItem: Item {
        implicitWidth: 8
        Rectangle {
            anchors.right: parent.right
            width: root.pressed || root.hovered ? 8 : 4
            height: parent.height
            radius: width / 2
            color: root.pressed ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
            opacity: root.size < 1 ? (root.pressed ? 1 : root.hovered ? 0.8 : root.interacting || linger.running ? 0.5 : 0) : 0
            Behavior on width {
                NumberAnimation {
                    duration: root.reducedMotion ? 0 : Appearance.animation.elementMoveSmall.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                }
            }
            Behavior on color { ColorAnimation { duration: root.motionDuration } }
            Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : root.motionDuration } }
        }
    }
}
