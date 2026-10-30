//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtTest
import qs.modules.common.widgets
import qs.modules.common.tool_app

AppWindow {
    id: window
    appTitle: "Tool app component tests"
    width: 480;height: 320
    property var events: []
    property int zoomEdits:0
    ToolZoomControl {id:zoom;anchors.centerIn:parent;percent:79.812345;onZoomEdited:value=>{window.zoomEdits++;percent=value;}}
    Item {id:focusSink;focus:true}
    ToolDocumentController {
        id: document
        onPickerRequested:action=>window.events.push(["picker",action])
        onOperationRequested:(op,path)=>window.events.push([op,path])
        onDiscardConfirmationRequested:window.events.push(["confirm"])
        onCloseRequested:window.events.push(["close"])
    }
    ToolFileType {id:fileType;extension:".lenscap";legacyExtensions:[".lensproject"]}
    TestCase {
        name:"ToolAppComponents"
        when:window.visible
        function init() {document.cancelContinuation();document.documentPath="/tmp/a.lenscap";document.hasDocument=true;document.dirty=false;document.available=true;document.busy=false;document.picking=false;window.events=[];}
        function test_unchangedNumberFocusDoesNotRound() {
            const spin=findChild(zoom,"zoomPercentInput"),input=spin.contentItem.children[0];
            zoom.percent=79.812345;window.zoomEdits=0;
            spin.commit();compare(window.zoomEdits,0);compare(zoom.percent,79.812345);
            input.forceActiveFocus();tryCompare(input,"activeFocus",true);focusSink.forceActiveFocus();tryCompare(input,"activeFocus",false);
            compare(window.zoomEdits,0);compare(zoom.percent,79.812345);
            input.text="125%";spin.commit();compare(window.zoomEdits,1);compare(zoom.percent,125);
            input.text="";spin.commit();verify(spin.invalid);compare(window.zoomEdits,1);
        }
        function test_saveAndSaveAs() {
            document.request("save");compare(JSON.stringify(window.events),JSON.stringify([["save","/tmp/a.lenscap"]]));
            document.request("save_as");compare(window.events[1][0],"picker");compare(window.events[1][1],"save_as");
            document.documentPath="";document.request("save");compare(window.events[2][0],"picker");
        }
        function test_saveBeforeOpen() {
            document.dirty=true;document.request("load","/tmp/b.lenscap");compare(window.events[0][0],"confirm");
            document.saveAndContinue();compare(window.events[1][0],"save");verify(document.dirty);
            document.saved("/tmp/a.lenscap");tryCompare(window.events,"length",3);compare(window.events[2][0],"load");compare(window.events[2][1],"/tmp/b.lenscap");
            verify(!document.dirty);compare(document.pendingPath,"");
        }
        function test_cancelAndFailureKeepDocument() {
            document.dirty=true;document.request("load","/tmp/b.lenscap");document.cancelContinuation();
            compare(document.pendingAction,"");verify(document.dirty);compare(document.documentPath,"/tmp/a.lenscap");
            document.request("load","/tmp/b.lenscap");document.saveAndContinue();document.failed();
            verify(document.dirty);compare(document.pendingAction,"");verify(!document.resumeAfterSave);
        }
        function test_discardAndClose() {
            document.dirty=true;document.request("load","/tmp/b.lenscap");document.discardAndContinue();
            compare(window.events[1][0],"load");verify(document.dirty);
            document.cancelContinuation();verify(!document.requestClose());document.discardAndContinue();compare(window.events[3][0],"close");
        }
        function test_busyAndType() {
            document.busy=true;verify(!document.request("save"));compare(window.events.length,0);
            verify(!document.saveAndContinue());verify(!document.resumeAfterSave);
            verify(fileType.accepts("ROOM.LENSCAP"));verify(fileType.isLegacy("a.lensproject"));verify(!fileType.accepts("a.png"));
            compare(fileType.normalize("a.lensproject"),"a.lenscap");compare(fileType.normalize("a"),"a.lenscap");
        }
        onCompletedChanged:if(completed) console.log("TOOL APP TOTAL",JSON.stringify({passed:qtest_results.passCount,failed:qtest_results.failCount}));
    }
}
