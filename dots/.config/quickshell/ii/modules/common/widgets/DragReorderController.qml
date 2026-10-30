pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

// Hosts own their data. The shared controller previews positions, lands the actual
// dragged face, then emits a single commit request after the movement finishes.
Item {
    id: root
    required property Item coordinateItem
    property Item dragLayer: coordinateItem
    property bool reducedMotion: Config.options.launcher.reducedMotion
    property int dragThreshold: 6
    property var locate: point => null
    property var returnDestination: (key,index) => null
    property var dragSource: null
    property Item sourceItem: null
    property Item face: null
    property string sourceKey: ""
    property int sourceIndex: -1
    property var destination: null
    property point lastPoint: Qt.point(0,0)
    property bool cancelled: false
    property bool dropPending: false
    property bool landingScheduled: false
    property bool committing: false
    property var pendingDestination: null
    readonly property bool dragging: !!dragSource && dragSource.drag.active && !cancelled
    readonly property bool active: (dragging || dropPending) && !committing
    signal committed(string key, int from, var destination)
    signal cleared()

    function orderFor(count,from,to) {
        const order=Array.from({length:count},(_,index) => index);
        if (from<0 || from>=count) return order;
        order.splice(from,1);
        order.splice(Math.max(0,Math.min(to,count-1)),0,from);
        return order;
    }
    function insertionAt(x,y,count,columns,cellWidth,cellHeight) {
        if (count<=0) return 0;
        const column=Math.max(0,Math.min(columns-1,Math.floor(x/cellWidth)));
        const row=Math.max(0,Math.floor(y/cellHeight));
        return Math.max(0,Math.min(count-1,row*columns+column));
    }
    function begin(pointer,item,dragFace,key,index,point) {
        if (dropPending) return false;
        clear();
        dragSource=pointer;
        sourceItem=item;
        face=dragFace;
        sourceKey=key;
        sourceIndex=index;
        update(point);
        return true;
    }
    function update(point) {
        lastPoint=point;
        if (!cancelled && !dropPending) destination=locate(point);
    }
    function release(point) {
        if (cancelled || !face) { clear();return; }
        update(point);
        // Dropping outside returns smoothly to the source without committing.
        pendingDestination=destination || returnDestination(sourceKey,sourceIndex);
        if (!pendingDestination) { clear();return; }
        destination=pendingDestination;
        dropPending=true;
        landingScheduled=true;
        Qt.callLater(() => {
            if (!landingScheduled || !face) return;
            const target=pendingDestination;
            const point=coordinateItem.mapToItem(dragLayer,target.x,target.y);
            landingX.to=point.x;
            landingY.to=point.y;
            landing.restart();
        });
    }
    function finishLanding() {
        const key=sourceKey,index=sourceIndex,target=pendingDestination;
        // New delegates must see the committed order, never the permutation of
        // the old model. Keep the old face held until the host updates its data.
        committing=true;
        if (!cancelled && target && target.commit!==false) committed(key,index,target);
        // Let bindings on newly-created delegates consume the new order while
        // their geometry Behaviors are disabled for this commit boundary.
        Qt.callLater(() => { if (committing) clear(); });
    }
    function cancel() {
        cancelled=true;
        landing.stop();
        clear();
    }
    function clear() {
        landingScheduled=false;
        dropPending=false;
        dragSource=null;
        sourceItem=null;
        face=null;
        sourceKey="";
        sourceIndex=-1;
        destination=null;
        pendingDestination=null;
        cancelled=false;
        committing=false;
        cleared();
    }
    ParallelAnimation {
        id:landing
        DragReorderAnimation { id:landingX;target:root.face;property:"x";reducedMotion:root.reducedMotion }
        DragReorderAnimation { id:landingY;target:root.face;property:"y";reducedMotion:root.reducedMotion }
        onFinished:root.finishLanding()
    }
}
