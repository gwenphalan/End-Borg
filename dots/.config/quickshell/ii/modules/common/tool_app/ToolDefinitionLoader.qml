import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id:root
    visible:false
    property string source:""
    property string pythonExecutable:"/usr/bin/python"
    property var definition:({})
    property string errorMessage:""
    readonly property bool loading:compiler.running
    readonly property bool ready:!!definition.version && !loading && !errorMessage
    signal loaded(var definition)
    signal failed(string message)
    function load(path) {
        if(compiler.running) {failed("Definition load already in progress");return false;}
        errorMessage="";compiler.output="";compiler.errors="";
        const input=String(path===undefined ? source : path);
        if(!input.trim()) {errorMessage="Definition path is empty";failed(errorMessage);return false;}
        const filename=input.startsWith("file://") ? decodeURIComponent(input.slice(7)) : input;
        source=filename;compiler.launchPending=true;
        compiler.command=[pythonExecutable,Quickshell.shellPath("scripts/tool_app/definition.py"),filename];
        compiler.running=true;return true;
    }
    // Explicit load only: importing the library or changing a file never runs a process.
    Process {
        id:compiler
        property string output:""
        property string errors:""
        property bool launchPending:false
        onStarted:launchPending=false
        onRunningChanged:if(!running && launchPending) Qt.callLater(()=>{
            if(!running && launchPending) {launchPending=false;root.errorMessage="Definition compiler could not start";root.failed(root.errorMessage);}
        })
        stdout:StdioCollector {onStreamFinished:compiler.output=text}
        stderr:StdioCollector {onStreamFinished:compiler.errors=text}
        onExited:(code,status)=>{
            launchPending=false;
            if(code!==0) {root.errorMessage=errors.trim() || "Definition compilation failed";root.failed(root.errorMessage);return;}
            try {
                const result=JSON.parse(output);
                if(result.version!==1) throw new Error("Unsupported definition version");
                root.definition=result;root.loaded(result);
            } catch(error) {root.errorMessage=String(error);root.failed(root.errorMessage);}
        }
    }
}
