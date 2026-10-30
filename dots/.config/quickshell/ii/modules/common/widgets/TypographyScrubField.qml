pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.common

// Drag for a continuous adjustment; click the value for exact entry.
Rectangle {
    id: root

    property int cancelRevision: 0
    property bool compact: false
    property int decimals: 0
    property real dragValue: value
    property bool editing: false
    property bool exactUnbounded: false
    property bool gesturing: false
    property string label: ""
    property real maximumValue: 100
    property real minimumValue: 0
    property real originalValue: 0
    property string prefix: ""
    property real stepSize: 1
    property string suffix: ""
    property real value: 0
    property var valueStops: []

    signal began
    signal cancelled
    signal committed(real value)
    signal previewed(real value)

    function begin() {
        if (gesturing)
            return;
        originalValue = value;
        dragValue = value;
        gesturing = true;
        began();
    }
    function cancel() {
        if (!gesturing && !editing)
            return;
        editing = false;
        gesturing = false;
        cancelled();
        root.forceActiveFocus();
    }
    function clamp(n) {
        return Math.max(minimumValue, Math.min(maximumValue, n));
    }
    function edit() {
        begin();
        editing = true;
        input.text = value.toFixed(decimals);
        input.forceActiveFocus();
        input.selectAll();
    }
    function finish(n) {
        if (!Number.isFinite(n)) {
            cancel();
            return;
        }
        n = Math.round((exactUnbounded ? Math.min(2147483647, Math.max(minimumValue, n)) : clamp(n))
                       * Math.pow(10, decimals)) / Math.pow(10, decimals);
        editing = false;
        gesturing = false;
        committed(n);
        root.forceActiveFocus();
    }
    function increment(direction, fine) {
        begin();
        finish(fine ? clamp(value+direction*stepSize) : valueStops.length ? valueStops[Math.max(0, Math.min(valueStops.length - 1, nearest(value)
                                                                   + direction))] : clamp(value + direction
                                                                                          * stepSize));
    }
    function nearest(n) {
        let best = 0;
        for (let i = 1; i < valueStops.length; i++)
            if (Math.abs(valueStops[i] - n) < Math.abs(valueStops[best] - n))
                best = i;
        return best;
    }
    function rounded(n) {
        return Math.round(n / stepSize) * stepSize;
    }

    Accessible.description: "Drag horizontally to adjust. Press Enter to type a value."
    Accessible.name: label
    Accessible.role: Accessible.SpinBox
    ToolTip.delay: 1000
    ToolTip.text: "Drag to adjust · Click to type"
    ToolTip.visible: pointer.containsMouse && !pointer.pressed && !root.editing
    activeFocusOnTab: true
    color: pointer.containsMouse || editing ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2
    implicitHeight: 68
    implicitWidth: 126
    opacity: enabled ? 1 : .42
    radius: 16

    Keys.onDownPressed: event => increment(-1, !!(event.modifiers & Qt.ShiftModifier))
    Keys.onEnterPressed: edit()
    Keys.onEscapePressed: cancel()
    Keys.onLeftPressed: event => increment(-1, !!(event.modifiers & Qt.ShiftModifier))
    Keys.onReturnPressed: edit()
    Keys.onRightPressed: event => increment(1, !!(event.modifiers & Qt.ShiftModifier))
    Keys.onUpPressed: event => increment(1, !!(event.modifiers & Qt.ShiftModifier))
    onCancelRevisionChanged: cancel()

    StyledText {
        color: Appearance.colors.colSubtext
        elide: Text.ElideRight
        font.pixelSize: 12
        text: root.label
        visible: !root.compact

        anchors {
            left: parent.left
            margins: 12
            right: parent.right
            top: parent.top
        }
    }

    StyledText {
        color: Appearance.colors.colOnLayer2
        elide: Text.ElideRight
        font.pixelSize: 16
        text: root.prefix + root.value.toFixed(root.decimals) + root.suffix
        visible: !root.editing
        y: root.compact ? (parent.height - height) / 2 : parent.height - height - 12

        anchors {
            left: parent.left
            margins: 12
            right: parent.right
        }
    }

    TextInput {
        id: input

        color: Appearance.m3colors.m3primary
        font.family: Appearance.font.family.main
        font.pixelSize: 16
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        selectByMouse: true
        visible: root.editing
        y: root.compact ? (parent.height - height) / 2 : parent.height - height - 12

        validator: DoubleValidator {
            bottom: root.minimumValue
            decimals: root.decimals
            locale: "C"
            notation: DoubleValidator.StandardNotation
            top: root.exactUnbounded ? Number.MAX_VALUE : root.maximumValue
        }

        Keys.onEnterPressed: {
            if (text.trim().length && acceptableInput)
                root.finish(Number(text));
            else
                root.cancel();
        }
        Keys.onEscapePressed: root.cancel()
        Keys.onReturnPressed: {
            if (text.trim().length && acceptableInput)
                root.finish(Number(text));
            else
                root.cancel();
        }
        onActiveFocusChanged: if (!activeFocus && root.editing) {
                                  if (text.trim().length && acceptableInput)
                                      root.finish(Number(text));
                                  else
                                      root.cancel();
                              }

        anchors {
            left: parent.left
            margins: 12
            right: parent.right
        }
    }

    MouseArea {
        id: pointer

        preventStealing: true

        property bool moved: false
        property real startX: 0

        anchors.fill: parent
        cursorShape: Qt.SizeHorCursor
        hoverEnabled: true
        visible: !root.editing

        onCanceled: root.cancel()
        onPositionChanged: event => {
            if (!pressed || !root.gesturing)
                return;
            const delta = event.x - startX;
            if (Math.abs(delta) > 3)
                moved = true;
            if (!moved)
                return;
            root.dragValue = (event.modifiers & Qt.ShiftModifier) ? root.clamp(root.rounded(root.originalValue + delta * root.stepSize)) : root.valueStops.length ? root.valueStops[Math.max(0, Math.min(
                                                                                   root.valueStops.length - 1,
                                                                                   root.nearest(
                                                                                       root.originalValue)
                                                                                   + Math.round(delta
                                                                                                / 12)))] :
                                                      root.clamp(root.rounded(root.originalValue + delta
                                                                              * root.stepSize));
            root.previewed(root.dragValue);
        }
        onPressed: event => {
            root.forceActiveFocus();
            startX = event.x;
            moved = false;
            root.begin();
        }
        onReleased: {
            if (!root.gesturing)
                return;
            if (moved)
                root.finish(root.dragValue);
            else
                root.edit();
        }
    }

    Rectangle {
        anchors.fill: parent
        border.color: Appearance.m3colors.m3primary
        border.width: root.activeFocus || root.editing ? 1 : 0
        color: "transparent"
        radius: parent.radius
    }
}
