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
