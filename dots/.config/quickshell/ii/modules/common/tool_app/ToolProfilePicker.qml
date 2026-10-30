import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets
import qs.modules.settings.desktop as Settings

ColumnLayout {
    id:root
    property var profiles:[] // [{id, name}], opaque IDs; no filesystem policy in QML.
    property string selectedId:""
    property string label:"Profile"
    property bool busy:false
    property bool canSave:true
    property bool canUpdate:canSave
    readonly property var selectedProfile:profiles.find(profile=>profile.id===selectedId) || null
    signal selectionRequested(string id)
    signal saveRequested(string name)
    signal renameRequested(string id,string name)
    signal updateRequested(string id)
    signal deleteRequested(string id)
    function complete(success,message) {nameDialog.message=success ? "" : (message || "Could not save profile");if(success) nameDialog.close();}
    // Profile IDs are strings; the numeric action value cannot select a profile.
    readonly property int saveActionValue:-1
    function requestSave() {
        if (busy || !canSave) return;
        nameDialog.renaming=false;
        nameDialog.targetId="";
        nameDialog.text="";
        nameDialog.message="";
        nameDialog.open();
    }
    spacing:8
    RowLayout {
        Layout.fillWidth:true
        spacing:8
        Settings.SettingsPresetDropdown {
            Layout.fillWidth:true
            label:root.label
            choices:[{name:"None",value:""}].concat(root.profiles.map(profile=>({name:profile.name,value:profile.id}))).concat(root.canSave ? [{name:"Save Profile…",value:root.saveActionValue}] : [])
            value:root.selectedId
            enabled:!root.busy
            onChosen:value=>value === root.saveActionValue ? root.requestSave() : root.selectionRequested(value)
        }
        IconToolbarButton {
            implicitWidth:36;implicitHeight:36;Layout.fillHeight:false
            text:"edit";Accessible.name:"Rename profile"
            enabled:!!root.selectedProfile && !root.busy;opacity:enabled ? 1 : .4
            onClicked:{nameDialog.renaming=true;nameDialog.targetId=root.selectedId;nameDialog.text=root.selectedProfile.name;nameDialog.message="";nameDialog.open();}
            StyledToolTip {text:parent.Accessible.name}
        }
        IconToolbarButton {
            implicitWidth:36;implicitHeight:36;Layout.fillHeight:false
            text:"sync";Accessible.name:"Update profile"
            enabled:!!root.selectedProfile && root.canUpdate && !root.busy;opacity:enabled ? 1 : .4
            onClicked:root.updateRequested(root.selectedId)
            StyledToolTip {text:parent.Accessible.name}
        }
        IconToolbarButton {
            implicitWidth:36;implicitHeight:36;Layout.fillHeight:false
            text:"delete";Accessible.name:"Delete profile"
            enabled:!!root.selectedProfile && !root.busy;opacity:enabled ? 1 : .4
            onClicked:root.deleteRequested(root.selectedId)
            StyledToolTip {text:parent.Accessible.name}
        }
    }
    ToolTextInputDialog {
        id:nameDialog
        property bool renaming:false
        property string targetId:""
        title:renaming ? "Rename profile" : "Name profile"
        confirmText:renaming ? "Rename" : "Save"
        placeholderText:"Profile name"
        confirmEnabled:text.trim().length>0 && !root.busy
        onConfirmed:renaming ? root.renameRequested(targetId,text.trim()) : root.saveRequested(text.trim())
    }
}
