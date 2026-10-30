import QtQuick
import QtQuick.Controls
import qs.modules.common.widgets

ToolSettingsDialog {
    id:root
    required property var definition
    required property var controller
    property var values:({})
    property var editorContext:({})
    property bool applying:false
    enabled:!applying
    closePolicy:applying ? Popup.NoAutoClose : Popup.CloseOnEscape
    readonly property alias store:settingsStore
    signal submitRequested(var values)
    title:(definition.settings || {}).title || "Project settings"
    height:Math.min(parent ? parent.height-48 : 660,660,form.implicitHeight+132)
    errorMessage:Object.values(settingsStore.errors).join("\n")
    onAboutToShow:settingsStore.begin(values)
    onClosed:if(!applying) settingsStore.discard()
    onApplyRequested:if(!applying) settingsStore.apply()
    function complete(success,message) {
        applying=false;
        if(success) {settingsStore.commit();close();}
        else settingsStore.invalid("_application",message || "Could not apply settings");
    }
    ToolSettingsStore {
        id:settingsStore
        definition:root.definition
        onApplyRequested:values=>{root.applying=true;root.submitRequested(values);}
    }
    contentItem:StyledFlickable {
        clip:true
        contentHeight:form.implicitHeight
        enabled:!root.applying
        ToolSettingsForm {
            id:form
            width:parent.width
            definition:root.definition
            valueStore:settingsStore
            controller:root.controller
            editorContext:root.editorContext
        }
    }
}
