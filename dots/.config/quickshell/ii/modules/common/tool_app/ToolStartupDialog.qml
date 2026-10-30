import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ToolModal {
    id:root
    property string appName:""
    property string iconName:""
    property string statusText:""
    property var recentFiles:[]
    property real recentListHeight:160
    property real recentHeaderInset:8
    signal recentFileRequested(string path)
    property bool failed:false
    property bool actionsEnabled:true
    default property alias actions:buttons.data
    preferredWidth:560
    padding:28
    header:null
    background:Rectangle {color:Appearance.colors.colLayer0Base;radius:Appearance.rounding.normal}
    contentItem:ColumnLayout {
        spacing:20
        RowLayout {
            Layout.alignment:Qt.AlignHCenter
            Layout.topMargin:12
            Layout.bottomMargin:12
            spacing:14
            MaterialSymbol {
                visible:root.iconName!==""
                text:root.iconName
                iconSize:48
                color:Appearance.colors.colPrimary
            }
            StyledText {
                text:root.appName
                font.family:Appearance.font.family.title
                font.pixelSize:Appearance.font.pixelSize.title+8
                font.weight:Font.Medium
                elide:Text.ElideRight
            }
        }
        ContentSection {
            title:"Recent"
            icon:"history"
            headerInset:root.recentHeaderInset
            visible:root.recentFiles.length>0
            Rectangle {
                objectName:"startupRecentContainer"
                Layout.fillWidth:true
                implicitHeight:root.recentListHeight+16
                color:Appearance.colors.colLayer2
                radius:Appearance.rounding.normal
                StyledFlickable {
                    id:recentList
                    objectName:"startupRecentList"
                    anchors.fill:parent
                    anchors.margins:8
                    contentHeight:recentRows.implicitHeight
                    contentWidth:width
                    clip:true
                    boundsBehavior:Flickable.StopAtBounds
                    ColumnLayout {
                        id:recentRows
                        width:recentList.width-8
                        spacing:0
                        Repeater {
                            model:root.recentFiles
                            MenuButton {
                                required property string modelData
                                required property int index
                                objectName:"startupRecentFile"+index
                                Layout.fillWidth:true
                                implicitHeight:40
                                enabled:root.actionsEnabled
                                buttonText:modelData.substring(modelData.lastIndexOf("/")+1)
                                Accessible.name:modelData
                                contentItem:StyledText {
                                    text:parent.buttonText
                                    leftPadding:12;rightPadding:12
                                    verticalAlignment:Text.AlignVCenter
                                    elide:Text.ElideMiddle
                                    font.pixelSize:Appearance.font.pixelSize.small
                                    color:Appearance.colors.colOnSurfaceVariant
                                }
                                onClicked:root.recentFileRequested(modelData)
                                StyledToolTip {text:parent.modelData}
                            }
                        }
                    }
                }
            }
        }
        StyledText {
            Layout.maximumWidth:480;Layout.alignment:Qt.AlignHCenter
            text:root.statusText
            color:root.failed ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
            font.pixelSize:Appearance.font.pixelSize.small
            wrapMode:Text.Wrap
            visible:text!==""
        }
        RowLayout {
            id:buttons
            Layout.alignment:Qt.AlignRight
            spacing:12
            enabled:root.actionsEnabled
        }

    }
}
