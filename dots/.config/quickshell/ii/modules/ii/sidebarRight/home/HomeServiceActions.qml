pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "home_actions.js" as Actions
ColumnLayout {
    id:root
    required property var entity
    objectName:"homeServiceActions"
    readonly property string entityId:entity.entity_id
    onEntityIdChanged:{expanded=false;actionKey="";values=({});validationError="";}
    property bool expanded:false
    property string actionKey:""
    property var values:({})
    property string validationError:""
    readonly property var actions:Actions.actions(HomeAssistant.services,entity)
    readonly property var action:actions.find(a=>a.key===actionKey) || null
    readonly property var fields:Actions.fields(action?.schema)
    readonly property bool busy:!!HomeAssistant.busy[entity.entity_id]
    onActionKeyChanged:{ values=({});validationError=""; }
    function setValue(key,value) {values=Object.assign({},values,{[key]:value});validationError="";}
    spacing:12;visible:actions.length>0
    RippleButtonWithIcon {
        Layout.fillWidth:true;materialIcon:root.expanded ? "expand_less" : "tune";mainText:Translation.tr("More actions")
        onClicked:root.expanded=!root.expanded
    }
    ColumnLayout {
        visible:root.expanded;Layout.fillWidth:true;spacing:12
        StyledComboBox {
            Layout.fillWidth:true;buttonIcon:"touch_app";textRole:"name"
            model:[{name:Translation.tr("Choose an action"),key:""}].concat(root.actions)
            currentIndex:Math.max(0,root.actions.findIndex(a=>a.key===root.actionKey)+1)
            onActivated:index => root.actionKey=index ? root.actions[index-1].key : ""
        }
        StyledText { visible:!!root.action?.schema.description;Layout.fillWidth:true;text:root.action?.schema.description || "";textFormat:Text.PlainText;wrapMode:Text.Wrap;color:Appearance.colors.colSubtext;font.pixelSize:Appearance.font.pixelSize.small }
        Repeater {
            model:root.fields
            delegate:ColumnLayout {
                id:field
                required property var modelData
                readonly property var selector:modelData.selector || {}
                readonly property bool sensitive:/code|password|secret/i.test(modelData.key)
                readonly property bool boolField:selector.boolean!==undefined
                readonly property bool choiceField:!!selector.select && !selector.select.multiple && !selector.select.custom_value
                readonly property var choices:(selector.select?.options || []).map(v=>typeof v==="string" ? {label:v,value:v} : v)
                Layout.fillWidth:true;spacing:6
                StyledText { Layout.fillWidth:true;text:field.modelData.name+(field.modelData.required ? " *" : "");wrapMode:Text.Wrap;color:Appearance.colors.colSubtext;font.pixelSize:Appearance.font.pixelSize.small }
                StyledSwitch {
                    visible:field.boolField;Accessible.name:field.modelData.name
                    checked:!!root.values[field.modelData.key]
                    Component.onCompleted:if(field.boolField && field.modelData.required)root.setValue(field.modelData.key,false)
                    onClicked:root.setValue(field.modelData.key,checked)
                }
                StyledComboBox {
                    visible:field.choiceField;Layout.fillWidth:true;textRole:"label"
                    model:[{label:Translation.tr("Choose…"),value:undefined}].concat(field.choices)
                    currentIndex:0
                    onActivated:index => root.setValue(field.modelData.key,index ? field.choices[index-1].value : undefined)
                }
                MaterialTextField {
                    visible:field.sensitive;Layout.fillWidth:true
                    echoMode:TextInput.Password;placeholderText:field.modelData.name
                    Accessible.name:field.modelData.name
                    onTextChanged:root.setValue(field.modelData.key,text)
                    background:Rectangle {
                        implicitHeight:56;color:Appearance.m3colors.m3surface;radius:4
                        Rectangle { anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;height:1;color:Appearance.m3colors.m3outline }
                    }
                }
                MaterialTextArea {
                    visible:!field.boolField && !field.choiceField && !field.sensitive;Layout.fillWidth:true
                    placeholderText:field.selector.number ? [field.selector.number.min ?? "",field.selector.number.max ?? ""].join(" – ") : field.selector.object!==undefined || field.selector.color_rgb!==undefined || field.selector.color_hs!==undefined || field.selector.select?.multiple ? Translation.tr("JSON value") : field.modelData.name
                    Accessible.name:field.modelData.name
                    onTextChanged:root.setValue(field.modelData.key,text)
                }
            }
        }
        StyledText { Layout.fillWidth:true;visible:!!root.validationError;text:root.validationError;wrapMode:Text.Wrap;color:Appearance.colors.colError }
        RippleButtonWithIcon {
            Layout.fillWidth:true;visible:root.action!==null;enabled:HomeAssistant.available(root.entity) && !root.busy
            materialIcon:"play_arrow";mainText:root.busy ? Translation.tr("Running…") : root.action?.name || Translation.tr("Run action")
            onClicked: {
                try { const data=Actions.payload(root.fields,root.values);root.validationError="";HomeAssistant.callService(root.entity,root.actionKey,data); }
                catch(error) {root.validationError=String(error.message || error);}
            }
        }
    }
}
