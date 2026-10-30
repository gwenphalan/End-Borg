import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

StyledText {
    id:root
    property string label:""
    property bool dirty:false
    property bool reserveDirtySpace:false
    readonly property real reservedWidth:measurement.implicitWidth
    text:label+(dirty ? "*" : "")
    width:reservedWidth
    Layout.minimumWidth:reservedWidth
    Layout.preferredWidth:reservedWidth
    Layout.maximumWidth:reservedWidth

    StyledText {
        id:measurement
        visible:false
        font:root.font
        text:root.label+((root.reserveDirtySpace || root.dirty) ? "*" : "")
    }
}
