import QtQml
import Quickshell.Io

QtObject {
    id:root
    property var command:[]
    property bool busy:false
    property int timeoutMs:30000
    property double serial:0
    property double pendingId:0
    property string pendingOperation:""
    property string pendingLine:""
    property bool processStarted:false
    property bool launchPending:false
    property bool stopping:false
    readonly property bool running:worker.running
    signal completed(string operation,var result)
    signal failed(string operation,string message)
    signal eventReceived(var event)
    function request(operation,payload) {
        if(busy || stopping || !command.length) {failed(operation,busy ? "Backend is busy" : stopping ? "Backend is stopping" : "Backend command is empty");return false;}
        let line;
        const id=serial+1;
        try {line=JSON.stringify({id:id,op:operation,payload:payload || {}})+"\n";}
        catch(error) {failed(operation,"Cannot encode backend request: "+String(error));return false;}
        serial=id;pendingId=id;pendingOperation=operation;pendingLine=line;busy=true;
        if(worker.running && processStarted) flush();
        else if(!worker.running) {launchPending=true;worker.running=true;}
        return true;
    }
    function flush() {if(pendingLine && worker.running && processStarted) {worker.write(pendingLine);pendingLine="";}}
    function failPending(message) {
        const op=pendingOperation,wasBusy=busy;
        pendingLine="";pendingId=0;pendingOperation="";busy=false;
        if(wasBusy) failed(op,message);
    }
    function stop() {
        if(worker.running) stopping=true;
        failPending("Backend stopped");
        if(worker.running) worker.signal(15);
    }
    function protocolFailure(message) {
        if(worker.running) stopping=true;
        failPending(message);
        if(worker.running) worker.signal(15);
    }
    property Timer requestTimer:Timer {
        interval:Math.max(1,root.timeoutMs)
        running:root.busy && root.timeoutMs>0
        onTriggered:root.protocolFailure("Backend request timed out")
    }
    property Process process:Process {
        id:worker
        command:root.command
        stdinEnabled:true
        onStarted:{root.launchPending=false;root.processStarted=true;root.flush();}
        onRunningChanged:if(!running && root.launchPending) Qt.callLater(()=>{
            if(!worker.running && root.launchPending) {root.launchPending=false;root.processStarted=false;root.stopping=false;root.failPending("Backend could not start");}
        })
        stdout:SplitParser {
            onRead:line=>{
                let result;
                try {result=JSON.parse(line);if(!result || typeof result!=="object" || Array.isArray(result)) throw new Error("Expected an object");}
                catch(error) {root.protocolFailure("Backend returned malformed JSON");return;}
                if(!root.busy || result.id!==root.pendingId) {if(!root.stopping) root.eventReceived(result);return;}
                const op=root.pendingOperation;
                root.pendingLine="";root.pendingOperation="";root.pendingId=0;root.busy=false;
                if(result.ok===true) root.completed(op,result.result);
                else root.failed(op,String(result.error || "Backend operation failed"));
            }
        }
        stderr:StdioCollector {onStreamFinished:if(text) console.warn("Tool backend:",text)}
        onExited:(code,status)=>{
            root.launchPending=false;root.processStarted=false;root.stopping=false;
            root.failPending("Backend stopped ("+code+")");
        }
    }
}
