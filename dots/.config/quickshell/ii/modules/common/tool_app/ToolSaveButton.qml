import QtQuick
import qs.modules.common.widgets

ToolBarButton {
    id:root
    property bool dirty:false
    text:"Save"
    materialSymbol:"save"
    current:false
    implicitWidth:root.iconSize+6+saveLabel.reservedWidth+horizontalPadding*2
    contentItem:Row {
        anchors.centerIn:parent
        spacing:6
        MaterialSymbol {
            anchors.verticalCenter:parent.verticalCenter
            text:root.materialSymbol
            iconSize:root.iconSize
        }
        ToolActionLabel {
            id:saveLabel
            anchors.verticalCenter:parent.verticalCenter
            label:root.text
            font.pixelSize:root.labelPixelSize
            dirty:root.dirty
            reserveDirtySpace:true
        }
    }
}
