import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property string title
    property string icon
    height: 42
    RowLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4; leftMargin: 6 }
        spacing: 8
        MaterialSymbol { text: root.icon; visible: root.icon !== ""; iconSize: 20; color: Appearance.colors.colPrimary }
        StyledText { text: root.title; font.weight: Font.Medium; color: Appearance.colors.colOnSurfaceVariant }
        Item { Layout.fillWidth: true }
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 6 }
        height: 1
        color: Appearance.colors.colOutlineVariant
    }
}
