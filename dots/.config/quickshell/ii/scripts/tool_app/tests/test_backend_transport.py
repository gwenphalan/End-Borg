"""Run the real Quickshell Process transport using only nonvisual QtObjects."""
from pathlib import Path
import json
import os
import shutil
import subprocess

import pytest

ROOT=Path(__file__).resolve().parents[3]


def test_backend_serial_busy_start_failure_malformed_timeout_and_retry(tmp_path):
    executable=shutil.which('qs')
    if not executable:pytest.skip('Quickshell executable unavailable')
    backend=tmp_path/'backend.py'
    backend.write_text('''import json,sys,time
for line in sys.stdin:
    request=json.loads(line)
    if request['op']=='malformed': print('broken JSON',flush=True);continue
    if request['op']=='stall': time.sleep(10);continue
    print(json.dumps({'event':'progress'}),flush=True)
    print(json.dumps({'id':request['id'],'ok':True,'result':request['payload']}),flush=True)
''')
    source='''import QtQml
import Quickshell
ShellRoot {
    id:root
    property var transport:null
    property int stage:0
    property int events:0
    property int failures:0
    property var command:COMMAND
    function check(value,message) {if(!value) {console.error("TRANSPORT CHECK FAILED",message);failures++;}}
    function request(op) {check(transport.request(op,{answer:42}),"Request accepted: "+op);}
    Component.onCompleted:{Quickshell.watchFiles=false;Qt.callLater(start);}
    function start() {
        const component=Qt.createComponent(COMPONENT,Component.PreferSynchronous);
        check(component.status===Component.Ready,component.errorString());
        if(component.status!==Component.Ready) {Qt.callLater(Qt.quit);return;}
        transport=component.createObject(root);
        check(transport!==null,"QtObject transport constructed");
        transport.command=command;transport.timeoutMs=2000;
        transport.eventReceived.connect(()=>events++);
        transport.completed.connect((op,result)=>{
            check(result.answer===42,"Serial payload matched");check(!transport.busy && transport.pendingId===0,"Reply clears pending state");
            if(op==="initial") {stage=1;transport.stop();}
            else if(op==="retry") {stage=4;transport.stop();}
            else if(op==="final") {check(events===3,"Progress frames remain events");transport.stop();console.log("TRANSPORT RESULT",failures);Qt.callLater(Qt.quit);}
        });
        transport.failed.connect((op,message)=>{
            if(op==="concurrent") {check(message.indexOf("busy")>=0,"Concurrent request rejected");return;}
            if(op==="whileStopping") {check(message.indexOf("stopping")>=0,"Reentrant retry waits for old process exit");return;}
            check(!transport.busy && transport.pendingId===0 && transport.pendingLine==="","Failure clears pending request");
            if(op==="missing") {check(message.indexOf("start")>=0,"Failed start reported");stage=3;}
            else if(op==="malformed") {check(message.indexOf("malformed")>=0,"Malformed JSON reported");check(!transport.request("whileStopping",{}),"Reentrant retry rejected safely");stage=6;}
            else if(op==="stall") {check(message.indexOf("timed out")>=0,"Timeout reported");stage=8;}
            else {check(false,"Unexpected failure: "+op+" "+message);console.log("TRANSPORT RESULT",failures);Qt.callLater(Qt.quit);}
        });
        request("initial");check(!transport.request("concurrent",{}),"Second request refuses while busy");
    }
    property Timer advance:Timer {
        interval:10;repeat:true;running:true
        onTriggered:{
            if(!root.transport || root.transport.running || root.transport.stopping) return;
            if(root.stage===1) {root.stage=2;root.transport.command=["/nonexistent-tool-app-backend"];root.request("missing");}
            else if(root.stage===3) {root.stage=0;root.transport.command=root.command;root.request("retry");}
            else if(root.stage===4) {root.stage=5;root.request("malformed");}
            else if(root.stage===6) {root.stage=7;root.transport.timeoutMs=30;root.request("stall");}
            else if(root.stage===8) {root.stage=9;root.transport.timeoutMs=2000;root.request("final");}
        }
    }
}
'''.replace('COMMAND',json.dumps(['/usr/bin/python','-u',str(backend)]))
    source=source.replace('COMPONENT',json.dumps((ROOT/'modules/common/tool_app/ToolBackendProcess.qml').as_uri()))
    shell=tmp_path/'shell.qml';shell.write_text(source)
    runtime=tmp_path/'runtime';runtime.mkdir(mode=0o700)
    env=dict(os.environ,QT_QPA_PLATFORM='offscreen',XDG_RUNTIME_DIR=str(runtime),
             DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent',QS_NO_RELOAD_POPUP='1')
    result=subprocess.run([executable,'-p',str(shell),'--no-color'],env=env,capture_output=True,text=True,timeout=12)
    output=result.stdout+result.stderr
    assert result.returncode==0,output
    assert 'TRANSPORT RESULT 0' in output,output
