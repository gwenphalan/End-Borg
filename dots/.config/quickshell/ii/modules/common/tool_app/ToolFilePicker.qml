import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false
    property string pythonExecutable: "/usr/bin/python"
    property string scriptPath: Quickshell.shellPath("scripts/tool_app/native_picker.py")
    readonly property bool running: process.running
    property var descriptor: ({})
    signal selected(string path, var paths)
    signal cancelled()
    signal failed(string message)
    function commandFor(spec) {
        return [pythonExecutable,scriptPath,"--request",JSON.stringify(spec)];
    }
    function open(spec) {
        if(process.running) return false;
        descriptor=spec;
        process.response="";
        process.command=commandFor(spec);
        process.running=true;
        return true;
    }
    Process {
        id: process
        property string response: ""
        stdout: StdioCollector {onStreamFinished:process.response=text}
        onExited: (exitCode,exitStatus) => {
            let result;
            try {result=JSON.parse(response);} catch(error) {root.failed("File chooser stopped unexpectedly.");return;}
            response="";
            if(!result.ok) root.failed(result.error || "Could not open file chooser.");
            else if(result.cancelled) root.cancelled();
            else if(result.path) root.selected(result.path,result.paths || [result.path]);
            else root.failed("File chooser returned no file.");
        }
    }
}
