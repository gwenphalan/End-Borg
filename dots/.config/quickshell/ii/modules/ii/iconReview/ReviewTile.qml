import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

Item {
    id: root
    property string imagePath: ""
    property color tileColor: Appearance.colors.colSecondaryContainer
    property bool fill: false
    implicitWidth: 48
    implicitHeight: 48

    Rectangle {
        id: tile
        anchors.fill: parent
        radius: Math.min(width, height) * .24
        color: root.tileColor
        Image {
            anchors.fill: parent
            anchors.margins: root.fill ? 0 : Math.round(Math.min(tile.width, tile.height) * .10)
            source: root.imagePath ? "file://" + root.imagePath : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            mipmap: true
        }
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: tile.width
                height: tile.height
                radius: tile.radius
            }
        }
    }
}
