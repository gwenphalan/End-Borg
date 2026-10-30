import QtQml

QtObject {
    id: root
    property string documentPath: ""
    property bool dirty: false
    property bool available: true
    property bool hasDocument: false
    property bool busy: false
    property bool picking: false
    property var recentFiles: []
    property string newAction: "open"
    property string openAction: "load"
    property string saveAction: "save"
    property string saveAsAction: "save_as"
    property string pendingAction: ""
    property string pendingPath: ""
    property bool resumeAfterSave: false
    property bool discardConfirmed: false

    signal pickerRequested(string action)
    signal operationRequested(string operation, string path)
    signal discardConfirmationRequested()
    signal closeRequested()
    signal errorOccurred(string message)

    function cancelContinuation() {
        pendingAction=""; pendingPath=""; resumeAfterSave=false; discardConfirmed=false;
    }
    function request(action, path) {
        if(!available || busy || picking) return false;
        if((action===saveAction || action===saveAsAction) && !hasDocument) return false;
        if(action===saveAction && documentPath) {
            operationRequested(saveAction, documentPath);
            return true;
        }
        if((action===newAction || action===openAction) && dirty && !discardConfirmed) {
            pendingAction=action; pendingPath=path || "";
            discardConfirmationRequested();
            return true;
        }
        discardConfirmed=false;
        if(action===openAction && path) operationRequested(openAction, path);
        else pickerRequested(action);
        return true;
    }
    function requestClose() {
        if(!available || busy || picking) {
            errorOccurred("Finish the current operation first.");
            return false;
        }
        if(!dirty || discardConfirmed) return true;
        pendingAction="close"; pendingPath="";
        discardConfirmationRequested();
        return false;
    }
    function discardAndContinue() {
        const next=pendingAction, path=pendingPath;
        pendingAction="";pendingPath="";resumeAfterSave=false;discardConfirmed=true;
        if(next==="close") closeRequested();
        else if(next) request(next,path);
    }
    function saveAndContinue() {
        resumeAfterSave=true;
        if(!request(saveAction)) {resumeAfterSave=false;return false;}
        return true;
    }
    function saved(path) {
        if(path) documentPath=path;
        dirty=false;
        const next=resumeAfterSave ? pendingAction : "", nextPath=pendingPath;
        cancelContinuation();
        if(next) Qt.callLater(() => {
            if(next==="close") closeRequested();
            else request(next,nextPath);
        });
    }
    function opened(path) {
        documentPath=path || "";dirty=false;cancelContinuation();
    }
    function failed() {cancelContinuation();}
    function pickerCancelled() {cancelContinuation();}
}
