pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "../../common/BarUtilities.js" as Utilities

Item {
    id:root
    Layout.fillWidth:true
    implicitHeight:content.implicitHeight
    property var draftKeys:[]
    readonly property var enabledKeys:draftKeys
    readonly property bool dragging:reorder.dragging
    readonly property bool dropPending:reorder.dropPending
    readonly property string dragKey:reorder.sourceKey
    readonly property bool overBar:reorder.destination?.list==="bar"
    readonly property var currentKeys: {
        const observed = SettingsCatalog.revision;
        return Utilities.ordered(SettingsCatalog.get("bar.utilButtons.order")).filter(key
                                                                                      => SettingsCatalog.get(
                                                                                             "bar.utilButtons."
                                                                                             + key));
    }
    readonly property bool dirty: JSON.stringify(draftKeys) !== JSON.stringify(currentKeys)
    Component.onCompleted: {
        const saved = SettingsCatalog.drafts["bar.utilButtons.order"];
        draftKeys = saved?.utilityToolbar ? saved.keys.slice() : currentKeys.slice();
    }
    Connections { target:SettingsCatalog; function onDismissPopups() { reorder.cancel(); } function onSaved() { reorder.cancel();const saved=SettingsCatalog.drafts["bar.utilButtons.order"]; root.draftKeys=saved?.utilityToolbar ? saved.keys.slice() : root.currentKeys.slice(); } function onDiscarded() { reorder.cancel();root.draftKeys=root.currentKeys.slice(); } }
    function keepDraft() {
        if (dirty)
            SettingsCatalog.saveDraft("bar.utilButtons.order", {
                                          utilityToolbar: true,
                                          keys: draftKeys.slice()
                                      });
        else
            SettingsCatalog.clearDraft("bar.utilButtons.order");
    }
    function save() {
        const keys = draftKeys.slice();
        const order = keys.concat(Utilities.ordered(SettingsCatalog.get("bar.utilButtons.order")).filter(key
                                                                                                         => !keys.includes(
                                                                                                                key)));
        if (!SettingsCatalog.write("bar.utilButtons.order", order))
            return;
        for (const utility of Utilities.definitions)
            if (!SettingsCatalog.write("bar.utilButtons." + utility.key, keys.includes(utility.key)))
                return;
        SettingsCatalog.clearDraft("bar.utilButtons.order");
        draftKeys = currentKeys.slice();
    }
    readonly property var library:Utilities.definitions.filter(item => !enabledKeys.includes(item.key))
    readonly property var previewKeys: {
        if (!reorder.active || !overBar || !dragKey) return enabledKeys;
        const keys=enabledKeys.filter(key => key!==dragKey);
        keys.splice(Math.max(0,Math.min(reorder.destination.index,keys.length)),0,dragKey);
        return keys;
    }
    readonly property var libraryPreviewKeys:Utilities.definitions.filter(item => !enabledKeys.includes(item.key) || reorder.active && reorder.destination?.list==="library" && item.key===dragKey).map(item => item.key)
    function place(key,index) {
        if (!Utilities.item(key)) return;
        const active=enabledKeys.filter(other => other!==key);
        active.splice(Math.max(0,Math.min(index,active.length)),0,key);
        draftKeys=active;
        keepDraft();
    }
    function remove(key) {
        draftKeys=draftKeys.filter(other => other!==key);
        keepDraft();
    }
    function focusTile(key) {
        Qt.callLater(() => {
            const tile=activeRepeater.itemAt(enabledKeys.indexOf(key));
            if (tile) { tile.forceActiveFocus(Qt.TabFocusReason);tile.keyboardFocus=true; }
        });
    }
    function move(key,delta) { place(key,enabledKeys.indexOf(key)+delta);focusTile(key); }
    function activate(key,inBar) { if (!inBar) place(key,enabledKeys.length); }
    function slot(key) { return Math.max(0,previewKeys.indexOf(key)); }
    function librarySlot(key) { return Math.max(0,libraryPreviewKeys.indexOf(key)); }
    function barDestination(index,commit=true) {
        const count=enabledKeys.filter(key => key!==dragKey).length+1;
        const rowX=(barPanel.width-(count*44-4))/2;
        const point=barPanel.mapToItem(root,rowX+index*44,(barPanel.height-36)/2);
        return {list:"bar",index:index,x:point.x,y:point.y,commit:commit};
    }
    function libraryDestination(key,commit=true) {
        const keys=Utilities.definitions.filter(item => !enabledKeys.includes(item.key) || item.key===key).map(item => item.key);
        const index=Math.max(0,keys.indexOf(key));
        const point=libraryGrid.mapToItem(root,index%libraryGrid.columns*48,Math.floor(index/libraryGrid.columns)*48+6);
        return {list:"library",index:index,x:point.x,y:point.y,commit:commit};
    }
    function containsPoint(item,point) {
        const local=root.mapToItem(item,point.x,point.y);
        return local.x>=0 && local.x<item.width && local.y>=0 && local.y<item.height;
    }
    DragReorderController {
        id:reorder
        coordinateItem:root
        dragLayer:root
        locate:point => {
            if (root.containsPoint(barPanel,point)) {
                const local=root.mapToItem(barPanel,point.x,point.y);
                const remaining=root.enabledKeys.filter(key => key!==sourceKey).length;
                const rowX=(barPanel.width-((remaining+1)*44-4))/2;
                const index=Math.max(0,Math.min(remaining,Math.round((local.x-rowX-20)/44)));
                return root.barDestination(index);
            }
            if (root.containsPoint(libraryArea,point)) return root.libraryDestination(sourceKey,root.enabledKeys.includes(sourceKey));
            return null;
        }
        returnDestination:(key,index) => root.enabledKeys.includes(key) ? root.barDestination(index,false) : root.libraryDestination(key,false)
        onCommitted:(key,from,destination) => {
            if (destination.list==="bar") root.place(key,destination.index);
            else root.remove(key);
        }
    }
    onDraftKeysChanged:if (reorder.active && !reorder.committing) reorder.cancel()
    Keys.onEscapePressed:event => { if (reorder.active) { reorder.cancel();event.accepted=true; } }

    component UtilityTile:Item {
        id:tile
        required property string utilityKey
        property bool inBar:false
        property bool keyboardFocus:false
        readonly property var utility:Utilities.item(utilityKey)
        implicitWidth:40
        implicitHeight:36
        activeFocusOnTab:true
        onActiveFocusChanged:if (activeFocus) keyboardFocus=true
        Accessible.role:Accessible.Button
        Accessible.name:(inBar ? Translation.tr("Bar button: %1") : Translation.tr("Add %1 to bar")).arg(Translation.tr(utility.name))
        Accessible.description:inBar ? Translation.tr("Use Left and Right to move, Delete to remove.") : ""
        Keys.onLeftPressed:event => { if (inBar) { root.move(utilityKey,-1);event.accepted=true; } }
        Keys.onRightPressed:event => { if (inBar) { root.move(utilityKey,1);event.accepted=true; } }
        Keys.onDeletePressed:event => { if (inBar) { root.remove(utilityKey);event.accepted=true; } }
        Keys.onReturnPressed:event => { root.activate(utilityKey,inBar);root.focusTile(utilityKey);event.accepted=true; }
        Keys.onSpacePressed:event => { root.activate(utilityKey,inBar);root.focusTile(utilityKey);event.accepted=true; }
        Rectangle {
            id:face
            width:tile.width
            height:tile.height
            radius:height/2
            color:pointer.containsMouse ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
            border.width:tile.activeFocus && tile.keyboardFocus ? 2 : 0
            border.color:Appearance.colors.colPrimary
            MaterialSymbol { anchors.centerIn:parent;text:tile.utility.icon;iconSize:20;color:Appearance.colors.colOnLayer2 }
            DragReorderHandle {
                id:pointer
                controller:reorder
                face:parent
                sourceItem:tile
                sourceKey:tile.utilityKey
                sourceIndex:root.enabledKeys.indexOf(tile.utilityKey)
                onPointerFocused:tile.keyboardFocus=false
                onActivated:root.activate(tile.utilityKey,tile.inBar)
            }
        }
        StyledToolTip { text:Translation.tr(tile.utility.name);extraVisibleCondition:pointer.containsMouse && !reorder.active }
    }

    ColumnLayout {
        id:content
        width:parent.width
        spacing:12
        Rectangle {
            id:barPanel
            Layout.fillWidth:true
            implicitHeight:80
            radius:Appearance.rounding.normal
            color:Appearance.colors.colLayer1
            Item {
                id:activeRow
                anchors.centerIn:parent
                width:Math.max(0,root.previewKeys.length*44-4)
                height:36
                Rectangle {
                    visible:reorder.dragging && root.overBar
                    x:root.slot(root.dragKey)*44
                    width:40;height:36;radius:18
                    color:Appearance.colors.colSecondaryContainer
                    opacity:.4
                }
                Repeater {
                    id:activeRepeater
                    model:root.enabledKeys
                    delegate:UtilityTile {
                        required property string modelData
                        utilityKey:modelData
                        inBar:true
                        x:root.slot(utilityKey)*44
                        Behavior on x { enabled:!reorder.committing;DragReorderAnimation {} }
                    }
                }
            }
            StyledText {
                visible:!root.enabledKeys.length && !root.overBar
                anchors.centerIn:parent
                text:Translation.tr("Drop buttons here")
                color:Appearance.colors.colSubtext
                font.pixelSize:Appearance.font.pixelSize.smaller
            }
        }
        Item {
            id:libraryArea
            Layout.fillWidth:true
            implicitHeight:Math.max(64,Math.ceil(root.libraryPreviewKeys.length/libraryGrid.columns)*48+24)
            Canvas {
                anchors.fill:parent
                property color outline:Appearance.m3colors.m3outline
                onOutlineChanged:requestPaint()
                onWidthChanged:requestPaint()
                onHeightChanged:requestPaint()
                onPaint: {
                    const ctx=getContext("2d"),w=width-1,h=height-1,r=12;
                    ctx.reset();ctx.lineWidth=1.5;ctx.strokeStyle=outline;ctx.lineCap="round";ctx.setLineDash([1,5]);
                    ctx.beginPath();ctx.moveTo(r,1);ctx.lineTo(w-r,1);ctx.quadraticCurveTo(w,1,w,r);ctx.lineTo(w,h-r);
                    ctx.quadraticCurveTo(w,h,w-r,h);ctx.lineTo(r,h);ctx.quadraticCurveTo(1,h,1,h-r);ctx.lineTo(1,r);ctx.quadraticCurveTo(1,1,r,1);ctx.stroke();
                }
            }
            Item {
                id:libraryGrid
                readonly property int columns:Math.max(1,Math.floor((parent.width-24)/48))
                width:Math.max(0,Math.min(root.libraryPreviewKeys.length,columns)*48-8)
                height:Math.ceil(root.libraryPreviewKeys.length/columns)*48
                anchors.centerIn:parent
                Rectangle {
                    visible:reorder.dragging && reorder.destination?.list==="library"
                    x:root.librarySlot(root.dragKey)%libraryGrid.columns*48
                    y:Math.floor(root.librarySlot(root.dragKey)/libraryGrid.columns)*48+6
                    width:40;height:36;radius:18
                    color:Appearance.colors.colSecondaryContainer
                    opacity:.4
                }
                Repeater {
                    model:root.library
                    delegate:UtilityTile {
                        required property var modelData
                        utilityKey:modelData.key
                        x:root.librarySlot(utilityKey)%libraryGrid.columns*48
                        y:Math.floor(root.librarySlot(utilityKey)/libraryGrid.columns)*48+6
                        Behavior on x { enabled:!reorder.committing;DragReorderAnimation {} }
                        Behavior on y { enabled:!reorder.committing;DragReorderAnimation {} }
                    }
                }
            }
            StyledText {
                visible:!root.library.length && reorder.destination?.list!=="library"
                anchors.centerIn:parent
                text:Translation.tr("All buttons are in the bar")
                font.pixelSize:Appearance.font.pixelSize.smaller
                color:Appearance.colors.colSubtext
            }
        }
        StyledText {
            Layout.fillWidth:true
            text:Translation.tr("Drag into the bar. Drag back to remove.")
            wrapMode:Text.Wrap
            font.pixelSize:Appearance.font.pixelSize.smaller
            color:Appearance.colors.colSubtext
        }
    }
}
