pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
ColumnLayout {
    id:root
    property string label:""
    property var values:[]
    property string current:""
    signal selected(string value)
    Layout.fillWidth:true;spacing:6
    StyledText { text:root.label;color:Appearance.colors.colSubtext;font.pixelSize:Appearance.font.pixelSize.small }
    StyledComboBox {
        Layout.fillWidth:true;textRole:"name";buttonIcon:"tune"
        model:root.values.map(v => ({name:String(v).replace(/_/g," ")}))
        currentIndex:root.values.indexOf(root.current)
        onActivated:index => root.selected(String(root.values[index]))
    }
}
