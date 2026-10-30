import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

ToolConfirmDialog {
    id:root
    property alias text:field.text
    property string placeholderText:""
    confirmEnabled:text.trim().length>0
    onOpened:{field.forceActiveFocus();field.selectAll();}
    formData:CompactTextField {
        id:field
        objectName:"dialogTextInput"
        Layout.fillWidth:true
        placeholderText:root.placeholderText
        maximumLength:120
        onAccepted:if(root.confirmEnabled) root.confirmed()
    }
}
