import QtQml
import "ToolDefinition.js" as Definition

QtObject {
    id:root
    property var definition:({})
    property var state:({})
    property var handlers:({})
    property var settingsValues:({})
    property bool enabled:true
    property bool shortcutsEnabled:true
    readonly property var effectiveState:{
        const merged=Object.assign({},definition.state || {},state);
        for(const path of Object.keys(settingsValues)) merged["settings."+path]=settingsValues[path];
        return merged;
    }
    signal backendRequested(string backend,string operation,var arguments)
    signal invoked(string action,var arguments)
    signal failed(string action,string message)
    function visibleFor(id,conditionState) {
        const item=Definition.action(definition,id);
        return !!item && Definition.evaluate(item.visibleWhen,conditionState || effectiveState);
    }
    function enabledFor(id,conditionState) {
        const item=Definition.action(definition,id);
        return enabled && visibleFor(id,conditionState) && Definition.evaluate(item.enabledWhen,conditionState || effectiveState);
    }
    function checkedFor(id,conditionState) {
        const item=Definition.action(definition,id);
        return !!item && Definition.evaluate(item.checkedWhen,conditionState || effectiveState);
    }
    function dirtyFor(id,conditionState) {
        const item=Definition.action(definition,id);
        return !!item && Definition.evaluate(item.dirtyWhen,conditionState || effectiveState);
    }
    function invoke(id,argumentsOverride,conditionState) {
        if(!enabledFor(id,conditionState)) return false;
        const item=Definition.action(definition,id);
        const payload=Object.assign({},item.arguments || {},argumentsOverride || {});
        try {
            if(item.target.kind==="qml") {
                const callback=handlers[item.target.handler];
                if(typeof callback!=="function") throw new Error("Unregistered QML handler: "+item.target.handler);
                if(callback(payload)===false) return false;
            } else backendRequested(item.target.backend,item.target.operation,payload);
            invoked(id,payload);return true;
        } catch(error) {failed(id,String(error));return false;}
    }
    function invokeShortcut(id) {return shortcutsEnabled && invoke(id);}
}
