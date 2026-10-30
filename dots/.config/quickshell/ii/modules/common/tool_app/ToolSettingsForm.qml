import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets
import qs.modules.settings.desktop as Settings
import "ToolDefinition.js" as Definition

ColumnLayout {
    id:root
    required property var definition
    required property var valueStore
    required property var controller
    property var editorContext:({})
    readonly property var conditionState:{
        const observed=valueStore.revision;
        const state=Object.assign({},controller.effectiveState);
        for(const path of Object.keys(Definition.fields(definition))) state["settings."+path]=valueStore.get(path);
        return state;
    }
    spacing:16
    function rows(group) {
        const state=conditionState;
        return group.items.filter(item=>item.kind!=="component" && Definition.evaluate(item.visibleWhen,state)).map(item=>{
            if(item.kind==="field") return {kind:"preference",setting:Object.assign({step:item.setting.type==="real" ? .1 : 1},item.setting,{enabled:Definition.evaluate(item.enabledWhen,state)})};
            const action=definition.actions[item.action];
            return {kind:"action",title:action.label,icon:action.icon,action:item.action,available:controller.visibleFor(item.action,state),enabled:controller.enabledFor(item.action,state) && Definition.evaluate(item.enabledWhen,state)};
        });
    }
    Repeater {
        model:(root.definition.settings || {}).groups || []
        ContentSection {
            id:section
            required property var modelData
            title:modelData.title
            icon:modelData.icon
            visible:Definition.evaluate(modelData.visibleWhen,root.conditionState)
            Settings.SettingsGroup {
                valueStore:root.valueStore
                showReset:false
                section:({title:"",items:root.rows(section.modelData)})
                onActionRequested:action=>root.controller.invoke(action,undefined,root.conditionState)
            }
            Repeater {
                model:section.modelData.items.filter(item=>item.kind==="component")
                Loader {
                    required property var modelData
                    Layout.fillWidth:true
                    active:Definition.evaluate(modelData.visibleWhen,root.conditionState)
                    visible:active
                    enabled:Definition.evaluate(modelData.enabledWhen,root.conditionState)
                    source:root.definition.components[modelData.component]
                    onLoaded:{
                        if("settingsStore" in item) item.settingsStore=Qt.binding(()=>root.valueStore);
                        if("actionController" in item) item.actionController=Qt.binding(()=>root.controller);
                        if("editorContext" in item) item.editorContext=Qt.binding(()=>root.editorContext);
                    }
                }
            }
        }
    }
}
