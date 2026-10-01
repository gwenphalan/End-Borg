import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter

    readonly property bool isRecording: RecordingService.isRecording

    readonly property int fixedRecordingWidth: 154
    readonly property int collapsedWidth: 26
    readonly property real extraWidth: isRecording ? (fixedRecordingWidth - collapsedWidth) : 0

    implicitHeight: 26
    implicitWidth: isRecording ? fixedRecordingWidth : collapsedWidth
    width: implicitWidth
    clip: false

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animationCurves.expressiveFastSpatialDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    function triggerRecord() {
        if (root.isRecording) {
            RecordingService.stop();
        } else {
            RecordingService.start();
        }
    }

    // Collapsed state: standard 26px circle button matching all other utility buttons
    CircleUtilButton {
        id: collapsedButton
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        visible: opacity > 0
        opacity: root.isRecording ? 0 : 1
        scale: root.isRecording ? 0.6 : 1.0
        enabled: !root.isRecording

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animationCurves.expressiveFastSpatialDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        onClicked: root.triggerRecord()

        MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Qt.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
            fill: 1
            text: "videocam"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer2
        }
    }

    // Active Recording state controls subpill (only visible while recording)
    Item {
        id: expandedPill
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        height: 26
        width: root.width
        clip: true
        visible: opacity > 0
        opacity: root.isRecording ? 1 : 0
        enabled: root.isRecording

        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        Rectangle {
            id: pillBackground
            anchors.fill: parent
            radius: Math.min(width, height) / 2
            color: ColorUtils.transparentize(Appearance.m3colors.m3secondaryContainer, 0.4)
            border.width: 0

            Behavior on color {
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        RowLayout {
            id: recordingRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.fixedRecordingWidth
            height: parent.height
            spacing: 0

            // 1. Red recording indicator dot
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 12
                implicitWidth: 8
                implicitHeight: 8

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Appearance.colors.colError

                    Behavior on color {
                        animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    SequentialAnimation on opacity {
                        running: RecordingService.isRecording && !RecordingService.isPaused
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 750; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 750; easing.type: Easing.InOutSine }
                    }
                }
            }

            // 2. Fixed-width record length in tabular digits font
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 8
                Layout.rightMargin: 10
                implicitWidth: 62
                implicitHeight: timeText.implicitHeight

                StyledText {
                    id: timeText
                    anchors.centerIn: parent
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                    color: RecordingService.isPaused ? Appearance.colors.colOutline : Appearance.colors.colOnSecondaryContainer
                    text: RecordingService.formattedTimeFull
                }
            }

            // 3. Pause / resume circle button
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 4
                implicitWidth: 22
                implicitHeight: 22

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: pauseMouseArea.containsPress ? Appearance.colors.colSecondaryContainerActive :
                           pauseMouseArea.containsMouse ? Appearance.colors.colSecondaryContainerHover : "transparent"
                    Behavior on color {
                        animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    fill: 1
                    text: RecordingService.isPaused ? "play_arrow" : "pause"
                    iconSize: 16
                    color: Appearance.colors.colOnSecondaryContainer
                }

                ButtonMouseArea {
                    id: pauseMouseArea
                    anchors.fill: parent
                    onClicked: RecordingService.togglePause()
                }
            }

            // 4. Stop circle button
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 6
                implicitWidth: 22
                implicitHeight: 22

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: stopMouseArea.containsPress ? ColorUtils.transparentize(Appearance.colors.colError, 0.4) :
                           stopMouseArea.containsMouse ? ColorUtils.transparentize(Appearance.colors.colError, 0.7) : "transparent"
                    Behavior on color {
                        animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    fill: 1
                    text: "stop"
                    iconSize: 16
                    color: Appearance.colors.colError
                }

                ButtonMouseArea {
                    id: stopMouseArea
                    anchors.fill: parent
                    onClicked: RecordingService.stop()
                }
            }
        }
    }
}
