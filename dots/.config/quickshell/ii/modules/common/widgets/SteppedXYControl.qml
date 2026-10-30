pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

// Shared two-axis control. Values quantize immediately; only the indicator eases.
Item {
    id: root
    property string xIcon: "width"
    property string yIcon: "format_bold"
    property string xLabel: "Width"
    property string yLabel: "Weight"
    property string unavailableText: "Unavailable"
    property string xSuffix: "%"
    property string ySuffix: ""
    property int xDecimals: 0
    property int yDecimals: 0
    property real xValue: 100
    property real yValue: 400
    property real minimumX: 25
    property real maximumX: 151
    property real minimumY: 1
    property real maximumY: 1000
    property real xStep: 1
    property real yStep: 1
    property bool xSupported: true
    property bool ySupported: true
    property int cancelRevision: 0
    property bool fineAdjusting: false
    property bool motionReady: false
    property int gridDivisions: 8
    property int motionDuration: 160
    property bool reducedMotion: Config.options.launcher.reducedMotion
    property bool gesturing: false
    property real liveX: xValue
    property real liveY: yValue
    readonly property real plotInset: 38
    readonly property real plotWidth: Math.max(1, width - plotInset * 2)
    readonly property real plotHeight: Math.max(1, width - plotInset * 2)
    readonly property bool anyAxisSupported: xSupported || ySupported
    signal began
    signal previewed(real xValue, real yValue)
    signal committed(real xValue, real yValue)
    signal cancelled
    implicitWidth: 270
    implicitHeight: width + 32
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: xLabel + " and " + yLabel
    Accessible.description: "Drag to adjust. Arrow keys adjust one axis. Escape cancels."
    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }
    function quantized(value, min, max, fine) {
        if (fine || min === max)
            return value;
        const grid = (max - min) / gridDivisions;
        return min + Math.round((value - min) / grid) * grid;
    }
    function rounded(value, decimals) {
        const factor = Math.pow(10, decimals);
        return Math.round(value * factor) / factor;
    }
    FrameAnimation {
        running: !root.motionReady
        property int settledFrames: 0
        onTriggered: {
            settledFrames++;
            if (settledFrames >= 2)
                root.motionReady = true;
        }
    }
    function at(x, y, fine) {
        if (!anyAxisSupported)
            return;
        fineAdjusting = fine;
        liveX = xSupported ? rounded(quantized(minimumX + clamp((x - plotInset) / plotWidth, 0, 1) * (maximumX
                                                                                                      - minimumX),
                                               minimumX, maximumX, fine), Math.max(xDecimals, 2)) : xValue;
        liveY = ySupported ? rounded(quantized(maximumY - clamp((y - plotInset) / plotHeight, 0, 1) * (
                                                   maximumY - minimumY), minimumY, maximumY, fine), Math.max(
                                         yDecimals, 1)) : yValue;
        previewed(liveX, liveY);
    }
    function adjust(dx, dy, fine) {
        if (!anyAxisSupported || (dx !== 0 && !xSupported) || (dy !== 0 && !ySupported))
            return;
        fineAdjusting = fine;
        began();
        committed(xSupported ? clamp(xValue + dx * xStep * (fine ? .2 : 1), minimumX, maximumX) : xValue,
                  ySupported ? clamp(yValue + dy * yStep * (fine ? .2 : 1), minimumY, maximumY) : yValue);
    }
    function cancel() {
        if (!gesturing)
            return;
        gesturing = false;
        cancelled();
    }
    onCancelRevisionChanged: cancel()
    Keys.onEscapePressed: cancel()
    Keys.onLeftPressed: event => adjust(-1, 0, !!(event.modifiers & Qt.ShiftModifier))
    Keys.onRightPressed: event => adjust(1, 0, !!(event.modifiers & Qt.ShiftModifier))
    Keys.onUpPressed: event => adjust(0, 1, !!(event.modifiers & Qt.ShiftModifier))
    Keys.onDownPressed: event => adjust(0, -1, !!(event.modifiers & Qt.ShiftModifier))

    Rectangle {
        id: padSurface
        objectName: "steppedXYSurface"
        width: root.width
        height: width
        radius: 18
        color: Appearance.colors.colLayer2
    }
    Repeater {
        objectName: "steppedXYDots"
        model: root.xSupported && root.ySupported ? (root.gridDivisions + 1) * (root.gridDivisions + 1) :
               root.anyAxisSupported ? root.gridDivisions + 1 : 0
        Rectangle {
            required property int index
            x: root.xSupported ? root.plotInset + (index % (root.gridDivisions + 1)) * root.plotWidth
                                 / root.gridDivisions - width / 2 : (root.width - width) / 2
            y: root.ySupported ? root.plotInset + (root.xSupported ? Math.floor(index / (
                                                                                          root.gridDivisions + 1)) :
                                                                  index) * root.plotHeight / root.gridDivisions
                                 - height / 2 : (padSurface.height - height) / 2
            width: root.xSupported && root.ySupported ? 2 : 3
            height: width
            radius: width / 2
            color: Appearance.colors.colSubtext
            opacity: root.xSupported && root.ySupported ? .22 : .45
        }
    }
    MaterialSymbol {
        id: yAxisIcon
        visible: root.ySupported
        anchors {
            top: padSurface.top
            horizontalCenter: padSurface.horizontalCenter
            topMargin: 8
        }
        text: root.yIcon
        iconSize: 20
        color: Appearance.colors.colSubtext
        opacity: root.ySupported ? 1 : .45
        HoverHandler {
            id: yAxisHover
        }
        StyledToolTip {
            extraVisibleCondition: yAxisHover.hovered
            text: root.yLabel + (root.ySupported ? "" : " — " + root.unavailableText)
            delay: 600
        }
    }
    MaterialSymbol {
        id: xAxisIcon
        visible: root.xSupported
        anchors {
            left: padSurface.left
            verticalCenter: padSurface.verticalCenter
            leftMargin: 8
        }
        text: root.xIcon
        iconSize: 20
        color: Appearance.colors.colSubtext
        opacity: root.xSupported ? 1 : .45
        HoverHandler {
            id: xAxisHover
        }
        StyledToolTip {
            extraVisibleCondition: xAxisHover.hovered
            text: root.xLabel + (root.xSupported ? "" : " — " + root.unavailableText)
            delay: 600
        }
    }
    Row {
        anchors {
            top: padSurface.bottom
            horizontalCenter: padSurface.horizontalCenter
            topMargin: 8
        }
        spacing: 8
        MaterialSymbol {
            visible: root.ySupported
            text: root.yIcon
            iconSize: 16
            color: Appearance.colors.colSubtext
            opacity: root.ySupported ? 1 : .45
        }
        StyledText {
            visible: root.ySupported
            text: root.ySupported ? root.yValue.toFixed(root.yDecimals).replace(/\.0+$/, "") + root.ySuffix :
                                    "—"

            font.pixelSize: 12
            color: Appearance.colors.colSubtext
        }
        Item {
            visible: root.xSupported && root.ySupported
            width: 8
            height: 1
        }
        MaterialSymbol {
            visible: root.xSupported
            text: root.xIcon
            iconSize: 16
            color: Appearance.colors.colSubtext
            opacity: root.xSupported ? 1 : .45
        }
        StyledText {
            visible: root.xSupported
            text: root.xSupported ? root.xValue.toFixed(root.xDecimals).replace(/\.0+$/, "") + root.xSuffix :
                                    "—"

            font.pixelSize: 12
            color: Appearance.colors.colSubtext
        }
    }
    Rectangle {
        objectName: "steppedXYIndicator"
        visible: root.anyAxisSupported
        width: 18
        height: 18
        radius: 9
        x: root.xSupported ? root.plotInset + root.clamp((root.xValue - root.minimumX) / (root.maximumX
                                                                                          - root.minimumX
                                                                                          || 1), 0, 1)
                             * root.plotWidth - width / 2 : (root.width - width) / 2
        y: root.ySupported ? root.plotInset + (1 - root.clamp((root.yValue - root.minimumY) / (root.maximumY
                                                                                               - root.minimumY
                                                                                               || 1), 0, 1))
                             * root.plotHeight - height / 2 : (padSurface.height - height) / 2
        color: Appearance.m3colors.m3primary
        Behavior on x {
            enabled: root.motionReady && !root.reducedMotion && !root.fineAdjusting
            NumberAnimation {
                duration: root.motionDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on y {
            enabled: root.motionReady && !root.reducedMotion && !root.fineAdjusting
            NumberAnimation {
                duration: root.motionDuration
                easing.type: Easing.OutCubic
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 5
            height: 5
            radius: 2.5
            color: Appearance.m3colors.m3onPrimary
        }
    }
    MouseArea {
        id: pointer
        objectName: "steppedXYPointer"
        anchors.fill: padSurface
        preventStealing: true
        cursorShape: root.anyAxisSupported ? Qt.CrossCursor : Qt.ArrowCursor
        onPressed: event => {
            if (!root.anyAxisSupported)
                return;
            root.forceActiveFocus();
            root.gesturing = true;
            root.began();
            root.at(event.x, event.y, !!(event.modifiers & Qt.ShiftModifier));
        }
        onPositionChanged: event => {
            if (pressed && root.gesturing)
                root.at(event.x, event.y, !!(event.modifiers & Qt.ShiftModifier));
        }
        onReleased: {
            if (root.gesturing) {
                root.gesturing = false;
                root.committed(root.liveX, root.liveY);
            }
        }
        onCanceled: root.cancel()
    }
    Rectangle {
        anchors.fill: padSurface
        radius: padSurface.radius
        color: "transparent"
        border.width: root.activeFocus ? 1 : 0
        border.color: Appearance.m3colors.m3primary
    }
}
