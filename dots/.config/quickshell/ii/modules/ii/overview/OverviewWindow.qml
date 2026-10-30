pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Item { // Window
    id: root
    property var toplevel
    property var windowData
    property var monitorData
    property real previewScale: 0.18
    property bool captureEnabled: false
    property bool reducedMotion: false
    property real iconLift: pressed ? 1 : hovered ? -4 : 0
    Behavior on iconLift {
        NumberAnimation {
            duration: root.reducedMotion ? 0 : Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
        }
    }
    readonly property bool previewHasContent: windowPreview.hasContent
    property bool restrictToWorkspace: true
    property real widthRatio: {
        if (!widgetMonitor || !monitorData) return 1;
        const widgetWidth = widgetMonitor.transform & 1 ? widgetMonitor.height : widgetMonitor.width;
        const monitorWidth = monitorData.transform & 1 ? monitorData.height : monitorData.width;
        return (widgetWidth * monitorData.scale) / (Math.max(1, monitorWidth) * widgetMonitor.scale);
    }
    property real heightRatio: {
        if (!widgetMonitor || !monitorData) return 1;
        const widgetHeight = widgetMonitor.transform & 1 ? widgetMonitor.width : widgetMonitor.height;
        const monitorHeight = monitorData.transform & 1 ? monitorData.width : monitorData.height;
        return (widgetHeight * monitorData.scale) / (monitorHeight * widgetMonitor.scale);
    }
    property real initX: {
        return Math.max((windowData?.at[0] - (monitorData?.x ?? 0) - monitorData?.reserved[0]) * widthRatio * root.previewScale, 0) + xOffset;
    }

    property real initY: {
        return Math.max((windowData?.at[1] - (monitorData?.y ?? 0) - monitorData?.reserved[1]) * heightRatio * root.previewScale, 0) + yOffset;
    }
    property real xOffset: 0
    property real yOffset: 0
    property var widgetMonitor
    property int widgetMonitorId: widgetMonitor?.id ?? -1

    property var targetWindowWidth: windowData?.size[0] * previewScale * widthRatio
    property var targetWindowHeight: windowData?.size[1] * previewScale * heightRatio
    property bool hovered: false
    property bool pressed: false

    property bool centerIcons: Config.options.overview.centerIcons
    property real iconGapRatio: 0.06
    property real iconToWindowRatio: centerIcons ? 0.35 : 0.15
    property real xwaylandIndicatorToIconRatio: 0.35
    property real iconToWindowRatioCompact: 0.6
    readonly property string rawIconName: AppSearch.guessIcon(windowData?.class)
    property bool compactMode: Appearance.font.pixelSize.smaller * 4 > targetWindowHeight || Appearance.font.pixelSize.smaller * 4 > targetWindowWidth

    property bool indicateXWayland: windowData?.xwayland ?? false

    x: initX
    y: initY
    width: targetWindowWidth
    height: targetWindowHeight
    opacity: windowData?.monitor == widgetMonitorId ? 1 : 0.4

    property real topLeftRadius
    property real topRightRadius
    property real bottomLeftRadius
    property real bottomRightRadius

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomRightRadius: root.bottomRightRadius
            bottomLeftRadius: root.bottomLeftRadius
        }
    }

    Behavior on x {
        enabled: !root.pressed
        NumberAnimation {
            duration: root.reducedMotion ? 0 : Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
        }
    }
    Behavior on y {
        enabled: !root.pressed
        NumberAnimation {
            duration: root.reducedMotion ? 0 : Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
        }
    }

    ScreencopyView {
        id: windowPreview
        anchors.fill: parent
        captureSource: root.captureEnabled ? root.toplevel : null
        live: true

        // Color overlay for interactions
        Rectangle {
            anchors.fill: parent
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomRightRadius: root.bottomRightRadius
            bottomLeftRadius: root.bottomLeftRadius
            color: pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5) :
                hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7) :
                ColorUtils.transparentize(Appearance.colors.colLayer2)
            border.color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.88)
            border.width: 1
            Behavior on color {
                ColorAnimation {
                    duration: root.reducedMotion ? 0 : Appearance.animation.elementMoveFast.duration
                }
            }
        }

        AdaptiveAppIcon {
            id: windowIconContainer
            transform: Translate { y: root.iconLift }
            appId: root.windowData?.class ?? ""
            iconName: root.rawIconName
            appName: root.windowData?.class ?? ""
            hovered: root.hovered
            pressed: root.pressed
            property real baseSize: Math.min(root.targetWindowWidth, root.targetWindowHeight)
            anchors {
                top: root.centerIcons ? undefined : parent.top
                left: root.centerIcons ? undefined : parent.left
                centerIn: root.centerIcons ? parent : undefined
                margins: baseSize * root.iconGapRatio
            }
            property var iconSize: {
                return baseSize * (root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio);
            }
            width: iconSize
            height: iconSize

        }
    }
}
