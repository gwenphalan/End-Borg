//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.tool_app
import qs.modules.lensCalibration
import "modules/lensCalibration/CurveGeometry.js" as CurveGeometry

AppWindow {
    id: window
    Component.onCompleted:Quickshell.watchFiles=false
    appTitle: "Lens Calibration verification"
    showWindowChrome: false
    width: 1200; height: 820
    readonly property string fixtureRoot:Quickshell.env("QS_LENS_TEST_FIXTURE") || "/tmp/lens-verification"
    readonly property int testOrder:Number(Quickshell.env("QS_LENS_TEST_ORDER") || "1")
    CalibrationWorkspace { id: workspace; objectName: "lensWorkspace"; anchors.fill: parent }
    Process {
        id: annotationWriter
        property int result: -1
        onExited: (exitCode, exitStatus) => result=exitCode
    }
    TestCase {
        name: "LensCalibrationIntegration"
        when: window.visible && workspace.ready
        function tracedCompare(actual,expected) {if(actual!==expected) console.log("LENS ASSERT",qtest_results.functionName,JSON.stringify(actual),JSON.stringify(expected),(new Error()).stack);compare(actual,expected);}
        function tracedVerify(value,message) {if(!value) console.log("LENS ASSERT",qtest_results.functionName,message || "verify failed",(new Error()).stack);verify(value,message);}
        function settle() { tryVerify(function() { return !workspace.busy; }, 20000); }
        function child(name) { const result=findChild(workspace,name); verify(result!==null,"Missing "+name); return result; }
        function loadFixture() {
            for(const name of ["fileMenu","calibrationMenu","exportMenu","adjustments","discard","legacyConversion"]) {const popup=findChild(workspace,name);if(popup && popup.visible) {popup.close();tryCompare(popup,"visible",false);}}
            settle(); workspace.send("load",{path:window.fixtureRoot+"/session.json"}); settle();
            verify(!workspace.error,workspace.message); verify(workspace.hasImage); verify(workspace.curves.length>=3);
            workspace.corrected=false; workspace.panTool=false; workspace.drawing=false;
            waitForPolish(window);wait(20);
        }
        function init() { const only=Quickshell.env("QS_LENS_TEST_FUNCTION");if(only && qtest_results.functionName!==only) skip("Focused regression run"); console.log("LENS TEST",qtest_results.functionName); loadFixture(); }
        function cleanup() {
            const labelme=findChild(workspace,"labelmeProcess");
            if(labelme && labelme.running) {labelme.signal(15);tryCompare(labelme,"running",false,10000);settle();}
            console.log("LENS RESULT",qtest_results.functionName,"failures",qtest_results.failCount);
        }
        onCompletedChanged: if(completed) console.log("LENS TOTAL",JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount,skipped:qtest_results.skipCount}));
        function test_zoomInputAndFitReset() {
            const zoom=child("zoomControl"),input=child("zoomPercentInput"),reset=child("resetViewButton"),view=child("lensViewport"),coords=child("cursorCoordinates");
            workspace.fit();waitForPolish(window);verify(reset.visible);verify(!reset.enabled);
            verify(coords.mapToItem(window.contentItem,0,0).x>zoom.mapToItem(window.contentItem,0,0).x);
            const old=workspace.zoom,cx=view.width/2,cy=view.height/2;
            const before=[(cx-workspace.offsetX)/old,(cy-workspace.offsetY)/old];
            input.edited(125);compare(workspace.zoom,1.25);verify(reset.visible);verify(reset.enabled);
            verify(Math.abs((cx-workspace.offsetX)/workspace.zoom-before[0])<1e-8);
            verify(Math.abs((cy-workspace.offsetY)/workspace.zoom-before[1])<1e-8);
            mouseClick(reset,reset.width/2,reset.height/2);verify(workspace.viewAtReset);verify(reset.visible);verify(!reset.enabled);
            workspace.offsetX+=25;verify(reset.visible);waitForPolish(window);mouseClick(reset,reset.width/2,reset.height/2);verify(reset.visible);verify(!reset.enabled);
            if(Quickshell.env("QS_LENS_CAPTURE_ZOOM")) {workspace.selected=0;workspace.selectedPoint=0;waitForPolish(window);grabImage(window.contentItem).save(Quickshell.env("QS_LENS_CAPTURE_ZOOM"));}
        }
        function test_viewportSurvivesActions() {
            workspace.zoom=1.7;workspace.offsetX=-275;workspace.offsetY=-180;
            function unchanged() {
                compare(workspace.zoom,1.7);compare(workspace.offsetX,-275);compare(workspace.offsetY,-180);
            }
            workspace.send("calibrate",{order:window.testOrder});settle();verify(!workspace.error,workspace.message);
            wait(50);unchanged();
            workspace.corrected=false;wait(50);unchanged();
            workspace.corrected=true;wait(50);unchanged();
            workspace.send("save",{path:window.fixtureRoot+"/qt-viewport.lenscap"});settle();unchanged();
            window.width+=80;window.height+=40;wait(100);unchanged();
            window.width-=80;window.height-=40;wait(100);unchanged();
            workspace.corrected=false;workspace.remember();workspace.curves[0][0][0]+=1;workspace.changed();
            workspace.undo();wait(50);unchanged();workspace.redo();wait(50);unchanged();
        }
        function test_automaticLabelMeHandoff() {
            workspace.send("calibrate",{order:window.testOrder});settle();verify(!workspace.error,workspace.message);
            workspace.send("prepare_labelme");settle();verify(!workspace.error,workspace.message);
            const labelme=child("labelmeProcess");tryCompare(labelme,"running",true,15000);
            tryCompare(window,"visible",false);verify(workspace.backgroundForLabelme);
            verify(workspace.annotating);verify(!workspace.editable);verify(workspace.labelmeJson.endsWith(".json"));
            const curves=JSON.stringify(workspace.curves);workspace.undo();compare(JSON.stringify(workspace.curves),curves);
            annotationWriter.result=-1;
            wait(2500); // LabelMe opens the PNG folder before any annotation exists.
            annotationWriter.command=[Quickshell.env("HOME")+"/.local/share/uv/tools/labelme/bin/python",Quickshell.env("HOME")+"/.config/quickshell/ii/scripts/lens_calibration/simulate_labelme_save.py",window.fixtureRoot+"/labelme.json",workspace.labelmeJson];
            annotationWriter.running=true;tryVerify(function(){return annotationWriter.result!==-1;},10000);compare(annotationWriter.result,0);
            // Allow the real LabelMe process to initialize, without sending user input.
            wait(2000);verify(labelme.running,"LabelMe exited before test close");
            labelme.signal(15);tryCompare(labelme,"running",false,10000);
            tryVerify(function(){return !workspace.busy && workspace.regions.length>0;},20000);
            verify(!workspace.error,workspace.message);verify(!workspace.annotating);
            tryCompare(window,"visible",true);verify(!workspace.backgroundForLabelme);
            compare(workspace.regions[0].label,"floor");verify(workspace.regions[0].points.length>1000);
        }
        function test_overshootingRegionsAreClipped() {
            workspace.send("calibrate",{order:window.testOrder});settle();verify(!workspace.error,workspace.message);
            const w=workspace.outputDimensions[0],h=workspace.outputDimensions[1];
            annotationWriter.result=-1;
            annotationWriter.command=["/usr/bin/python","-c","import json,sys;w,h=map(int,sys.argv[2:]);json.dump(dict(imageWidth=w,imageHeight=h,shapes=[dict(label='coverage',shape_type='polygon',points=[[0,0],[w-1,0],[w-1,h-1],[0,h-1]])]),open(sys.argv[1],'w'))",window.fixtureRoot+"/qt-overshoot.json",String(w),String(h)];
            annotationWriter.running=true;tryVerify(()=>annotationWriter.result!==-1,10000);compare(annotationWriter.result,0);
            workspace.send("labelme",{path:window.fixtureRoot+"/qt-overshoot.json"});settle();verify(!workspace.error,workspace.message);verify(workspace.hasRegions);
            for(const region of workspace.regions) for(const p of region.points) {
                verify(p[0]>=0 && p[0]<=workspace.dimensions[0]-1);verify(p[1]>=0 && p[1]<=workspace.dimensions[1]-1);
            }
            workspace.send("regions",{path:window.fixtureRoot+"/qt-clipped-frigate.json"});settle();verify(!workspace.error,workspace.message);
        }
        function test_namedLensProfileLifecycle() {
            workspace.send("calibrate",{order:window.testOrder});settle();tracedVerify(!workspace.error,workspace.message);
            const settings=child("calibrationMenu");settings.open();tryCompare(settings,"opened",true);waitForPolish(window);
            const dropdown=findChild(settings.contentItem,"lensProfileDropdown"),save=findChild(settings.contentItem,"saveLensProfile");
            const rename=findChild(settings.contentItem,"renameLensProfile"),update=findChild(settings.contentItem,"updateLensProfile"),remove=findChild(settings.contentItem,"deleteLensProfile");
            tracedVerify(dropdown!==null);tracedCompare(dropdown.choices[0].name,"None");
            tracedVerify(!rename.enabled);tracedVerify(!update.enabled);tracedVerify(!remove.enabled);
            settings.contentItem.contentY=Math.max(0,settings.contentItem.contentHeight-settings.contentItem.height);wait(300);
            mouseClick(save,save.width/2,save.height/2);
            const dialog=child("profileNameDialog");tryCompare(dialog,"opened",true);tracedVerify(!dialog.confirmEnabled);
            dialog.text="Test profile "+Date.now();dialog.confirmed();settle();tracedVerify(!workspace.error,workspace.message);tryCompare(dialog,"visible",false);
            const filename=workspace.lensProfilePath;tracedVerify(filename!=="");tracedVerify(workspace.lensProfiles.some(p=>p.path===filename));
            tracedVerify(rename.enabled);tracedVerify(update.enabled);tracedVerify(remove.enabled);
            tracedVerify(rename.x>dropdown.x+dropdown.width-1);tracedVerify(update.x>rename.x);tracedVerify(remove.x>update.x);
            dropdown.chosen("");settle();tracedCompare(workspace.calibration,null);tracedCompare(workspace.lensProfilePath,"");tracedVerify(!rename.enabled);
            dropdown.chosen(filename);settle();tracedVerify(!workspace.error,workspace.message);tracedCompare(workspace.lensProfilePath,filename);tracedVerify(!!workspace.calibration);
            workspace.send("update_profile",{path:filename});settle();tracedVerify(!workspace.error,workspace.message);
            workspace.send("rename_profile",{path:filename,name:"Renamed "+Date.now()});settle();tracedVerify(!workspace.error,workspace.message);
            workspace.send("delete_profile",{path:filename});settle();tracedVerify(!workspace.error,workspace.message);tracedCompare(workspace.lensProfilePath,"");tracedVerify(!workspace.lensProfiles.some(p=>p.path===filename));
            settings.close();tryCompare(settings,"visible",false);
        }
        function test_presetsAndExtraImageFolder() {
            workspace.send("calibrate",{order:window.testOrder});settle();verify(!workspace.error,workspace.message);
            const coefficients=JSON.stringify(workspace.calibration.coefficients);
            workspace.send("save_preset",{path:window.fixtureRoot+"/qt-preset.json"});settle();verify(!workspace.error,workspace.message);
            workspace.send("load_preset",{path:window.fixtureRoot+"/qt-preset.json",curves:[]});settle();verify(!workspace.error,workspace.message);
            compare(JSON.stringify(workspace.calibration.coefficients),coefficients);compare(workspace.curves.length,0);
            annotationWriter.result=-1;
            annotationWriter.command=["/usr/bin/python","-c","import shutil,sys;shutil.copyfile(sys.argv[1],sys.argv[2])",window.fixtureRoot+"/original.png",window.fixtureRoot+"/extra-verification.png"];
            annotationWriter.running=true;tryVerify(()=>annotationWriter.result!==-1,10000);compare(annotationWriter.result,0);
            workspace.send("add_images",{paths:[window.fixtureRoot+"/extra-verification.png"]});settle();verify(!workspace.error,workspace.message);
            compare(workspace.extraImages.length,1);compare(JSON.stringify(workspace.calibration.coefficients),coefficients);
            workspace.send("prepare_labelme");settle();verify(!workspace.error,workspace.message);
            const labelme=child("labelmeProcess");tryCompare(labelme,"running",true,15000);
            const folder=workspace.labelmeJson.substring(0,workspace.labelmeJson.lastIndexOf("/"));
            annotationWriter.result=-1;
            wait(2500);
            annotationWriter.command=[Quickshell.env("HOME")+"/.local/share/uv/tools/labelme/bin/python",Quickshell.env("HOME")+"/.config/quickshell/ii/scripts/lens_calibration/simulate_labelme_save.py",window.fixtureRoot+"/labelme.json",folder];
            annotationWriter.running=true;tryVerify(()=>annotationWriter.result!==-1,10000);compare(annotationWriter.result,0);
            wait(2000);verify(labelme.running);labelme.signal(15);tryCompare(labelme,"running",false,10000);
            tryVerify(()=>!workspace.busy && workspace.batchRegions.length===2,20000);verify(!workspace.error,workspace.message);verify(workspace.hasRegions);
            workspace.send("regions",{path:window.fixtureRoot+"/qt-batch-frigate.json"});settle();verify(!workspace.error,workspace.message);
            workspace.send("save",{path:window.fixtureRoot+"/qt-batch-session.json"});settle();verify(!workspace.error,workspace.message);
            workspace.send("load",{path:window.fixtureRoot+"/qt-batch-session.json"});settle();verify(!workspace.error,workspace.message);
            compare(workspace.extraImages.length,1);compare(workspace.batchRegions.length,2);compare(JSON.stringify(workspace.calibration.coefficients),coefficients);
        }
        function test_calibrationAndCoefficientValidation() {
            workspace.send("calibrate",{order:window.testOrder}); settle();
            verify(!workspace.error,workspace.message); verify(workspace.calibration!==null);
            verify(workspace.calibration.rmsAfter<(window.fixtureRoot==="/tmp/lens-verification" ? .1 : workspace.calibration.rmsBefore)); verify(workspace.corrected); verify(workspace.preview!=="");
            const a=child("k1"),b=child("k2");
            a.text="-0.2"; b.text="0"; workspace.applyAdjustment(); settle();
            verify(!workspace.error,workspace.message); compare(workspace.calibration.coefficients[0],-.2);
            a.text="-3";b.text="0"; workspace.applyAdjustment(); settle();
            verify(workspace.error); compare(workspace.calibration.coefficients[0],-.2);
            a.text="";b.text="0";workspace.applyAdjustment();
            verify(workspace.error); verify(!workspace.busy); compare(workspace.calibration.coefficients[0],-.2);
        }
        function test_menus() {
            for(const name of ["fileMenu","calibrationMenu","exportMenu"]) {
                const menu=child(name); menu.open();tryCompare(menu,"opened",true);verify(menu.width>100);verify(menu.height>50);
                verify(menu.x>=0 && menu.x+menu.width<=workspace.width);
                menu.close();tryCompare(menu,"opened",false);
            }
            const adjustments=child("adjustments");adjustments.open();tryCompare(adjustments,"opened",true);
            adjustments.close();tryCompare(adjustments,"opened",false);
        }
        function test_projectSettingsModal() {
            const dialog=child("calibrationMenu"),custom=child("customFov"),fov=child("hfovInput"),model=child("modelSetting"),snap=child("snapSetting");
            const originalSettings=JSON.stringify(workspace.projectSettings),originalCalibration=JSON.stringify(workspace.calibration),originalPreview=workspace.preview;
            dialog.open();tryCompare(dialog,"opened",true);custom.checked=true;fov.edited(120);model.currentIndex=1;snap.checked=false;
            const saveProfile=findChild(dialog.contentItem,"saveLensProfile"),loadProfile=findChild(dialog.contentItem,"lensProfileDropdown");
            verify(saveProfile!==null);verify(loadProfile!==null);verify(loadProfile.enabled);
            compare(saveProfile.enabled,!!workspace.calibration);
            const actualFov=findChild(dialog.contentItem,"lens.hfov");verify(actualFov!==null,"Missing shared HFOV row");actualFov.invalidNumber("bad");verify(actualFov.validation!=="");
            dialog.close();tryCompare(dialog,"visible",false);
            compare(JSON.stringify(workspace.projectSettings),originalSettings);compare(JSON.stringify(workspace.calibration),originalCalibration);compare(workspace.preview,originalPreview);
            dialog.open();tryCompare(dialog,"opened",true);verify(dialog.modal);compare(dialog.title,"Project settings");
            compare(findChild(dialog.contentItem,"lens.hfov").validation,"");compare(findChild(dialog.contentItem,"lens.hfov").localNumericDraft,undefined);verify(!fov.invalid);
            if(Quickshell.env("QS_LENS_CAPTURE_SETTINGS")) {
                wait(250);let captured=false;
                dialog.contentItem.grabToImage(result=>{result.saveToFile(Quickshell.env("QS_LENS_CAPTURE_SETTINGS"));captured=true;});
                tryVerify(()=>captured,10000);
            }
            verify(Math.abs(dialog.x-(workspace.width-dialog.width)/2)<2);
            const curves=JSON.stringify(workspace.curves);
            custom.checked=true;fov.edited(100);model.currentIndex=1;snap.checked=false;
            workspace.applyProjectSettings("");settle();verify(!workspace.error,workspace.message);
            compare(workspace.projectSettings.hfov,100);compare(workspace.order,2);compare(workspace.snapping,false);verify(workspace.dirty);
            verify(!saveProfile.enabled,"Save lens profile must disable without a correction");
            compare(JSON.stringify(workspace.curves),curves);compare(workspace.calibration,null);compare(workspace.preview,"");verify(!workspace.corrected);
            workspace.send("save",{path:window.fixtureRoot+"/qt-settings.lenscap"});settle();verify(!workspace.error,workspace.message);
            workspace.send("load",{path:window.fixtureRoot+"/qt-settings.lenscap"});settle();verify(!workspace.error,workspace.message);
            compare(workspace.projectSettings.hfov,100);compare(workspace.order,2);compare(workspace.snapping,false);compare(JSON.stringify(workspace.curves),curves);
            dialog.open();tryCompare(dialog,"opened",true);compare(dialog.draftHfov,100);verify(custom.checked);compare(model.currentIndex,1);verify(!snap.checked);
            fov.invalid=true;workspace.applyProjectSettings("");verify(workspace.error);verify(!workspace.busy);verify(dialog.opened);
            fov.invalid=false;custom.checked=false;model.currentIndex=window.testOrder-1;snap.checked=true;
            workspace.applyProjectSettings("");settle();verify(!workspace.error,workspace.message);compare(workspace.projectSettings.hfov,null);
            dialog.open();tryCompare(dialog,"opened",true);verify(!custom.checked);verify(!fov.enabled);verify(dialog.draftHfov>1 && dialog.draftHfov<179);
            workspace.applyProjectSettings("calibrate");
            tryVerify(()=>!workspace.busy && workspace.calibration!==null,20000);verify(!workspace.error,workspace.message);verify(workspace.corrected);
        }
        function test_editUndoRedoDeleteAndCoordinates() {
            workspace.selected=0;workspace.selectedPoint=0;
            const original=workspace.curves[0][0][0];
            workspace.setCoordinate(0,String(original+1));compare(workspace.curves[0][0][0],original+1);verify(workspace.dirty);
            workspace.undo();compare(workspace.curves[0][0][0],original);
            workspace.redo();compare(workspace.curves[0][0][0],original+1);
            workspace.selected=0;workspace.selectedPoint=0;
            workspace.setCoordinate(0,"");verify(workspace.error);compare(workspace.curves[0][0][0],original+1);
            workspace.setCoordinate(1,"-1");verify(workspace.error);
            const count=workspace.curves[0].length;workspace.removePointOrCurve(false);compare(workspace.curves[0].length,count-1);
            workspace.undo();compare(workspace.curves[0].length,count);
            workspace.selected=0;const curves=workspace.curves.length;workspace.removePointOrCurve(true);compare(workspace.curves.length,curves-1);
            workspace.undo();compare(workspace.curves.length,curves);
        }
        function test_canvasAnnotationAndViewport() {
            const area=child("lensMouseArea"), view=child("lensViewport");
            workspace.fit();workspace.drawing=true;workspace.activeCurve=-1;workspace.snapping=true;
            const count=workspace.curves.length;
            const x=workspace.offsetX+workspace.dimensions[0]*.5*workspace.zoom;
            const y=workspace.offsetY+workspace.dimensions[1]*.5*workspace.zoom;
            mouseClick(area,x,y,Qt.LeftButton);compare(workspace.curves.length,count+1);
            const point=workspace.curves[count][0];
            verify(Math.abs(point[0]-Math.round(workspace.dimensions[0]*.5))<=1);
            verify(Math.abs(point[1]-Math.round(workspace.dimensions[1]*.5))<=1);
            const saved=JSON.stringify(workspace.curves);
            workspace.zoom*=1.5;workspace.offsetX-=20;workspace.offsetY+=30;view.requestPaint();
            compare(JSON.stringify(workspace.curves),saved);
            workspace.undo();compare(workspace.curves.length,count);
            workspace.redo();compare(workspace.curves.length,count+1);
        }
        function test_cursorCoordinatesFollowViewport() {
            const area=child("lensMouseArea"),readout=child("cursorCoordinates"),view=child("lensViewport"),zoom=child("zoomControl");
            workspace.corrected=false;workspace.fit();waitForPolish(window);
            const zoomX=zoom.mapToItem(window.contentItem,0,0).x;
            verify(readout.mapToItem(window.contentItem,0,0).x>zoomX);compare(readout.width,128);
            for(const x of [1,Math.min(1920,workspace.dimensions[0]-1)]) {
                mouseMove(area,workspace.offsetX+x*workspace.zoom,workspace.offsetY+500*workspace.zoom);waitForPolish(window);
                verify(Math.abs(zoom.mapToItem(window.contentItem,0,0).x-zoomX)<.01);compare(readout.width,128);
            }
            mouseMove(area,workspace.offsetX+1000.4*workspace.zoom,workspace.offsetY+500.3*workspace.zoom);
            tryCompare(readout,"active",true);
            verify(Math.abs(workspace.cursorPosition[0]-1000.4)<2);verify(Math.abs(workspace.cursorPosition[1]-500.3)<2);
            workspace.setZoomPercent(150);workspace.offsetX+=20;
            mouseMove(area,workspace.offsetX+1000.4*workspace.zoom,workspace.offsetY+500.3*workspace.zoom);
            verify(Math.abs(workspace.cursorPosition[0]-1000.4)<2);verify(Math.abs(workspace.cursorPosition[1]-500.3)<2);
            workspace.fit();mouseMove(area,view.width-1,1);tryCompare(readout,"active",false);
            verify(readout.text.indexOf("—")>=0);
            waitForPolish(window);verify(Math.abs(zoom.mapToItem(window.contentItem,0,0).x-zoomX)<.01);
        }
        function test_correctedToggleLivesBelowUndoRedo() {
            const toggle=child("toggleCorrectedView"),view=child("lensViewport");
            workspace.send("calibrate",{order:window.testOrder});settle();verify(!workspace.error,workspace.message);waitForPolish(window);
            verify(toggle.enabled);verify(toggle.toggled);verify(toggle.parent.width<70);
            verify(toggle.y>toggle.parent.children[0].y);verify(toggle.y>toggle.parent.children[1].y);
            const location=toggle.mapToItem(view,0,0);verify(location.x>view.width-100);verify(location.y<200);
            mouseClick(toggle,toggle.width/2,toggle.height/2);verify(!workspace.corrected);verify(!toggle.toggled);
            mouseClick(toggle,toggle.width/2,toggle.height/2);verify(workspace.corrected);verify(toggle.toggled);
        }
        function test_contextActionsUseCanvasPill() {
            const view=child("lensViewport"),remove=child("deletePointAction");
            verify(findChild(workspace,"finishCurveAction")===null);
            verify(findChild(workspace,"continueCurveAction")===null);
            workspace.corrected=false;workspace.drawing=false;workspace.selected=0;workspace.selectedPoint=0;workspace.activeCurve=-1;
            waitForPolish(window);verify(remove.visible);
            const position=remove.mapToItem(view,0,0);verify(position.x<80);verify(position.x+remove.width<=view.width);verify(position.y>80 && position.y<200);
            const count=workspace.curves[0].length;
            mouseClick(remove,remove.width/2,remove.height/2);compare(workspace.curves[0].length,count-1);
            workspace.undo();compare(workspace.curves[0].length,count);
            workspace.drawing=true;workspace.activeCurve=0;workspace.selected=0;workspace.selectedPoint=0;
            verify(!remove.visible);view.forceActiveFocus();keyClick(Qt.Key_Return);compare(workspace.activeCurve,-1);compare(workspace.selected,-1);compare(workspace.selectedPoint,-1);
        }
        function test_curveOverlayRenders() {
            const view=child("lensViewport");
            workspace.corrected=false;workspace.curves=[];workspace.regions=[];workspace.fit();
            view.requestPaint();wait(100);
            const sample=view.mapToItem(window.contentItem,workspace.offsetX+750*workspace.zoom,workspace.offsetY+500*workspace.zoom);
            const x=Math.round(sample.x),y=Math.round(sample.y);
            const blank=grabImage(window.contentItem);
            workspace.curves=[[[500,500],[1000,500]]];view.requestPaint();wait(100);
            const painted=grabImage(window.contentItem);let difference=0;
            for(let dy=-2;dy<=2;dy++) difference=Math.max(difference,Math.abs(painted.red(x,y+dy)-blank.red(x,y+dy)),Math.abs(painted.alpha(x,y+dy)-blank.alpha(x,y+dy)));
            verify(difference>0,"Curve must render onto the canvas, not just exist in annotation state");
        }
        function test_undoKeepsUnfinishedCurveActive() {
            const area=child("lensMouseArea"),view=child("lensViewport");
            workspace.corrected=false;workspace.drawing=true;workspace.panTool=false;workspace.snapping=true;
            workspace.curves=[];workspace.past=[];workspace.future=[];workspace.activeCurve=-1;workspace.fit();waitForPolish(window);
            function clickAt(x,y) {mouseClick(area,workspace.offsetX+x*workspace.zoom,workspace.offsetY+y*workspace.zoom);}
            clickAt(400,300);clickAt(600,320);clickAt(800,300);
            view.forceActiveFocus();tryCompare(view,"activeFocus",true);tryCompare(workspace,"canvasShortcuts",true);wait(20);keyClick(Qt.Key_Z,Qt.ControlModifier);
            tracedCompare(workspace.curves[0].length,2);tracedCompare(workspace.activeCurve,0);tracedCompare(workspace.selected,0);tracedCompare(workspace.selectedPoint,1);
            clickAt(1000,320);tracedCompare(workspace.curves.length,1);tracedCompare(workspace.curves[0].length,3);
            tracedVerify(workspace.curves[0][2][0]>950);
            keyClick(Qt.Key_Return);tracedCompare(workspace.activeCurve,-1);workspace.undo();tracedCompare(workspace.activeCurve,-1);
        }
        function test_finishClearsCurveAndNodeSelection() {
            const area=child("lensMouseArea"),view=child("lensViewport");
            workspace.corrected=false;workspace.drawing=true;workspace.panTool=false;workspace.fit();
            const original=JSON.stringify(workspace.curves);
            function prepare() {workspace.activeCurve=0;workspace.selected=0;workspace.selectedPoint=0;waitForPolish(window);}
            function cleared() {compare(workspace.activeCurve,-1);compare(workspace.selected,-1);compare(workspace.selectedPoint,-1);compare(JSON.stringify(workspace.curves),original);}
            prepare();view.forceActiveFocus();keyClick(Qt.Key_Return);cleared();
            prepare();mouseClick(area,area.width/2,area.height/2,Qt.RightButton);cleared();
        }
        function test_ctrlClickTogglesNonAdjacentPoints() {
            const area=child("lensMouseArea");
            workspace.corrected=false;workspace.drawing=false;workspace.panTool=false;
            workspace.curves=[[[400,300],[600,320],[800,300]],[[900,450],[1100,450]]];
            workspace.selected=-1;workspace.selectedPoint=-1;workspace.explicitPoints=[];
            workspace.fit();waitForPolish(window);
            function clickPoint(x,y,modifiers) {mouseClick(area,workspace.offsetX+x*workspace.zoom,workspace.offsetY+y*workspace.zoom,Qt.LeftButton,modifiers);}
            clickPoint(400,300,Qt.NoModifier);clickPoint(800,300,Qt.ControlModifier);
            compare(JSON.stringify(workspace.selectedNodes),"[[0,0],[0,2]]");
            clickPoint(1100,450,Qt.ControlModifier);compare(workspace.selectedNodes.length,3);
            clickPoint(800,300,Qt.ControlModifier);compare(JSON.stringify(workspace.selectedNodes),"[[0,0],[1,1]]");
            workspace.setCoordinate(0,"800");compare(workspace.curves[0][1][0],600);
        }
        function test_shiftClickSelectsCurveAndEditsAverage() {
            const area=child("lensMouseArea");
            workspace.corrected=false;workspace.drawing=false;workspace.panTool=false;
            workspace.curves=[[[400,300],[600,320],[800,300]]];workspace.selected=-1;workspace.selectedPoint=-1;
            workspace.fit();waitForPolish(window);
            mouseClick(area,workspace.offsetX+600*workspace.zoom,workspace.offsetY+320*workspace.zoom,Qt.LeftButton,Qt.ShiftModifier);
            verify(workspace.allCurvePoints);compare(workspace.selectedIndices.length,3);
            compare(workspace.selectedPosition[0],600);
            workspace.setCoordinate(0,"650");compare(workspace.curves[0][0][0],450);compare(workspace.curves[0][2][0],850);
            workspace.undo();compare(workspace.curves[0][0][0],400);
            workspace.selected=0;workspace.selectedPoint=1;workspace.allCurvePoints=true;
            workspace.removePointOrCurve(false);compare(workspace.curves.length,0);
        }
        function test_editCurveContinuationUsesSelectedEnd() {
            const area=child("lensMouseArea"),view=child("lensViewport");
            workspace.corrected=false;workspace.drawing=false;workspace.panTool=false;workspace.snapping=true;
            workspace.curves=[[[400,300],[600,320],[800,300]]];workspace.activeCurve=-1;workspace.selected=-1;workspace.selectedPoint=-1;workspace.fit();waitForPolish(window);
            function clickAt(x,y) {mouseClick(area,workspace.offsetX+x*workspace.zoom,workspace.offsetY+y*workspace.zoom);}
            clickAt(400,300);compare(workspace.selectedPoint,0);
            clickAt(250,300);compare(workspace.selectedPoint,0);compare(workspace.curves.length,1);verify(!workspace.drawing);compare(workspace.activeCurve,-1);
            verify(workspace.curves[0][0][0]<300);compare(workspace.curves[0][1][0],400);compare(workspace.curves[0][3][0],800);
            clickAt(150,300);verify(workspace.curves[0][0][0]<200);verify(workspace.curves[0][1][0]<300);
            workspace.undo();compare(workspace.curves[0].length,4);workspace.redo();compare(workspace.curves[0].length,5);
            clickAt(800,300);compare(workspace.selectedPoint,4);clickAt(1000,300);
            compare(workspace.curves[0].length,6);verify(workspace.curves[0][5][0]>950);verify(!workspace.drawing);
            view.forceActiveFocus();keyClick(Qt.Key_Escape);compare(workspace.selected,-1);
            clickAt(1100,550);compare(workspace.curves.length,1);compare(workspace.curves[0].length,6);
        }
        function test_newCurveAlwaysStartsIndependentCurve() {
            const area=child("lensMouseArea"),view=child("lensViewport");
            workspace.corrected=false;workspace.drawing=true;workspace.panTool=false;
            workspace.curves=[[[400,300],[600,320],[800,300]]];workspace.activeCurve=-1;
            workspace.past=[];workspace.future=[];workspace.fit();waitForPolish(window);
            const original=JSON.stringify(workspace.curves[0]);
            mouseClick(area,workspace.offsetX+800*workspace.zoom,workspace.offsetY+300*workspace.zoom);
            tracedCompare(workspace.curves.length,2);tracedCompare(workspace.activeCurve,1);tracedCompare(workspace.curves[1].length,1);tracedCompare(JSON.stringify(workspace.curves[0]),original);
            mouseClick(area,workspace.offsetX+1000*workspace.zoom,workspace.offsetY+400*workspace.zoom);
            tracedCompare(workspace.curves.length,2);tracedCompare(workspace.curves[1].length,2);
            workspace.undo();tracedCompare(workspace.curves[1].length,1);tracedCompare(workspace.activeCurve,1);
            workspace.redo();tracedCompare(workspace.curves[1].length,2);tracedCompare(workspace.activeCurve,1);
            view.forceActiveFocus();keyClick(Qt.Key_Return);tracedCompare(workspace.activeCurve,-1);tracedCompare(workspace.selected,-1);
            mouseClick(area,workspace.offsetX+400*workspace.zoom,workspace.offsetY+300*workspace.zoom);
            tracedCompare(workspace.curves.length,3);tracedCompare(workspace.activeCurve,2);tracedCompare(JSON.stringify(workspace.curves[0]),original);
        }
        function test_centripetalBezierInterpolationAndNearestPoint() {
            const points=[[200,300],[500,600],[550,300],[1000,500]];
            const segments=CurveGeometry.segments(points);compare(segments.length,points.length-1);
            for(let i=0;i<segments.length;i++) {
                compare(JSON.stringify(CurveGeometry.evaluate(segments[i],0)),JSON.stringify(points[i]));
                compare(JSON.stringify(CurveGeometry.evaluate(segments[i],1)),JSON.stringify(points[i+1]));
                for(let j=0;j<=20;j++) for(const value of CurveGeometry.evaluate(segments[i],j/20)) verify(Number.isFinite(value));
            }
            const target=CurveGeometry.evaluate(segments[1],.4),hit=CurveGeometry.nearestPoint(points,target,1);
            verify(hit!==null);compare(hit.index,1);verify(Math.abs(hit.t-.4)<1e-5);verify(hit.distance<1e-4);
            verify(CurveGeometry.nearestPoint(points,[2000,2000],9)===null);
            for(const s of CurveGeometry.segments([[0,0],[0,0],[.00001,1],[5000,2],[5000,2]]))
                for(const p of [s.p0,s.c1,s.c2,s.p1]) for(const v of p) verify(Number.isFinite(v));
            const linear=CurveGeometry.segments([[0,0],[100,200]])[0];
            compare(JSON.stringify(CurveGeometry.evaluate(linear,.5)),JSON.stringify([50,100]));
        }
        function test_altClickInsertsOnEditPolylineInOrder() {
            const area=child("lensMouseArea"),view=child("lensViewport");
            workspace.corrected=false;workspace.drawing=false;workspace.panTool=false;workspace.fit();
            workspace.curves=[[[200,300],[500,600],[550,300],[1000,500]]];workspace.past=[];workspace.future=[];
            const before=workspace.copy(workspace.curves[0]);
            const target=[before[1][0]+.4*(before[2][0]-before[1][0]),before[1][1]+.4*(before[2][1]-before[1][1])];
            mouseClick(area,workspace.offsetX+target[0]*workspace.zoom,workspace.offsetY+target[1]*workspace.zoom,Qt.LeftButton,Qt.AltModifier);
            compare(workspace.curves[0].length,5);compare(workspace.selectedPoint,2);compare(workspace.activeCurve,-1);
            compare(JSON.stringify(workspace.curves[0][1]),JSON.stringify(before[1]));compare(JSON.stringify(workspace.curves[0][3]),JSON.stringify(before[2]));
            verify(Math.hypot(workspace.curves[0][2][0]-target[0],workspace.curves[0][2][1]-target[1])<4/workspace.zoom);
            workspace.undo();compare(JSON.stringify(workspace.curves[0]),JSON.stringify(before));workspace.redo();compare(workspace.curves[0].length,5);
        }
        function test_drawAndEditHaveSeparateBehaviors() {
            const area=child("lensMouseArea"),view=child("lensViewport"),draw=child("drawCurveTool"),edit=child("editCurveTool");
            workspace.curves=[[[400,300],[600,500],[800,300]]];workspace.fit();workspace.corrected=false;workspace.activeCurve=-1;
            workspace.drawing=true;workspace.panTool=false;waitForPolish(window);
            const x=workspace.offsetX+400*workspace.zoom,y=workspace.offsetY+300*workspace.zoom,original=JSON.stringify(workspace.curves[0]);
            mouseDrag(area,x,y,20,20,Qt.LeftButton,Qt.NoModifier,30);
            tracedCompare(JSON.stringify(workspace.curves[0]),original);tracedCompare(workspace.activeCurve,1);tracedCompare(workspace.curves[1].length,1);
            const before=JSON.stringify(workspace.curves);
            workspace.setCoordinate(0,"401");workspace.removePointOrCurve(false);
            view.forceActiveFocus();keyClick(Qt.Key_Right);keyClick(Qt.Key_Delete);tracedCompare(JSON.stringify(workspace.curves),before);
            tracedVerify(!child("deletePointAction").visible);tracedVerify(findChild(workspace,"finishCurveAction")===null);
            mouseClick(edit,edit.width/2,edit.height/2);tracedVerify(!workspace.drawing);tracedCompare(workspace.activeCurve,-1);
            view.forceActiveFocus();keyClick(Qt.Key_Escape);
            mouseClick(area,workspace.offsetX+1100*workspace.zoom,workspace.offsetY+600*workspace.zoom);tracedCompare(JSON.stringify(workspace.curves),before);
            mouseDrag(area,workspace.offsetX+600*workspace.zoom,workspace.offsetY+500*workspace.zoom,20,20,Qt.LeftButton,Qt.NoModifier,30);tracedVerify(JSON.stringify(workspace.curves[0])!==original);tracedCompare(workspace.curves.length,2);
            tracedVerify(child("deletePointAction").visible);tracedVerify(findChild(workspace,"finishCurveAction")===null);
            view.forceActiveFocus();keyClick(Qt.Key_Delete);tracedCompare(workspace.curves[0].length,2);workspace.undo();tracedCompare(workspace.curves[0].length,3);
            mouseClick(draw,draw.width/2,draw.height/2);tracedVerify(workspace.drawing);tracedVerify(!child("deletePointAction").visible);
        }
        function test_finishingSwitchesPolylineToBezierRendering() {
            const view=child("lensViewport");workspace.corrected=false;workspace.fit();workspace.drawing=true;
            workspace.curves=[[[300,400],[600,600],[900,300],[1200,500]]];workspace.regions=[];workspace.activeCurve=0;
            view.requestPaint();wait(80);const active=grabImage(window.contentItem);
            workspace.activeCurve=-1;view.requestPaint();wait(80);const finished=grabImage(window.contentItem);
            const target=CurveGeometry.evaluate(CurveGeometry.segments(workspace.curves[0])[1],.3);
            const sample=view.mapToItem(window.contentItem,workspace.offsetX+target[0]*workspace.zoom,workspace.offsetY+target[1]*workspace.zoom);
            const x=Math.round(sample.x),y=Math.round(sample.y);
            let difference=0;
            for(let dx=-3;dx<=3;dx++) for(let dy=-3;dy<=3;dy++) difference=Math.max(difference,Math.abs(active.red(x+dx,y+dy)-finished.red(x+dx,y+dy)),Math.abs(active.alpha(x+dx,y+dy)-finished.alpha(x+dx,y+dy)));
            verify(difference>0,"Finishing must render the interpolated Bézier curve rather than the active polyline");
        }
        function test_editShowsRawNodesFinishedViewHidesThem() {
            const view=child("lensViewport");workspace.corrected=false;workspace.fit();workspace.finishCurve();
            workspace.curves=[[[400,400],[700,400],[1000,400]]];workspace.regions=[];workspace.drawing=true;
            view.requestPaint();wait(80);const finished=grabImage(window.contentItem);
            workspace.drawing=false;view.requestPaint();wait(80);const editing=grabImage(window.contentItem);
            const sample=view.mapToItem(window.contentItem,workspace.offsetX+700*workspace.zoom,workspace.offsetY+400*workspace.zoom);
            const x=Math.round(sample.x),y=Math.round(sample.y);let difference=0;
            for(let dx=-4;dx<=4;dx++) for(let dy=-4;dy<=4;dy++) if(Math.abs(dy)>1)
                difference=Math.max(difference,Math.abs(finished.red(x+dx,y+dy)-editing.red(x+dx,y+dy)),Math.abs(finished.green(x+dx,y+dy)-editing.green(x+dx,y+dy)),Math.abs(finished.blue(x+dx,y+dy)-editing.blue(x+dx,y+dy)));
            verify(difference>0,"Edit must expose raw control-point circles; finished curves must hide them");
            compare(JSON.stringify(workspace.curves),JSON.stringify([[[400,400],[700,400],[1000,400]]]));
        }
        function test_dragZoomPanSnapAndFinish() {
            const area=child("lensMouseArea"),view=child("lensViewport");
            workspace.fit();workspace.corrected=false;workspace.drawing=false;workspace.panTool=false;
            const i=Math.floor(workspace.curves[0].length/2),old=workspace.copy(workspace.curves[0][i]);
            const x=workspace.offsetX+old[0]*workspace.zoom,y=workspace.offsetY+old[1]*workspace.zoom;
            mouseDrag(area,x,y,20,10,Qt.LeftButton,Qt.NoModifier,30);
            compare(workspace.selected,0);compare(workspace.selectedPoint,i);
            verify(workspace.curves[0][i][0]!==old[0]);verify(workspace.past.length>0);
            workspace.undo();compare(workspace.curves[0][i][0],old[0]);
            const saved=JSON.stringify(workspace.curves),z=workspace.zoom;
            mouseWheel(area,view.width/2,view.height/2,0,120,Qt.NoButton,Qt.NoModifier,20);
            verify(workspace.zoom>z);compare(JSON.stringify(workspace.curves),saved);
            const ox=workspace.offsetX,oy=workspace.offsetY;
            mouseDrag(area,view.width/2,view.height/2,35,25,Qt.MiddleButton,Qt.NoModifier,30);
            verify(workspace.offsetX!==ox);verify(workspace.offsetY!==oy);compare(JSON.stringify(workspace.curves),saved);
            workspace.fit();workspace.drawing=true;workspace.activeCurve=-1;workspace.snapping=true;
            const px=workspace.offsetX+1000.3*workspace.zoom,py=workspace.offsetY+600.6*workspace.zoom;
            mouseClick(area,px,py,Qt.LeftButton,Qt.AltModifier);
            verify(workspace.activeCurve>=0);const p=workspace.curves[workspace.activeCurve][0];
            verify(Math.abs(p[0]-Math.round(p[0]))>.01 || Math.abs(p[1]-Math.round(p[1]))>.01);
            view.forceActiveFocus();keyClick(Qt.Key_Return);compare(workspace.activeCurve,-1);
        }
        function test_typingDoesNotTriggerCanvasShortcuts() {
            const field=child("pointX");workspace.selected=0;workspace.selectedPoint=0;
            field.forceActiveFocus();tryCompare(field,"activeFocus",true);
            verify(workspace.textEditing);verify(!workspace.canvasShortcuts);
            const saved=JSON.stringify(workspace.curves),drawing=workspace.drawing;
            field.selectAll();keyClick(Qt.Key_D);compare(JSON.stringify(workspace.curves),saved);compare(workspace.drawing,drawing);
            keyClick(Qt.Key_Z,Qt.ControlModifier);compare(JSON.stringify(workspace.curves),saved);
            field.text=String(workspace.selectedPosition[0]);child("lensViewport").forceActiveFocus();
        }
        function test_toolbarActionsAreClearlyDisabledWithoutCalibration() {
            workspace.invalidate();
            const draw=child("drawRegionsButton"),exportAction=child("exportButton"),menu=child("exportMenu");
            verify(!draw.enabled);verify(!exportAction.enabled);verify(draw.opacity<.5);verify(exportAction.opacity<.5);
            workspace.send("calibrate",{order:window.testOrder});settle();verify(!workspace.error,workspace.message);
            verify(draw.enabled);verify(exportAction.enabled);waitForPolish(window);
            mouseMove(draw,draw.width/2,draw.height/2);tryCompare(draw,"hovered",true);
            mouseClick(exportAction,exportAction.width/2,exportAction.height/2);tryCompare(menu,"opened",true);
            const png=findChild(menu.contentItem,"exportCorrectedImage");verify(png!==null);verify(png.enabled);
            menu.close();
        }
        function test_saveContinuationReset() {
            workspace.dirty=true;
            compare(workspace.requestClose(),false);
            const dialog=child("discard");tryCompare(dialog,"opened",true);
            compare(dialog.title,"Discard Changes?");verify(dialog.modal);
            compare(workspace.pendingAction,"close");dialog.close();tryCompare(dialog,"visible",false);
            compare(workspace.pendingAction,"");compare(workspace.resumeAfterSave,false);
            workspace.pendingAction="close";workspace.resumeAfterSave=true;
            workspace.send("save",{path:window.fixtureRoot+"/missing-folder/project.lenscap"});settle();
            verify(workspace.error);verify(workspace.dirty);compare(workspace.pendingAction,"");compare(workspace.resumeAfterSave,false);
        }
        function test_saveAndExports() {
            workspace.send("calibrate",{order:window.testOrder});settle();verify(!workspace.error,workspace.message);
            workspace.send("save",{path:window.fixtureRoot+"/qt-project.lenscap"});settle();verify(!workspace.error,workspace.message);verify(!workspace.dirty);
            workspace.send("image",{path:window.fixtureRoot+"/qt-corrected.png"});settle();verify(!workspace.error,workspace.message);
            workspace.send("parameters",{path:window.fixtureRoot+"/qt-calibration.json"});settle();verify(!workspace.error,workspace.message);
            workspace.send("labelme",{path:window.fixtureRoot+"/labelme.json"});settle();verify(!workspace.error,workspace.message);verify(workspace.regions.length>0);
            workspace.send("regions",{path:window.fixtureRoot+"/qt-frigate.json"});settle();verify(!workspace.error,workspace.message);
            workspace.send("save",{path:window.fixtureRoot+"/qt-project.lenscap"});settle();
            workspace.send("load",{path:window.fixtureRoot+"/qt-project.lenscap"});settle();verify(!workspace.error,workspace.message);verify(workspace.regions.length>0);
        }
        function test_projectSaveAndSaveAs() {
            verify(workspace.isProjectFile("room.lenscap"));verify(workspace.isProjectFile("old.lensproject"));verify(!workspace.isProjectFile("image.png"));
            compare(workspace.newProjectName("old.lensproject"),"old.lenscap");
            const project=window.fixtureRoot+"/qt-save-behavior.lenscap";
            workspace.send("save",{path:project});settle();verify(!workspace.error,workspace.message);
            compare(workspace.projectPath,project);verify(!workspace.dirty);
            workspace.selected=0;workspace.selectedPoint=0;
            const edited=workspace.curves[0][0][0]+.25;
            workspace.setCoordinate(0,String(edited));verify(workspace.dirty);
            workspace.file("save");
            verify(!workspace.picking,"Save with an existing path must never open Files");
            verify(workspace.busy);verify(workspace.dirty,"Changes remain dirty until the worker confirms Save");
            settle();verify(!workspace.error,workspace.message);verify(!workspace.dirty);compare(workspace.projectPath,project);
            workspace.send("load",{path:project});settle();verify(!workspace.error,workspace.message);
            compare(workspace.curves[0][0][0],edited);compare(workspace.projectPath,project);
            // Inspect the exact production picker command without opening a native dialog.
            const saveAs=workspace.filePickerCommand("save_as");
            compare(saveAs[2],"--request");
            const saveSpec=JSON.parse(saveAs[3]);compare(saveSpec.mode,"save");compare(saveSpec.folder,window.fixtureRoot);
            compare(saveSpec.name,"qt-save-behavior.lenscap");compare(saveSpec.purpose,"project");
            compare(saveSpec.filters[0].patterns.join(","),"*.lenscap,*.lensproject");
            const openSpec=JSON.parse(workspace.filePickerCommand("load")[3]);compare(openSpec.mode,"open");compare(openSpec.purpose,"project");
            workspace.dirty=true;
            workspace.send("save",{path:window.fixtureRoot+"/missing-folder/failed.lenscap"});settle();
            verify(workspace.error);compare(workspace.projectPath,project);verify(workspace.dirty);
            workspace.send("open",{path:window.fixtureRoot+"/original.png"});settle();verify(!workspace.error,workspace.message);
            compare(workspace.projectPath,"");
            const firstSave=JSON.parse(workspace.filePickerCommand("save")[3]);compare(firstSave.mode,"save");compare(firstSave.name,"Untitled.lenscap");verify(!workspace.picking);
        }
        function test_recentProjectsKeepSaveContinuation() {
            const a=window.fixtureRoot+"/qt-recent-a.lenscap",b=window.fixtureRoot+"/qt-recent-b.lenscap";
            workspace.send("save",{path:b});settle();verify(!workspace.error,workspace.message);
            workspace.send("save",{path:a});settle();verify(!workspace.error,workspace.message);
            compare(workspace.recentProjects[0],a);verify(workspace.recentProjects.indexOf(b)>=0);
            workspace.selected=0;workspace.selectedPoint=0;
            const edited=workspace.curves[0][0][0]+.25;workspace.setCoordinate(0,String(edited));
            workspace.file("load",b);const dialog=child("discard");tryCompare(dialog,"opened",true);
            compare(workspace.pendingPath,b);verify(!workspace.picking);
            dialog.close();tryCompare(dialog,"visible",false);
            compare(workspace.projectPath,a);verify(workspace.dirty);compare(workspace.pendingPath,"");
            workspace.file("load",b);tryCompare(dialog,"opened",true);compare(workspace.pendingPath,b);
            dialog.saveRequested();
            tryCompare(workspace,"projectPath",b,20000);settle();verify(!workspace.error,workspace.message);
            compare(workspace.recentProjects[0],b);verify(!workspace.dirty);compare(workspace.pendingPath,"");
            workspace.file("load",a);settle();verify(!workspace.error,workspace.message);
            compare(workspace.curves[0][0][0],edited);compare(workspace.projectPath,a);verify(!workspace.picking);
        }
        function test_legacyConversionRequiresConfirmation() {
            const legacy=window.fixtureRoot+"/qt-legacy-conversion.lensproject",converted=window.fixtureRoot+"/qt-legacy-conversion.lenscap";
            annotationWriter.result=-1;
            annotationWriter.command=["/usr/bin/python","-c","import pathlib,shutil,sys;pathlib.Path(sys.argv[2]).unlink(missing_ok=True);shutil.copyfile(sys.argv[3],sys.argv[1])",legacy,converted,window.fixtureRoot+"/session.json"];
            annotationWriter.running=true;tryVerify(()=>annotationWriter.result!==-1,10000);compare(annotationWriter.result,0);
            const project=workspace.projectPath,curves=JSON.stringify(workspace.curves),image=workspace.original;
            workspace.file("load",legacy);
            const dialog=child("legacyConversion");tryCompare(dialog,"opened",true);
            compare(dialog.title,"Convert file?");verify(dialog.message.indexOf(".lensproject")>=0);verify(dialog.message.indexOf(".lenscap")>=0);verify(dialog.modal);
            verify(!workspace.busy);compare(workspace.projectPath,project);compare(JSON.stringify(workspace.curves),curves);compare(workspace.original,image);
            dialog.close();tryCompare(dialog,"visible",false);compare(workspace.pendingLegacyPath,"");
            annotationWriter.result=-1;
            annotationWriter.command=["/usr/bin/python","-c","import pathlib,sys;assert pathlib.Path(sys.argv[1]).is_file();assert not pathlib.Path(sys.argv[2]).exists()",legacy,converted];
            annotationWriter.running=true;tryVerify(()=>annotationWriter.result!==-1,10000);compare(annotationWriter.result,0);
            // The common worker entry point also intercepts direct startup/IPC loads.
            workspace.send("load",{path:legacy});tryCompare(dialog,"opened",true);verify(!workspace.busy);
            workspace.confirmLegacyConversion();
            tryCompare(workspace,"projectPath",converted,20000);settle();verify(!workspace.error,workspace.message);verify(workspace.hasImage);
            compare(workspace.recentProjects[0],converted);verify(workspace.recentProjects.indexOf(legacy)<0);
            annotationWriter.result=-1;
            annotationWriter.command=["/usr/bin/python","-c","import pathlib,sys;assert not pathlib.Path(sys.argv[1]).exists();assert pathlib.Path(sys.argv[2]).is_file()",legacy,converted];
            annotationWriter.running=true;tryVerify(()=>annotationWriter.result!==-1,10000);compare(annotationWriter.result,0);
        }
    }
}
