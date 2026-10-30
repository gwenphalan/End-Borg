import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.tool_app
import qs.modules.settings.desktop as SettingsControls

Item {
    id: root
    property alias footerPrefix:footer.prefixControls
    objectName:"spatialEditor"
    property string mode: "calibration"
    property url imageSource: ""
    property var imageSize: [1,1]
    property var scene: ({version:1,objects:[],regions:[]})
    property var referencePlane:null
    property var planeCalibration: null
    property var projectedObjects: []
    property bool busy: false
    property bool operationsInputFocused:false
    readonly property real viewZoomPercent:100*zoom/fittedZoom
    readonly property bool viewAtReset:fitted
    function setZoomPercent(percent) {zoomAt(fittedZoom*percent/100,surface.width/2,surface.height/2);}
    property real referenceWidth:.3048
    property real referenceDepth:.3048
    property var referenceAxes:["x","y"]
    readonly property bool referenceDirty:!referencePlane || JSON.stringify(corners)!==JSON.stringify(referencePlane.corners) || referenceWidth!==referencePlane.width || referenceDepth!==referencePlane.depth || JSON.stringify(referenceAxes)!==JSON.stringify(referencePlane.axes || ["x","y"])
    function saveReferencePlane() {if(!busy && corners.length===4)operationRequested("save_reference_plane",{plane:{corners:corners,width:referenceWidth,depth:referenceDepth,axes:referenceAxes}});}
    function calculateSpace() {if(!busy && referencePlane && !referenceDirty)operationRequested("calculate_spatial_calibration",{});}
    function referenceAxisVector(axis) {const v=[0,0,0];v["xyz".indexOf(axis.replace("-",""))]=axis.startsWith("-") ? -1 : 1;return v;}
    readonly property string normalAxis:{const a=referenceAxisVector(referenceAxes[0]),b=referenceAxisVector(referenceAxes[1]);const n=[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];const i=n.findIndex(value=>value!==0);return (n[i]>0 ? "+" : "−")+"XYZ"[i];}
    property var operationDraft:({label:"",position:[0,0,0],size:[1,1,1],yaw:0,orientation:"xy"})
    function refreshOperationDraft() {const selected=(objects || []).find(o=>o.id===selectedId);operationDraft=selected ? copy(selected) : {label:"3D region",position:[0,0,0],size:[.3048,.3048,.3048],yaw:0,orientation:"xy"};}
    function writeOperationDraft(field,index,value) {const next=copy(operationDraft);if(index>=0)next[field][index]=value;else next[field]=value;operationDraft=next;}
    function applyOperationDraft() {if(busy || !hasSelectedObject || !operationDraft.label.trim())return;const next=copy(scene),index=next.objects.findIndex(o=>o.id===selectedId);if(index<0)return;next.objects[index]=copy(operationDraft);commit(next);}
    function setReferencePlane() {saveReferencePlane();}
    function redrawReferencePlane() {corners=[];selectedCorner=-1;}
    function beginPlacement() {if(!calibrated || busy)return;placingObject=true;selectedId="";surface.forceActiveFocus();}
    property var corners: []
    property int selectedCorner: -1
    property string selectedId: ""
    property real zoom: 1
    property real panX: 0
    property real panY: 0
    property bool fitted: true
    readonly property real fittedZoom:Math.max(1e-6,Math.min(Math.max(1,surface.width-60)/Math.max(1,imageSize[0]),Math.max(1,surface.height-60)/Math.max(1,imageSize[1])))
    property bool placingObject: false
    property var footprintStart: []
    property var footprintEnd: []
    property var past: []
    property var future: []
    signal operationRequested(string op, var payload)
    signal sceneEdited(var scene)
    signal doneRequested()
    readonly property bool calibrated: planeCalibration !== null && !planeCalibration.stale
    readonly property var objects: (scene.objects || []).filter(object=>object.kind==="cuboid")
    readonly property var projections: Array.isArray(projectedObjects) ? projectedObjects.filter(object=>object.kind==="cuboid") : []
    readonly property bool inputFocused: operationsInputFocused || objectDialog.opened || measurement.opened || footer.zoomFocused || pointCoords.inputFocused
    onImageSizeChanged:if(fitted)Qt.callLater(fit)
    readonly property bool hasImage:imageSource.toString()!=="" && imageSize[0]>0 && imageSize[1]>0
    readonly property bool keyboardEnabled:visible && hasImage && !busy && !inputFocused
    readonly property bool hasSelectedObject:objects.some(object=>object.id===selectedId)
    readonly property var contextHints:buildContextHints()
    function buildContextHints() {
        if(!keyboardEnabled)return [];
        const hints=[];
        if(mode==="calibration") {
            if(corners.length<4) hints.push({keys:["LMB"],action:"Place "+["origin","+X corner","opposite corner","+Y corner"][corners.length]});
            else hints.push({keys:["LMB"],action:selectedCorner>=0 ? "Drag corner" : "Select corner"});
            if(corners.length===4) hints.push({keys:["Enter"],action:"Save plane"});
            if(selectedCorner>=0) hints.push({keys:["Esc"],action:"Deselect corner"});
        } else {
            if(placingObject && calibrated) hints.push({keys:["LMB"],action:"Drag footprint"});
            else if(objects.length) hints.push({keys:["LMB"],action:"Select region"});
            if(hasSelectedObject && calibrated) hints.push({keys:["Enter"],action:"Edit region"});
            if(hasSelectedObject) hints.push({keys:["Del"],action:"Delete region"});
            if(placingObject) hints.push({keys:["Esc"],action:"Cancel placement"});
            else if(hasSelectedObject) hints.push({keys:["Esc"],action:"Deselect"});
        }
        hints.push({keys:["MMB"],action:"Pan"});
        return hints;
    }
    function copy(v) {return JSON.parse(JSON.stringify(v));}
    function fit() {
        zoom=fittedZoom;
        panX=(surface.width-imageSize[0]*zoom)/2;panY=(surface.height-imageSize[1]*zoom)/2;fitted=true;
    }
    function zoomAt(value,x,y) {
        const next=Math.max(fittedZoom*.02,Math.min(fittedZoom*32,value)),ratio=next/zoom;
        panX=x-(x-panX)*ratio;panY=y-(y-panY)*ratio;zoom=next;fitted=false;
    }
    function imagePoint(x,y) {return [(x-panX)/zoom,(y-panY)/zoom];}
    function within(p) {return p[0]>=0 && p[1]>=0 && p[0]<=imageSize[0]-1 && p[1]<=imageSize[1]-1;}
    function hitCorner(p) {
        for(let i=0;i<corners.length;i++)if(Math.hypot(p[0]-corners[i][0],p[1]-corners[i][1])*zoom<10)return i;
        return -1;
    }
    function selectObject(p) {
        let best=12/zoom,id="";
        for(const obj of projections)for(const edge of obj.edges || []) {
            const a=obj.vertices[edge[0]],b=obj.vertices[edge[1]];
            if(!a || !b)continue;
            const dx=b[0]-a[0],dy=b[1]-a[1],den=dx*dx+dy*dy;
            const t=Math.max(0,Math.min(1,den ? ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/den : 0));
            const distance=Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy);
            if(distance<best){best=distance;id=obj.id;}
        }
        selectedId=id;
    }
    function commit(next) {
        past=past.concat([copy(scene)]).slice(-100);future=[];
        sceneEdited(next);
    }
    function recordImportedScene(previous) {past=past.concat([copy(previous)]).slice(-100);future=[];}
    function undo() {if(!busy && past.length){future=future.concat([copy(scene)]);const next=past[past.length-1];past=past.slice(0,-1);sceneEdited(next);}}
    function redo() {if(!busy && future.length){past=past.concat([copy(scene)]);const next=future[future.length-1];future=future.slice(0,-1);sceneEdited(next);}}
    function mapHomography(matrix,p) {
        if(!matrix || matrix.length!==3)return null;
        const d=matrix[2][0]*p[0]+matrix[2][1]*p[1]+matrix[2][2];
        if(Math.abs(d)<1e-10)return null;
        return [(matrix[0][0]*p[0]+matrix[0][1]*p[1]+matrix[0][2])/d,(matrix[1][0]*p[0]+matrix[1][1]*p[1]+matrix[1][2])/d];
    }
    function worldAt(p) {return calibrated ? mapHomography(planeCalibration.inverseHomography,p) : null;}
    function openObject(existing,footprint) {
        objectDialog.draft=existing ? copy(existing) : {id:"spatial-"+Date.now()+"-"+Math.random().toString(36).slice(2,8),kind:"cuboid",label:"3D region",color:["#4db6ac","#ffb74d","#64b5f6","#e57373","#ba68c8","#aed581"][objects.length%6],position:[0,0,0],orientation:"xy",size:[.3048,.3048,.3048],yaw:0};
        if(!existing){const defaults=copy(operationDraft);objectDialog.draft.label=defaults.label || objectDialog.draft.label;objectDialog.draft.position=defaults.position;objectDialog.draft.size=defaults.size;objectDialog.draft.yaw=defaults.yaw;objectDialog.draft.orientation=defaults.orientation;}
        if(footprint){
            const axes=planeCalibration.referenceAxes || ["x","y"],u=referenceAxisVector(axes[0]),v=referenceAxisVector(axes[1]);
            const a=u.map((n,i)=>n*footprint[0][0]+v[i]*footprint[0][1]),b=u.map((n,i)=>n*footprint[1][0]+v[i]*footprint[1][1]);
            const spans=a.map((n,i)=>Math.abs(b[i]-n));objectDialog.draft.position=a.map((n,i)=>Math.min(n,b[i]));
            objectDialog.draft.size=spans.map((span,i)=>span>1e-8 ? span : operationDraft.size[i] || .3048);
        }
        objectDialog.errorMessage="";objectDialog.invalidLengths=({});objectNameField.text=objectDialog.draft.label;
        objectStore.resetRequested();objectDialog.open();
    }
    function openSettings() {
        if(mode==="calibration" && corners.length===4)measurement.open();
        else if(selectedId)openObject(objects.find(o=>o.id===selectedId));
    }
    function operationFinished(op,result) {
        if(!["save_reference_plane","calculate_spatial_calibration","set_spatial_calibration","project_spatial"].includes(op))return;
        if(result.ok){measurement.close();objectDialog.close();}
        else {
            if(measurement.opened)measurement.errorMessage=result.error;
            if(objectDialog.opened)objectDialog.errorMessage=result.error;
        }
    }
    function removeObject() {
        if(!selectedId || busy)return;
        const next=copy(scene);next.objects=(scene.objects || []).filter(o=>o.id!==selectedId);selectedId="";commit(next);
    }
    onModeChanged:{if(mode==="calibration" || !(objects || []).some(o=>o.id===selectedId && o.kind==="cuboid"))selectedId="";refreshOperationDraft();placingObject=false;footprintStart=[];footprintEnd=[];selectedCorner=-1;surface.forceActiveFocus();}
    property string acceptedReferenceKey:""
    function syncReferencePlane(force) {
        const reference=referencePlane;
        const key=JSON.stringify(reference ? {corners:reference.corners,width:reference.width,depth:reference.depth,axes:reference.axes || ["x","y"]} : null);
        // Background scene replies repeat the accepted plane; preserve local edits.
        if(!force && key===acceptedReferenceKey)return;
        acceptedReferenceKey=key;
        if(reference){corners=copy(reference.corners);referenceWidth=reference.width;referenceDepth=reference.depth;referenceAxes=(reference.axes || ["x","y"]).slice();}
        else {corners=[];referenceWidth=.3048;referenceDepth=.3048;referenceAxes=["x","y"];}
        canvas.requestPaint();
    }
    onReferencePlaneChanged:syncReferencePlane(false)
    onReferenceAxesChanged:canvas.requestPaint()
    onPlaneCalibrationChanged: {if(!referencePlane && planeCalibration){corners=copy(planeCalibration.corners);referenceWidth=planeCalibration.width;referenceDepth=planeCalibration.depth;referenceAxes=(planeCalibration.referenceAxes || ["x","y"]).slice();}canvas.requestPaint();}
    onSceneChanged:{refreshOperationDraft();canvas.requestPaint();}
    onProjectedObjectsChanged:canvas.requestPaint()
    onCornersChanged:canvas.requestPaint()
    onSelectedIdChanged:{refreshOperationDraft();canvas.requestPaint();}
    onZoomChanged:canvas.requestPaint()
    onPanXChanged:canvas.requestPaint()
    onPanYChanged:canvas.requestPaint()
    Component.onCompleted:Qt.callLater(fit)

    ToolLengthInput {id:lengthFormat;visible:false;width:0;height:0}
    Rectangle {anchors.fill:parent;color:Appearance.colors.colLayer0Base}
    ToolApp {
        id:chrome
        anchors.fill:parent
        controlsEnabled:!root.busy
        tools:[
            IconToolbarButton {
                text:root.mode==="calibration" ? "crop_free" : "add"
                enabled:root.mode==="calibration" || root.calibrated
                onClicked:{if(root.mode==="calibration"){root.corners=[];root.selectedCorner=-1;}else {root.placingObject=true;root.selectedId="";surface.forceActiveFocus();}}
                StyledToolTip {text:root.mode==="calibration" ? "Redraw reference plane" : "Add 3D region"}
            },
            IconToolbarButton {
                text:"edit";visible:root.mode!=="calibration";enabled:!!root.selectedId && root.calibrated
                onClicked:root.openObject(root.objects.find(o=>o.id===root.selectedId))
                StyledToolTip {text:"Edit selected object"}
            }
        ]
        contextActionsVisible:false
        Item {
            id:surface
            objectName:"spatialSurface"
            anchors.fill:parent
            focus:true
            clip:true
            Image {source:root.imageSource;x:root.panX;y:root.panY;width:root.imageSize[0]*root.zoom;height:root.imageSize[1]*root.zoom;smooth:true;cache:false}
            Canvas {
                id:canvas
                objectName:"spatialCanvas"
                anchors.fill:parent
                onPaint:{
                    const c=getContext("2d");c.reset();c.translate(root.panX,root.panY);c.scale(root.zoom,root.zoom);
                    const line=1.6/root.zoom;
                    for(const object of root.projections){
                        const selected=object.id===root.selectedId;c.strokeStyle=object.color || "#64b5f6";c.fillStyle=object.color || "#64b5f6";
                        for(const face of object.faces || []){
                            if(!face.length)continue;c.beginPath();
                            face.forEach((v,i)=>{const p=object.vertices[v];if(p){if(i)c.lineTo(p[0],p[1]);else c.moveTo(p[0],p[1]);}});
                            c.closePath();c.globalAlpha=selected ? .17 : .07;c.fill();c.globalAlpha=1;
                        }
                        c.lineWidth=selected ? line*2 : line;
                        for(const edge of object.edges || []){const a=object.vertices[edge[0]],b=object.vertices[edge[1]];if(a&&b){c.beginPath();c.moveTo(a[0],a[1]);c.lineTo(b[0],b[1]);c.stroke();}}
                        if(selected)for(const p of object.vertices){c.beginPath();c.arc(p[0],p[1],3/root.zoom,0,Math.PI*2);c.fill();}
                        if(object.vertices.length){const p=object.vertices[0];c.font=(12/root.zoom)+"px sans-serif";c.fillText(object.label || object.kind,p[0]+6/root.zoom,p[1]-6/root.zoom);}
                    }
                    if(root.footprintStart.length && root.footprintEnd.length && root.calibrated){
                        const a=root.footprintStart,b=root.footprintEnd;
                        const points=[[a[0],a[1]],[b[0],a[1]],[b[0],b[1]],[a[0],b[1]]].map(p=>root.mapHomography(root.planeCalibration.homography,p));
                        if(points.every(p=>p!==null)){c.strokeStyle=Appearance.colors.colPrimary;c.lineWidth=line;c.beginPath();points.forEach((p,i)=>{if(i)c.lineTo(p[0],p[1]);else c.moveTo(p[0],p[1]);});c.closePath();c.stroke();}
                    }
                    if(root.mode==="calibration" && root.corners.length){
                        c.strokeStyle=Appearance.colors.colPrimary;c.fillStyle=Appearance.colors.colPrimary;c.lineWidth=line;
                        c.beginPath();root.corners.forEach((p,i)=>{if(i)c.lineTo(p[0],p[1]);else c.moveTo(p[0],p[1]);});if(root.corners.length===4)c.closePath();c.stroke();
                        const axisLabels=root.referenceAxes.map(axis=>(axis.startsWith("-") ? "−" : "+")+axis.replace("-","").toUpperCase());const labels=["Origin",axisLabels[0],axisLabels.join(" "),axisLabels[1]];
                        root.corners.forEach((p,i)=>{c.beginPath();c.arc(p[0],p[1],(i===root.selectedCorner ? 6 : 4)/root.zoom,0,Math.PI*2);c.fill();c.font=(12/root.zoom)+"px sans-serif";c.fillText(labels[i],p[0]+8/root.zoom,p[1]-8/root.zoom);});
                    }
                }
            }
            Keys.onPressed:event=>{
                if(!root.keyboardEnabled)return;
                if(event.key===Qt.Key_Escape){root.placingObject=false;root.footprintStart=[];root.footprintEnd=[];canvas.requestPaint();root.selectedId="";root.selectedCorner=-1;event.accepted=true;}
                else if(event.key===Qt.Key_Enter || event.key===Qt.Key_Return){if(root.mode==="calibration" && root.corners.length===4)root.setReferencePlane();else if(root.mode!=="calibration" && root.hasSelectedObject && root.calibrated)root.openObject(root.objects.find(o=>o.id===root.selectedId));event.accepted=true;}
                else if(event.key===Qt.Key_Delete && root.mode!=="calibration" && root.hasSelectedObject){root.removeObject();event.accepted=true;}
                else if(event.modifiers&Qt.ControlModifier && event.key===Qt.Key_Z){if(event.modifiers&Qt.ShiftModifier)root.redo();else root.undo();event.accepted=true;}
                else if(event.modifiers&Qt.ControlModifier && event.key===Qt.Key_Y){root.redo();event.accepted=true;}
            }
            MouseArea {
                id:mouse
                objectName:"spatialMouse"
                anchors.fill:parent
                acceptedButtons:Qt.LeftButton|Qt.MiddleButton
                hoverEnabled:true
                property point last
                property bool panning:false
                onPressed:event=>{
                    surface.forceActiveFocus();last=Qt.point(event.x,event.y);
                    panning=event.button===Qt.MiddleButton;
                    if(panning || root.busy)return;
                    const p=root.imagePoint(event.x,event.y);
                    if(root.mode==="calibration"){
                        root.selectedCorner=root.hitCorner(p);
                        if(root.selectedCorner<0 && root.corners.length<4 && p.every(Number.isFinite)){
                            root.corners=root.corners.concat([p]);root.selectedCorner=root.corners.length-1;

                        }
                    } else if(root.placingObject && root.calibrated){const world=root.worldAt(p);if(world){root.footprintStart=world;root.footprintEnd=world;}}
                    else root.selectObject(p);
                }
                onPositionChanged:event=>{
                    if(panning){root.panX+=event.x-last.x;root.panY+=event.y-last.y;root.fitted=false;}
                    else if(pressed && root.mode==="calibration" && root.selectedCorner>=0 && !root.busy){const p=root.imagePoint(event.x,event.y);if(p.every(Number.isFinite)){const next=root.copy(root.corners);next[root.selectedCorner]=p;root.corners=next;}}
                    else if(pressed && root.placingObject && root.footprintStart.length){const world=root.worldAt(root.imagePoint(event.x,event.y));if(world){root.footprintEnd=world;canvas.requestPaint();}}
                    last=Qt.point(event.x,event.y);
                }
                onReleased:event=>{
                    panning=false;
                    if(root.placingObject && root.footprintStart.length){const world=root.worldAt(root.imagePoint(event.x,event.y));if(world)root.footprintEnd=world;}
                    if(root.placingObject && root.footprintStart.length && root.footprintEnd.length){
                        const footprint=[root.footprintStart,root.footprintEnd];
                        if(Math.abs(footprint[1][0]-footprint[0][0])>.001 && Math.abs(footprint[1][1]-footprint[0][1])>.001){root.placingObject=false;root.openObject(null,footprint);}
                        root.footprintStart=[];root.footprintEnd=[];canvas.requestPaint();
                    }
                }
                onDoubleClicked:if(!root.busy && root.selectedId && root.mode!=="calibration")root.openObject(root.objects.find(o=>o.id===root.selectedId))
                onWheel:event=>{root.zoomAt(root.zoom*Math.pow(1.0015,event.angleDelta.y),event.x,event.y);event.accepted=true;}
            }
        }
        status:[
            ToolCanvasFooter {
                id:footer
                showZoom:false
                leadingControls:ToolIconButton {
                    visible:false
                    implicitWidth:28;implicitHeight:28;Layout.fillHeight:false
                    text:"visibility";enabled:false;toggled:true
                    Accessible.name:"Corrected image"
                    StyledToolTip{text:"Spatial tools use the corrected image"}
                }
                Layout.fillWidth:true
                zoomPercent:100*root.zoom/root.fittedZoom;atReset:root.fitted
                onZoomEdited:percent=>root.zoomAt(root.fittedZoom*percent/100,surface.width/2,surface.height/2)
                onResetRequested:root.fit()
                showCursorCoordinates:!(root.mode==="calibration" && root.selectedCorner>=0)
                cursorActive:mouse.containsMouse && root.within(root.imagePoint(mouse.mouseX,mouse.mouseY))
                cursorX:root.imagePoint(mouse.mouseX,mouse.mouseY)[0];cursorY:root.imagePoint(mouse.mouseX,mouse.mouseY)[1]
                toolInputs:[
                    StyledText {
                        visible:root.calibrated
                        text:root.calibrated ? "Pose fit "+Number(root.planeCalibration.reprojectionRms).toFixed(2)+" px · assumed camera" : ""
                        font.pixelSize:Appearance.font.pixelSize.smaller
                        color:Appearance.colors.colSubtext
                    },
                    ToolPointCoordinates {
                        id:pointCoords
                        visible:root.mode==="calibration" && root.selectedCorner>=0
                        position:root.selectedCorner>=0 ? root.corners[root.selectedCorner] : []
                        selectionCount:root.selectedCorner>=0 ? 1 : 0
                        bounds:[]
                        enabled:!root.busy
                        onCoordinateEdited:(axis,value)=>{
                            const next=root.copy(root.corners);next[root.selectedCorner][axis]=value;root.corners=next;
                        }
                    }
                ]
                hints:root.contextHints
            }
        ]
    }
    ToolSettingsDialog {
        id:measurement
        objectName:"spatialMeasurement"
        title:"Reference plane"
        enabled:!root.busy
        preferredWidth:520
        property real planeWidth:.3048
        property real planeDepth:.3048
        onAboutToShow:{errorMessage="";planeWidth=root.referenceWidth;planeDepth=root.referenceDepth;}
        onApplyRequested:{root.referenceWidth=planeWidth;root.referenceDepth=planeDepth;root.saveReferencePlane();}
        contentItem:ColumnLayout {
            spacing:16
            ContentSection {
                title:"Size";icon:"straighten"
                RowLayout {StyledText{text:"Width"}Item{Layout.fillWidth:true}ToolLengthInput{metres:measurement.planeWidth;description:"Reference width";onEdited:value=>measurement.planeWidth=value}}
                RowLayout {StyledText{text:"Depth"}Item{Layout.fillWidth:true}ToolLengthInput{metres:measurement.planeDepth;description:"Reference depth";onEdited:value=>measurement.planeDepth=value}}
            }
        }
    }
    ToolSettingsDialog {
        id:objectDialog
        objectName:"spatialObjectDialog"
        enabled:!root.busy
        title:"3D region"
        preferredWidth:560
        height:Math.min(root.height-32,720)
        property var invalidLengths:({})
        property var draft:({kind:"cuboid",position:[0,0,0],size:[.3048,.3048,.3048],yaw:0})
        onApplyRequested:{
            if(Object.keys(invalidLengths).length){errorMessage="Enter lengths in feet and inches, for example 4' 7\".";return;}
            if(!objectNameField.text.trim()){errorMessage="Enter a name.";return;}
            const next=root.copy(root.scene),object=root.copy(draft);object.label=objectNameField.text.trim();
            const index=(next.objects || []).findIndex(o=>o.id===object.id);
            if(!next.objects)next.objects=[];
            if(index>=0)next.objects[index]=object;else next.objects.push(object);
            root.selectedId=object.id;root.commit(next);
        }
        QtObject {
            id:objectStore
            signal resetRequested()
            function get(path){const d=objectDialog.draft;if(path==="orientation")return d.orientation || "xy";if(path==="yaw")return d.yaw || 0;const [field,index]=path.split(".");return lengthFormat.formatted(d[field][Number(index)]);}
            function write(path,value){const d=root.copy(objectDialog.draft);if(path==="orientation")d.orientation=value;else if(path==="yaw")d.yaw=value;else{
                const parts=path.split("."),index=Number(parts[1]);
                if(String(value)===lengthFormat.formatted(d[parts[0]][index]))return;
                const metres=lengthFormat.parse(String(value)),invalid=Object.assign({},objectDialog.invalidLengths);
                if(!Number.isFinite(metres) || (parts[0]==="size" && metres<=0)){invalid[path]=true;objectDialog.invalidLengths=invalid;objectDialog.errorMessage="Use feet and inches, for example 4' 7\".";return;}
                delete invalid[path];objectDialog.invalidLengths=invalid;objectDialog.errorMessage="";d[parts[0]][index]=metres;
            }objectDialog.draft=d;}
        }
        contentItem:StyledFlickable {
            contentHeight:objectFields.implicitHeight;clip:true
            ColumnLayout {
                id:objectFields
                width:parent.width;spacing:16
                CompactTextField {id:objectNameField;Layout.fillWidth:true;placeholderText:"Name";maximumLength:120}
                ContentSection {
                    title:"Position";icon:"open_with"
                    SettingsControls.SettingsGroup {
                        valueStore:objectStore;showReset:false
                        section:({title:"",items:[0,1,2].map(i=>({kind:"preference",setting:{path:"position."+i,type:"string",label:["X · right","Y · back","Z · up"][i],icon:["swap_horiz","swap_vert","height"][i],}}))})
                    }
                }
                ContentSection {
                    title:"Size & orientation";icon:"view_in_ar"
                    SettingsControls.SettingsGroup {
                        valueStore:objectStore;showReset:false
                        section:({title:"",items:(objectDialog.draft.kind==="plane" ? [{kind:"preference",setting:{path:"orientation",type:"string",label:"Plane axes",icon:"view_in_ar",choices:[{name:"XY · horizontal",value:"xy"},{name:"XZ · vertical",value:"xz"},{name:"YZ · vertical",value:"yz"}]}}] : []).concat([0,1].concat(objectDialog.draft.kind==="cuboid" ? [2] : []).map(i=>({kind:"preference",setting:{path:"size."+i,type:"string",label:["Width","Depth","Height"][i],icon:"straighten",}}))).concat([{kind:"preference",setting:{path:"yaw",type:"real",label:"Rotation around Z",icon:"rotate_right",min:-180,max:180,step:1,unit:"°"}}])})
                    }
                }
            }
        }
    }
}
