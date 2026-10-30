import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ToolModal {
    id:root
    property string errorMessage:""
    signal applyRequested()
    footer:Item {
        implicitHeight:actions.implicitHeight+24
        RowLayout {
            id:actions
            anchors.left:parent.left;anchors.right:parent.right
            anchors.top:parent.top
            anchors.leftMargin:24;anchors.rightMargin:24
            spacing:12
            StyledText {
                visible:root.errorMessage!==""
                Layout.fillWidth:true;Layout.maximumWidth:300
                text:root.errorMessage
                color:Appearance.colors.colError
                wrapMode:Text.Wrap
                font.pixelSize:Appearance.font.pixelSize.small
            }
            Item {Layout.fillWidth:true}
            DialogButton {
                buttonText:"Cancel";Layout.minimumWidth:96;implicitHeight:44
                colBackground:Appearance.colors.colLayer3
                colBackgroundHover:Appearance.colors.colLayer3Hover
                colText:Appearance.colors.colOnLayer2
                onClicked:root.close()
            }
            DialogButton {
                buttonText:"Apply";Layout.minimumWidth:96;implicitHeight:44
                colBackground:Appearance.m3colors.m3primary
                colBackgroundHover:Appearance.colors.colPrimaryHover
                colText:Appearance.m3colors.m3onPrimary
                onClicked:root.applyRequested()
            }
        }
    }
}
