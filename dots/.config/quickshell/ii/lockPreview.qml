//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.lock

// Standalone visual preview. It does not instantiate LockScreen or WlSessionLock;
// preview guards prevent authentication and session actions.
ApplicationWindow {
    id: preview
    visible: true
    width: 1280
    height: 720
    minimumWidth: 720
    minimumHeight: 480
    title: "Lock screen preview"
    color: Appearance.colors.colLayer0
    property bool bedtimePreview: true
    property bool delayLimitReached: Quickshell.env("QS_LOCK_PREVIEW_DISABLED") === "1"
    property bool clockStateReady: false

    // This singleton belongs to this separate qs -p process only. It selects
    // the real clock widget's locked style and placement.
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        GlobalStates.screenLocked = true;
        GlobalStates.bedtimeLockActive = true;
        GlobalStates.bedtimeLockDeadlineText = "9:00 AM";
        GlobalStates.bedtimePasswordRevealed = !bedtimePreview;
        clockStateReady = true;
    }
    onBedtimePreviewChanged: GlobalStates.bedtimePasswordRevealed = !bedtimePreview
    onDelayLimitReachedChanged: {
        if (clockStateReady && Quickshell.env("QS_LOCK_PREVIEW_TOGGLE_CAPTURE"))
            toggleCapture.restart();
    }
    onActiveChanged: if (active) previewKeyboard.forceActiveFocus()

    Item {
        id: previewKeyboard
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Alt) {
                preview.delayLimitReached = !preview.delayLimitReached;
                event.accepted = true;
            }
        }
    }

    Shortcut {
        sequence: "Tab"
        context: Qt.WindowShortcut
        onActivated: preview.bedtimePreview = !preview.bedtimePreview
    }

    Timer {
        running: !!Quickshell.env("QS_LOCK_PREVIEW_CAPTURE")
        interval: 3000
        repeat: false
        onTriggered: canvas.grabToImage(result => {
            result.saveToFile(Quickshell.env("QS_LOCK_PREVIEW_CAPTURE"));
        })
    }
    Timer {
        id: toggleCapture
        interval: 500
        repeat: false
        onTriggered: canvas.grabToImage(result => {
            result.saveToFile(Quickshell.env("QS_LOCK_PREVIEW_TOGGLE_CAPTURE"));
        })
    }

    LockContext {
        id: previewContext
        previewMode: true
    }

    Item {
        id: canvas
        readonly property real previewScale: Math.min(preview.contentItem.width / width,
                                                      preview.contentItem.height / height)
        width: 1920
        height: 1080
        x: (preview.contentItem.width - width * previewScale) / 2
        y: (preview.contentItem.height - height * previewScale) / 2
        transform: Scale {
            origin.x: 0
            origin.y: 0
            xScale: canvas.previewScale
            yScale: canvas.previewScale
        }
        clip: true

        Image {
            id: wallpaper
            anchors.fill: parent
            source: Config.options.background.wallpaperPath
            fillMode: Image.PreserveAspectCrop
            visible: !blurLayer.active
        }
        Loader {
            id: blurLayer
            anchors.fill: wallpaper
            active: Config.options.lock.blur.enable
            scale: Config.options.lock.blur.extraZoom
            sourceComponent: GaussianBlur {
                source: wallpaper
                radius: Config.options.lock.blur.radius
                samples: radius * 2 + 1

                Rectangle {
                    anchors.fill: parent
                    color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: "#58000000"
            opacity: GlobalStates.bedtimePasswordRevealed ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: 350
                    easing.type: Easing.InOutCubic
                }
            }
        }

        Loader {
            // The real shell initializes DateTime before the user locks. A
            // standalone preview must wait, or ClockText's entry animation
            // retains a position from the uninitialized layout.
            active: preview.clockStateReady && Config.ready
                    && DateTime.time.length > 0 && DateTime.longDate.length > 0
            sourceComponent: ClockWidget {
                screenWidth: canvas.width
                screenHeight: canvas.height
                scaledScreenWidth: canvas.width
                scaledScreenHeight: canvas.height
                wallpaperScale: 1
                bedtimeActive: true
                bedtimeDeadlineText: "9:00 AM"
            }
        }

        // The same toolbar component as the secure lock, with all interactive
        // actions gated inside LockSurface and a final input shield above it.
        LockSurface {
            anchors.fill: parent
            context: previewContext
            previewMode: true
            bedtimeActive: true
            passwordRevealed: !preview.bedtimePreview
            bedtimeDeadlineText: "9:00 AM"
            bedtimeDelayUntilText: "3:00 AM"
            bedtimeDelaysRemaining: preview.delayLimitReached ? 0 : 1
            bedtimeDelayAllowed: !preview.delayLimitReached
        }

        MouseArea {
            anchors.fill: parent
            z: 100
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => mouse.accepted = true
        }
    }

    StyledText {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        text: preview.bedtimePreview ? "Bedtime lock preview · "
                                      + (preview.delayLimitReached ? "Delay limit reached" : "Delay available")
                                      + " · Alt toggles · Tab switches"
                                      : "Regular lock preview · Tab to switch"
        color: Appearance.colors.colOnLayer0
        font.pixelSize: Appearance.font.pixelSize.small
    }
}
