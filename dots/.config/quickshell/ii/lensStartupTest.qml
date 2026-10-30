//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.tool_app
import qs.modules.lensCalibration

AppWindow {
    id: harness
    appTitle: "Lens startup regression"
    width: 640
    height: 480
    TestCase {
        id: tests
        name: "LensStartupRegression"
        when: harness.visible
        property var application: null
        property var workspace: null
        property var chooser: null
        function initTestCase() {
            const component=Qt.createComponent("lensCalibration.qml");
            console.log("STARTUP component",component.status,component.errorString());
            tryCompare(component,"status",Component.Ready,20000);
            compare(component.status,Component.Ready,component.errorString());
            application=component.createObject(null);
            verify(application!==null,component.errorString());
            tryVerify(()=>application.appWindow!==null,20000);
            compare(Quickshell.watchFiles,false,"Standalone Lens Cap must not rebuild when desktop configuration changes");
            workspace=findChild(application.appWindow,"lensWorkspace");
            chooser=findChild(application.appWindow,"startupChooser");
            console.log("STARTUP children",workspace,chooser);
            verify(workspace!==null,"Real workspace must be discoverable");
            verify(chooser!==null,"Real startup chooser must be discoverable");
            tryCompare(workspace,"ready",true,20000);
        }
        function cleanupTestCase() {
            if(application) { workspace.dirty=false; application.destroy(); }
        }
        function test_startupCancelAndSuccessfulOpen() {
            console.log("STARTUP test begins");
            verify(!workspace.hasImage);
            tryCompare(chooser,"opened",true);
            verify(chooser.modal,"Startup chooser must overlay the actual canvas");
            workspace.picking=true;
            tryCompare(chooser,"visible",false);
            workspace.picking=false;
            tryCompare(chooser,"opened",true);
            // A genuine cancel returns to the chooser without starting work.
            verify(!workspace.busy);verify(!workspace.hasImage);
            workspace.picking=true;
            tryCompare(chooser,"visible",false);
            workspace.busy=true;
            workspace.picking=false;
            wait(50);compare(chooser.visible,false);
            // Reproduce busy falling before hasImage rises in one response turn.
            workspace.busy=false;
            workspace.original="file:///tmp/lens-real-verification/original.png";
            wait(50);compare(chooser.visible,false);
            workspace.original="";
            workspace.picking=true;
            workspace.send("open",{path:"/tmp/lens-real-verification/original.png"});
            workspace.picking=false;
            tryCompare(workspace,"busy",false,20000);
            verify(!workspace.error,workspace.message);
            verify(workspace.hasImage,"Actual worker must load the original camera image");
            tryCompare(chooser,"visible",false);
            wait(100);compare(chooser.visible,false);
            console.log("RECENT begin");
            const recentPath="/tmp/lens-real-verification/startup-recent.lenscap";
            workspace.send("save",{path:recentPath});tryCompare(workspace,"busy",false,20000);
            verify(!workspace.error,workspace.message);console.log("RECENT saved",workspace.projectPath,JSON.stringify(workspace.recentProjects));
            workspace.original="";workspace.dirty=false;
            tryCompare(chooser,"opened",true);
            tryVerify(()=>chooser.recentFiles.indexOf(recentPath)>=0);
            console.log("RECENT chooser",chooser.opened,JSON.stringify(chooser.recentFiles));
            const savedRecents=workspace.recentProjects.slice();
            workspace.recentProjects=Array.from({length:12},(_,i)=>recentPath);
            waitForPolish(application.appWindow);
            const container=findChild(chooser.contentItem,"startupRecentContainer");verify(container!==null);verify(container.radius>0);
            const list=findChild(chooser.contentItem,"startupRecentList");verify(list!==null);
            verify(list.contentHeight>list.height,"Recent projects must scroll instead of growing the modal");
            verify(findChild(chooser.contentItem,"startupRecentFile11")!==null,"All recent projects must be available");
            list.contentY=list.contentHeight-list.height;wait(250);verify(list.contentY>0);
            list.contentY=0;workspace.recentProjects=savedRecents;wait(250);
            const recent=findChild(chooser.contentItem,"startupRecentFile0");console.log("RECENT item",recent);verify(recent!==null);
            compare(recent.modelData,recentPath);
            waitForPolish(application.appWindow);wait(100);console.log("RECENT click",recent.width,recent.height,recent.enabled);
            mouseClick(recent,recent.width/2,recent.height/2);
            console.log("RECENT clicked",workspace.busy,workspace.message);
            tryCompare(workspace,"hasImage",true,20000);
            tryCompare(chooser,"visible",false);
            compare(workspace.projectPath,recentPath);
            console.log("LENS STARTUP PASS: cancel, busy handoff, response race, real image open");
        }
        onCompletedChanged: if(completed) {console.log("LENS STARTUP TOTAL",JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount,skipped:qtest_results.skipCount}));Qt.callLater(Qt.quit);}
    }
}
