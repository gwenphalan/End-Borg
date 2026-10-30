import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.services

ApplicationWindow {
    id: root
    property var closeHandler:null
    property string appTitle: ""
    property bool showWindowChrome:true
    property real contentPadding: 0
    property alias appBody:body
    default property alias appContent: body.data
    minimumWidth:640
    minimumHeight:480
    width:1100
    height:760
    visible:true
    title:appTitle
    color:Appearance.colors.colLayer0
    onClosing:event => { if (root.closeHandler && !root.closeHandler()) { event.accepted=false; return; } Qt.quit(); }
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Config.readWriteDelay = 80;
    }
    ColumnLayout {
        anchors.fill:parent
        anchors.margins:root.contentPadding
        spacing:12
        Item {
            Layout.fillWidth:true
            implicitHeight:38
            Layout.fillHeight:false
            Layout.maximumHeight:38
            visible:root.showWindowChrome && Config.options.windows.showTitlebar
            StyledText {
                anchors.verticalCenter:parent.verticalCenter
                anchors.left:Config.options.windows.centerTitle ? undefined : parent.left
                anchors.horizontalCenter:Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                text:root.appTitle
                font.family:Appearance.font.family.title
                font.variableAxes:Appearance.font.variableAxes.title
                font.pixelSize:Appearance.font.pixelSize.larger
                font.weight:Font.Medium
            }
            RowLayout {
                anchors.right:parent.right
                anchors.verticalCenter:parent.verticalCenter
                IconToolbarButton {
                    implicitWidth:34; implicitHeight:34
                    text:"remove"
                    Accessible.name:Translation.tr("Minimize")
                    onClicked:root.showMinimized()
                    StyledToolTip { text:Translation.tr("Minimize") }
                }
                IconToolbarButton {
                    implicitWidth:34; implicitHeight:34
                    text:root.visibility === Window.Maximized ? "filter_none" : "crop_square"
                    Accessible.name:Translation.tr("Maximize or restore")
                    onClicked:root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
                    StyledToolTip { text:Translation.tr("Maximize or restore") }
                }
                IconToolbarButton {
                    implicitWidth:34; implicitHeight:34
                    text:"close"
                    Accessible.name:Translation.tr("Close")
                    onClicked:root.close()
                    StyledToolTip { text:Translation.tr("Close") }
                }
            }
        }
        Rectangle { id:body; color:root.color; Layout.fillWidth:true; Layout.fillHeight:true }
    }
}
