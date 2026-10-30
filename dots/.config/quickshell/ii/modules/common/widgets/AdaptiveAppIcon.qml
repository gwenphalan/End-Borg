import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common

Item {
    id: root
    property string appId: ""
    property string iconName: ""
    property string appName: ""
    property real implicitSize: 48
    property bool hovered: false
    property bool selected: false
    property bool selectionOutline:false
    property real selectionWidth:3.5
    property color selectionColor:Appearance.colors.colPrimary
    property bool pressed: false
    property bool contextMenuOpen: false
    readonly property var policy: AppSearch.resolveAdaptiveIcon(appId, iconName, appName)
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    Item {
        id: container
        anchors.fill: parent
        transformOrigin: Item.Center
        scale: root.pressed ? 0.94 : (root.contextMenuOpen ? 1 : (root.selected || root.hovered) ? 1.07 : 1)
        Behavior on scale {
            NumberAnimation {
                duration: root.pressed ? 75 : 170
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.pressed ? [0.2, 0, 0, 1, 1, 1] : [0.2, 1.18, 0.3, 1, 1, 1]
            }
        }

        Loader {
            anchors.fill:parent
            anchors.margins:-root.selectionWidth
            active:root.selectionOutline
            z:10
            sourceComponent:G2Squircle { borderWidth:root.selectionWidth; borderColor:root.selectionColor }
        }
        Image {
            id: adaptedImage
            anchors.fill: parent
            source: root.policy.source
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            mipmap: true
        }
        IconImage {
            anchors.fill: adaptedImage
            source: Quickshell.iconPath(root.iconName || "application-x-executable",
                                        "application-x-executable")
            visible: adaptedImage.status !== Image.Ready
            asynchronous: true
            mipmap: true
        }
    }
}
