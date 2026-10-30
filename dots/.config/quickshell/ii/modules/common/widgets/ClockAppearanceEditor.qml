pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.services

ColumnLayout {
    id: root
    property var clockFont: ({
                                 family: "Google Sans Flex",
                                 size: 96,
                                 weight: 350,
                                 width: 100,
                                 roundness: 0,
                                 letterSpacing: 0
                             })
    property var displayFont: clockFont
    property string wallpaperPath: ""
    property color clockColor: Appearance.colors.colOnSecondaryContainer
    property string timeFormat: Config.options.time.format
    property bool verticalClock: Config.options.background.widgets.clock.digital.vertical
    readonly property string currentTime: Qt.locale().toString(DateTime.clock.date, timeFormat)
    readonly property string verticalHours: currentTime.split(":")[0].padStart(2, "0")
    readonly property string verticalMinutes: currentTime.split(":").slice(1).join(":").trim()
    property var fontChoices: ClockFonts.choices
    readonly property var curatedFamilies: fontChoices.map(f => ClockFonts.choiceId(f))
    readonly property var choices: fontChoices
    readonly property var fontFamilies: choices.map(f => ClockFonts.choiceId(f))
    readonly property var sizeSteps: [48, 60, 72, 84, 96, 108, 120, 144, 168, 192, 216, 240]
    readonly property var controlValues: ClockFonts.controls(displayFont)
    readonly property string selectedFamily: displayFont.family || "Google Sans Flex"
    readonly property bool weightSupported: ClockFonts.supportsAxis(selectedFamily, "wght")
    readonly property bool widthSupported: ClockFonts.supportsAxis(selectedFamily, "wdth")
    readonly property bool roundnessSupported: ClockFonts.supportsAxis(selectedFamily, "ROND")
                                               || ClockFonts.supportsAxis(selectedFamily, "SOFT")
                                               || ClockFonts.supportsAxis(selectedFamily, "soft")
    property bool sizeFine: false
    property bool gesturing: false
    property var originalFont: ({})
    property int cancelRevision: 0
    property bool sizeSliderBlocked: false
    property bool sizeGesture: false
    property bool initialized: false
    // Animate the presentation only; gestures and persisted values stay snapped.
    readonly property bool previewMotion: initialized && !Config.options.launcher.reducedMotion
    property real previewSize: number("size", 96)
    property real previewWeight: number("weight", 400)
    property real previewWidth: number("width", 100)
    property real previewRoundness: number("roundness", 0)
    property real previewSpacing: number("letterSpacing", 0)
    component PreviewTransition: NumberAnimation {
        duration: 160
        easing.type: Easing.OutCubic
    }
    Behavior on previewSize { enabled: root.previewMotion; PreviewTransition {} }
    Behavior on previewWeight { enabled: root.previewMotion; PreviewTransition {} }
    Behavior on previewWidth { enabled: root.previewMotion; PreviewTransition {} }
    Behavior on previewRoundness { enabled: root.previewMotion; PreviewTransition {} }
    Behavior on previewSpacing { enabled: root.previewMotion; PreviewTransition {} }
    signal previewed(var fontChanges)
    signal committed(var fontChanges)
    signal cancelled
    signal resetRequested
    implicitWidth: 760
    spacing: 16

    function merged(base, changes) {
        return Object.assign({}, base, changes);
    }
    function number(key, fallback) {
        const v = Number(displayFont[key]);
        return Number.isFinite(v) ? v : fallback;
    }
    function nearestSize(size) {
        let best = 0;
        for (let i = 1; i < sizeSteps.length; i++)
            if (Math.abs(sizeSteps[i] - size) < Math.abs(sizeSteps[best] - size))
                best = i;
        return best;
    }
    function sizePosition(size) {
        if (size <= sizeSteps[0])
            return 0;
        for (let i = 1; i < sizeSteps.length; i++)
            if (size <= sizeSteps[i])
                return i - 1 + (size - sizeSteps[i - 1]) / (sizeSteps[i] - sizeSteps[i - 1]);
        return sizeSteps.length - 1;
    }
    function sizeValue(position) {
        position = Math.max(0, Math.min(sizeSteps.length - 1, position));
        if (!sizeFine)
            return sizeSteps[Math.round(position)];
        const lo = Math.floor(position), hi = Math.min(lo + 1, sizeSteps.length - 1);
        return Math.round(sizeSteps[lo] + (sizeSteps[hi] - sizeSteps[lo]) * (position - lo));
    }
    function begin() {
        if (gesturing)
            return;
        originalFont = Object.assign({}, clockFont);
        displayFont = Object.assign({}, clockFont);
        gesturing = true;
    }
    function preview(changes) {
        if (!gesturing)
            begin();
        displayFont = merged(displayFont, changes);
        previewed(changes);
    }
    function commit(changes) {
        displayFont = merged(displayFont, changes);
        gesturing = false;
        sizeGesture = false;
        committed(changes);
    }
    function cancel() {
        sizeSlider.pendingEdit = false;
        sizeSliderBlocked = sizeSlider.pressed;
        sizeGesture = false;
        if (!gesturing)
            return;
        displayFont = originalFont;
        gesturing = false;
        cancelRevision++;
        cancelled();
    }
    function chooseFont(choice) {
        cancel();
        if (typeof choice === "string")
            choice = {
                family: choice
            };
        const change = {
            family: choice.family,
            italic: !!choice.italic
        };
        displayFont = merged(clockFont, change);
        committed(change);
    }
    function supportedChanges(values) {
        const changes = ClockFonts.fromControls(values);
        if (!weightSupported)
            delete changes.weight;
        if (!widthSupported)
            delete changes.width;
        if (!roundnessSupported)
            delete changes.roundness;
        return changes;
    }
    onClockFontChanged: {
        if (gesturing)
            cancel();
        displayFont = clockFont;
    }
    onEnabledChanged: if (!enabled)
                          cancel()
    Keys.onEscapePressed: cancel()
    Component.onCompleted: initialized = true
    Component.onDestruction: {
        if (gesturing)
            cancelled();
    }

    Rectangle {
        id: previewCard
        Layout.fillWidth: true
        Layout.preferredHeight: 224
        Layout.minimumHeight: 224
        Layout.maximumHeight: 224
        objectName: "typographyPreviewCard"
        radius: 20
        color: Appearance.colors.colLayer3
        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: previewCard.width
                height: previewCard.height
                radius: previewCard.radius
            }
        }
        Image {
            anchors.fill: parent
            source: root.wallpaperPath ? Qt.resolvedUrl(root.wallpaperPath) : ""
            sourceSize: Qt.size(1000, 0)
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
        }
        Rectangle {
            anchors.fill: parent
            color: "#18000000"
        }
        Item {
            id: previewViewport
            anchors.fill: parent
            anchors.margins: 16
            Item {
                id: previewClock
                objectName: "typographyPreviewComposition"
                x: (previewViewport.width - width) / 2
                y: (previewViewport.height - height) / 2
                width: implicitWidth
                height: implicitHeight
                implicitWidth: Math.max(face.implicitWidth, minutesFace.visible ? minutesFace.implicitWidth : 0)
                implicitHeight: minutesFace.visible ? minutesFace.y + minutesFace.height : face.height
                transform: Scale {
                    origin.x: previewClock.width / 2
                    origin.y: previewClock.height / 2
                    xScale: Math.min(.5, previewViewport.width / Math.max(1, previewClock.implicitWidth),
                                     previewViewport.height / Math.max(1, previewClock.implicitHeight))
                    yScale: xScale
                }
                ClockFace {
                    id: face
                    objectName: "typographyPreviewClock"
                    width: previewClock.width
                    text: root.verticalClock ? root.verticalHours : root.currentTime
                    clockFont: root.merged(root.displayFont, {
                                               size: root.previewSize,
                                               weight: root.previewWeight,
                                               width: root.previewWidth,
                                               roundness: root.previewRoundness,
                                               letterSpacing: root.previewSpacing
                                           })
                    color: root.clockColor
                    horizontalAlignment: Text.AlignHCenter
                    animateChange: false
                }
                ClockFace {
                    id: minutesFace
                    objectName: "typographyPreviewMinutes"
                    width: previewClock.width
                    y: face.height + 4 - Math.max(0, Math.min(40,
                        face.implicitHeight - face.inkBounds.height - 8))
                    visible: root.verticalClock
                    text: root.verticalMinutes
                    clockFont: face.clockFont
                    color: root.clockColor
                    horizontalAlignment: Text.AlignHCenter
                    animateChange: false
                }
            }
        }
    }
    Flickable {
        id: fontStrip
        objectName: "typographyFontStrip"
        Layout.fillWidth: true
        Layout.preferredHeight: 78
        contentWidth: fontRow.width
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        property Item hoveredTile: null
        Row {
            id: fontRow
            x: Math.max(0, (fontStrip.width - width) / 2)
            spacing: 10
            Repeater {
                id: fontRepeater
                model: root.choices
                delegate: Item {
                    id: fontTile
                    required property var modelData
                    width: Math.max(56, Math.min(86, (fontStrip.width - 10 * (root.choices.length - 1))
                                                 / root.choices.length))
                    height: 70
                    objectName: "fontChoice_" + ClockFonts.choiceId(modelData)
                    readonly property bool selected: ClockFonts.matches(modelData, root.displayFont)
                    activeFocusOnTab: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.name || modelData.family
                    Accessible.checked: selected
                    Keys.onReturnPressed: root.chooseFont(modelData)
                    Keys.onSpacePressed: root.chooseFont(modelData)
                    ClockFace {
                        id: sample
                        objectName: "fontSample_" + ClockFonts.choiceId(fontTile.modelData)
                        text: "12"
                        calibrationText: "12"
                        clockFont: ({
                                        family: fontTile.modelData.family,
                                        italic: !!fontTile.modelData.italic,
                                        size: 50,
                                        weight: 400,
                                        width: 100,
                                        roundness: 0,
                                        letterSpacing: 0
                                    })
                        x: (fontTile.width - inkBounds.width) / 2 - inkBounds.x
                        y: (fontTile.height - inkBounds.height) / 2 - inkBounds.y
                        color: Appearance.colors.colOnLayer2
                    }
                    MouseArea {
                        id: fontPointer
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: fontStrip.hoveredTile = fontTile
                        onExited: if (fontStrip.hoveredTile === fontTile)
                                      fontStrip.hoveredTile = null
                        onClicked: root.chooseFont(fontTile.modelData)
                    }
                    StyledToolTip {
                        extraVisibleCondition: fontPointer.containsMouse || fontTile.activeFocus
                        text: fontTile.modelData.name || fontTile.modelData.family
                        delay: 600
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: "transparent"
                        border.width: fontTile.activeFocus ? 1 : 0
                        border.color: Appearance.m3colors.m3primary
                    }
                }
            }
        }
        SelectionIndicator {
            x: fontRow.x
            y: fontRow.y
            width: fontRow.width
            height: fontRow.height
            z: -1
            container: fontRow
            radius: 12
            selectedItem: {
                for (let i = 0; i < fontRepeater.count; i++) {
                    const tile = fontRepeater.itemAt(i);
                    if (tile && tile.selected)
                        return tile;
                }
                return null;
            }
            hoveredItem: fontStrip.hoveredTile
            selectedColor: "transparent"
            selectedBorderWidth: 2
            selectedBorderColor: Appearance.m3colors.m3primary
            hoverColor: Appearance.m3colors.m3secondaryContainer
        }
        HoverHandler {
            onHoveredChanged: if (!hovered)
                                  fontStrip.hoveredTile = null
        }
        ScrollBar.horizontal: ScrollBar {
            height: 3
            policy: fontStrip.contentWidth > fontStrip.width ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }
    }
    RowLayout {
        id: pads
        Layout.alignment: Qt.AlignHCenter
        spacing: 16
        readonly property real padSize: Math.min(284, (root.width - 16) / 2)
        SteppedXYControl {
            id: shapePad
            objectName: "typographyShapePad"
            visible: root.roundnessSupported || root.weightSupported
            Layout.preferredWidth: pads.padSize
            Layout.preferredHeight: pads.padSize + 32
            cancelRevision: root.cancelRevision
            xLabel: "Roundness"
            yLabel: "Weight"
            xIcon: "rounded_corner"
            yIcon: "format_bold"
            xSuffix: "%"
            ySuffix: "%"
            xDecimals: 1
            yDecimals: 1
            xValue: root.controlValues.roundness
            yValue: root.controlValues.weight
            xSupported: root.roundnessSupported
            ySupported: root.weightSupported
            unavailableText: "Not supported by this font"
            minimumX: 0
            maximumX: 100
            minimumY: -100
            maximumY: 100
            xStep: 12.5
            yStep: 25
            onBegan: root.begin()
            onPreviewed: (x, y) => root.preview(root.supportedChanges({
                                                                            roundness: x,
                                                                            weight: y
                                                                        }))
            onCommitted: (x, y) => root.commit(root.supportedChanges({
                                                                           roundness: x,
                                                                           weight: y
                                                                       }))
            onCancelled: root.cancel()
        }
        SteppedXYControl {
            id: detailsPad
            objectName: "typographyDetailsPad"
            Layout.preferredWidth: pads.padSize
            Layout.preferredHeight: pads.padSize + 32
            cancelRevision: root.cancelRevision
            xLabel: "Spacing"
            yLabel: "Width"
            xIcon: "format_letter_spacing"
            yIcon: "width"
            xSuffix: "%"
            ySuffix: "%"
            xDecimals: 1
            yDecimals: 1
            xValue: root.controlValues.spacing
            yValue: root.controlValues.width
            xSupported: true
            ySupported: root.widthSupported
            unavailableText: "Not supported by this font"
            minimumX: 0
            maximumX: 100
            minimumY: -100
            maximumY: 100
            xStep: 12.5
            yStep: 25
            onBegan: root.begin()
            onPreviewed: (x, y) => root.preview(root.supportedChanges({
                                                                            spacing: x,
                                                                            width: y
                                                                        }))
            onCommitted: (x, y) => root.commit(root.supportedChanges({
                                                                           spacing: x,
                                                                           width: y
                                                                       }))
            onCancelled: root.cancel()
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        StyledText {
            text: "Size"
            font.pixelSize: 14
        }
        CommittedSlider {
            id: sizeSlider
            objectName: "typographySizeSlider"
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            from: 0
            to: root.sizeSteps.length - 1
            stepSize: root.sizeFine ? 1 / 24 : 1
            snapMode: root.sizeFine ? Slider.NoSnap : Slider.SnapAlways
            fineAdjusting: root.sizeFine
            value: root.sizePosition(root.number("size", 96))
            stopIndicatorValues: root.sizeSteps.map((_, i) => i)
            usePercentTooltip: false
            tooltipContent: root.sizeValue(value) + " px"
            Keys.onEscapePressed: root.cancel()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Shift)
                    root.sizeFine = true;
                event.accepted = false;
            }
            Keys.onReleased: event => {
                if (event.key === Qt.Key_Shift)
                    root.sizeFine = false;
                event.accepted = false;
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                function update(event) {
                    root.sizeFine = !!(event.modifiers & Qt.ShiftModifier);
                    const position = Math.max(0, Math.min(sizeSlider.to, (event.x - sizeSlider.leftPadding)
                                                          / sizeSlider.effectiveDraggingWidth
                                                          * sizeSlider.to));
                    sizeSlider.value = root.sizeFine ? position : Math.round(position);
                    sizeSlider.moved();
                }
                onPressed: event => {
                    sizeSlider.forceActiveFocus();
                    sizeSlider.pressed = true;
                    update(event);
                }
                onPositionChanged: event => {
                    if (pressed)
                        update(event);
                }
                onReleased: {
                    sizeSlider.pressed = false;
                    sizeSlider.value = Qt.binding(() => root.sizePosition(root.number("size", 96)));
                }
                onCanceled: {
                    root.cancel();
                    sizeSlider.pressed = false;
                    sizeSlider.value = Qt.binding(() => root.sizePosition(root.number("size", 96)));
                }
            }
            onCommitted: value => {
                if (!root.sizeSliderBlocked && root.gesturing && root.sizeGesture)
                    root.commit({
                                    size: root.displayFont.size
                                });
            }
        }
        Connections {
            target: sizeSlider
            function onPressedChanged() {
                if (!sizeSlider.pressed)
                    root.sizeSliderBlocked = false;
            }
            function onMoved() {
                if (root.sizeSliderBlocked) {
                    sizeSlider.pendingEdit = false;
                    return;
                }
                if (!root.gesturing)
                    root.begin();
                root.sizeGesture = true;
                root.preview({
                                 size: root.sizeValue(sizeSlider.value)
                             });
            }
        }
        TypographyScrubField {
            id: sizeField
            objectName: "typographySizeField"
            cancelRevision: root.cancelRevision
            Layout.preferredWidth: 108
            Layout.preferredHeight: 36
            compact: true
            label: "Size"
            suffix: " px"
            value: root.number("size", 96)
            minimumValue: 48
            maximumValue: 240
            exactUnbounded: true
            valueStops: root.sizeSteps
            onBegan: root.begin()
            onPreviewed: value => root.preview({
                                                   size: value
                                               })
            onCommitted: value => root.commit({
                                                  size: value
                                              })
            onCancelled: root.cancel()
        }
    }
    RowLayout {
        Layout.fillWidth: true
        RippleButton {
            implicitWidth: 100
            implicitHeight: 32
            buttonRadius: 16
            onClicked: {
                root.cancel();
                root.resetRequested();
            }
            contentItem: StyledText {
                text: "Reset style"
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.m3colors.m3primary
                font.pixelSize: 13
            }
        }
        Item {
            Layout.fillWidth: true
        }
    }
}
