pragma ComponentBehavior: Bound
import QtQuick

// Same pointer threshold, scene mapping and overlay lifetime for every reorder host.
MouseArea {
    id:root
    required property DragReorderController controller
    required property Item face
    required property Item sourceItem
    required property string sourceKey
    required property int sourceIndex
    property bool moved: false
    property bool allowDrag: false
    readonly property bool ownsDrag:controller.dragSource===root
    signal pointerFocused()
    signal activated()
    signal contextRequested(real x, real y)
    anchors.fill:parent
    acceptedButtons:Qt.LeftButton | Qt.RightButton
    hoverEnabled:true
    preventStealing:true
    cursorShape:drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    drag.target:allowDrag && ownsDrag && !controller.cancelled ? face : null
    drag.threshold:controller.dragThreshold
    onPressed:mouse => {
        moved=false;
        allowDrag=mouse.button===Qt.LeftButton && !controller.dropPending;
        if (!allowDrag) return;
        sourceItem.forceActiveFocus(Qt.MouseFocusReason);
        pointerFocused();
        allowDrag=controller.begin(root,sourceItem,face,sourceKey,sourceIndex,mapToItem(controller.coordinateItem,mouse.x,mouse.y));
    }
    onPositionChanged:mouse => {
        if (!allowDrag || !ownsDrag) return;
        if (drag.active) moved=true;
        controller.update(mapToItem(controller.coordinateItem,mouse.x,mouse.y));
    }
    onReleased:mouse => {
        if (mouse.button!==Qt.LeftButton || !ownsDrag) return;
        if (moved || drag.active) {
            moved=true;
            const point=face.parent===controller.dragLayer ? mapToItem(controller.coordinateItem,mouse.x,mouse.y) : controller.lastPoint;
            controller.release(point);
        } else controller.clear();
        allowDrag=false;
    }
    onClicked:mouse => {
        if (mouse.button===Qt.RightButton) contextRequested(mouse.x,mouse.y);
        else if (!moved) activated();
    }
    onCanceled: {
        allowDrag=false;
        if (ownsDrag && !controller.dropPending) controller.cancel();
    }
    states:State {
        when:root.ownsDrag && (root.drag.active || root.moved || root.controller.dropPending)
        ParentChange { target:root.face;parent:root.controller.dragLayer }
        PropertyChanges { target:root.face;z:1000 }
    }
}
