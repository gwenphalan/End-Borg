pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

// Bounded numeric entry with units, draft validation and a compact shared stepper.
StyledSpinBox {
    id: root
    property real number: 0
    property real minimum: 0
    property real maximum: 1000000
    property real increment: 1
    property bool integral: false
    property string unit: ""
    property int precisionFactor: 100
    property var displayFormatter: null
    property var valueParser: null
    readonly property int factor: integral ? 1 : precisionFactor
    property var rawDraft: undefined
    property bool invalid: false
    signal edited(real number)
    signal invalidEdited(string text)
    signal cancelled()

    function numberText(value) { return Number(Number(value).toFixed(integral ? 0 : 2)).toString(); }
    function formatted(value) { if (displayFormatter) return displayFormatter(value); return numberText(value) + (unit ? (unit === "%" ? "" : " ") + unit : ""); }
    function rawNumberText(text) {
        let raw=text.trim();
        if (unit && raw.toLocaleLowerCase().endsWith(unit.toLocaleLowerCase())) raw=raw.slice(0,-unit.length).trim();
        return raw;
    }
    function enteredValue(text) { if (valueParser) return valueParser(text); const raw=rawNumberText(text); return raw ? Number(raw) : NaN; }
    function commit() {
        // Merely focusing a formatted display must not round the stored value.
        if (!invalid && rawDraft === undefined && input.text === formatted(number))
            return;
        const typed = input.text.trim();
        const entered = enteredValue(typed);
        if (typed && Number.isFinite(entered) && entered >= minimum && entered <= maximum && (!integral || Number.isInteger(entered))) {
            invalid=false;
            edited(entered);
            input.text = formatted(entered);
        } else { invalid=true; invalidEdited(rawNumberText(typed)); }
    }

    from: Math.round(minimum * factor)
    to: Math.round(maximum * factor)
    stepSize: Math.max(1, Math.round(increment * factor))
    value: Math.round(number * factor)
    onValueModified: { invalid=false; edited(value / factor); input.text=formatted(value / factor); }
    contentItem: Item {
        implicitHeight: root.baseHeight
        implicitWidth: Math.max(70, measurement.width + 16)
        TextMetrics {
            id: measurement
            font: input.font
            text: root.formatted(Math.max(Math.abs(root.minimum), Math.abs(root.maximum)))
        }
        StyledTextInput {
            id: input
            anchors.centerIn: parent
            width: parent.width - 8
            horizontalAlignment: TextInput.AlignHCenter
            color: root.invalid ? Appearance.colors.colError : Appearance.colors.colOnLayer2
            font.family: Appearance.font.family.numbers
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            selectByMouse: true
            Accessible.name: root.Accessible.name + (root.unit ? " (" + root.unit + ")" : "")
            onTextEdited: {
                const raw=text.trim();
                const entered=root.enteredValue(raw);
                if (raw && Number.isFinite(entered) && entered>=root.minimum && entered<=root.maximum && (!root.integral || Number.isInteger(entered))) { root.invalid=false; root.edited(entered); }
                else { root.invalid=true; root.invalidEdited(root.rawNumberText(raw)); }
            }
            onEditingFinished: root.commit()
            onActiveFocusChanged: {
                root.inputFocused=activeFocus;
                if (activeFocus) select(0, root.displayFormatter ? text.length : root.numberText(root.number).length);
                else if (text !== root.formatted(root.number)) root.commit();
            }
            Keys.onEscapePressed: event => { root.invalid=false; text = root.formatted(root.number); root.cancelled(); focus = false; event.accepted = true; }
        }
    }
    Component.onCompleted: {
        invalid=rawDraft!==undefined;
        input.text=invalid ? String(rawDraft) : formatted(number);
    }
    onRawDraftChanged:if (!input.activeFocus) { invalid=rawDraft!==undefined; input.text=invalid ? String(rawDraft) : formatted(number); }
    onNumberChanged: if (!input.activeFocus && !invalid) input.text = formatted(number)
    onUnitChanged: if (!input.activeFocus && !invalid) input.text = formatted(number)
}
