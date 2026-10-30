pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.services

// Exact entry and +/- without QSpinBox's fixed integer range or an arbitrary UI ceiling.
Item {
    id:root
    required property real number
    property real minimum:0
    property real increment:1
    property var stepValues:[]
    property string unit:""
    property bool integral:true
    // Presentation only; focus restores exact entry and the model is never rounded.
    property int displayDecimals:-1
    property var rawDraft:undefined
    property bool invalid:false
    readonly property bool inputFocused:input.activeFocus
    signal edited(real number)
    signal invalidEdited(string text)
    signal cancelled()
    implicitWidth:180
    implicitHeight:35
    opacity:enabled ? 1 : .4
    function numberText(value) { return integral ? String(Math.round(value)) : String(Number(value)); }
    function formatted(value) { const text=displayDecimals>=0 && !input.activeFocus ? String(Number(Number(value).toFixed(displayDecimals))) : numberText(value);return text+(unit ? " "+unit : ""); }
    function parse(text) {
        let raw=text.trim();
        if (unit && raw.toLocaleLowerCase().endsWith(unit.toLocaleLowerCase())) raw=raw.slice(0,-unit.length).trim();
        return {raw:raw,value:raw ? Number(raw) : NaN};
    }
    function commit(text) {
        const parsed=parse(text);
        if (Number.isFinite(parsed.value) && parsed.value>=minimum && (!integral || Number.isInteger(parsed.value))) {
            const changed=invalid || parsed.value!==number;
            invalid=false;
            if(changed) edited(parsed.value);
            return true;
        }
        invalid=true;
        invalidEdited(parsed.raw);
        return false;
    }
    function step(delta) {
        let next=Math.max(minimum,number+delta*increment);
        if (stepValues.length) {
            const candidates=stepValues.filter(value => delta>0 ? value>number : value<number);
            next=candidates.length ? delta>0 ? candidates[0] : candidates[candidates.length-1] : number;
        }
        if (Number.isFinite(next)) { invalid=false;edited(next);input.text=formatted(next); }
    }
    Rectangle {
        anchors.fill:parent
        color:Appearance.colors.colLayer2
        radius:Appearance.rounding.small
    }

    component StepButton:Button {
        required property int direction
        implicitWidth:35
        implicitHeight:35
        autoRepeat:true
        Accessible.name:(direction<0 ? Translation.tr("Decrease %1") : Translation.tr("Increase %1")).arg(root.Accessible.name)
        onClicked:root.step(direction)
        background:Rectangle {
            topLeftRadius:parent.direction<0 ? Appearance.rounding.small : Appearance.rounding.unsharpen
            bottomLeftRadius:topLeftRadius
            topRightRadius:parent.direction>0 ? Appearance.rounding.small : Appearance.rounding.unsharpen
            bottomRightRadius:topRightRadius
            color:parent.down ? Appearance.colors.colSecondaryContainerActive : parent.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
            Behavior on color {
                animation:Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
        contentItem:MaterialSymbol {
            text:parent.direction<0 ? "remove" : "add"
            iconSize:20
            color:Appearance.colors.colOnSecondaryContainer
            horizontalAlignment:Text.AlignHCenter
            verticalAlignment:Text.AlignVCenter
        }
    }
    StepButton {
        id:decrease
        direction:-1
        anchors.left:parent.left
        anchors.verticalCenter:parent.verticalCenter
    }
    StyledTextInput {
        id:input
        anchors.left:decrease.right
        anchors.right:increase.left
        anchors.leftMargin:4
        anchors.rightMargin:4
        anchors.verticalCenter:parent.verticalCenter
        horizontalAlignment:TextInput.AlignHCenter
        verticalAlignment:TextInput.AlignVCenter
        color:root.invalid ? Appearance.colors.colError : Appearance.colors.colOnLayer2
        font.family:Appearance.font.family.numbers
        font.variableAxes:Appearance.font.variableAxes.numbers
        font.pixelSize:Appearance.font.pixelSize.small
        selectByMouse:true
        clip:true
        inputMethodHints:Qt.ImhFormattedNumbersOnly
        Accessible.name:root.Accessible.name+(root.unit ? " ("+root.unit+")" : "")
        onTextEdited:root.commit(text)
        onEditingFinished:if (root.commit(text)) text=root.formatted(root.number)
        onActiveFocusChanged:if (activeFocus) {text=root.formatted(root.number);select(0,root.numberText(root.number).length);}
        Keys.onUpPressed:event => { root.step(1);event.accepted=true; }
        Keys.onDownPressed:event => { root.step(-1);event.accepted=true; }
        Keys.onEscapePressed:event => { root.invalid=false;text=root.formatted(root.number);root.cancelled();focus=false;event.accepted=true; }
    }
    StepButton {
        id:increase
        direction:1
        anchors.right:parent.right
        anchors.verticalCenter:parent.verticalCenter
    }
    Rectangle {
        anchors.fill:parent
        radius:Appearance.rounding.small
        color:"transparent"
        border.width:input.activeFocus || decrease.visualFocus || increase.visualFocus || root.invalid ? 2 : 0
        border.color:root.invalid ? Appearance.colors.colError : Appearance.colors.colPrimary
    }
    Component.onCompleted: { invalid=rawDraft!==undefined;input.text=invalid ? String(rawDraft) : formatted(number); }
    onRawDraftChanged:if (!input.activeFocus) { invalid=rawDraft!==undefined;input.text=invalid ? String(rawDraft) : formatted(number); }
    onNumberChanged:if (!input.activeFocus && !invalid) input.text=formatted(number)
    onUnitChanged:if (!input.activeFocus && !invalid) input.text=formatted(number)
}
