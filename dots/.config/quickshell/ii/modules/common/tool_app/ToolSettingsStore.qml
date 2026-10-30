import QtQml
import "ToolDefinition.js" as Definition

QtObject {
    id:root
    property var definition:({})
    property var committed:({})
    property var draft:({})
    property var errors:({})
    property int revision:0
    readonly property bool dirty:JSON.stringify(committed)!==JSON.stringify(draft)
    readonly property bool valid:Object.keys(errors).length===0
    readonly property var fields:Definition.fields(definition)
    signal resetRequested()
    signal applyRequested(var values)
    function begin(values) {
        const next=Object.assign({},(definition.settings || {}).defaults || {},Definition.copy(values || {}));
        committed=Definition.copy(next);draft=Definition.copy(next);errors={};revision++;resetRequested();
    }
    function get(path) {const observed=revision;return draft[path];}
    function write(path,value) {
        if(!Object.prototype.hasOwnProperty.call(fields,path) || fields[path].readOnly) return false;
        const error=Definition.validateSetting(fields[path],value),nextErrors=Object.assign({},errors);
        if(error) nextErrors[path]=error;else delete nextErrors[path];
        errors=nextErrors;
        if(error) return false;
        const next=Definition.copy(draft);next[path]=value;draft=next;revision++;return true;
    }
    function invalid(path,message) {
        const next=Object.assign({},errors);if(message) next[path]=message;else delete next[path];errors=next;
    }
    function apply() {
        const remaining=Object.assign({},errors);delete remaining._application;errors=remaining;
        const next={};
        for(const path of Object.keys(fields)) {
            if(fields[path].readOnly) continue;
            const error=Definition.validateSetting(fields[path],draft[path]);if(error) next[path]=error;
        }
        errors=Object.assign({},errors,next);
        if(!valid) return false;
        applyRequested(Definition.copy(draft));return true;
    }
    // Only the host acknowledges successful persistence; Apply alone never commits.
    function commit(values) {begin(values || draft);}
    function discard() {draft=Definition.copy(committed);errors={};revision++;resetRequested();}
}
