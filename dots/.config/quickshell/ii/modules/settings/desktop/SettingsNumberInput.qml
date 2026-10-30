import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

StyledSpinBox {
    id:root
    property real number:0
    property real minimum:0
    property real maximum:1000000
    property real increment:1
    property bool integral:false
    readonly property int factor:integral ? 1 : 100
    signal edited(real number)
    from:Math.round(minimum*factor)
    to:Math.round(maximum*factor)
    stepSize:Math.max(1,Math.round(increment*factor))
    value:Math.round(number*factor)
    onValueModified:edited(value/factor)
    contentItem:Item {
        implicitHeight:root.baseHeight
        implicitWidth:Math.max(input.implicitWidth,70)
        StyledTextInput {
            id:input
            anchors.centerIn:parent
            text:Number((root.value/root.factor).toFixed(2)).toString()
            color:Appearance.colors.colOnLayer2
            font.family:Appearance.font.family.numbers
            validator:DoubleValidator { bottom:root.minimum; top:root.maximum; decimals:root.integral ? 0 : 2; locale:"C" }
            onEditingFinished:if (acceptableInput) { root.value=Math.round(Number(text)*root.factor); root.edited(root.value/root.factor); }
        }
    }
}
