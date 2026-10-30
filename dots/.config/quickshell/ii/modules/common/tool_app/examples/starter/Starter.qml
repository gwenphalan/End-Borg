//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.modules.common.tool_app
import qs.modules.common.widgets

ShellRoot {
    id:root
    property var appState:({hasDocument:false,canUndo:false,canRedo:false,mode:"draw",hasSelection:false,busy:false,dirty:false})
    property var projectSettings:({})
    property var profiles:[]
    property string selectedProfile:""
    property var profileDialog:null
    property string profileDialogOperation:""
    function patchState(patch) {appState=Object.assign({},appState,patch);}
    function profileRequest(operation,payload) {
        if(!app.backend("worker")) return false;
        return app.backend("worker").request(operation,payload);
    }
    ToolDefinitionLoader {
        id:definition
        Component.onCompleted:load(Qt.resolvedUrl("app.yaml"))
        onFailed:message=>console.error(message)
    }
    ToolAppWindow {
        id:window
        visible:definition.ready
        appTitle:definition.definition.app ? definition.definition.app.name : "Tool Starter"
        ToolConfiguredApp {
            id:app
            anchors.fill:parent
            definition:definition.definition
            state:Object.assign({},root.appState,{busy:app.backend("worker") ? app.backend("worker").busy : false})
            settingsValues:root.projectSettings
            shortcutsEnabled:!app.settingsDialog.opened && !footer.zoomFocused
            handlers:({
                openSettings:()=>{app.settingsDialog.editorContext=profileContext;app.openSettings();root.profileRequest("profiles.list",{});},
                openDocument:()=>notification.show("Connect openDocument to your picker and document loader",false),
                saveDocument:()=>notification.show("Connect saveDocument to your document controller",false),
                drawTool:()=>root.patchState({mode:"draw"}),
                editTool:()=>root.patchState({mode:"edit"}),
                resetView:()=>console.log("Reset the domain viewport here"),
                confirmSelection:()=>root.patchState({hasSelection:false}),
                undo:()=>console.log("Call the domain undo stack here"),
                redo:()=>console.log("Call the domain redo stack here")
            })
            onSettingsSubmitted:values=>{
                // Keep the modal open until the worker acknowledges the submitted draft.
                root.profileRequest("settings.apply",{values:values});
            }
            onBackendCompleted:(backend,operation,result)=>{
                if(result.profiles) root.profiles=result.profiles;
                if(operation==="profiles.read") {app.settingsDialog.store.begin(result.payload);}
                if(operation==="settings.apply") {root.projectSettings=result.values;app.settingsDialog.complete(true,"");}
                if(root.profileDialog && operation===root.profileDialogOperation) {root.profileDialog.complete(true,"");root.profileDialog=null;root.profileDialogOperation="";}
                if(operation==="profiles.save") root.selectedProfile=result.profile.id;
                if(operation==="profiles.delete") root.selectedProfile="";
            }
            onBackendFailed:(backend,operation,message)=>{
                if(operation==="settings.apply") app.settingsDialog.complete(false,message);
                if(root.profileDialog && operation===root.profileDialogOperation) {root.profileDialog.complete(false,message);root.profileDialog=null;root.profileDialogOperation="";}
                feedback.report(operation,message,true);
            }
            onActionFailed:(action,message)=>feedback.report(action,message,true)
            canvasContent:Item {anchors.fill:parent /* Supply your canvas here. */}
            status:ToolCanvasFooter {
                id:footer
                zoomPercent:100
                atReset:true
                hints:[{keys:["LMB"],action:"Domain tool action"}]
                onZoomEdited:percent=>console.log("Set viewport zoom",percent)
            }
        }
        ToolOperationFeedback {id:feedback;onToastRequested:(message,failed)=>notification.show(message,failed)}
        ToolToast {id:notification}
    }
    property var profileContext:({
        profiles:root.profiles,selectedProfile:root.selectedProfile,
        profileBusy:app.backend("worker") ? app.backend("worker").busy : false,
        selectProfile:id=>{root.selectedProfile=id;if(id) root.profileRequest("profiles.read",{id:id});},
        saveProfile:(name,values,dialog)=>{root.profileDialog=dialog;root.profileDialogOperation="profiles.save";root.profileRequest("profiles.save",{name:name,values:values});},
        renameProfile:(id,name,dialog)=>{root.profileDialog=dialog;root.profileDialogOperation="profiles.rename";root.profileRequest("profiles.rename",{id:id,name:name});},
        updateProfile:(id,values)=>root.profileRequest("profiles.update",{id:id,values:values}),
        deleteProfile:id=>root.profileRequest("profiles.delete",{id:id})
    })
}
