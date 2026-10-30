import QtQuick
import qs.modules.common

MouseArea {
    id: root
    required property Flickable flickable
    required property var animation
    property bool reducedMotion: false
    property real destination: 0
    property int wheelEvents: 0
    readonly property bool running: animation.running
    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120
    visible: Config?.options.interactions.scrolling.fasterTouchpadScroll ?? false
    acceptedButtons: Qt.NoButton
    parent: flickable
    z: 2
    anchors.fill: parent
    function bounded(value) {
        return Math.max(flickable.originY, Math.min(value,
            Math.max(flickable.originY, flickable.originY + flickable.contentHeight - flickable.height)));
    }
    function stop() { animation.stop(); }
    function scrollTo(value) {
        destination = bounded(value);
        flickable.contentY = destination;
    }
    onWheel: event => {
        wheelEvents++;
        const delta = event.angleDelta.y / root.mouseScrollDeltaThreshold;
        const scrollFactor = Math.abs(event.angleDelta.y) >= root.mouseScrollDeltaThreshold
            ? root.mouseScrollFactor : root.touchpadScrollFactor;
        scrollTo((running ? destination : flickable.contentY) - delta * scrollFactor);
        event.accepted = true;
    }
    Connections {
        target: root.flickable
        function onContentYChanged() {
            if (!root.running) root.destination = root.flickable.contentY;
        }
    }
}
