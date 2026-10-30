import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.tool_app
import "RegionGeometry.js" as Geometry
import "../common/tool_app/ToolPointSelection.js" as Selection

Item {
    id:root
    property alias footerPrefix:footer.prefixControls
    objectName:"nativeRegionEditor"
    property var images:[]
    property string activeImage:""
    property string pendingImage:""
    signal imageRequested(string source)
    property url imageSource
    property var imageSize:[0,0]
    property var regions:[]
    property var workingRegions:[]
    property var projectedObjects:[]
    property bool editable:true
    property bool busy:false
    property bool operationsInputFocused:false
    readonly property real viewZoomPercent:100*zoom/fittedZoom
    readonly property bool viewAtReset:atReset
    function setZoomPercent(percent) {const old=zoom;zoom=fittedZoom*Math.max(.02,Math.min(32,percent/100));offsetX=area.width/2-(area.width/2-offsetX)*zoom/old;offsetY=area.height/2-(area.height/2-offsetY)*zoom/old;canvas.requestPaint();}
    function setCreating(value) {if(value===creating)return;if(draft.length)return;creating=value;selectedNodes=[];selectedRegion=-1;canvas.requestPaint();}
    function setSelectedLabel(value) {if(selectedRegion<0 || !value.trim() || busy)return;remember();const next=copy(workingRegions);next[selectedRegion].label=value.trim();workingRegions=next;publish();}
    property bool creating:true
    property var draft:[]
    property var selectedNodes:[]
    property int selectedRegion:-1
    property var past:[]
    property var future:[]
    property real zoom:1
    property real offsetX:0
    property real offsetY:0
    property bool snapping:false
    onKeyboardEnabledChanged:if(!keyboardEnabled)snapping=false
    readonly property var polylines:workingRegions.map(region=>region.points)
    readonly property bool keyboardEnabled:visible && !operationsInputFocused && !naming.opened && !imageDiscard.opened && editable && !busy && !coordinates.inputFocused && !footer.zoomFocused
    readonly property bool canFinish:creating && Geometry.valid(draft)
    readonly property bool hasSnapTargets:projectedObjects.some(object=>(object.edges || []).some(edge=>(object.vertices || [])[edge[0]] && (object.vertices || [])[edge[1]]))
    onHasSnapTargetsChanged:if(!hasSnapTargets)snapping=false
    readonly property var contextHints:buildContextHints()
    function buildContextHints() {
        if(!keyboardEnabled || !imageSource.toString() || imageSize[0]<1 || imageSize[1]<1)return [];
        const hints=[];
        if(creating) {
            hints.push({keys:["LMB"],action:draft.length ? "Add point" : "Start polygon"});
            if(canFinish) hints.push({keys:["Enter"],action:"Close polygon"});
            if(draft.length) hints.push({keys:["Esc"],action:"Cancel polygon"});
        } else if(workingRegions.length) {
            if(selectedNodes.length){
                hints.push({keys:["LMB"],action:"Drag"},{keys:["Del"],action:"Delete"},{keys:["← ↑ ↓ →"],action:"Nudge"});
                hints.push({keys:["Ctrl","LMB"],action:"Toggle"},{keys:["Shift","LMB"],action:"Polygon"});
            } else {
                hints.push({keys:["LMB"],action:"Select"},{keys:["Alt","LMB"],action:"Insert point"});
                if(selectedRegion>=0)hints.push({keys:["F2"],action:"Rename"},{keys:["Shift","Del"],action:"Delete polygon"});
            }
            if(selectedRegion>=0 || selectedNodes.length)hints.push({keys:["Esc"],action:"Deselect"});
        }
        if(hasSnapTargets && (creating || selectedNodes.length)) hints.push({keys:["S"],action:"Snap"});
        if(!selectedNodes.length)hints.push({keys:["MMB"],action:"Pan"});
        return hints;
    }
    readonly property var selectedPosition:Selection.centroidNodes(polylines,selectedNodes)
    readonly property real fittedZoom:Math.max(.02,Math.min((area.width-112)/Math.max(1,imageSize[0]),(area.height-40)/Math.max(1,imageSize[1])))
    readonly property bool atReset:Math.abs(zoom-fittedZoom)<1e-8 && Math.abs(offsetX-(area.width-imageSize[0]*zoom)/2)<.01 && Math.abs(offsetY-(area.height-imageSize[1]*zoom)/2)<.01
    signal regionsEdited(var regions)
    signal doneRequested()
    signal stageRequested(string stage)
    onRegionsChanged:{workingRegions=copy(regions);if(canvas)canvas.requestPaint();}
    onProjectedObjectsChanged:if(canvas)canvas.requestPaint()
    onActiveImageChanged:{draft=[];selectedNodes=[];selectedRegion=-1;past=[];future=[];if(canvas)canvas.requestPaint();}
    onImageSourceChanged:{draft=[];selectedNodes=[];selectedRegion=-1;past=[];future=[];Qt.callLater(fit);}
    function requestImage(source) {
        if(source===activeImage || busy || !editable)return;
        if(draft.length) {pendingImage=source;imageDiscard.open();return;}
        imageRequested(source);
    }
    function copy(value) {return JSON.parse(JSON.stringify(value));}
    function fit() {if(imageSize[0]<1 || area.width<1 || area.height<1)return;zoom=fittedZoom;offsetX=(area.width-imageSize[0]*zoom)/2;offsetY=(area.height-imageSize[1]*zoom)/2;canvas.requestPaint();}
    function snapshot() {return {workingRegions:copy(workingRegions),draft:copy(draft)};}
    function remember() {past=past.concat([snapshot()]).slice(-100);future=[];}
    function publish() {workingRegions=copy(workingRegions);regionsEdited(copy(workingRegions));canvas.requestPaint();}
    function rejectChanges(accepted) {
        // Keep the rejected attempt available for deliberate redo/recovery, while
        // displaying only the worker-acknowledged document after validation fails.
        future=future.concat([snapshot()]).slice(-100);
        if(past.length && JSON.stringify(past[past.length-1].workingRegions)===JSON.stringify(accepted)) past=past.slice(0,-1);
        workingRegions=copy(accepted);selectedNodes=[];selectedRegion=-1;canvas.requestPaint();
    }
    function restore(state) {workingRegions=copy(state.workingRegions);draft=copy(state.draft);selectedNodes=[];selectedRegion=-1;regionsEdited(copy(workingRegions));canvas.requestPaint();}
    function undo() {if(!past.length)return;future=future.concat([snapshot()]);const state=past[past.length-1];past=past.slice(0,-1);restore(state);}
    function redo() {if(!future.length)return;past=past.concat([snapshot()]);const state=future[future.length-1];future=future.slice(0,-1);restore(state);}
    function finish() {if(!Geometry.valid(draft)) {feedback.show("Place at least three non-collinear points.",true);return;}nameField.text="";naming.open();nameField.forceActiveFocus();}
    function commitName() {
        const label=nameField.text.trim();if(!label)return;
        remember();const id="region-"+Date.now()+"-"+Math.random().toString(36).slice(2,8);
        workingRegions=workingRegions.concat([{id:id,label:label,color:Geometry.color(id),points:copy(draft)}]);draft=[];selectedNodes=[];selectedRegion=workingRegions.length-1;naming.close();publish();
    }
    function remove(whole) {
        if(creating || selectedRegion<0)return;remember();
        if(whole || !selectedNodes.length) workingRegions=workingRegions.filter((region,i)=>i!==selectedRegion);
        else {const points=Selection.copyPolylines(polylines);for(const node of selectedNodes.slice().sort((a,b)=>b[0]-a[0]||b[1]-a[1]))points[node[0]].splice(node[1],1);workingRegions=workingRegions.map((region,i)=>Object.assign({},region,{points:points[i]})).filter(region=>Geometry.valid(region.points));}
        selectedNodes=[];selectedRegion=-1;publish();
    }
    function translate(dx,dy) {
        if(!selectedNodes.length)return;remember();
        const result=Selection.translateNodes(polylines,selectedNodes,dx,dy,imageSize);
        workingRegions=workingRegions.map((region,i)=>Object.assign({},region,{points:result.polylines[i]}));publish();
    }
    function rename() {if(selectedRegion<0)return;nameField.text=workingRegions[selectedRegion].label;naming.renaming=true;naming.open();nameField.forceActiveFocus();}
    Rectangle {anchors.fill:parent;color:Appearance.colors.colLayer0Base}
    ToolApp {
        id:app
        anchors.fill:parent
        controlsEnabled:root.editable
        tools:[
            IconToolbarButton {text:"polyline";toggled:root.creating;Accessible.name:"New region · D";onClicked:{root.creating=true;root.selectedNodes=[];root.selectedRegion=-1;}StyledToolTip{text:parent.Accessible.name}},
            IconToolbarButton {text:"edit";toggled:!root.creating;Accessible.name:"Edit regions · V";onClicked:{root.creating=false;root.draft=[];canvas.requestPaint();}StyledToolTip{text:parent.Accessible.name}}
        ]
        contextActionsVisible:!root.creating && root.selectedRegion>=0
        contextActions:[
            IconToolbarButton {text:"label";Accessible.name:"Rename region";onClicked:root.rename();StyledToolTip{text:parent.Accessible.name}}
        ]
        status:[
            ToolCanvasFooter {
                id:footer
                showZoom:false
                leadingControls:ToolIconButton {
                    objectName:"nativeCorrectedView"
                    visible:false
                    implicitWidth:28;implicitHeight:28;Layout.fillHeight:false
                    text:"visibility";toggled:true;enabled:false;opacity:.4
                    Accessible.name:"Corrected image · required for region editing"
                    StyledToolTip {text:parent.Accessible.name}
                }
                zoomPercent:100*root.zoom/root.fittedZoom
                atReset:root.atReset
                showCursorCoordinates:!coordinates.visible
                cursorActive:mouse.containsMouse && mouse.mouseX>=root.offsetX && mouse.mouseY>=root.offsetY && mouse.mouseX<=root.offsetX+root.imageSize[0]*root.zoom && mouse.mouseY<=root.offsetY+root.imageSize[1]*root.zoom
                cursorX:(mouse.mouseX-root.offsetX)/root.zoom
                cursorY:(mouse.mouseY-root.offsetY)/root.zoom
                onResetRequested:root.fit()
                onZoomEdited:percent=>{const old=root.zoom;root.zoom=root.fittedZoom*Math.max(.02,Math.min(32,percent/100));root.offsetX=area.width/2-(area.width/2-root.offsetX)*root.zoom/old;root.offsetY=area.height/2-(area.height/2-root.offsetY)*root.zoom/old;canvas.requestPaint();}
                hints:root.contextHints
                toolInputs:ToolPointCoordinates {
                    id:coordinates
                    visible:!root.creating && root.selectedNodes.length>0
                    position:root.selectedPosition
                    selectionCount:root.selectedNodes.length
                    bounds:root.imageSize
                    onCoordinateEdited:(axis,value)=>root.translate(axis===0 ? value-root.selectedPosition[0] : 0,axis===1 ? value-root.selectedPosition[1] : 0)
                    onInvalid:message=>feedback.show(message,true)
                }
            }
        ]
        canvasContent:[
            Item {
                id:area
                anchors.fill:parent
                clip:true
                onWidthChanged:canvas.requestPaint()
                onHeightChanged:canvas.requestPaint()
                Image {x:root.offsetX;y:root.offsetY;width:root.imageSize[0]*root.zoom;height:root.imageSize[1]*root.zoom;source:root.imageSource;cache:false;smooth:true;onStatusChanged:if(status===Image.Ready)Qt.callLater(root.fit)}
                Canvas {
                    id:canvas
                    objectName:"nativeCanvas"
                    anchors.fill:parent
                    focus:true
                    function screen(point) {return [root.offsetX+point[0]*root.zoom,root.offsetY+point[1]*root.zoom];}
                    function draw(ctx,points,color,closed,nodes) {
                        if(!points.length)return;ctx.beginPath();const start=screen(points[0]);ctx.moveTo(start[0],start[1]);
                        for(let i=1;i<points.length;i++){const p=screen(points[i]);ctx.lineTo(p[0],p[1]);}if(closed)ctx.closePath();
                        ctx.strokeStyle=color;ctx.lineWidth=1.7;if(closed){ctx.globalAlpha=.13;ctx.fillStyle=color;ctx.fill();ctx.globalAlpha=1;}ctx.stroke();
                        if(nodes)for(let i=0;i<points.length;i++){const p=screen(points[i]);ctx.beginPath();ctx.arc(p[0],p[1],3.5,0,Math.PI*2);ctx.fillStyle=color;ctx.fill();}
                    }
                    onPaint:{
                        const ctx=getContext("2d");ctx.reset();
                        for(const object of root.projectedObjects){const vertices=object.vertices || [];for(const edge of object.edges || [])if(vertices[edge[0]]&&vertices[edge[1]])draw(ctx,[vertices[edge[0]],vertices[edge[1]]],object.color || "#8fa7b8",false,false);}
                        for(let i=0;i<root.workingRegions.length;i++){const region=root.workingRegions[i];draw(ctx,region.points,region.color || Geometry.color(region.id),true,!root.creating);if(region.points.length){const p=screen(region.points[0]);ctx.fillStyle=region.color || Geometry.color(region.id);ctx.font="12px sans-serif";ctx.fillText(region.label,p[0]+7,p[1]-7);}}
                        draw(ctx,root.draft,Appearance.colors.colPrimary,false,true);
                        for(const node of root.selectedNodes){if(!root.polylines[node[0]]||!root.polylines[node[0]][node[1]])continue;const p=screen(root.polylines[node[0]][node[1]]);ctx.beginPath();ctx.arc(p[0],p[1],6,0,Math.PI*2);ctx.strokeStyle=Appearance.colors.colPrimary;ctx.stroke();}
                    }
                    MouseArea {
                        id:mouse
                        objectName:"nativeMouse"
                        anchors.fill:parent
                        acceptedButtons:Qt.LeftButton|Qt.RightButton|Qt.MiddleButton
                        hoverEnabled:true
                        property bool panning:false
                        property bool dragging:false
                        property bool moved:false
                        property var anchor:[0,0]
                        property var previous:[0,0]
                        function point(x,y) {let p=[(x-root.offsetX)/root.zoom,(y-root.offsetY)/root.zoom];if(root.snapping)p=Geometry.snap(root.projectedObjects,p,10/root.zoom);return [Math.max(0,Math.min(root.imageSize[0]-1,p[0])),Math.max(0,Math.min(root.imageSize[1]-1,p[1]))];}
                        onPressed:event=>{
                            canvas.forceActiveFocus();previous=[event.x,event.y];moved=false;
                            if(event.button===Qt.MiddleButton){panning=true;return;}if(!root.editable)return;
                            if(event.button===Qt.RightButton){if(root.creating&&root.draft.length)root.finish();return;}
                            if(event.x<root.offsetX||event.y<root.offsetY||event.x>root.offsetX+root.imageSize[0]*root.zoom||event.y>root.offsetY+root.imageSize[1]*root.zoom)return;
                            const p=point(event.x,event.y);
                            if(root.creating){if(root.draft.length>=3&&Math.hypot(root.draft[0][0]-p[0],root.draft[0][1]-p[1])*root.zoom<10){root.finish();return;}root.remember();root.draft=root.draft.concat([p]);canvas.requestPaint();return;}
                            let hit=null,best=10/root.zoom;
                            for(let r=0;r<root.workingRegions.length;r++)for(let n=0;n<root.workingRegions[r].points.length;n++){const q=root.workingRegions[r].points[n],d=Math.hypot(q[0]-p[0],q[1]-p[1]);if(d<best){best=d;hit=[r,n];}}
                            if(hit){const selection=Selection.selectNode(root.polylines,root.selectedNodes,hit,{toggle:!!(event.modifiers&Qt.ControlModifier),wholePolyline:!!(event.modifiers&Qt.ShiftModifier)});root.selectedNodes=selection.nodes;root.selectedRegion=selection.primary[0];anchor=p;dragging=!(event.modifiers&Qt.ControlModifier);canvas.requestPaint();return;}
                            let edge=null;for(let r=0;r<root.workingRegions.length;r++){const candidate=Geometry.nearest(root.workingRegions[r].points,p,10/root.zoom);if(candidate&&(!edge||candidate.distance<edge.distance))edge=Object.assign({region:r},candidate);}
                            if(edge&&(event.modifiers&Qt.AltModifier)){root.remember();const next=root.copy(root.workingRegions);next[edge.region].points.splice(edge.index+1,0,edge.point);root.workingRegions=next;root.selectedRegion=edge.region;root.selectedNodes=[[edge.region,edge.index+1]];root.publish();return;}
                            root.selectedRegion=edge?edge.region:-1;root.selectedNodes=[];
                            if(root.selectedRegion<0)for(let r=root.workingRegions.length-1;r>=0;r--)if(Geometry.contains(root.workingRegions[r].points,p)){root.selectedRegion=r;break;}
                            if(root.selectedRegion>=0&&(event.modifiers&Qt.ShiftModifier))root.selectedNodes=Selection.wholePolylineNodes(root.polylines,root.selectedRegion);
                            anchor=p;dragging=root.selectedNodes.length>0;canvas.requestPaint();
                        }
                        onPositionChanged:event=>{
                            if(panning){root.offsetX+=event.x-previous[0];root.offsetY+=event.y-previous[1];canvas.requestPaint();}
                            else if(dragging&&root.editable){if(!moved)root.remember();const target=point(event.x,event.y),result=Selection.translateNodes(root.polylines,root.selectedNodes,target[0]-anchor[0],target[1]-anchor[1],root.imageSize);root.workingRegions=root.workingRegions.map((region,i)=>Object.assign({},region,{points:result.polylines[i]}));anchor=[anchor[0]+result.delta[0],anchor[1]+result.delta[1]];moved=true;canvas.requestPaint();}
                            previous=[event.x,event.y];
                        }
                        onReleased:{if(dragging&&moved)root.publish();panning=false;dragging=false;}
                        onCanceled:{if(dragging&&moved)root.publish();panning=false;dragging=false;}
                        onWheel:event=>{const old=root.zoom;root.zoom=Math.max(root.fittedZoom*.02,Math.min(root.fittedZoom*32,old*Math.pow(1.0015,event.angleDelta.y)));root.offsetX=event.x-(event.x-root.offsetX)*root.zoom/old;root.offsetY=event.y-(event.y-root.offsetY)*root.zoom/old;canvas.requestPaint();}
                    }
                }
            }
        ]
    }
    ToolConfirmDialog {
        id:naming
        objectName:"regionNameDialog"
        property bool renaming:false
        title:renaming ? "Region label" : "New region"
        confirmText:"Save"
        confirmEnabled:nameField.text.trim()!==""
        formData:MaterialTextField {id:nameField;objectName:"regionNameInput";Layout.fillWidth:true;placeholderText:"Label";onAccepted:if(naming.confirmEnabled)naming.confirmed()}
        onConfirmed:{if(renaming){root.remember();const next=root.copy(root.workingRegions);next[root.selectedRegion].label=nameField.text.trim();root.workingRegions=next;root.publish();close();}else root.commitName();}
        onClosed:renaming=false
    }
    ToolConfirmDialog {
        id:imageDiscard
        title:"Discard unfinished polygon?"
        message:"The unfinished polygon has not been saved. Switch images?"
        confirmText:"Discard"
        onConfirmed:{const source=root.pendingImage;root.pendingImage="";root.draft=[];root.selectedNodes=[];close();canvas.requestPaint();root.imageRequested(source);}
        onCancelled:root.pendingImage=""
    }
    ToolToast {id:feedback}
    Shortcut {sequence:"D";enabled:root.keyboardEnabled;onActivated:{root.creating=true;root.selectedNodes=[];}}
    Shortcut {sequence:"V";enabled:root.keyboardEnabled;onActivated:{root.creating=false;root.draft=[];canvas.requestPaint();}}
    Shortcut {sequence:"Return";enabled:root.keyboardEnabled&&root.canFinish;onActivated:root.finish()}
    Shortcut {sequence:"Escape";enabled:root.keyboardEnabled && (root.draft.length>0 || root.selectedRegion>=0 || root.selectedNodes.length>0);onActivated:{root.draft=[];root.selectedNodes=[];root.selectedRegion=-1;canvas.requestPaint();}}
    Shortcut {sequence:"Delete";enabled:root.keyboardEnabled && !root.creating && root.selectedRegion>=0;onActivated:root.remove(false)}
    Shortcut {sequence:"Shift+Delete";enabled:root.keyboardEnabled && !root.creating && root.selectedRegion>=0;onActivated:root.remove(true)}
    Shortcut {sequence:"F2";enabled:root.keyboardEnabled && !root.creating && root.selectedRegion>=0;onActivated:root.rename()}
    Shortcut {sequence:"Ctrl+Z";enabled:root.keyboardEnabled;onActivated:root.undo()}
    Shortcut {sequence:"Ctrl+Shift+Z";enabled:root.keyboardEnabled;onActivated:root.redo()}
    Shortcut {sequence:"Ctrl+Y";enabled:root.keyboardEnabled;onActivated:root.redo()}
    Shortcut {sequence:"F";enabled:root.keyboardEnabled;onActivated:root.fit()}
    Keys.onPressed:event=>{
        if(root.keyboardEnabled && root.hasSnapTargets && (root.creating || root.selectedNodes.length) && event.key===Qt.Key_S && !(event.modifiers&(Qt.ControlModifier|Qt.AltModifier|Qt.MetaModifier))){root.snapping=true;event.accepted=true;}
        else if(root.keyboardEnabled && !root.creating && root.selectedNodes.length && [Qt.Key_Left,Qt.Key_Right,Qt.Key_Up,Qt.Key_Down].includes(event.key)) {
            const step=(event.modifiers&Qt.ShiftModifier) ? 10 : (event.modifiers&Qt.AltModifier) ? .1 : 1;
            root.translate(event.key===Qt.Key_Left ? -step : event.key===Qt.Key_Right ? step : 0,event.key===Qt.Key_Up ? -step : event.key===Qt.Key_Down ? step : 0);event.accepted=true;
        }
    }
    Keys.onReleased:event=>{if(event.key===Qt.Key_S){root.snapping=false;event.accepted=true;}}
}
