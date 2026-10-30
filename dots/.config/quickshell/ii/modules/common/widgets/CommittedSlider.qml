import QtQuick
import qs.modules.common.widgets

// Commit drags and key presses on release; coalesce wheel edits after a short pause.
StyledSlider {
    id: root
    // A deferred commit must use the exact pointer value, without an in-flight value animation.
    animateValue:false
    property bool pendingEdit: false
    signal committed(real value)

    function commit() {
        settle.stop();
        if (!pendingEdit || !enabled) return;
        pendingEdit = false;
        committed(value);
    }

    onMoved: {
        pendingEdit = true;
        if (!pressed) settle.restart();
    }
    onPressedChanged: if (!pressed) commit()
    onEnabledChanged: if (!enabled) { settle.stop(); pendingEdit = false; }

    Timer { id: settle; interval: 180; onTriggered: root.commit() }
}
