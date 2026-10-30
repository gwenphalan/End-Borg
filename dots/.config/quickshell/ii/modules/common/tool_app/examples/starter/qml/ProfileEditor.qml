import QtQuick
import qs.modules.common.tool_app

ToolProfilePicker {
    id:root
    property var settingsStore:null
    property var actionController:null
    property var editorContext:({})
    profiles:editorContext.profiles || []
    selectedId:editorContext.selectedProfile || ""
    busy:!!editorContext.profileBusy
    onSelectionRequested:id=>editorContext.selectProfile(id)
    onSaveRequested:name=>editorContext.saveProfile(name,settingsStore.draft,root)
    onRenameRequested:(id,name)=>editorContext.renameProfile(id,name,root)
    onUpdateRequested:id=>editorContext.updateProfile(id,settingsStore.draft)
    onDeleteRequested:id=>editorContext.deleteProfile(id)
}
