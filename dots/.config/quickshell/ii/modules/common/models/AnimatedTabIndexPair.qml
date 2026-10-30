import QtQuick

// idx1 is the "leading" indicator position, idx2 is the "following" one
// The former animates faster than the latter, see the NumberAnimations below
QtObject {
    id: root
    required property real index
    property bool enabled: true
    property bool settling: false

    property real idx1: index
    property real idx2: index
    property int idx1Duration: 100
    property int idx2Duration: 300

    onEnabledChanged: if (!enabled) settle()

    function settle() {
        settling = true;
        idx1 = Qt.binding(() => index);
        idx2 = Qt.binding(() => index);
        settling = false;
    }

    Behavior on idx1 {
        enabled: root.enabled && !root.settling
        NumberAnimation {
            duration: root.idx1Duration
            easing.type: Easing.OutSine
        }
    }
    Behavior on idx2 {
        enabled: root.enabled && !root.settling
        NumberAnimation {
            duration: root.idx2Duration
            easing.type: Easing.OutSine
        }
    }
}
