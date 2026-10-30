import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    required property var controller
    property real availableWidth: 700
    readonly property real baseWidth: Math.min(Appearance.sizes.searchWidthCollapsed + 112, availableWidth)
    readonly property real finalWidth: Math.min(600, availableWidth)
    readonly property real inputWidth: Math.max(80, finalWidth - 130)
    readonly property real reveal: Math.max(0, Math.min(1, controller.presence))
    readonly property real spatialProgress: Math.max(0, controller.presence)
    readonly property real contentsReveal: Math.max(0, Math.min(1, controller.barReveal))
    property real contentsOpacity: controller.barExpanded ? 1 : 0
    property real expansion: controller.query.length > 0 && controller.inputFocused ? 1 : 0
    property alias input: field
    readonly property real presentedWidth: surface.width
    readonly property real presentedY: surface.y
    readonly property real inputOffset: 8 + 52 * inputMotion.progress
    signal moveFocusDown()
    implicitWidth: finalWidth
    implicitHeight: 72
    SpotlightContentMotion {
        id: inputMotion
        shown: root.controller.barExpanded
        reducedMotion: root.controller.reducedMotion
    }
    SpotlightContentMotion {
        id: iconMotion
        shown: root.controller.searchShown
        reducedMotion: root.controller.reducedMotion
    }
    Behavior on contentsOpacity {
        NumberAnimation {
            duration: root.controller.reducedMotion ? 0 : Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on expansion {
        NumberAnimation {
            duration: root.controller.motionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.controller.entranceCurve
        }
    }
    function focusInput() {
        controller.engageSearch();
        field.forceActiveFocus();
        field.cursorPosition = field.length;
    }
    function insertText(text) {
        focusInput();
        field.insert(field.cursorPosition, text);
        controller.edit(field.text);
    }
    Connections {
        target: root.controller
        function onQueryChanged() {
            if (field.text !== root.controller.query) field.text = root.controller.query;
        }
        function onInputFocusedChanged() {
            if (!root.controller.inputFocused) field.focus = false;
        }
    }
    SpotlightMaterial {
        id: surface
        baseColor: Appearance.colors.colBackgroundSurfaceContainer
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8 - 72 * (1 - root.spatialProgress)
        width: 56 + (root.baseWidth + (root.finalWidth - root.baseWidth) * root.expansion - 56) * Math.max(0, root.controller.barReveal)
        height: 56
        radius: height / 2
        clip: true
        MouseArea { anchors.fill: parent; onClicked: root.focusInput() }

        // The clipping viewport changes size. The input itself never does.
        Item {
            x: 8 + 52 * inputMotion.progress
            y: 8
            width: Math.max(0, surface.width - 120)
            height: 40
            clip: true
            opacity: root.contentsOpacity
            TextField {
                id: field
                width: root.inputWidth
                height: 40
                text: root.controller.query
                color: Appearance.colors.colOnSurface
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.small
                placeholderText: Translation.tr("Search...")
                placeholderTextColor: Appearance.colors.colOnSurfaceVariant
                background: Item {}
                selectByMouse: true
                activeFocusOnTab: false
                cursorVisible: activeFocus && root.controller.inputFocused
                Keys.forwardTo: [root.controller.keyRouter]
                TapHandler { onTapped: root.controller.engageSearch() }
                onTextEdited: {
                    root.controller.edit(text);
                }
                onAccepted: {
                    const entry = LauncherSearch.results[0];
                    if (entry) {
                        root.controller.close();
                        entry.execute();
                    }
                }
                Keys.onDownPressed: root.moveFocusDown()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_PageDown) {
                        root.moveFocusDown();
                        event.accepted = true;
                    }
                }
            }
        }
        IconToolbarButton {
            id: modeButton
            x: 8 + (surface.width - width - 20) * inputMotion.progress
            implicitWidth: implicitHeight + (down ? 6 : 0)
            Behavior on implicitWidth {
                NumberAnimation {
                    duration: root.controller.reducedMotion ? 0 : Appearance.animation.clickBounce.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
                }
            }
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.contentsOpacity
            enabled: root.contentsReveal > 0.9
            text: root.controller.modeIcon
            Keys.forwardTo: [root.controller.keyRouter]
            Accessible.name: root.controller.mode + ". " + Translation.tr("Switch to") + " " + root.controller.nextMode
            scale: down ? 0.9 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: root.controller.reducedMotion ? 0 : Appearance.animation.clickBounce.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
                }
            }
            onClicked: root.controller.cycleMode()
            StyledToolTip { text: root.controller.mode + " · " + Translation.tr("Switch to") + " " + root.controller.nextMode + " (Tab)" }
        }
        MaterialShapeWrappedMaterialSymbol {
            id: star
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            iconSize: 28
            shape: MaterialShape.Shape.Cookie7Sided
            text: "search"
            scale: 0.82 + 0.18 * iconMotion.progress
            transform: Translate { y: 10 * (1 - iconMotion.progress) }
            opacity: root.reveal
            MouseArea {
                anchors.fill: parent
                onClicked: root.focusInput()
            }
        }
    }
}
