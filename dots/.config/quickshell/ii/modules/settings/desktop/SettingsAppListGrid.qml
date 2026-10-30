pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.services
import "../../ii/overview/LauncherLabels.js" as LauncherLabels

// Reuses real Spotlight tiles. Moving a tile changes only the caller's draft.
Item {
    id: root
    required property var applicationIds
    required property string listKey
    property string removalLabel: Translation.tr("Unpin")
    signal moveRequested(int from, int to)
    signal removeRequested(int index)
    signal addRequested()
    readonly property int columns: Math.max(1,Math.floor(width/106))
    readonly property real cellWidth: width/columns
    readonly property real cellHeight: 106
    readonly property int tileCount: applicationIds.length
    implicitHeight: Math.ceil((tileCount+1)/columns)*cellHeight
    readonly property Item dragLayer: Overlay.overlay || root
    readonly property bool dragging:reorder.dragging
    readonly property bool dropPending:reorder.dropPending
    readonly property int dragIndex:reorder.sourceIndex
    readonly property int insertion:reorder.destination?.index ?? -1
    readonly property bool overGrid:reorder.destination?.list === "grid"
    property int contextIndex: -1
    property int contextFocusReason:Qt.MouseFocusReason
    readonly property var visualOrder:reorder.orderFor(tileCount,reorder.active && overGrid ? dragIndex : -1,insertion)
    Accessible.name: Translation.tr("Application list")
    Accessible.description: Translation.tr("Drag to reorder. Use Alt and arrow keys to move applications, Delete to remove, or the context menu.")

    function slot(index) { return Math.max(0,visualOrder.indexOf(index)); }
    function cellX(slot) { return slot%columns*cellWidth; }
    function cellY(slot) { return Math.floor(slot/columns)*cellHeight; }
    function appFor(id) {
        return AppSearch.list.find(app => app.id===id) || {id:id,name:String(id).replace(/\.desktop$/i,""),icon:"application-x-executable"};
    }
    function labelFor(app) { return LauncherLabels.displayName(app,AppSearch.list,AppSearch.launcherLabels); }
    DragReorderController {
        id:reorder
        coordinateItem:root
        dragLayer:root.dragLayer
        locate:point => {
            if (point.x<0 || point.x>=root.width || point.y<0 || point.y>=root.height) return null;
            const index=insertionAt(point.x,point.y,root.tileCount,root.columns,root.cellWidth,root.cellHeight);
            return {list:"grid",index:index,x:root.cellX(index),y:root.cellY(index)};
        }
        returnDestination:(key,index) => ({list:"grid",index:index,x:root.cellX(index),y:root.cellY(index),commit:false})
        onCommitted:(key,from,destination) => {
            if (from>=0 && from<root.tileCount && root.applicationIds[from]===key && from!==destination.index) root.moveRequested(from,destination.index);
        }
    }
    function cancelDrag() { reorder.cancel(); }
    function focusIndex(index,reason=Qt.TabFocusReason) {
        Qt.callLater(() => {
            const target=index>=tileCount ? addTile : appRepeater.itemAt(Math.max(0,index))?.face;
            if (target) target.forceActiveFocus(reason);
        });
    }
    function keyboardMove(index,delta) {
        const target=Math.max(0,Math.min(tileCount-1,index+delta));
        if (target!==index) moveRequested(index,target);
        focusIndex(target);
    }
    function showContext(index,source,x,y,keyboard=false) {
        if (index<0 || index>=tileCount || dragging || dropPending) return;
        contextIndex=index;
        contextFocusReason=keyboard ? Qt.TabFocusReason : Qt.MouseFocusReason;
        const point=source.mapToItem(contextMenu,x,y);
        tileController.menuApp=appFor(applicationIds[index]);
        tileController.menuAnchor=point;
        tileController.menuOpen=true;
        Qt.callLater(() => contextMenu.focusFirstAction());
    }
    function handleTileKey(event,index,face) {
        const delta=event.key===Qt.Key_Left ? -1 : event.key===Qt.Key_Right ? 1 : event.key===Qt.Key_Up ? -columns : event.key===Qt.Key_Down ? columns : 0;
        if (delta) {
            if (event.modifiers & Qt.AltModifier) keyboardMove(index,delta);
            else focusIndex(Math.max(0,Math.min(tileCount,index+delta)));
            event.accepted=true;
        } else if (event.key===Qt.Key_Delete || event.key===Qt.Key_Backspace) {
            removeRequested(index);
            focusIndex(Math.min(index,tileCount));
            event.accepted=true;
        } else if (event.key===Qt.Key_Menu || event.key===Qt.Key_F10 && event.modifiers & Qt.ShiftModifier) {
            showContext(index,face,face.width/2,face.height/2,true);
            event.accepted=true;
        }
    }
    Keys.onEscapePressed:event => {
        if (dragging || dropPending) { cancelDrag();event.accepted=true; }
        else if (tileController.menuOpen) { tileController.dismissMenus();event.accepted=true; }
    }
    onApplicationIdsChanged: {
        if (tileController.menuOpen) tileController.dismissMenus();
        if (reorder.active && !reorder.committing) cancelDrag();
    }
    Connections {
        target:SettingsCatalog
        function onDismissPopups() { tileController.dismissMenus(); if (root.dragging || root.dropPending) root.cancelDrag(); }
    }
    QtObject {
        id:tileController
        property bool reducedMotion:Config.options.launcher.reducedMotion
        property int createdAppTiles:0
        property var keyRouter:root
        property bool open:true
        property bool menuOpen:false
        property var menuApp:null
        property point menuAnchor:Qt.point(0,0)
        property int exitDuration:reducedMotion ? 0 : 160
        property int panelEntranceDuration:reducedMotion ? 0 : Appearance.animation.clickBounce.duration
        property int searchEntranceDuration:reducedMotion ? 0 : 160
        property var exitCurve:Appearance.animationCurves.emphasizedAccel
        function dismissMenus() { menuOpen=false; }
    }
    G2Squircle {
        visible:root.dragging && root.overGrid
        x:root.cellX(root.insertion)+(root.cellWidth-width)/2
        y:root.cellY(root.insertion)+4
        width:48; height:48
        color:"transparent"
        borderWidth:1.5
        borderColor:Appearance.m3colors.m3outlineVariant
    }
    Repeater {
        id:appRepeater
        model:root.applicationIds
        delegate:Item {
            id:cell
            required property int index
            required property string modelData
            property alias face:face
            readonly property var application:root.appFor(modelData)
            width:root.cellWidth; height:root.cellHeight
            x:root.cellX(root.slot(index))
            y:root.cellY(root.slot(index))
            Behavior on x { enabled:!reorder.committing;DragReorderAnimation {} }
            Behavior on y { enabled:!reorder.committing;DragReorderAnimation {} }
            SpotlightAppTile {
                id:face
                x:0; y:0
                width:cell.width; height:cell.height
                app:cell.application
                label:root.labelFor(cell.application)
                controller:tileController
                selected:activeFocus && focusReason!==Qt.MouseFocusReason
                chosen:false
                labelAlwaysBold:false
                labelBoldOnSelection:false
                labelRestWeight:Font.Normal
                activeFocusOnTab:true
                opacity:1
                Accessible.name:label
                Accessible.description:root.Accessible.description
                onLaunch:root.showContext(cell.index,face,width/2,height/2,visualFocus)
                onContextRequested:root.showContext(cell.index,face,width/2,height/2)
                Keys.onShortcutOverride:event => {
                    const arrow=[Qt.Key_Left,Qt.Key_Right,Qt.Key_Up,Qt.Key_Down].includes(event.key);
                    if (arrow && event.modifiers & Qt.AltModifier || root.dragging && event.key===Qt.Key_Escape) event.accepted=true;
                }
                Keys.onPressed:event => root.handleTileKey(event,cell.index,face)
                DragReorderHandle {
                    id:pointer
                    controller:reorder
                    face:parent
                    sourceItem:cell.face
                    sourceKey:cell.modelData
                    sourceIndex:cell.index
                    onContextRequested:(x,y) => root.showContext(cell.index,pointer,x,y)
                }
            }
        }
    }
    RippleButton {
        id:addTile
        x:root.cellX(root.tileCount)
        y:root.cellY(root.tileCount)
        width:root.cellWidth; height:root.cellHeight
        padding:6
        activeFocusOnTab:true
        rippleEnabled:false
        buttonRadius:Appearance.rounding.normal
        colBackground:"transparent"
        colBackgroundHover:"transparent"
        Accessible.name:Translation.tr("Add application")
        onClicked:root.addRequested()
        Keys.onLeftPressed:event => { root.focusIndex(Math.max(0,root.tileCount-1));event.accepted=true; }
        Keys.onUpPressed:event => { root.focusIndex(Math.max(0,root.tileCount-root.columns));event.accepted=true; }
        contentItem:Column {
            spacing:4
            Item {
                width:parent.width; height:56
                G2Squircle {
                    anchors.centerIn:parent
                    width:48; height:48
                    color:addTile.isHovered || addTile.activeFocus && addTile.focusReason!==Qt.MouseFocusReason ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    borderWidth:0
                    borderColor:Appearance.colors.colPrimary
                    MaterialSymbol { anchors.centerIn:parent; text:"add"; iconSize:28; color:addTile.isHovered || addTile.activeFocus && addTile.focusReason!==Qt.MouseFocusReason ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer }
                }
            }
            Item { width:parent.width; height:34 }
        }
        StyledToolTip { text:Translation.tr("Add application") }
    }
    SpotlightContextMenu {
        id:contextMenu
        parent:root.dragLayer
        anchors.fill:parent
        z:1001
        controller:tileController
        actions:[{icon:root.listKey==="launcher.hiddenApps" ? "visibility" : "keep_off",label:root.removalLabel,action:"remove"}]
        onActionTriggered:(action,app) => {
            const index=root.contextIndex;
            root.contextIndex=-1;
            if (action==="remove" && index>=0 && index<root.tileCount && root.applicationIds[index]===app.id) root.removeRequested(index);
            root.focusIndex(Math.min(Math.max(index,0),root.tileCount),root.contextFocusReason);
        }
    }
}
