import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.tool_app
import qs.modules.settings.desktop as SettingsControls
import "CurveGeometry.js" as CurveGeometry
import "CurveDiagnostics.js" as CurveDiagnostics
import "RegionGeometry.js" as RegionGeometry
import "../common/tool_app/ToolPointSelection.js" as PointSelection
import "../common/tool_app/ToolPolyline.js" as Polyline

Item {
    id: root
    component WorkspaceModePicker:ToolModePicker {
        id:selector
        objectName:"workspaceModePicker"
        Layout.preferredWidth:180;Layout.maximumWidth:180;Layout.fillWidth:false
        choices:[
            {name:"Lens correction",value:"lens",icon:"camera"},
            {name:"Reference plane",value:"calibration",icon:"grid_4x4",separatorBefore:true,enabled:root.hasLensCorrection}
        ]
        value:root.stage
        enabled:root.hasImage && !root.busy && !root.picking
        onChosen:value=>root.changeStage(value)
        Binding {target:selector;property:"currentIndex";value:selector.choices.findIndex(choice=>choice.value===root.stage);when:!selector.popup.visible}
    }
    property var curves: []
    property var correctedCurves: []
    property var curveDiagnostics:[]
    onCurveDiagnosticsChanged:if(viewport) viewport.requestPaint()
    property bool showRegions:true
    property bool showCalibrationCurves:true
    onShowRegionsChanged:if(viewport) viewport.requestPaint()
    onShowCalibrationCurvesChanged:if(viewport) viewport.requestPaint()
    property var regions: []
    property var nativeRegions:[]
    property var acceptedNativeRegions:[]
    property var acceptedNativeScene:({version:1,objects:[],regions:[]})
    property var nativeScene:({version:1,objects:[],regions:[]})
    property var referencePlane:null
    property var planeCalibration:null
    property var projectedScene:[]
    property string stage:"lens"
    readonly property bool hasLensCorrection:!!calibration && preview!==""
    readonly property bool hasReferencePlane:hasLensCorrection && !!planeCalibration && !planeCalibration.stale
    readonly property bool canExportBlender:hasReferencePlane && !spatialEditor.referenceDirty && !busy
    readonly property var spatialTools:spatialEditor
    readonly property var activeView:stage==="lens" ? root : spatialEditor
    readonly property var activeHistory:stage==="lens" ? root : spatialEditor
    property bool pendingNativeRegions:false
    property var pendingSpatialScene:null
    function unfinishedPolygon() {return false;}
    function polygonMustFinish() {status("Finish or cancel the unfinished polygon first.",true);}
    function changeStage(next) {
        if(["regions","planes","boxes"].includes(next))next=hasLensCorrection ? "calibration" : "lens";
        if(next!=="lens" && next!=="calibration")return false;
        if(next!=="lens" && !hasLensCorrection) {status("Calculate a lens correction first.",true);return false;}
        finishCurve();stage=next;return true;
    }
    function flushNativeEdits() {
        if(busy || !ready)return;
        if(pendingNativeRegions) {pendingNativeRegions=false;send("native_regions",{regions:nativeRegions});}
        else if(pendingSpatialScene) {const next=pendingSpatialScene;pendingSpatialScene=null;send("project_spatial",{nativeScene:next,calibration:calibration});}
    }
    function rollbackNativeOperation() {
        if(operation!=="native_regions" && operation!=="project_spatial")return;
        pendingNativeRegions=false;pendingSpatialScene=null;
        nativeRegions=copy(acceptedNativeRegions);nativeScene=copy(acceptedNativeScene);
    }
    onBusyChanged:if(!busy)Qt.callLater(flushNativeEdits)

    property var extraImages:[]
    property string activeImage:""
    property string annotationPreview:""
    readonly property var annotationImages:(sourcePath ? [{source:sourcePath,label:"Reference · "+sourcePath.substring(sourcePath.lastIndexOf("/")+1)}] : []).concat(extraImages.map(source=>({source:typeof source==="string" ? source : source.source,label:(typeof source==="string" ? source : source.source).substring((typeof source==="string" ? source : source.source).lastIndexOf("/")+1)})))
    property var batchRegions:[]
    readonly property bool hasRegions:regions.length>0 || batchRegions.some(batch=>batch.regions.length>0)
    property var calibration: null
    property var dimensions: [0, 0]
    property var outputDimensions:[0,0]
    readonly property var viewDimensions:corrected ? outputDimensions : dimensions
    property string original: ""
    property string preview: ""
    property string sourcePath: ""
    property alias projectPath: documentFlow.documentPath
    property var lensProfiles:[]
    property string lensProfilePath:""
    property alias recentProjects: documentFlow.recentFiles
    property string pendingLegacyPath:""
    property bool corrected: false
    property bool drawing: true
    property bool panTool: false
    property alias resumeAfterSave: documentFlow.resumeAfterSave
    property bool picking: false
    readonly property bool annotating:labelmeProcess.running
    property bool backgroundForLabelme:false
    property string labelmeJson:""
    property string fileAction: ""
    readonly property bool textEditing: pointCoordinates.inputFocused || k1.activeFocus || k2.activeFocus || canvasFooter.zoomFocused || lensOperations.inputFocused
    readonly property bool canvasShortcuts: stage==="lens" && !textEditing && !picking && !busy && !annotating && !legacyConversion.opened && !profileNameDialog.opened && !discard.opened && !adjustments.opened && !fileMenu.opened && !calibrationMenu.opened && !exportMenu.opened && !normalizeDialog.opened && !snapEdgesDialog.opened
    property bool snapping: true
    property bool busy: false
    property bool ready: false
    property alias dirty: documentFlow.dirty
    property alias discardConfirmed: documentFlow.discardConfirmed
    property alias pendingAction: documentFlow.pendingAction
    property alias pendingPath: documentFlow.pendingPath
    property string message: ""
    property bool error: false
    property int selected: -1
    property int selectedPoint: -1
    property bool allCurvePoints:false
    property var explicitPoints:[]
    onSelectedChanged:{allCurvePoints=false;explicitPoints=[];const detail=CurveDiagnostics.description(curveDiagnostics,selected);if(detail) notification.show(detail,true);}
    onSelectedPointChanged:{allCurvePoints=false;explicitPoints=[];}
    property int activeCurve: -1
    property bool extendFromStart:false
    onActiveCurveChanged:{if(activeCurve<0) extendFromStart=false;if(viewport) viewport.requestPaint();}
    onDrawingChanged:{if(!drawing) activeCurve=-1;if(viewport) viewport.requestPaint();}
    readonly property var selectedNodes:explicitPoints.length ? explicitPoints.filter(node=>node[0]>=0 && node[0]<curves.length && node[1]>=0 && node[1]<curves[node[0]].length) : selected>=0 && selected<curves.length && selectedPoint>=0 && selectedPoint<curves[selected].length ? (allCurvePoints ? curves[selected].map((p,i)=>[selected,i]) : [[selected,selectedPoint]]) : []
    readonly property var selectedIndices:selectedNodes.filter(node=>node[0]===selected).map(node=>node[1])
    readonly property var selectedPosition:PointSelection.centroidNodes(curves,selectedNodes)
    function translateSelection(dx,dy) {
        if(!selectedNodes.length) return;
        curves=PointSelection.translateNodes(curves,selectedNodes,dx,dy,dimensions).polylines;
        changed();
    }
    function togglePoint(curve,index) {
        const next=PointSelection.toggleNode(curves,selectedNodes,[curve,index]);
        selected=next.primary[0];selectedPoint=next.primary[1];allCurvePoints=next.wholePolyline;explicitPoints=next.nodes;
        viewport.requestPaint();
    }
    readonly property bool canConnectEndpoints:Polyline.canJoinSelectedEndpoints(curves,selectedNodes)
    function connectEndpoints() {
        if(!editable || drawing) return;
        const joined=Polyline.joinSelectedEndpoints(curves,selectedNodes);
        if(!joined.ok) {status(joined.error,true);return;}
        remember();curves=joined.polylines;
        selected=joined.joinedIndex;selectedPoint=-1;explicitPoints=[];allCurvePoints=false;activeCurve=-1;changed();
    }
    property var past: []
    property var future: []
    property string operation: ""
    property var pendingCalibration: null
    property int order: 0
    property var projectSettings:({hfov:null,snapping:true,order:0})
    property string settingsNextAction:""
    property real zoom: 1
    property real offsetX: 0
    property real offsetY: 0
    readonly property bool hasImage: original !== ""
    readonly property var cursorPosition: {
        if(!hasImage || !mouse.containsMouse) return [];
        const x=(mouse.mouseX-offsetX)/zoom,y=(mouse.mouseY-offsetY)/zoom;
        return x>=0 && y>=0 && x<viewDimensions[0] && y<viewDimensions[1] ? [x,y] : [];
    }
    readonly property bool editable: stage==="lens" && hasImage && !corrected && !busy && !picking && !annotating && !legacyConversion.opened
    onCorrectedChanged:viewport.requestPaint()
    function selectCurveTool(draw) {
        if(!hasImage || busy || picking || annotating)return;
        corrected=false;
        if(draw)finishCurve();
        panTool=false;drawing=draw;
        if(!draw)activeCurve=-1;
    }
    function buildLensHints() {
        if(stage!=="lens" || !canvasShortcuts || !hasImage)return [];
        const hints=[];
        if(corrected) {
            if(preview)hints.push({keys:["Tab"],action:"Original"});
            if(!viewAtReset)hints.push({keys:["F"],action:"Reset view"});
            hints.push({keys:["MMB"],action:"Pan"});
            return hints;
        }
        if(drawing){
            hints.push({keys:["LMB"],action:activeCurve>=0 ? "Add point" : "Start curve"});
            if(activeCurve>=0)hints.push({keys:["Enter"],action:"Finish curve"});
            if(activeCurve>=0 || selected>=0)hints.push({keys:["Esc"],action:"Deselect"});
        } else {
            if(curves.some(curve=>curve.length))hints.push({keys:["LMB"],action:selectedNodes.length ? "Drag points" : "Select"});
            if(selected>=0){
                hints.push({keys:["Del"],action:selectedNodes.length ? "Delete points" : "Delete curve"});
                if(selectedNodes.length){
                    hints.push({keys:["← ↑ ↓ →"],action:"Nudge"});
                    hints.push({keys:["Ctrl","LMB"],action:"Toggle point"});
                    hints.push({keys:["Shift","LMB"],action:"Select curve"});
                }
                if(canConnectEndpoints)hints.push({keys:["M"],action:"Connect"});
                hints.push({keys:["Esc"],action:"Deselect"});
            }
            if(mouse.containsMouse){
                const query=[(mouse.mouseX-offsetX)/zoom,(mouse.mouseY-offsetY)/zoom];
                if(curves.some(curve=>CurveGeometry.nearestPolyline(curve,query,10/zoom)!==null))hints.push({keys:["Alt","LMB"],action:"Insert point"});
            }
        }
        if(!selectedNodes.length){
            hints.push({keys:["MMB"],action:"Pan"});
            if(preview)hints.push({keys:["Tab"],action:"Corrected"});
            if(!viewAtReset)hints.push({keys:["F"],action:"Reset view"});
        }
        return hints;
    }
    function copy(v) { return JSON.parse(JSON.stringify(v)); }
    function staleMappingMessage(op) {
        if(planeCalibration && planeCalibration.stale)
            return "3D calibration uses an older lens correction. Save the reference plane and calculate 3D again before exporting.";
        if(nativeScene && nativeScene.mappingStale && (nativeScene.regions || []).length>0 && ["calibrate","preview","load","load_preset","convert_legacy"].includes(op))
            return "2D regions use an older lens correction. Review or redraw those regions before exporting them.";
        return "";
    }
    function status(text, failed) { message=text; error=!!failed;operationFeedback.report(operation,text,failed); }
    ToolOperationFeedback {id:operationFeedback;silentSuccessOperations:["save","save_as","set_settings"];onToastRequested:(text,failed)=>notification.show(text,failed)}
    property var modelRecommendation: null
    ToolToast {
        id:notification
        objectName:"operationToast"
        actionEnabled: !root.busy && !root.picking && !root.annotating && root.modelRecommendation !== null
        onActionTriggered: {
            const recommendation=root.modelRecommendation;
            root.modelRecommendation=null;
            if(recommendation && recommendation.order===2) root.send("calibrate",{order:2});
        }
    }
    function invalidate() {
        modelRecommendation=null;
        notification.actionText="";
        curveDiagnostics=[];
        stage="lens";pendingNativeRegions=false;
        if(nativeScene.objects.length || nativeRegions.length) nativeScene=Object.assign({},nativeScene,{mappingStale:true});
        if(planeCalibration) planeCalibration=Object.assign({},planeCalibration,{stale:true});
        calibration=null; preview=""; corrected=false; regions=[]; batchRegions=[];correctedCurves=[]; dirty=true;
        viewport.requestPaint();
    }
    function finishCurve() {
        activeCurve=-1;selected=-1;selectedPoint=-1;viewport.requestPaint();
    }
    function remember() { past=past.concat([copy(curves)]).slice(-100); future=[]; }
    function changed() { curves=copy(curves); invalidate(); }
    function restoreHistoryCurves(snapshot) {
        const continuation=activeCurve,fromStart=extendFromStart;
        const keepDrawing=drawing && continuation>=0;
        curves=snapshot;
        if(keepDrawing && continuation<curves.length && curves[continuation].length>0) {
            activeCurve=continuation;extendFromStart=fromStart;
            selected=continuation;selectedPoint=fromStart ? 0 : curves[continuation].length-1;
        } else {activeCurve=-1;selected=-1;selectedPoint=-1;}
        invalidate();
    }
    function undo() {
        if(busy || picking || annotating || !past.length) return;
        future=future.concat([copy(curves)]);
        const snapshot=past[past.length-1];past=past.slice(0,-1);
        restoreHistoryCurves(snapshot);
    }
    function redo() {
        if(busy || picking || annotating || !future.length) return;
        past=past.concat([copy(curves)]);
        const snapshot=future[future.length-1];future=future.slice(0,-1);
        restoreHistoryCurves(snapshot);
    }
    function removePointOrCurve(whole) {
        if (!editable || drawing || panTool || selected<0) return;
        remember();
        if(!whole && selectedNodes.length) {
            const nodes=copy(selectedNodes).sort((a,b)=>b[0]-a[0] || b[1]-a[1]);
            for(const node of nodes) curves[node[0]].splice(node[1],1);
            curves=curves.filter(curve=>curve.length>0);
        } else curves.splice(selected,1);
        activeCurve=-1;selected=-1;selectedPoint=-1;explicitPoints=[];allCurvePoints=false;changed();
    }
    function displayCoordinate(value) {return String(Number(value.toFixed(3)));}
    function setCoordinate(axis, text) {
        const value=Number(text);
        if(!editable || drawing || panTool || selected<0 || selectedPoint<0) return;
        if(!String(text).trim() || !Number.isFinite(value) || value<0 || value>dimensions[axis]-1) {status("Coordinate outside the image.",true);return;}
        if(value===selectedPosition[axis] || String(text)===displayCoordinate(selectedPosition[axis])) return;
        remember();translateSelection(axis===0 ? value-selectedPosition[0] : 0,axis===1 ? value-selectedPosition[1] : 0);
    }
    // 100% is the original image's fitted display footprint, never pixel scale.
    readonly property var fittedView: {
        if(!hasImage || dimensions[0]<=0 || dimensions[1]<=0 || viewDimensions[0]<=0 || viewDimensions[1]<=0)
            return {zoom:1,x:0,y:0,width:0,height:0,cx:0,cy:0};
        const originalScale=Math.min(Math.max(1,viewport.width-96)/dimensions[0],viewport.height/dimensions[1])*.94;
        const scale=Math.min(dimensions[0]*originalScale/viewDimensions[0],dimensions[1]*originalScale/viewDimensions[1]);
        const cx=80+(viewport.width-80)/2,cy=viewport.height/2;
        return {zoom:scale,x:cx-viewDimensions[0]*scale/2,y:cy-viewDimensions[1]*scale/2,width:viewDimensions[0],height:viewDimensions[1],cx:cx,cy:cy};
    }
    property var previousFit:null
    readonly property real viewZoomPercent:100*zoom/fittedView.zoom
    onFittedViewChanged: {
        const old=previousFit,next=fittedView;
        previousFit=next;
        if(old && old.width>0 && next.width>0 && zoom>0) {
            const relative=zoom/old.zoom;
            const anchorX=(old.cx-offsetX)/(old.width*zoom),anchorY=(old.cy-offsetY)/(old.height*zoom);
            zoom=next.zoom*relative;
            offsetX=next.cx-anchorX*next.width*zoom;
            offsetY=next.cy-anchorY*next.height*zoom;
            viewport.requestPaint();
        }
    }
    readonly property bool viewAtReset:Math.abs(zoom-fittedView.zoom)<1e-8 && Math.abs(offsetX-fittedView.x)<.01 && Math.abs(offsetY-fittedView.y)<.01
    function fit() {
        if(!hasImage) return;
        zoom=fittedView.zoom;offsetX=fittedView.x;offsetY=fittedView.y;viewport.requestPaint();
    }
    function setZoomPercent(percent) {
        if(!hasImage || !Number.isFinite(percent) || percent<2 || percent>3200) return;
        const old=zoom, next=fittedView.zoom*percent/100,cx=viewport.width/2,cy=viewport.height/2;
        offsetX=cx-(cx-offsetX)*next/old;offsetY=cy-(cy-offsetY)*next/old;
        zoom=next;viewport.requestPaint();
    }
    function acceptCalibration(next) {
        const previous=calibration;
        const changed=!previous || JSON.stringify(previous.coefficients)!==JSON.stringify(next.coefficients) || (previous.hfov || null)!==(next.hfov || null);
        calibration=next;
        if(changed) {regions=[];batchRegions=[];}
    }
    function send(op, extra) {
        if (busy || !ready) return;
        if(["open","load","convert_legacy","save"].includes(op) && unfinishedPolygon()) {polygonMustFinish();return;}
        if(legacyConversion.opened && pendingLegacyPath) return;
        if(op==="load" && extra && /\.lensproject$/i.test(extra.path || "")) {
            pendingLegacyPath=extra.path;legacyConversion.open();return;
        }
        modelRecommendation=null; notification.actionText="";
        operation=op; busy=true; status("");
        const request=Object.assign({op:op, curves:curves, calibration:calibration},extra || {});
        if(op==="save" && spatialEditor.corners.length===4) request.referencePlane={corners:root.copy(spatialEditor.corners),width:spatialEditor.referenceWidth,depth:spatialEditor.referenceDepth,axes:spatialEditor.referenceAxes.slice()};
        worker.write(JSON.stringify(request)+"\n");
    }
    function confirmLegacyConversion() {
        const path=pendingLegacyPath;
        pendingLegacyPath="";legacyConversion.close();
        if(path) send("convert_legacy",{path:path});
    }
    function clearContinuation() { documentFlow.cancelContinuation(); }
    function restoreFromLabelme() {
        if(!backgroundForLabelme) return;
        backgroundForLabelme=false;
        const window=root.Window.window;
        if(window) {window.show();window.requestActivate();}
    }
    ToolFileType {
        id:projectFileType
        label:"Lens Cap project";extension:".lenscap";legacyExtensions:[".lensproject"]
        mimeType:"application/x-lens-calibration-project";icon:"camera"
    }
    ToolDocumentController {
        id:documentFlow
        available:root.ready && !root.annotating && !legacyConversion.opened
        hasDocument:root.hasImage
        busy:root.busy || root.pendingNativeRegions || root.pendingSpatialScene!==null
        picking:root.picking
        onOperationRequested:(op,path)=> {
            if(op==="load" && !projectFileType.accepts(path)) {failed();root.status("Choose a .lenscap project file.",true);return;}
            root.send(op,{path:path});
        }
        onPickerRequested:action=> {
            root.fileAction=action;root.picking=true;
            if(!picker.open(root.filePickerDescriptor(action))) {root.picking=false;failed();}
        }
        onDiscardConfirmationRequested:discard.open()
        onCloseRequested:root.Window.window.close()
        onErrorOccurred:message=>root.status(message,true)
    }
    function isProjectFile(path) {return projectFileType.accepts(path);}
    function newProjectName(path) {return projectFileType.suggestedName(path);}
    property string blenderRecalibrationSource:""
    function cancelBlenderRecalibration() {blenderRecalibrationSource="";}
    function filePickerDescriptor(action) {
        const mode=["open","load","labelme","load_preset","add_images","recalibrate_blend_source"].indexOf(action)>=0 ? "open" : "save";
        const project=["load","save","save_as"].indexOf(action)>=0;
        const image=action==="open" || action==="add_images";
        const sceneObj=action==="scene_obj";
        const sceneBlend=["scene_blend","recalibrate_blend_source","recalibrate_blend_target"].includes(action);
        const basePath=action==="recalibrate_blend_target" && blenderRecalibrationSource ? blenderRecalibrationSource : project && projectPath ? projectPath : sourcePath;
        const filters=project ? [{name:projectFileType.label,patterns:projectFileType.patterns}]
            : image ? [{name:"Images",patterns:["*.png","*.jpg","*.jpeg","*.bmp","*.webp","*.PNG","*.JPG","*.JPEG"]}]
            : [{name:sceneBlend ? "Blender scene" : sceneObj ? "Wavefront OBJ" : action==="image" ? "PNG image" : action==="export_labelme" ? "LabelMe annotations" : action==="regions" ? "Frigate zones" : "JSON",patterns:[sceneBlend ? "*.blend" : sceneObj ? "*.obj" : action==="image" ? "*.png" : "*.json"]}];
        return {appId:"org.quickshell.LensCalibration",appName:"Lens Cap",mode:mode,filters:filters,
            folder:basePath ? basePath.substring(0,basePath.lastIndexOf("/")) : Quickshell.env("HOME"),
            name:project ? (projectPath ? projectFileType.suggestedName(projectPath.substring(projectPath.lastIndexOf("/")+1)) : "Untitled.lenscap") : action==="recalibrate_blend_target" && blenderRecalibrationSource ? blenderRecalibrationSource.substring(blenderRecalibrationSource.lastIndexOf("/")+1).replace(/\.blend$/i,"")+"-recalibrated.blend" : ["scene_blend","recalibrate_blend_source"].includes(action) ? "scene.blend" : action==="scene_obj" ? "scene.obj" : action==="scene_json" ? "scene.json" : action==="image" ? "corrected.png" : action==="regions" ? "frigate-zones.json" : action==="export_labelme" ? (activeImage || sourcePath || "image").substring((activeImage || sourcePath || "image").lastIndexOf("/")+1).replace(/\.[^.]+$/,"")+"-distorted.json" : action==="save_preset" ? "lens-profile.json" : "calibration.json",
            multiple:action==="add_images",purpose:project ? "project" : image ? "image" : ["load_preset","save_preset"].indexOf(action)>=0 ? "preset" : action,
            historyNamespace:"lens-calibration",primaryExtension:projectFileType.extension,extensions:projectFileType.extensions};
    }
    function filePickerCommand(action) {return picker.commandFor(filePickerDescriptor(action));}
    function file(action,preferredPath) {
        if(ribbonSettingsDraft || ribbonCoefficientDraft) {
            pendingRibbonDocument={action:action,path:preferredPath || ""};
            flushRibbonChanges();return false;
        }
        return fileNow(action,preferredPath);
    }
    function fileNow(action,preferredPath) {
        if(["recalibrate_blend_source","recalibrate_blend_target"].includes(action) && !canExportBlender) {cancelBlenderRecalibration();status("Calculate the current reference plane before recalibrating a Blender file.",true);return false;}
        if(action==="recalibrate_blend_source")cancelBlenderRecalibration();
        if(action==="import_blend") {status("Region editing is handled in LabelMe.",true);return false;}
        if(["save","save_as","open","load"].includes(action) && unfinishedPolygon()) {polygonMustFinish();return false;}
        if(pendingNativeRegions || pendingSpatialScene!==null) {flushNativeEdits();status("Finish saving the current edit first.",true);return false;}
        return documentFlow.request(action,preferredPath);
    }
    function requestClose() {
        if(ribbonSettingsDraft || ribbonCoefficientDraft) {flushRibbonChanges();status("Finish applying the current edit first.");return false;}
        if(unfinishedPolygon()) {polygonMustFinish();return false;}
        if(pendingNativeRegions || pendingSpatialScene!==null) {flushNativeEdits();status("Finish saving the current edit first.",true);return false;}
        return documentFlow.requestClose();
    }
    readonly property real defaultHfov:2*Math.atan(dimensions[0]/(2*Math.max(dimensions[0],dimensions[1],1)))*180/Math.PI
    property var ribbonSettingsDraft:null
    readonly property var ribbonSettings:ribbonSettingsDraft || projectSettings
    property var ribbonCoefficientDraft:null
    readonly property var ribbonCoefficients:ribbonCoefficientDraft || (calibration ? calibration.coefficients : [0,0])
    property var pendingRibbonDocument:null
    function queueRibbonSettings(change) {
        ribbonSettingsDraft=Object.assign({},ribbonSettings,change);
        dirty=true;ribbonSettingsTimer.restart();
    }
    function queueRibbonCoefficient(index,value) {
        if(!calibration || !Number.isFinite(value))return;
        const next=ribbonCoefficients.slice();next[index]=value;
        ribbonCoefficientDraft=next;dirty=true;ribbonCoefficientTimer.restart();
    }
    function flushRibbonChanges() {
        if(busy)return;
        if(ribbonSettingsDraft) {
            ribbonSettingsTimer.stop();ribbonCoefficientTimer.stop();ribbonCoefficientDraft=null;
            send("set_settings",{projectSettings:ribbonSettingsDraft});
        } else if(ribbonCoefficientDraft && calibration) {
            ribbonCoefficientTimer.stop();
            pendingCalibration=Object.assign({},calibration,{coefficients:ribbonCoefficientDraft.slice(),manual:true});
            delete pendingCalibration.rmsBefore;delete pendingCalibration.rmsAfter;
            send("preview",{calibration:pendingCalibration});
        }
    }
    function cancelRibbonCoefficient() {ribbonCoefficientTimer.stop();ribbonCoefficientDraft=null;}
    readonly property bool canOpenLabelme:ready && hasLensCorrection && !busy && !picking && !annotating
    property bool pendingLabelmeLaunch:false
    function labelmeCommand(result) {return [Quickshell.env("HOME")+"/.local/bin/labelme",result.labelmeImage,"--output",result.labelmeOutputDir];}
    function openLabelme() {
        if(!canOpenLabelme)return false;
        if(ribbonSettingsDraft || ribbonCoefficientDraft) {pendingLabelmeLaunch=true;flushRibbonChanges();return true;}
        finishCurve();send("prepare_labelme",{});return true;
    }
    function calculateFromRibbon() {
        ribbonCoefficientTimer.stop();ribbonCoefficientDraft=null;
        if(ribbonSettingsDraft) {settingsNextAction="calibrate";flushRibbonChanges();}
        else {finishCurve();send("calibrate",{order:order});}
    }
    function toggleRibbonView() {if(preview){corrected=!corrected;viewport.requestPaint();}}
    function openStageSettings() {spatialEditor.openSettings();}
    Timer {id:ribbonSettingsTimer;interval:650;onTriggered:if(root.busy)restart();else root.flushRibbonChanges()}
    Timer {id:ribbonCoefficientTimer;interval:650;onTriggered:if(root.busy)restart();else root.flushRibbonChanges()}
    function applyProjectSettings(next) {
        if(customFov.checked && (hfovInput.invalid || !Number.isFinite(calibrationMenu.draftHfov) || calibrationMenu.draftHfov<1 || calibrationMenu.draftHfov>179)) {status("Horizontal field of view must be 1–179°.",true);return;}
        settingsNextAction=next || "";
        send("set_settings",{projectSettings:{hfov:customFov.checked ? calibrationMenu.draftHfov : null,snapping:snapSetting.checked,order:modelSetting.currentIndex}});
        calibrationMenu.close();
    }
    function applyAdjustment() {
        const a=Number(k1.text), b=Number(k2.text);
        if (!k1.text.trim() || !k2.text.trim() || !Number.isFinite(a) || !Number.isFinite(b)) { status("Enter finite coefficients.",true); return; }
        pendingCalibration=Object.assign({},calibration,{coefficients:[a,b],manual:true});
        delete pendingCalibration.rmsBefore; delete pendingCalibration.rmsAfter;
        send("preview",{calibration:pendingCalibration}); adjustments.close();
    }
    Process {
        id: worker
        command: [Quickshell.env("HOME")+"/.local/share/lens-calibration/venv/bin/python", Quickshell.shellPath("scripts/lens_calibration/backend.py")]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                let result;
                try { result=JSON.parse(data); } catch(e) { root.rollbackNativeOperation();root.status("Invalid backend response",true); root.busy=false;root.restoreFromLabelme(); return; }
                if(result.lensProfiles) root.lensProfiles=result.lensProfiles;
                if(Object.prototype.hasOwnProperty.call(result,"profilePath")) root.lensProfilePath=result.profilePath;
                if(result.recentProjects) root.recentProjects=result.recentProjects;
                if (result.ready) {
                    root.ready=true;
                    const project=Quickshell.env("QS_LENS_PROJECT"), legacy=Quickshell.env("QS_LENS_SESSION");
                    if(project && !root.isProjectFile(project)) root.status("Choose a .lenscap project file.",true);
                    else if(project || legacy) root.send("load",{path:project || legacy});
                    return;
                }
                root.busy=false;
                spatialEditor.operationFinished(root.operation,result);
                if(root.operation==="finish_labelme") root.restoreFromLabelme();
                if(result.outputGeometry) root.outputDimensions=result.outputGeometry.size;
                if (!result.ok) {
                    root.rollbackNativeOperation();
                    if(["save_profile","rename_profile"].indexOf(root.operation)>=0) lensOperations.profileFinished(false,result.error);
                    root.pendingLabelmeLaunch=false;
                    root.pendingRibbonDocument=null;
                    root.ribbonSettingsDraft=null;root.ribbonCoefficientDraft=null;
                    if(root.operation==="calibrate") {
                        root.curveDiagnostics=CurveDiagnostics.normalized(result.diagnostics,root.curves.length);
                        if(root.curveDiagnostics.length) root.corrected=false;
                    }
                    root.settingsNextAction="";
                    root.pendingCalibration=null;
                    root.clearContinuation();
                    const details=root.operation==="calibrate" ? CurveDiagnostics.summary(root.curveDiagnostics) : "";
                    root.status(result.error+(details ? "\n"+details : ""),true);
                    if(root.operation==="calibrate" && result.recommendation && result.recommendation.order===2) {
                        root.modelRecommendation=result.recommendation;
                        notification.actionText="Use k1+k2";
                    }
                    return;
                }
                if(Object.prototype.hasOwnProperty.call(result,"activeImage")) root.activeImage=result.activeImage;
                if(Object.prototype.hasOwnProperty.call(result,"annotationPreview")) root.annotationPreview=result.annotationPreview;
                if(Object.prototype.hasOwnProperty.call(result,"nativeRegions")) {root.nativeRegions=root.copy(result.nativeRegions);root.acceptedNativeRegions=root.copy(result.nativeRegions);}
                if(Object.prototype.hasOwnProperty.call(result,"nativeScene")) {root.nativeScene=root.copy(result.nativeScene);root.acceptedNativeScene=root.copy(result.nativeScene);}
                if(Object.prototype.hasOwnProperty.call(result,"referencePlane")) root.referencePlane=result.referencePlane;
                if(Object.prototype.hasOwnProperty.call(result,"planeCalibration")) root.planeCalibration=result.planeCalibration;
                if(Object.prototype.hasOwnProperty.call(result,"projectedScene")) root.projectedScene=result.projectedScene;
                if(result.projectSettings) {root.ribbonSettingsDraft=null;root.projectSettings=result.projectSettings;root.snapping=result.projectSettings.snapping;root.order=result.projectSettings.order;}
                if(["save_profile","rename_profile"].indexOf(root.operation)>=0) {profileNameDialog.close();lensOperations.profileFinished(true,"");}
                if(root.operation==="normalize_vertices") normalizeDialog.close();
                if(root.operation==="snap_vertices_to_edges") snapEdgesDialog.close();
                if(root.operation==="load_preset" && calibrationMenu.opened) calibrationMenu.syncDraft();
                if (root.operation==="open" || root.operation==="load" || root.operation==="convert_legacy") {
                    root.stage="lens";root.pendingNativeRegions=false;root.pendingSpatialScene=null;root.activeImage=result.activeImage || result.source;root.annotationPreview=result.annotationPreview || "";root.nativeRegions=result.nativeRegions || [];root.nativeScene=result.nativeScene || {version:1,objects:[],regions:[]};root.planeCalibration=result.planeCalibration || null;root.projectedScene=result.projectedScene || [];
                    root.acceptedNativeRegions=root.copy(root.nativeRegions);root.acceptedNativeScene=root.copy(root.nativeScene);
                    root.original=""; root.original=result.original+"?v="+Date.now();
                    root.dimensions=result.size; root.outputDimensions=result.outputGeometry ? result.outputGeometry.size : result.size; root.sourcePath=result.source;
                    spatialEditor.syncReferencePlane(true);
                    documentFlow.opened(root.operation!=="open" ? (result.projectPath || "") : "");
                    root.lensProfilePath="";root.curveDiagnostics=[];root.curves=result.curves; root.calibration=result.calibration;root.curveDiagnostics=CurveDiagnostics.normalized(result.calibration && result.calibration.diagnostics,root.curves.length);
                    if(!result.projectSettings) root.order=result.calibration && result.calibration.order===2 ? 2 : 1;
                    root.regions=result.regions; root.extraImages=result.extraImages || [];root.batchRegions=result.batchRegions || [];root.preview=result.preview || "";
                    root.correctedCurves=result.correctedCurves || [];
                    root.past=[]; root.future=[]; root.dirty=false;
                    root.selected=-1; root.selectedPoint=-1; root.activeCurve=-1; root.corrected=false; root.clearContinuation();
                    Qt.callLater(root.fit);
                } else {
                    if(["set_settings","clear_profile"].indexOf(root.operation)>=0 && Object.prototype.hasOwnProperty.call(result,"calibration") && result.calibration===null) {root.calibration=null;root.preview="";root.corrected=false;root.correctedCurves=[];root.regions=[];root.batchRegions=[];}
                    if(root.operation==="clear_profile") {root.lensProfilePath="";root.dirty=true;}
                    if(["set_settings","save_reference_plane","calculate_spatial_calibration","set_spatial_calibration"].includes(root.operation)) root.dirty=true;
                    if (result.calibration) { root.curveDiagnostics=CurveDiagnostics.normalized(result.calibration.diagnostics,root.curves.length);root.acceptCalibration(result.calibration); root.dirty=true; }
                    if (root.pendingCalibration) { root.acceptCalibration(root.pendingCalibration); root.pendingCalibration=null; root.dirty=true; }
                    if (result.preview) { root.preview=result.preview; root.correctedCurves=result.correctedCurves; root.corrected=true; }
                    if (result.regions) { root.regions=result.regions; root.dirty=true; }
                    if(result.extraImages) {root.extraImages=result.extraImages;root.dirty=true;}
                    if(result.batchRegions) {root.batchRegions=result.batchRegions;root.dirty=true;}
                    if(root.operation==="load_preset") {root.curveDiagnostics=[];root.curves=[];root.correctedCurves=[];root.selected=-1;root.selectedPoint=-1;root.activeCurve=-1;root.past=[];root.future=[];}
                    if(root.operation==="save") documentFlow.saved(result.projectPath);

                }
                if(result.labelmeImage) {
                    root.labelmeJson=result.labelmeJson;
                    labelmeProcess.command=root.labelmeCommand(result);
                    labelmeProcess.launchPending=true;
                    labelmeProcess.running=true;
                    root.status("LabelMe · Save annotations, then close to return"+(result.labelmeNotice ? "\n"+result.labelmeNotice : ""));
                }
                if (result.message) root.status(result.message);
                else if (result.calibration && root.operation==="calibrate")
                    root.status((result.calibration.modelSelection==="auto" ? "Auto · "+(result.calibration.order===2 ? "k1+k2" : "k1")+" · " : "")+result.calibration.rmsBefore.toFixed(3)+" → "+result.calibration.rmsAfter.toFixed(3)+" px RMS"+(result.calibration.ignoredCurves ? " · "+result.calibration.ignoredCurves+" traces need a third distinct point" : "")+(root.curveDiagnostics.length ? "\n"+CurveDiagnostics.summary(root.curveDiagnostics) : ""));
                if(root.operation==="calibrate" && result.calibration) {
                    const warnings=result.calibration.warnings || [];
                    root.modelRecommendation=result.calibration.recommendation || null;
                    if(warnings.length || root.modelRecommendation) {
                        const summary=result.calibration.rmsBefore.toFixed(2)+" → "+result.calibration.rmsAfter.toFixed(2)+" px RMS";
                        const explanation=warnings.concat(root.curveDiagnostics.length ? [CurveDiagnostics.summary(root.curveDiagnostics)] : []).join("\n");
                        notification.show(summary+(explanation ? "\n"+explanation : ""),false,root.modelRecommendation && root.modelRecommendation.order===2 ? "Use k1+k2" : "");
                    }
                }
                const staleMessage=root.staleMappingMessage(root.operation);
                if(staleMessage)notification.show(staleMessage,true);
                if(root.operation==="preview")root.ribbonCoefficientDraft=null;
                if(root.pendingLabelmeLaunch && !root.settingsNextAction) {root.pendingLabelmeLaunch=false;Qt.callLater(()=>{if(!root.openLabelme())root.status("Calculate a lens correction before opening LabelMe.",true);});}
                if(root.pendingRibbonDocument && !root.settingsNextAction) {const pending=root.pendingRibbonDocument;root.pendingRibbonDocument=null;Qt.callLater(()=>root.file(pending.action,pending.path));}
                viewport.requestPaint();
                if(root.operation==="set_settings" && root.settingsNextAction) {const next=root.settingsNextAction;root.settingsNextAction="";Qt.callLater(() => {if(next==="calibrate") {root.activeCurve=-1;root.send("calibrate",{order:root.order});}});}
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) console.warn("Lens worker:",text) }
        onExited: { root.rollbackNativeOperation();root.ready=false; root.busy=false; root.restoreFromLabelme();root.status("Image worker stopped. Reopen the application.",true); }
    }
    IpcHandler {
        target: "lensCalibration"
        function openSession(path: string): bool {
            if(root.busy || root.dirty) return false;
            root.send("load",{path:path}); return true;
        }
        function openProject(path: string): bool {
            if(!root.isProjectFile(path)) {root.status("Choose a .lenscap project file.",true);return false;}
            if(root.busy || root.picking || root.annotating || legacyConversion.opened || !root.ready) return false;
            if(root.Window.window) {root.Window.window.show();root.Window.window.requestActivate();}
            root.file("load",path);return true;
        }
        function state(): string {
            return JSON.stringify({ready:root.ready,busy:root.busy,error:root.error,message:root.message,
                curves:root.curves.length,calibration:root.calibration,size:root.dimensions,outputSize:root.outputDimensions,corrected:root.corrected,projectPath:root.projectPath});
        }
        function calculate(): bool {
            if(root.busy || !root.hasImage) return false;
            root.send("calibrate",{order:root.order}); return true;
        }
        function toggleView(): void { if(root.preview) {root.corrected=!root.corrected;viewport.requestPaint();} }
    }
    Process {
        id:labelmeProcess
        objectName:"labelmeProcess"
        property bool launchPending:false
        onStarted: {
            launchPending=false;
            root.backgroundForLabelme=true;
            if(root.Window.window) root.Window.window.hide();
        }
        onRunningChanged:if(!running && launchPending) Qt.callLater(() => {
            if(!running && launchPending) {launchPending=false;root.restoreFromLabelme();root.status("LabelMe could not start.",true);}
        })
        stdout:StdioCollector {}
        stderr:StdioCollector {onStreamFinished:if(text) console.log("LabelMe:",text)}
        onExited:(exitCode,exitStatus)=> {
            launchPending=false;
            if(root.ready && root.labelmeJson) root.send("finish_labelme",{path:root.labelmeJson});
            else {root.restoreFromLabelme();root.status("LabelMe could not start.",true);}
        }
    }
    ToolFilePicker {
        id:picker
        objectName:"workspaceFilePicker"
        onRunningChanged:root.picking=running
        onFailed:message=> {root.picking=false;root.cancelBlenderRecalibration();documentFlow.failed();root.status(message,true);}
        onCancelled:{root.picking=false;root.cancelBlenderRecalibration();documentFlow.pickerCancelled();}
        onSelected:(path,paths)=> {
            root.picking=false;
            if(root.fileAction==="add_images") {root.send("add_images",{paths:paths});return;}
            let selected=path;
            if(root.fileAction==="recalibrate_blend_source") {
                if(!selected.toLowerCase().endsWith(".blend")) {root.cancelBlenderRecalibration();root.status("Choose a .blend file.",true);return;}
                root.blenderRecalibrationSource=selected;
                Qt.callLater(()=>root.file("recalibrate_blend_target"));return;
            }
            if(root.fileAction==="recalibrate_blend_target") {
                if(!selected.toLowerCase().endsWith(".blend"))selected+=".blend";
                const source=root.blenderRecalibrationSource;
                if(!source) {root.status("Choose a Blender file to recalibrate first.",true);return;}
                if(selected===source) {root.cancelBlenderRecalibration();root.status("Save the recalibrated scene as a new Blender file.",true);return;}
                root.cancelBlenderRecalibration();
                if(!root.canExportBlender) {root.status("Calculate the current reference plane before recalibrating a Blender file.",true);return;}
                root.send("recalibrate_blend",{sourcePath:source,path:selected});return;
            }
            if(["scene_json","scene_obj","scene_blend"].includes(root.fileAction)) {
                const format=root.fileAction==="scene_blend" ? "blend" : root.fileAction==="scene_obj" ? "obj" : "json";
                if(!selected.toLowerCase().endsWith("."+format))selected+="."+format;
                root.send("export_spatial",{path:selected,format:format});return;
            }
            if(root.fileAction==="load" && !projectFileType.accepts(selected)) {documentFlow.failed();root.status("Choose a .lenscap project file.",true);return;}
            if(root.fileAction==="image" && !selected.toLowerCase().endsWith(".png")) selected+=".png";
            else if(["save","save_as"].indexOf(root.fileAction)>=0) selected=projectFileType.normalize(selected);
            else if(["parameters","regions","save_preset","export_labelme"].indexOf(root.fileAction)>=0 && !selected.toLowerCase().endsWith(".json")) selected+=".json";
            root.send(root.fileAction==="save_as" ? "save" : root.fileAction,{path:selected,curves:root.fileAction==="load_preset" ? [] : root.curves});
        }
    }
    ToolConfirmDialog {
        id:legacyConversion
        objectName:"legacyConversion"
        title:"Convert file?"
        message:"Convert this legacy .lensproject file to .lenscap?"
        confirmText:"Convert"
        onClosed:root.pendingLegacyPath=""
        onConfirmed:root.confirmLegacyConversion()
    }
    ToolConfirmDialog {
        id:normalizeDialog
        objectName:"normalizeRegionsDialog"
        title:"Normalize vertices"
        message:"Move nearby vertices from different regions to a shared position. Unsafe moves are skipped. Tolerance is measured in "+(root.stage==="lens" && !root.corrected ? "original" : "corrected")+"-image pixels."
        confirmText:"Normalize"
        confirmEnabled:!root.busy && !normalizeTolerance.invalid
        formData:RowLayout {
            Layout.fillWidth:true
            StyledText {text:"Tolerance";Layout.fillWidth:true}
            NumberInput {
                id:normalizeTolerance
                objectName:"normalizeTolerance"
                number:2;minimum:0.1;maximum:50;increment:0.5;unit:"px"
                onEdited:number=>normalizeTolerance.number=number
            }
        }
        onConfirmed:root.send("normalize_vertices",{tolerance:normalizeTolerance.number,viewSpace:root.stage==="lens" && !root.corrected ? "original" : "corrected"})
    }
    ToolConfirmDialog {
        id:snapEdgesDialog
        objectName:"snapVerticesToEdgesDialog"
        title:"Snap vertices to edges"
        message:"Move vertices onto nearby edges of other regions. Unsafe moves are skipped. Tolerance is measured in corrected-image pixels."
        confirmText:"Snap"
        confirmEnabled:!root.busy && !snapEdgesTolerance.invalid
        formData:RowLayout {
            Layout.fillWidth:true
            StyledText {text:"Tolerance";Layout.fillWidth:true}
            NumberInput {
                id:snapEdgesTolerance
                objectName:"snapEdgesTolerance"
                number:2;minimum:0.1;maximum:50;increment:0.5;unit:"px"
                onEdited:number=>snapEdgesTolerance.number=number
            }
        }
        onConfirmed:root.send("snap_vertices_to_edges",{tolerance:snapEdgesTolerance.number})
    }
    ToolTextInputDialog {
        id:profileNameDialog
        objectName:"profileNameDialog"
        property bool renaming:false
        title:renaming ? "Rename profile" : "Name profile"
        confirmText:renaming ? "Rename" : "Save"
        placeholderText:"Profile name"
        message:""
        confirmEnabled:text.trim().length>0 && !root.busy
        onAboutToShow:root.status("")
        onConfirmed:root.send(renaming ? "rename_profile" : "save_profile",{name:text.trim(),path:root.lensProfilePath})
    }
    ToolSaveChangesDialog {
        id: discard
        objectName:"discard"
        message:"Your project contains unsaved changes.\nChanges that are not saved will be lost."
        busy: root.busy
        onRejected:root.clearContinuation()
        onClosed:if(!root.resumeAfterSave && !root.discardConfirmed) {root.pendingAction="";root.pendingPath="";}
        onDiscardRequested: {root.discardConfirmed=true;close();documentFlow.discardAndContinue();}
        onSaveRequested: {root.resumeAfterSave=true;close();documentFlow.saveAndContinue();}
    }
    ToolApp {
        id:mainChrome
        anchors.fill: parent
        controlsEnabled: root.ready && !root.busy && !root.picking && !root.annotating
        toolbar: [
            ToolBarButton {
                id: calibrationButton

                text: "Settings"
                materialSymbol: "tune"
                current: calibrationMenu.opened || adjustments.opened
                toggled: current
                enabled: root.hasImage
                onClicked: calibrationMenu.open()
            },
            ToolBarSeparator {},
            ToolBarButton {
                id: fileButton

                text: "File"
                materialSymbol: "folder_open"
                current: fileMenu.opened
                toggled: current
                onClicked: fileMenu.open()
            },
            ToolSaveButton {
                objectName:"saveProjectButton"
                dirty:root.dirty
                enabled: root.hasImage
                onClicked: root.file("save")
                Accessible.name: "Save project · Ctrl+S"

                StyledToolTip {
                    text: parent.Accessible.name
                }

            },
            ToolBarSeparator {},
            ToolBarButton {
                objectName:"labelmeButton"
                text:"LabelMe";materialSymbol:"polyline"
                enabled:root.canOpenLabelme
                onClicked:root.openLabelme()
                Accessible.name:"Open corrected image in LabelMe"
                StyledToolTip{text:parent.Accessible.name}
            },
            ToolBarButton {
                id: exportButton
                objectName:"exportButton"

                text: "Export"
                materialSymbol: "download"
                current: exportMenu.opened
                toggled: current
                enabled: !!root.calibration
                onClicked: exportMenu.open()
                Accessible.name:"Export image, calibration, or regions"
                StyledToolTip {text:parent.Accessible.name}
            },
            Item { Layout.fillWidth:true }
        ]
        operationsContent:LensOperations {
            id:lensOperations
            Layout.fillWidth:true
            workspace:root
        }
        canvasContent: [
            Image {
                id: photo

                x: root.offsetX
                y: root.offsetY
                width: root.viewDimensions[0] * root.zoom
                height: root.viewDimensions[1] * root.zoom
                source: root.corrected ? root.preview : root.original
                cache: false
                smooth: true
            },
            Canvas {
                id: viewport

                objectName: "lensViewport"
                anchors.fill: parent
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const lines = root.showCalibrationCurves ? (root.corrected ? root.correctedCurves : root.curves) : [];
                    for (let c = 0; c < lines.length; c++) {
                        const editing=!root.drawing && !root.corrected;
                        const active=root.drawing && c===root.activeCurve && !root.corrected;
                        const smooth=!editing && !active;
                        const shown=smooth ? CurveGeometry.denoise(lines[c],1) : lines[c];
                        const flagged=CurveDiagnostics.forCurve(root.curveDiagnostics,c).length>0;
                        draw(ctx, shown, flagged ? Appearance.colors.colError : active ? Appearance.colors.colPrimary : RegionGeometry.color("trace-"+c), false, smooth);
                        if(flagged && lines[c].length) {
                            const marker=lines[c][Math.floor(lines[c].length/2)];
                            ctx.font="bold 12px sans-serif";ctx.fillStyle=Appearance.colors.colError;
                            ctx.fillText((c+1)+" !",root.offsetX+marker[0]*root.zoom+8,root.offsetY+marker[1]*root.zoom-8);
                        }
                        if (editing || active || flagged) {
                            for (let i = 0; i < lines[c].length; i++) {
                            const p = lines[c][i];
                            ctx.beginPath();
                            ctx.arc(root.offsetX + p[0] * root.zoom, root.offsetY + p[1] * root.zoom, root.selectedNodes.some(node=>node[0]===c && node[1]===i) ? 5 : 3, 0, Math.PI * 2);
                            ctx.fillStyle = flagged ? Appearance.colors.colError : active || root.selectedNodes.some(node=>node[0]===c && node[1]===i) ? Appearance.colors.colPrimary : RegionGeometry.color("trace-"+c);
                            ctx.fill();
                        };
                        }
                    }
                    for (const region of (root.showRegions ? root.regions : [])) {
                        const pts = root.corrected ? (region.correctedPoints || []) : (region.points || []);
                        if (pts.length)
                            draw(ctx, pts, RegionGeometry.color(region.sourceLabel !== undefined ? region.sourceLabel : region.label || ""), true, false);

                    }
                }

                function draw(ctx, points, color, closed, smooth) {
                    if (!points.length)
                        return ;

                    const p = points.map((v) => {
                        return [root.offsetX + v[0] * root.zoom, root.offsetY + v[1] * root.zoom];
                    });
                    ctx.beginPath();
                    ctx.moveTo(p[0][0], p[0][1]);
                    if(smooth) {
                        for(const segment of CurveGeometry.segments(p)) ctx.bezierCurveTo(segment.c1[0],segment.c1[1],segment.c2[0],segment.c2[1],segment.p1[0],segment.p1[1]);
                    } else {
                        for(let i=1;i<p.length;i++) ctx.lineTo(p[i][0],p[i][1]);
                    }
                    if (closed)
                        ctx.closePath();

                    ctx.strokeStyle = color;
                    ctx.lineWidth = 1.5;
                    ctx.stroke();
                }

                focus: true
                Keys.onReturnPressed:if(root.drawing) root.finishCurve()
                Keys.onEscapePressed: {
                    root.activeCurve = -1;
                    root.selected = -1;
                    root.selectedPoint = -1;
                    requestPaint();
                }
                Keys.onDeletePressed: (event) => {
                    return root.removePointOrCurve(!!(event.modifiers & Qt.ShiftModifier));
                }
                Keys.onPressed: (event) => {
                    if (!root.editable || root.drawing || root.panTool || root.selected < 0 || root.selectedPoint < 0)
                        return ;

                    let dx = 0, dy = 0;
                    if (event.key === Qt.Key_Left)
                        dx = -1;
                    else if (event.key === Qt.Key_Right)
                        dx = 1;
                    else if (event.key === Qt.Key_Up)
                        dy = -1;
                    else if (event.key === Qt.Key_Down)
                        dy = 1;
                    else
                        return ;
                    const step = (event.modifiers & Qt.ShiftModifier) ? 1 : 0.1;
                    root.remember();
                    root.translateSelection(dx*step,dy*step);
                    event.accepted = true;
                }

                MouseArea {
                    id: mouse

                    property bool pan: false
                    property bool dragging: false
                    property bool moved: false
                    property real lastX: 0
                    property real lastY: 0

                    function point(x, y, mods) {
                        let px = (x - root.offsetX) / root.zoom, py = (y - root.offsetY) / root.zoom;
                        if (root.snapping && !(mods & Qt.AltModifier)) {
                            px = Math.round(px);
                            py = Math.round(py);
                        }
                        return [Math.max(0, Math.min(root.dimensions[0] - 1, px)), Math.max(0, Math.min(root.dimensions[1] - 1, py))];
                    }

                    objectName: "lensMouseArea"
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    hoverEnabled: true
                    readonly property string diagnosticText: {
                        if(!containsMouse || pan || dragging || !root.curveDiagnostics.length) return "";
                        const lines=root.corrected ? root.correctedCurves : root.curves;
                        const query=[(mouseX-root.offsetX)/root.zoom,(mouseY-root.offsetY)/root.zoom];
                        let best=12/root.zoom,index=-1;
                        for(const entry of root.curveDiagnostics) {
                            const points=lines[entry.curve] || [];
                            const hit=CurveGeometry.nearestPolyline(points,query,best);
                            if(hit && hit.distance<=best) {best=hit.distance;index=entry.curve;}
                            for(const point of points) {const distance=Math.hypot(point[0]-query[0],point[1]-query[1]);if(distance<best) {best=distance;index=entry.curve;}}
                        }
                        return CurveDiagnostics.description(root.curveDiagnostics,index);
                    }
                    StyledToolTip {text:mouse.diagnosticText;extraVisibleCondition:mouse.diagnosticText!=="";x:mouse.mouseX+12;y:mouse.mouseY+16}
                    cursorShape: pan ? Qt.ClosedHandCursor : root.panTool ? Qt.OpenHandCursor : root.drawing && !root.corrected ? Qt.CrossCursor : Qt.ArrowCursor
                    onPressed: (event) => {
                        viewport.forceActiveFocus();
                        lastX = event.x;
                        lastY = event.y;
                        moved = false;
                        if (root.busy || root.picking || root.annotating)
                            return ;

                        let best = 11, curve = -1, index = -1;
                        for (let c = 0; c < root.curves.length; c++) for (let i = 0; i < root.curves[c].length; i++) {
                            const p = root.curves[c][i], d = Math.hypot(event.x - root.offsetX - p[0] * root.zoom, event.y - root.offsetY - p[1] * root.zoom);
                            if (d < best) {
                                best = d;
                                curve = c;
                                index = i;
                            }
                        }
                        if (root.panTool || event.button === Qt.MiddleButton || ((event.modifiers & Qt.ControlModifier) && !(event.button===Qt.LeftButton && !root.drawing && root.editable && index>=0))) {
                            pan = true;
                            return ;
                        }
                        if (event.button === Qt.RightButton) {
                            if(root.drawing) root.finishCurve();
                            return ;
                        }
                        if (!root.editable)
                            return ;

                        const previousCurve=root.selected,previousPoint=root.selectedPoint,previousAll=root.allCurvePoints,previousNodes=root.copy(root.selectedNodes);
                        const inside=event.x>=root.offsetX && event.y>=root.offsetY && event.x<=root.offsetX+root.dimensions[0]*root.zoom && event.y<=root.offsetY+root.dimensions[1]*root.zoom;
                        if(root.drawing) {
                            if(inside) {
                                root.remember();
                                if(root.activeCurve<0) {root.curves.push([]);root.activeCurve=root.curves.length-1;}
                                root.extendFromStart=false;
                                root.curves[root.activeCurve].push(point(event.x,event.y,event.modifiers));
                                root.selected=root.activeCurve;root.selectedPoint=root.curves[root.activeCurve].length-1;root.changed();
                            }
                        } else {
                            if(index>=0 && (event.modifiers & Qt.ControlModifier)) {
                                root.togglePoint(curve,index);
                                dragging=false;viewport.requestPaint();return;
                            }
                            root.selected=curve;root.selectedPoint=index;root.explicitPoints=[];root.allCurvePoints=false;
                            if(index>=0) {
                                const next=PointSelection.selectNode(root.curves,previousNodes,[curve,index],{wholePolyline:!!(event.modifiers & Qt.ShiftModifier)});
                                root.allCurvePoints=next.wholePolyline;root.explicitPoints=next.nodes;
                                dragging=true;
                            }
                            else {
                                const query=[(event.x-root.offsetX)/root.zoom,(event.y-root.offsetY)/root.zoom];
                                let hit=null;
                                for(let c=0;c<root.curves.length;c++) {
                                    const candidate=CurveGeometry.nearestPolyline(root.curves[c],query,9/root.zoom);
                                    if(candidate && (!hit || candidate.distance<hit.distance)) hit=Object.assign({curve:c},candidate);
                                }
                                if(hit) {
                                    root.selected=hit.curve;
                                    if(event.modifiers & Qt.AltModifier) {
                                        const p=hit.point;
                                        if(p[0]>=0 && p[1]>=0 && p[0]<=root.dimensions[0]-1 && p[1]<=root.dimensions[1]-1) {
                                            root.remember();root.curves[hit.curve].splice(hit.index+1,0,p);
                                            root.selectedPoint=hit.index+1;root.activeCurve=-1;root.changed();
                                        }
                                    }
                                } else if(inside && previousNodes.length===1 && !previousAll && !(event.modifiers & Qt.AltModifier) && previousCurve>=0 && previousCurve<root.curves.length && (previousPoint===0 || previousPoint===root.curves[previousCurve].length-1)) {
                                    root.remember();
                                    const nodes=root.curves[previousCurve],prepend=previousPoint===0 && nodes.length>1;
                                    if(prepend) nodes.unshift(point(event.x,event.y,event.modifiers));else nodes.push(point(event.x,event.y,event.modifiers));
                                    root.selected=previousCurve;root.selectedPoint=prepend ? 0 : nodes.length-1;root.activeCurve=-1;root.changed();
                                }
                            }
                        }
                        viewport.requestPaint();
                    }
                    onPositionChanged: (event) => {
                        if (pan) {
                            root.offsetX += event.x - lastX;
                            root.offsetY += event.y - lastY;
                            viewport.requestPaint();
                        } else if (dragging && !root.drawing && root.editable) {
                            if (!moved)
                                root.remember();

                            const target=point(event.x,event.y,event.modifiers),anchor=root.curves[root.selected][root.selectedPoint];
                            root.translateSelection(target[0]-anchor[0],target[1]-anchor[1]);
                            moved = true;
                        }
                        lastX = event.x;
                        lastY = event.y;
                    }
                    onReleased: {
                        pan = false;
                        dragging = false;
                    }
                    onCanceled: {
                        pan = false;
                        dragging = false;
                    }
                    onWheel: (event) => {
                        if (!root.hasImage || root.busy)
                            return ;

                        const old = root.zoom;
                        root.zoom = Math.max(root.fittedView.zoom*.02, Math.min(root.fittedView.zoom*32, old * Math.pow(1.0015, event.angleDelta.y)));
                        root.offsetX = event.x - (event.x - root.offsetX) * root.zoom / old;
                        root.offsetY = event.y - (event.y - root.offsetY) * root.zoom / old;
                        viewport.requestPaint();
                        event.accepted = true;
                    }
                }

            }
        ]
        tools: [
            IconToolbarButton {
                implicitWidth: 40
                implicitHeight: 40
                Layout.fillHeight: false
                buttonRadius: height / 2
                text: "gesture"
                objectName:"drawCurveTool"
                Accessible.name: "New curve · D"
                toggled: root.drawing && !root.panTool
                enabled: root.hasImage
                onClicked: {
                    root.selectCurveTool(true);
                }

                StyledToolTip {
                    text: parent.Accessible.name
                }

            },
            IconToolbarButton {
                implicitWidth: 40
                implicitHeight: 40
                Layout.fillHeight: false
                buttonRadius: height / 2
                text: "edit"
                objectName:"editCurveTool"
                Accessible.name: "Edit curve · V"
                toggled: !root.drawing && !root.panTool
                enabled: root.hasImage
                onClicked: {
                    root.selectCurveTool(false);
                }

                StyledToolTip {
                    text: parent.Accessible.name
                }

            }
        ]
        contextBelowTools:true
        contextActionsVisible:root.editable && !root.drawing && !root.panTool && root.selected>=0
        contextActions: [
            IconToolbarButton {
                objectName:"deletePointAction"
                implicitWidth:32;implicitHeight:32;Layout.fillHeight:false;buttonRadius:height/2
                text:"delete";Accessible.name:root.selectedPoint>=0 ? "Delete point" : "Delete curve"
                visible:!root.drawing && !root.panTool && root.selected>=0
                onClicked:root.removePointOrCurve(false)
                StyledToolTip {text:parent.Accessible.name}
            }
        ]
        status: [
            ToolCanvasFooter {
                id:canvasFooter
                prefixControls:WorkspaceModePicker {}
                showZoom:false
                leadingControls:IconToolbarButton {
                visible:false
                objectName:"toggleCorrectedView"
                implicitWidth:32
                implicitHeight:32
                Layout.fillHeight:false
                buttonRadius:height/2
                text:root.corrected ? "visibility" : "visibility_off"
                toggled:root.corrected
                enabled:root.preview!==""
                opacity:enabled ? 1 : 0.4
                Accessible.name:root.corrected ? "Corrected · Switch to original · Tab" : "Original · Switch to corrected · Tab"
                onClicked:{root.corrected=!root.corrected;viewport.requestPaint();}
                StyledToolTip {text:parent.Accessible.name}
            }
                zoomPercent:root.viewZoomPercent
                atReset:root.viewAtReset
                zoomEnabled:root.hasImage && !root.busy && !root.annotating
                showCursorCoordinates:!pointCoordinates.visible
                cursorActive:root.cursorPosition.length===2
                cursorX:cursorActive ? root.cursorPosition[0] : 0
                cursorY:cursorActive ? root.cursorPosition[1] : 0
                onZoomEdited:value=>root.setZoomPercent(value)
                onResetRequested:root.fit()
                hints:root.buildLensHints()
                toolInputs:ToolPointCoordinates {
                    id:pointCoordinates
                    visible:root.editable && !root.drawing && !root.panTool && root.selectedNodes.length>0
                    position:root.selectedPosition
                    selectionCount:root.selectedNodes.length
                    bounds:root.dimensions
                    onCoordinateEdited:(axis,value)=>root.setCoordinate(axis,String(value))
                    onInvalid:message=>root.status(message,true)
                }
            }
        ]
    }
    ToolPill {
        objectName:"historyPill"
        z:30
        anchors.left:parent.left
        anchors.leftMargin:mainChrome.canvasArea.x+18
        anchors.bottom:parent.bottom
        anchors.bottomMargin:root.height-mainChrome.canvasArea.y-mainChrome.canvasArea.height+18
        enabled:root.ready && !root.busy && !root.picking && !root.annotating
        ToolIconButton {
            objectName:"workspaceUndo";text:"undo";Accessible.name:"Undo · Ctrl+Z"
            implicitWidth:32;implicitHeight:32;iconSize:20
            enabled:root.activeHistory.past.length>0
            onClicked:root.activeHistory.undo()
            StyledToolTip {text:parent.Accessible.name}
        }
        ToolIconButton {
            objectName:"workspaceRedo";text:"redo";Accessible.name:"Redo · Ctrl+Shift+Z"
            implicitWidth:32;implicitHeight:32;iconSize:20
            enabled:root.activeHistory.future.length>0
            onClicked:root.activeHistory.redo()
            StyledToolTip {text:parent.Accessible.name}
        }
    }
    Shortcut {
        objectName:"workspaceTabShortcut"
        sequence:"Tab"
        context:Qt.WindowShortcut
        onActivated:if(root.stage==="lens" && root.canvasShortcuts && root.preview!==""){root.corrected=!root.corrected;viewport.requestPaint();}
    }
    Shortcut {sequence:"Shift+Tab";context:Qt.WindowShortcut;onActivated:{}}
    ToolMenu {
        id:fileMenu
        objectName:"fileMenu"
        x:fileButton.mapToItem(root,0,0).x;y:fileButton.mapToItem(root,0,fileButton.height).y+4
        contentItem:ColumnLayout {
            spacing:0
            MenuButton {buttonText:"New image";Layout.fillWidth:true;onClicked:{fileMenu.close();root.file("open");}}
            MenuButton {buttonText:"Open project";Layout.fillWidth:true;onClicked:{fileMenu.close();root.file("load");}}
            MenuButton {buttonText:"Save";Layout.fillWidth:true;enabled:root.hasImage;onClicked:{fileMenu.close();root.file("save");}}
            MenuButton {buttonText:"Save as";Layout.fillWidth:true;enabled:root.hasImage;onClicked:{fileMenu.close();root.file("save_as");}}
            MenuButton {objectName:"recalibrateBlenderFile";buttonText:"Recalibrate Blender";Layout.fillWidth:true;enabled:root.canExportBlender;onClicked:{fileMenu.close();root.file("recalibrate_blend_source");}}
            MenuButton {buttonText:"Import LabelMe";Layout.fillWidth:true;enabled:!!root.calibration;onClicked:{fileMenu.close();root.file("labelme");}}
            MenuButton {objectName:"normalizeRegions";buttonText:"Normalize region vertices…";Layout.fillWidth:true;enabled:root.hasRegions && !root.busy;onClicked:{fileMenu.close();normalizeDialog.open();}}
            MenuButton {objectName:"snapVerticesToEdges";buttonText:"Snap vertices to edges…";Layout.fillWidth:true;enabled:root.hasRegions && !root.busy;onClicked:{fileMenu.close();snapEdgesDialog.open();}}
            StyledText {visible:root.recentProjects.length>0;Layout.leftMargin:12;Layout.topMargin:8;Layout.bottomMargin:4;text:"Recent projects";font.pixelSize:Appearance.font.pixelSize.smaller;color:Appearance.colors.colSubtext}
            Repeater {
                model:root.recentProjects.slice(0,6)
                MenuButton {
                    required property string modelData
                    Layout.fillWidth:true
                    buttonText:modelData.substring(modelData.lastIndexOf("/")+1)
                    Accessible.name:modelData
                    onClicked:{fileMenu.close();root.file("load",modelData);}
                    StyledToolTip {text:parent.modelData}
                }
            }
        }
    }
    ToolSettingsDialog {
        id:calibrationMenu
        objectName:"calibrationMenu"
        readonly property real defaultHfov:2*Math.atan(root.dimensions[0]/(2*Math.max(root.dimensions[0],root.dimensions[1])))*180/Math.PI
        property real draftHfov:90
        height:Math.min(root.height-48,settingsContent.implicitHeight+topPadding+bottomPadding+(header ? header.implicitHeight : 0)+(footer ? footer.implicitHeight : 0)+spacing*2+8)
        title:"Project settings"
        onAboutToShow:syncDraft()
        function syncDraft() {
            const custom=root.projectSettings.hfov!==null && root.projectSettings.hfov!==undefined;
            draftHfov=custom ? root.projectSettings.hfov : defaultHfov;
            customFov.checked=custom;
            hfovInput.invalid=false;
            snapSetting.checked=root.snapping;
            modelSetting.currentIndex=root.order;
            projectSettingsStore.resetRequested();
        }
        QtObject {id:customFov;objectName:"customFov";property bool checked:false}
        QtObject {id:hfovInput;objectName:"hfovInput";property bool invalid:false;property bool enabled:customFov.checked;signal edited(real number);onEdited:number=>calibrationMenu.draftHfov=number}
        QtObject {id:modelSetting;objectName:"modelSetting";property int currentIndex:0}
        QtObject {id:snapSetting;objectName:"snapSetting";property bool checked:true}
        QtObject {
            id:projectSettingsStore
            signal resetRequested()
            function get(path) {
                switch(path) {
                case "lens.customFov":return customFov.checked;
                case "lens.hfov":return calibrationMenu.draftHfov;
                case "lens.order":return modelSetting.currentIndex;
                case "lens.snapping":return snapSetting.checked;
                case "lens.project":return root.projectPath ? root.projectPath.substring(root.projectPath.lastIndexOf("/")+1) : "Unsaved";
                case "lens.source":return root.sourcePath.substring(root.sourcePath.lastIndexOf("/")+1)+" · "+root.dimensions.join(" × ");
                case "lens.extras":return String(root.extraImages.length)+" extra";
                default:return "";
                }
            }
            function write(path,value) {
                switch(path) {
                case "lens.customFov":customFov.checked=value;break;
                case "lens.hfov":calibrationMenu.draftHfov=value;hfovInput.invalid=false;break;
                case "lens.order":modelSetting.currentIndex=value;break;
                case "lens.snapping":snapSetting.checked=value;break;
                }
            }
            function invalid(path,message) {if(path==="lens.hfov") hfovInput.invalid=!!message;}
        }
        contentItem:StyledFlickable {
            clip:true
            contentHeight:Math.ceil(settingsContent.implicitHeight)
            interactive:contentHeight>height
            ColumnLayout {
                id:settingsContent
                width:parent.width
                spacing:16
                ContentSection {
                    title:"Files"
                    icon:"folder_open"
                    SettingsControls.SettingsGroup {
                        valueStore:projectSettingsStore
                        showReset:false
                        section:({title:"",items:[
                            {kind:"action",title:"Project",icon:"save",valuePath:"lens.project",action:"save_as"},
                            {kind:"preference",setting:{path:"lens.source",type:"label",label:"Source",icon:"image",readOnly:true}},
                            {kind:"action",title:"Extra images",icon:"photo_library",valuePath:"lens.extras",action:"add_images"}
                        ]})
                        onActionRequested:action=>{if(action) {calibrationMenu.close();root.file(action);}}
                    }
                    SettingsControls.SettingsPresetDropdown {
                        label:"Working image"
                        visible:root.stage!=="lens" && root.annotationImages.length>1
                        Layout.fillWidth:true
                        choices:root.annotationImages.map(image=>({name:image.label,value:image.source}))
                        value:root.activeImage || root.sourcePath
                        enabled:!root.busy && !root.pendingNativeRegions && root.pendingSpatialScene===null
                        onChosen:value=>{calibrationMenu.close();root.send("select_image",{source:value});}
                    }

                }

            }
        }
        errorMessage:""
        onApplyRequested:calibrationMenu.close()
    }
    ToolMenu {
        id:exportMenu
        objectName:"exportMenu"
        x:exportButton.mapToItem(root,0,0).x;y:exportButton.mapToItem(root,0,exportButton.height).y+4
        contentItem:ColumnLayout {
            spacing:0
            MenuButton {objectName:"exportCorrectedImage";buttonText:"Corrected PNG";Layout.fillWidth:true;enabled:!!root.calibration;onClicked:{exportMenu.close();root.file("image");}}
            MenuButton {buttonText:"Calibration JSON";Layout.fillWidth:true;enabled:!!root.calibration;onClicked:{exportMenu.close();root.file("parameters");}}
            MenuButton {buttonText:"Scene JSON";Layout.fillWidth:true;enabled:!!root.planeCalibration;onClicked:{exportMenu.close();root.file("scene_json");}}
            MenuButton {objectName:"exportBlenderScene";buttonText:"Blender scene";Layout.fillWidth:true;enabled:root.canExportBlender;onClicked:{exportMenu.close();root.file("scene_blend");}}
            MenuButton {buttonText:"Scene OBJ";Layout.fillWidth:true;enabled:!!root.planeCalibration;onClicked:{exportMenu.close();root.file("scene_obj");}}
            MenuButton {objectName:"exportDistortedLabelme";buttonText:"Distorted LabelMe JSON";Layout.fillWidth:true;enabled:root.hasLensCorrection;onClicked:{exportMenu.close();root.file("export_labelme");}}
            MenuButton {buttonText:"Frigate zones";Layout.fillWidth:true;enabled:root.hasRegions;onClicked:{exportMenu.close();root.file("regions");}}
        }
    }
    Item {
        anchors.fill:parent
        anchors.topMargin:mainChrome.canvasArea.y
        z:20
        visible:root.stage!=="lens"
        SpatialEditor {
            id:spatialEditor
            operationsInputFocused:lensOperations.inputFocused
            footerPrefix:WorkspaceModePicker {}
            objectName:"spatialEditor"
            anchors.fill:parent
            visible:root.stage==="calibration"
            mode:"calibration"
            imageSource:root.annotationPreview || root.preview
            imageSize:root.outputDimensions
            scene:root.nativeScene
            planeCalibration:root.planeCalibration
            referencePlane:root.referencePlane
            projectedObjects:[]
            busy:root.busy
            onOperationRequested:(op,payload)=>root.send(op,payload)
            onReferenceDirtyChanged:if(referenceDirty && corners.length===4 && !root.busy)root.dirty=true
            onSceneEdited:scene=>{root.nativeScene=scene;root.dirty=true;root.pendingSpatialScene=scene;root.flushNativeEdits();}
            onDoneRequested:root.changeStage("lens")
        }
    }

    ToolModal {
        id:adjustments
        objectName:"adjustments"
        preferredWidth:500
        padding:12
        contentItem:RowLayout {
            StyledText {text:"k1"}
            MaterialTextField {id:k1;objectName:"k1";implicitWidth:140;Accessible.name:"Radial coefficient k1";onAccepted:root.applyAdjustment()}
            StyledText {text:"k2"}
            MaterialTextField {id:k2;objectName:"k2";implicitWidth:140;Accessible.name:"Radial coefficient k2";onAccepted:root.applyAdjustment()}
            IconToolbarButton { implicitWidth:36;implicitHeight:36;Layout.fillHeight:false;buttonRadius:height/2;text:"check";Accessible.name:"Apply correction";onClicked:root.applyAdjustment()
                StyledToolTip { text: parent.Accessible.name } }
        }
    }
    Shortcut {sequence:"Alt+F";enabled:root.ready && !root.busy && !root.picking && !root.annotating;onActivated:fileMenu.open()}
    Shortcut {sequence:"Ctrl+O";onActivated:root.file("load")}
    Shortcut {sequence:"Ctrl+S";enabled:root.hasImage;onActivated:root.file("save")}
    Shortcut {sequence:"Ctrl+Shift+S";enabled:root.hasImage;onActivated:root.file("save_as")}
    Shortcut {sequence:"Ctrl+Z";enabled:root.canvasShortcuts;onActivated:root.undo()}
    Shortcut {sequence:"Ctrl+Shift+Z";enabled:root.canvasShortcuts;onActivated:root.redo()}
    Shortcut {objectName:"drawCurveShortcut";sequence:"D";enabled:root.hasImage && root.canvasShortcuts;onActivated:root.selectCurveTool(true)}
    Shortcut {objectName:"editCurveShortcut";sequence:"V";enabled:root.hasImage && root.canvasShortcuts;onActivated:root.selectCurveTool(false)}
    Shortcut {sequence:"M";enabled:root.editable && !root.drawing && root.canvasShortcuts;onActivated:root.connectEndpoints()}
    Shortcut {sequence:"F";enabled:root.canvasShortcuts;onActivated:root.fit()}
}
