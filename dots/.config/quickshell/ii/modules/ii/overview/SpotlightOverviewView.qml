import QtQuick

Item {
    id: root
    required property var controller
    required property var screen
    required property real availableWidth
    required property real availableHeight
    property real contentOpacity: 1
    property bool captureEnabled: false
    property bool contentShown: false
    implicitWidth: preview.implicitWidth
    implicitHeight: preview.implicitHeight
    function inspect() { return preview.inspect(); }
    OverviewWidget {
        id: preview
        screen: root.screen
        controller: root.controller
        availableWidth: root.availableWidth
        availableHeight: root.availableHeight
        contentOpacity: root.contentOpacity
        captureEnabled: root.captureEnabled
        contentShown: root.contentShown
        width: implicitWidth
        height: implicitHeight
    }
}
