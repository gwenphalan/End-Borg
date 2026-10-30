//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtTest
import Quickshell
import qs.modules.common.widgets
import qs.modules.common.tool_app
import qs.modules.lensCalibration

AppWindow {
    id:window
    appTitle:"Lens Cap · Staging verification"
    showWindowChrome:false
    width:1920;height:1080
    Component.onCompleted:Quickshell.watchFiles=false
    CalibrationWorkspace {id:workspace;anchors.fill:parent}
    Component {
        id:footerLayoutFixture
        ToolCanvasFooter {
            id:fixture
            property bool showSelected:false
            property bool showExtra:false
            property var testHints:[]
            hints:testHints
            showZoom:false
            showCursorCoordinates:!showSelected
            prefixControls:Item {implicitWidth:180;implicitHeight:32}
            toolInputs:[
                StyledText {text:"Pose fit 6.03 px · assumed camera"},
                ToolPointCoordinates {visible:fixture.showSelected;position:[123.456,789.123];selectionCount:1}
            ]
            leadingControls:ToolIconButton {visible:fixture.showExtra;text:"visibility";implicitWidth:28;implicitHeight:28}
        }
    }
    Timer {interval:90000;running:true;onTriggered:{console.error("STAGED TEST TIMEOUT");Qt.quit();}}
    TestCase {
        name:"StagedNativeSpatial"
        when:window.visible && workspace.ready
        function checked(actual,expected){if(actual!==expected)console.error("STAGED ASSERT",qtest_results.functionName,JSON.stringify(actual),JSON.stringify(expected));compare(actual,expected);}
        function confirmed(value,message){if(!value)console.error("STAGED ASSERT",qtest_results.functionName,message || "verify");verify(value,message || "");}
        function init(){console.log("STAGED CASE",qtest_results.functionName);}
        function settle(){try {tryVerify(()=>!workspace.busy && !workspace.pendingNativeRegions && !workspace.pendingSpatialScene,20000);} catch(e){console.error("STAGED SETTLE",workspace.operation,workspace.busy,workspace.pendingNativeRegions,JSON.stringify(workspace.pendingSpatialScene),workspace.message);throw e;}}
        function child(name){const item=findChild(workspace,name);confirmed(item!==null,"Missing "+name);return item;}
        function initTestCase(){
            workspace.send("load",{path:"/tmp/lens-cap-stage-ui/reference.lenscap"});settle();confirmed(!workspace.error,workspace.message);
            workspace.send("calibrate",{order:0});settle();confirmed(!workspace.error,workspace.message);confirmed(workspace.preview!=="");
        }
        function test_00_distortedLabelmePicker(){
            const descriptor=workspace.filePickerDescriptor("export_labelme");
            checked(descriptor.mode,"save");checked(descriptor.filters[0].patterns[0],"*.json");confirmed(descriptor.name.endsWith("-distorted.json"),"Distinct original-image LabelMe output name");
            confirmed(child("exportDistortedLabelme").enabled===workspace.hasLensCorrection,"Distorted annotation export is independent of Frigate zone labels");
        }
        function test_00_labelmeActiveImageCommand(){
            const args=workspace.labelmeCommand({labelmeImage:"/tmp/lens-handoff/001-extra.png",labelmeFolder:"/tmp/lens-handoff",labelmeOutputDir:"/tmp/lens-handoff"});
            checked(args[1],"/tmp/lens-handoff/001-extra.png");checked(args[2],"--output");checked(args[3],"/tmp/lens-handoff");
        }
        function test_00_sharedChrome(){
            const bar=child("toolTopBar"),hover=findChild(bar,"toolHoverGroup"),save=child("saveProjectButton");
            confirmed(hover!==null,"Shared hover group");checked(bar.height,32);
            confirmed(child("toolOperationsBar").height>=96 && child("toolOperationsBar").height<=104,"Two-row ribbon height");
            const undo=child("workspaceUndo"),mode=child("workspaceModePicker");
            confirmed(undo.mapToItem(window.contentItem,0,0).x<window.width*.2 && undo.mapToItem(window.contentItem,0,0).y>window.height*.7,"History pill at canvas bottom left");
            confirmed(mode.mapToItem(window.contentItem,0,0).x<window.width*.25 && mode.mapToItem(window.contentItem,0,0).y>window.height*.8,"Mode before footer hints");confirmed(mode.width<=180,"Compact mode picker");confirmed(mode.choices.every(choice=>!!choice.icon),"Icons for every mode");checked(mode.choices.length,2);checked(mode.choices[1].name,"Reference plane");confirmed(mode.choices[1].separatorBefore,"Calibration workflow separator");confirmed(findChild(workspace,"nativeRegionEditor")===null,"No built-in region editor is instantiated");
            const cursor=child("cursorCoordinates"),reset=child("resetViewButton"),input=child("zoomPercentInput"),view=child("toggleCorrectedView");
            function x(item){return item.mapToItem(window.contentItem,0,0).x;}
            confirmed(reset.mapToItem(window.contentItem,0,0).y<180,"Reset in operations");confirmed(x(reset)<x(input),"Reset before zoom");confirmed(!workspace.textEditing,"No input focused initially");
            confirmed(!save.activeFocusOnTab,"Buttons skip Tab traversal");
            const tab=child("workspaceTabShortcut"),before=workspace.corrected;tab.activated();checked(workspace.corrected,!before);tab.activated();checked(workspace.corrected,before);
            mouseMove(save,save.width/2,save.height/2,30);wait(30);confirmed(hover.hoveredButton===save,"Hover tracks enabled button");
            const corner=save.mapToItem(bar,save.width+1,save.height/2);
            mouseMove(bar,corner.x,corner.y,30);wait(30);confirmed(hover.hoveredButton===save,"Hover retained across gap");
            save.enabled=false;mouseMove(save,save.width/2,save.height/2,30);wait(30);confirmed(hover.hoveredButton===null,"Disabled button clears hover");save.enabled=true;
        }
        function test_00a_modePrerequisites() {
            const picker=child("workspaceModePicker"),saved=workspace.calibration,button=child("labelmeButton");
            workspace.calibration=null;wait(10);
            confirmed(!picker.choices[1].enabled,"Reference plane requires lens correction");confirmed(!button.enabled,"LabelMe requires corrected image");
            confirmed(!workspace.openLabelme(),"Unavailable LabelMe handoff does not launch a process");
            picker.chooseIndex(1);checked(workspace.stage,"lens");
            workspace.changeStage("boxes");checked(workspace.stage,"lens");
            workspace.calibration=saved;wait(10);
            confirmed(picker.choices[1].enabled && button.enabled,"Correction enables reference plane and LabelMe");
            workspace.changeStage("regions");checked(workspace.stage,"calibration");workspace.changeStage("lens");
        }

        function test_00a_fitRelativeZoom() {
            workspace.corrected=false;workspace.fit();compare(workspace.viewZoomPercent,100);
            const originalWidth=workspace.dimensions[0]*workspace.zoom,originalHeight=workspace.dimensions[1]*workspace.zoom;
            workspace.toggleRibbonView();wait(20);
            verify(Math.abs(workspace.viewZoomPercent-100)<1e-7);
            verify(workspace.outputDimensions[0]*workspace.zoom<=originalWidth+.01);
            verify(workspace.outputDimensions[1]*workspace.zoom<=originalHeight+.01);
            workspace.setZoomPercent(175);workspace.offsetX+=37;workspace.offsetY-=21;
            const scale=workspace.zoom,x=workspace.offsetX,y=workspace.offsetY,size=JSON.stringify(workspace.outputDimensions);
            workspace.toggleRibbonView();workspace.toggleRibbonView();
            verify(Math.abs(workspace.viewZoomPercent-175)<1e-7);
            verify(Math.abs(workspace.zoom-scale)<1e-8 && Math.abs(workspace.offsetX-x)<1e-6 && Math.abs(workspace.offsetY-y)<1e-6);
            compare(JSON.stringify(workspace.outputDimensions),size);
            workspace.fit();verify(Math.abs(workspace.viewZoomPercent-100)<1e-7);
        }
        function test_00a_projectModal() {
            const modal=child("calibrationMenu");modal.open();wait(250);waitForPolish(window);
            confirmed(modal.contentItem.height>=modal.contentItem.contentHeight,"Settings fit without needless scrolling");
            confirmed(modal.footer.height>=68,"Footer includes bottom padding");
            function buttons(item,found){if(item.buttonText!==undefined)found.push(item);for(const c of item.children || [])buttons(c,found);return found;}
            const actions=buttons(modal.footer,[]),cancel=actions.find(a=>a.buttonText==="Cancel"),apply=actions.find(a=>a.buttonText==="Apply");
            confirmed(cancel && apply,"Modal actions exist");
            confirmed(cancel.mapToItem(modal.footer,0,0).x>modal.footer.width*.5,"Cancel grouped on right");
            confirmed(apply.mapToItem(modal.footer,apply.width,0).x<=modal.footer.width-23,"Right action padding");
            grabImage(window.contentItem).save("/tmp/lens-cap-stage-ui/settings-modal.png");modal.close();
            const mode=child("workspaceModePicker");mode.popup.open();wait(200);grabImage(window.contentItem).save("/tmp/lens-cap-stage-ui/modes.png");mode.popup.close();
        }
        function test_00b_ribbonBackend() {
            const picker=child("lensProfilePicker");
            const dropdown=(function visit(item){if(item.choices!==undefined)return item;for(const child of item.children || []){const found=visit(child);if(found)return found;}return null;})(picker);
            confirmed(dropdown!==undefined,"Profile dropdown exists");
            checked(dropdown.choices[dropdown.choices.length-1].name,"Save Profile…");
            confirmed(findChild(workspace,"annotationImagePicker")===null,"Image chooser removed from operations");
            const before=workspace.calibration.coefficients[0],oldZoom=workspace.zoom,oldX=workspace.offsetX,oldY=workspace.offsetY;
            child("ribbonK1").edited(before+.000001);wait(750);settle();confirmed(!workspace.error,workspace.message);
            confirmed(Math.abs(workspace.calibration.coefficients[0]-(before+.000001))<1e-10,"Coefficient applied precisely");
            checked(workspace.zoom,oldZoom);checked(workspace.offsetX,oldX);checked(workspace.offsetY,oldY);
            workspace.projectPath="/tmp/lens-cap-stage-ui/ribbon-save.lenscap";child("ribbonK1").edited(before);workspace.file("save","/tmp/lens-cap-stage-ui/ribbon-save.lenscap");wait(100);settle();wait(100);settle();
            confirmed(!workspace.error,workspace.message);checked(workspace.projectPath,"/tmp/lens-cap-stage-ui/ribbon-save.lenscap");
            workspace.fit();waitForPolish(window);wait(150);grabImage(window.contentItem).save("/tmp/lens-cap-stage-ui/ribbon.png");
            window.width=1280;waitForPolish(window);wait(100);
            const view=child("toggleCorrectedView");confirmed(view.mapToItem(window.contentItem,view.width,0).x<=window.width+1,"View fits at1280px");
            grabImage(window.contentItem).save("/tmp/lens-cap-stage-ui/ribbon-1280.png");window.width=1920;waitForPolish(window);
        }
        function test_00c_curveToolSelectionFromCorrectedView(){
            workspace.changeStage("lens");workspace.corrected=true;waitForPolish(window);wait(50);
            const edit=child("editCurveTool"),draw=child("drawCurveTool");
            confirmed(edit.enabled && draw.enabled,"Curve tools stay selectable on corrected view");
            mouseClick(edit,edit.width/2,edit.height/2);wait(30);
            checked(workspace.corrected,false);checked(workspace.drawing,false);confirmed(edit.toggled,"Edit curve selected by click");
            workspace.corrected=true;mouseClick(draw,draw.width/2,draw.height/2);wait(30);
            checked(workspace.corrected,false);checked(workspace.drawing,true);confirmed(draw.toggled,"New curve selected by click");
            workspace.corrected=true;workspace.forceActiveFocus();confirmed(child("editCurveShortcut").enabled,"Edit shortcut available on corrected view");child("editCurveShortcut").activated();wait(30);
            checked(workspace.corrected,false);checked(workspace.drawing,false);
            workspace.corrected=true;confirmed(child("drawCurveShortcut").enabled,"Draw shortcut available on corrected view");child("drawCurveShortcut").activated();wait(30);
            checked(workspace.corrected,false);checked(workspace.drawing,true);
        }
        function test_01_preserveAnnotationsForLabelMe(){
            confirmed(child("labelmeButton").enabled,"Corrected image is available to LabelMe");
            const before=child("labelmeProcess").running;
            workspace.send("native_regions",{regions:[{id:"existing-annotation",label:"Existing saved annotation",color:"#4db6ac",points:[[100,100],[200,100],[200,200]]}]});settle();confirmed(!workspace.error,workspace.message);
            checked(workspace.nativeRegions.length,1);checked(workspace.regions.length,1);
            workspace.send("save",{path:"/tmp/lens-cap-stage-ui/overlay-save.lenscap"});settle();confirmed(!workspace.error,workspace.message);
            checked(workspace.regions.length,1,"Save preserves visible regions");
            workspace.acceptCalibration(JSON.parse(JSON.stringify(workspace.calibration)));
            checked(workspace.regions.length,1,"Equivalent calibration preserves visible regions");
            confirmed(child("normalizeRegions").enabled,"Vertex normalization remains separate");
            confirmed(child("snapVerticesToEdges").enabled,"Edge snapping available with regions");
            const snap=child("snapVerticesToEdgesDialog");snap.open();wait(300);
            confirmed(!workspace.canvasShortcuts,"Canvas shortcuts pause during edge snap settings");
            checked(child("snapEdgesTolerance").number,2);snap.close();


            checked(child("labelmeProcess").running,before);confirmed(findChild(workspace,"nativeRegionEditor")===null,"Saved annotations do not instantiate an editor");
        }


        function test_03_referenceAndBox(){try{
            workspace.changeStage("calibration");wait(50);
            const editor=child("spatialEditor");editor.fit();
            confirmed(!child("recalibrateReferenceBlender").enabled,"Blender recalibration requires solved pose");confirmed(!child("exportReferenceBlender").enabled,"Blender export requires solved pose");
            editor.corners=[[1069.0307094349473,906.0456449474146],[1733.9692905650527,906.0456449474146],[1634.2285033955368,623.9360970736194],[1168.7714966044632,623.9360970736194]];
            editor.referenceWidth=4;editor.referenceDepth=3;editor.referenceAxes=["x","y"];editor.saveReferencePlane();settle();confirmed(!workspace.error,workspace.message);confirmed(workspace.referencePlane!==null);confirmed(workspace.planeCalibration===null,"Saving reference must not solve pose");editor.calculateSpace();settle();confirmed(!workspace.error,workspace.message);confirmed(workspace.planeCalibration!==null);
            confirmed(child("exportReferenceBlender").enabled,"Solved plane enables Blender export");
            confirmed(child("recalibrateReferenceBlender").enabled && child("recalibrateBlenderFile").enabled,"Solved reference enables Blender recalibration");
            const recalibrateSource=workspace.filePickerDescriptor("recalibrate_blend_source");checked(recalibrateSource.mode,"open");checked(recalibrateSource.filters[0].patterns[0],"*.blend");
            workspace.blenderRecalibrationSource="/tmp/lens-cap-stage-ui/edited-scene.blend";
            const recalibrateTarget=workspace.filePickerDescriptor("recalibrate_blend_target");checked(recalibrateTarget.mode,"save");checked(recalibrateTarget.name,"edited-scene-recalibrated.blend");checked(recalibrateTarget.folder,"/tmp/lens-cap-stage-ui");checked(recalibrateTarget.filters[0].patterns[0],"*.blend");
            child("workspaceFilePicker").cancelled();checked(workspace.blenderRecalibrationSource,"");
            const priorOperation=workspace.operation;workspace.blenderRecalibrationSource="/tmp/lens-cap-stage-ui/edited-scene.blend";workspace.fileAction="recalibrate_blend_target";child("workspaceFilePicker").selected(workspace.blenderRecalibrationSource,[workspace.blenderRecalibrationSource]);checked(workspace.blenderRecalibrationSource,"");checked(workspace.operation,priorOperation);
            const acceptedPose=workspace.planeCalibration,acceptedScene=workspace.nativeScene;
            workspace.nativeScene=Object.assign({},acceptedScene,{mappingStale:true,regions:[{id:"stale-mapping-test",label:"Old 2D mapping",points:[[0,0],[10,0],[10,10]]}]});
            checked(workspace.staleMappingMessage("calculate_spatial_calibration"),"");checked(workspace.staleMappingMessage("save_reference_plane"),"");checked(workspace.staleMappingMessage("recalibrate_blend"),"");confirmed(workspace.staleMappingMessage("preview").startsWith("2D regions"),"Stale 2D regions have a distinct warning");
            workspace.nativeScene=Object.assign({},acceptedScene,{mappingStale:true,regions:[]});checked(workspace.staleMappingMessage("preview"),"");
            workspace.planeCalibration=Object.assign({},acceptedPose,{stale:true});wait(10);confirmed(!child("recalibrateReferenceBlender").enabled,"Stale camera disables recalibration");confirmed(workspace.staleMappingMessage("calculate_spatial_calibration").startsWith("3D calibration"),"Only stale pose triggers a 3D calibration warning");workspace.planeCalibration=acceptedPose;workspace.nativeScene=acceptedScene;wait(10);
            const blenderPicker=workspace.filePickerDescriptor("scene_blend");
            checked(blenderPicker.name,"scene.blend");checked(blenderPicker.filters[0].name,"Blender scene");checked(blenderPicker.filters[0].patterns[0],"*.blend");
            editor.referenceWidth=4.1;wait(20);confirmed(!child("exportReferenceBlender").enabled,"Unsaved reference edits disable Blender export");editor.referenceWidth=4;wait(20);confirmed(child("exportReferenceBlender").enabled,"Restoring current reference enables Blender export");
            for(const legacy of ["regions","planes","boxes"]) {workspace.changeStage(legacy);checked(workspace.stage,"calibration");}
            confirmed(findChild(workspace,"importBlenderRegions")===null && findChild(workspace,"importBlenderFile")===null,"Region import controls are removed");
            checked(workspace.nativeScene.objects.length,0);
        }catch(e){console.error("STAGED EXCEPTION",String(e),e.stack);throw e;}
        }
        function test_03a_referenceOutsideImage() {
            workspace.changeStage("calibration");waitForPolish(window);wait(100);
            const editor=workspace.spatialTools;editor.fit();wait(50);
            const before=editor.copy(editor.corners),mouse=child("spatialMouse"),point=before[0];
            const start=[editor.panX+point[0]*editor.zoom,editor.panY+point[1]*editor.zoom];
            const target=[15,mouse.height*.55];confirmed(target[0]<editor.panX,"Drag target is canvas background outside image");
            mousePress(mouse,start[0],start[1],Qt.LeftButton);mouseMove(mouse,target[0],target[1],50);mouseRelease(mouse,target[0],target[1],Qt.LeftButton);
            confirmed(editor.corners[0][0]<0,"Reference corner moves outside image");
            const field=findChild(editor,"pointX");confirmed(field!==null,"Selected corner coordinate input");field.text="-75";field.editingFinished();
            checked(editor.corners[0][0],-75);
            grabImage(window.contentItem).save("/tmp/lens-cap-stage-ui/reference-outside.png");editor.corners=before;
        }
        function test_03b_modeOperations() {
            const picker=child("workspaceModePicker");checked(picker.choices.length,2);
            workspace.changeStage("calibration");waitForPolish(window);wait(100);
            confirmed(child("modeOperations").visible,"Reference controls present");
            workspace.activeView.fit();confirmed(Math.abs(workspace.activeView.viewZoomPercent-100)<1e-6,"Reset100%");
            workspace.activeView.setZoomPercent(150);confirmed(Math.abs(workspace.activeView.viewZoomPercent-150)<1e-6,"Top zoom adapter");
            confirmed(!findChild(workspace.activeView,"zoomControl").visible,"No footer zoom");
            confirmed(child("toggleCorrectedView").mapToItem(window.contentItem,0,0).y<180,"Top view controls");
            window.width=1280;waitForPolish(window);wait(100);
            const view=child("toggleCorrectedView");confirmed(view.mapToItem(window.contentItem,view.width,0).x<=window.width+1,"Compact reference operations fit");
            window.width=1920;waitForPolish(window);
        }

        function test_03c_footerRightAnchoring() {
            const fixture=footerLayoutFixture.createObject(window.contentItem,{x:14,y:window.height-46,height:40,z:100});
            confirmed(fixture!==null,"Shared footer fixture created");
            try {
                const right=findChild(fixture,"footerRightControls");confirmed(right!==null,"Footer has one compact right control group");
                const hintSets=[[],[{keys:["LMB"],action:"Select"}],Array.from({length:12},(_,i)=>({keys:["Shift","LMB"],action:"Long contextual action "+i}))];
                for(const width of [1920,1280]) {
                    window.width=width;fixture.width=width-28;
                    for(const selected of [false,true])for(const extra of [false,true])for(const zoom of [false,true]) {
                        fixture.showSelected=selected;fixture.showExtra=extra;fixture.showZoom=zoom;
                        for(const hints of hintSets) {
                            fixture.testHints=hints;waitForPolish(window);wait(10);
                            const edge=right.mapToItem(fixture,right.width,0).x;
                            confirmed(Math.abs(edge-fixture.width)<.5,"Right controls stay anchored with changing hints/hidden controls at "+width+"px: "+edge+" / "+fixture.width);
                            confirmed(Math.abs(right.width-right.implicitWidth)<.5,"Right group never stretches into footer space");
                            confirmed(right.width<fixture.width*.7,"Right group stays compact");
                        }
                    }
                }
            } finally {fixture.destroy();window.width=1920;waitForPolish(window);}
        }
        function test_04_extraImages(){
            workspace.send("add_images",{paths:["/tmp/lens-cap-stage-ui/extra.jpeg"]});settle();confirmed(!workspace.error,workspace.message);
            workspace.send("select_image",{source:"/tmp/lens-cap-stage-ui/extra.jpeg"});settle();confirmed(!workspace.error,workspace.message);
            checked(workspace.nativeRegions.length,0);checked(workspace.nativeScene.objects.length,0);
            workspace.send("native_regions",{regions:[{id:"extra-region",label:"Extra image region",color:"#4db6ac",points:[[100,100],[200,100],[200,200]]}]});settle();confirmed(!workspace.error,workspace.message);
            workspace.send("select_image",{source:workspace.sourcePath});settle();confirmed(!workspace.error,workspace.message);
            checked(workspace.nativeRegions.length,1);confirmed(workspace.nativeRegions[0].label!=="Extra image region");
        }
        function test_05_persistenceAndExport(){
            workspace.send("save",{path:"/tmp/lens-cap-stage-ui/scene.lenscap"});settle();confirmed(!workspace.error,workspace.message);
            workspace.send("export_spatial",{path:"/tmp/lens-cap-stage-ui/scene.obj",format:"obj"});settle();confirmed(!workspace.error,workspace.message);
            workspace.send("load",{path:"/tmp/lens-cap-stage-ui/scene.lenscap"});settle();confirmed(!workspace.error,workspace.message);
            checked(workspace.nativeRegions.length,1);checked(workspace.nativeScene.objects.length,0);confirmed(workspace.planeCalibration!==null);
        }
        function test_06_silentOperationsSettings() {
            workspace.changeStage("lens");const toast=child("operationToast");toast.close();wait(100);
            workspace.queueRibbonSettings({snapping:!workspace.snapping});wait(750);settle();
            confirmed(!workspace.error,workspace.message);confirmed(!toast.opened,"Routine settings do not toast");
        }
        function test_07_focusedReferenceMeasurementsSaveAndReload() {
            workspace.changeStage("calibration");waitForPolish(window);wait(50);
            const editor=workspace.spatialTools,operations=child("modeOperations");
            function lengthControl(item,description) {
                if(item.description===description && item.metres!==undefined)return item;
                for(const candidate of item.children || []) {const found=lengthControl(candidate,description);if(found)return found;}
                return null;
            }
            function entry(item) {
                if(typeof item.selectAll==="function" && item.text!==undefined)return item;
                for(const candidate of item.children || []) {const found=entry(candidate);if(found)return found;}
                return null;
            }
            const width=lengthControl(operations,"Reference width"),depth=lengthControl(operations,"Reference depth");
            confirmed(width!==null && depth!==null,"Shared length controls exist");
            const widthInput=entry(width.contentItem),depthInput=entry(depth.contentItem);
            confirmed(widthInput!==null && depthInput!==null,"Editable length fields exist");
            widthInput.forceActiveFocus();widthInput.text=`4' 7"`;widthInput.textEdited();
            confirmed(Math.abs(editor.referenceWidth-1.397)<1e-9,"Width editing reaches reference model");
            depthInput.forceActiveFocus();depthInput.text=`6' 6"`;depthInput.textEdited();
            confirmed(Math.abs(editor.referenceDepth-1.9812)<1e-9,"Depth editing reaches reference model");
            confirmed(editor.referenceDirty,"Measurement edits mark reference dirty");
            workspace.referencePlane=editor.copy(workspace.referencePlane);wait(20);
            confirmed(Math.abs(editor.referenceWidth-1.397)<1e-9 && Math.abs(editor.referenceDepth-1.9812)<1e-9,"Repeated backend reference object preserves local measurement edits");
            confirmed(depthInput.activeFocus,"Save exercised with measurement still focused");
            workspace.projectPath="/tmp/lens-cap-stage-ui/reference-measured.lenscap";workspace.file("save","/tmp/lens-cap-stage-ui/reference-measured.lenscap");settle();confirmed(!workspace.error,workspace.message);
            confirmed(Math.abs(workspace.referencePlane.width-1.397)<1e-9 && Math.abs(workspace.referencePlane.depth-1.9812)<1e-9,"Main Save persists latest measurement draft");
            workspace.send("load",{path:"/tmp/lens-cap-stage-ui/reference-measured.lenscap"});settle();confirmed(!workspace.error,workspace.message);
            confirmed(Math.abs(editor.referenceWidth-1.397)<1e-9 && Math.abs(editor.referenceDepth-1.9812)<1e-9,"Reopened project retains exact feet and inches");
        }
        onCompletedChanged:if(completed){console.log("STAGED TOTAL",JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}));Qt.callLater(Qt.quit);}
    }
}
