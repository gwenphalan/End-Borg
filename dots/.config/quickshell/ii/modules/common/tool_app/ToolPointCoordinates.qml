import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id:root
    property var position:[0,0]
    property int selectionCount:1
    property var bounds:[]
    property int decimals:3
    property real fieldWidth:92
    readonly property bool inputFocused:xInput.activeFocus || yInput.activeFocus
    signal coordinateEdited(int axis,real value)
    signal invalid(string message)
    spacing:4
    function formatted(value) {return Number.isFinite(value) ? String(Number(value.toFixed(Math.max(0,Math.min(15,decimals))))) : "";}
    function commit(axis,text) {
        // Display rounding never quantizes the underlying model on focus loss.
        if(String(text)===formatted(position[axis])) return false;
        const value=Number(text);
        if(!String(text).trim() || !Number.isFinite(value)) {invalid("Enter a finite coordinate.");return false;}
        if(bounds.length===2 && (value<0 || value>bounds[axis]-1)) {invalid("Coordinate outside the image.");return false;}
        coordinateEdited(axis,value);return true;
    }
    StyledText {text:root.selectionCount>1 ? "avg x" : "x";font.pixelSize:Appearance.font.pixelSize.small}
    CompactTextField {
        id:xInput
        objectName:"pointX"
        implicitWidth:root.fieldWidth;implicitHeight:28
        topPadding:2;bottomPadding:2
        Accessible.name:root.selectionCount>1 ? "Selection average x" : "Point x"
        onEditingFinished:root.commit(0,text)
        Binding {target:xInput;property:"text";value:root.formatted(root.position[0]);when:!xInput.activeFocus}
    }
    StyledText {text:root.selectionCount>1 ? "avg y" : "y";font.pixelSize:Appearance.font.pixelSize.small}
    CompactTextField {
        id:yInput
        objectName:"pointY"
        implicitWidth:root.fieldWidth;implicitHeight:28
        topPadding:2;bottomPadding:2
        Accessible.name:root.selectionCount>1 ? "Selection average y" : "Point y"
        onEditingFinished:root.commit(1,text)
        Binding {target:yInput;property:"text";value:root.formatted(root.position[1]);when:!yInput.activeFocus}
    }
}
