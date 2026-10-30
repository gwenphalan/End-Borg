import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ToolModal {
    id:root
    property alias formData:form.data
    property bool confirmEnabled:true
    property string message:""
    property string confirmText:"Confirm"
    property string cancelText:"Cancel"
    signal confirmed()
    signal cancelled()
    preferredWidth:480
    z:2000
    contentItem:ColumnLayout {
        spacing:20
        StyledText {
            visible:root.message!==""
            Layout.fillWidth:true
            text:root.message
            wrapMode:Text.Wrap
            font.pixelSize:Appearance.font.pixelSize.normal
            color:Appearance.colors.colOnLayer2
        }
        ColumnLayout {id:form;Layout.fillWidth:true;visible:children.length>0}
        RowLayout {
            Layout.fillWidth:true
            spacing:12
            DialogButton {
                buttonText:root.cancelText;Layout.minimumWidth:96;implicitHeight:44
                colBackground:Appearance.colors.colLayer3
                colBackgroundHover:Appearance.colors.colLayer3Hover
                colText:Appearance.colors.colOnLayer2
                onClicked:{root.close();root.cancelled();}
            }
            Item {Layout.fillWidth:true}
            DialogButton {
                enabled:root.confirmEnabled
                buttonText:root.confirmText;Layout.minimumWidth:96;implicitHeight:44
                colBackground:Appearance.m3colors.m3primary
                colBackgroundHover:Appearance.colors.colPrimaryHover
                colText:Appearance.m3colors.m3onPrimary
                onClicked:root.confirmed()
            }
        }
    }
}
