import QtQml

// Success is a notification, never an implicit document commit. The host still
// calls ToolDocumentController.saved/opened only after its I/O acknowledgement.
QtObject {
    id:root
    property var silentSuccessOperations:["save","save_as"]
    signal toastRequested(string message,bool failed)
    function report(operation,message,failed) {
        if(!message || (!failed && silentSuccessOperations.includes(operation))) return false;
        toastRequested(String(message),!!failed);return true;
    }
}
