pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "../../ii/overview/LauncherLabels.js" as LauncherLabels

ColumnLayout {
    id:root
    Connections { target:SettingsCatalog; function onSaved() { if (SettingsCatalog.drafts[root.setting.path]===undefined) root.sync(); } function onDiscarded() { root.sync(); } }
    required property var setting
    required property var currentValue
    readonly property bool applicationList:["dock.pinnedApps","launcher.pinnedApps","launcher.hiddenApps"].includes(setting.path)
    readonly property bool displayList:setting.path==="bar.screenList"
    readonly property var availableApplications:AppSearch.list.filter(a => !draft.includes(a.id)).map(a => ({id:a.id,name:a.name,icon:a.icon || "",value:a.id})).sort((a,b) => a.name.localeCompare(b.name))
    readonly property var availableDisplays:(HyprlandData.monitors || []).filter(m => !!m.name && !draft.includes(m.name)).map(m => ({name:m.description ? m.name+" · "+m.description : m.name,value:m.name}))
    function addApplication(id) { draft=draft.concat([id]); dirty=true;structureChanged();SettingsCatalog.saveDraft(setting.path,draft); }
    function addDisplay(name) { draft=draft.concat([name]); dirty=true;structureChanged();SettingsCatalog.saveDraft(setting.path,draft); }
    property var draft: []
    property bool dirty: false
    property var fieldErrors:({})
    readonly property string error:Object.keys(fieldErrors).length ? Translation.tr("Enter valid numbers in the highlighted entries.") : ""
    signal structureChanged()
    function updateDraftError() {
        if (typeof SettingsCatalog.setDraftError === "function") SettingsCatalog.setDraftError(setting.path,error);
    }
    onErrorChanged:updateDraftError()
    function setError(key,invalid) { const next=Object.assign({},fieldErrors); if (invalid) next[key]=true; else delete next[key]; fieldErrors=next; }
    function validateDraft() {
        const errors={};
        for (let index=0;index<draft.length;index++) for (const field of fields(index)) {
            if (!["int","real"].includes(field.type)) continue;
            const value=root.value(index,field.key);
            if (typeof value!=="number" || !Number.isFinite(value) || field.type==="int" && !Number.isInteger(value) || field.min!==undefined && value<field.min || field.max!==undefined && value>field.max) errors[index+"."+field.key]=true;
        }
        fieldErrors=errors;
        updateDraftError();
    }
    signal applied(var value)
    spacing:8
    function sync() { draft=SettingsCatalog.copy(currentValue || []); dirty=false; fieldErrors=({}); }
    Component.onCompleted: { const saved=SettingsCatalog.drafts[setting.path]; if (saved !== undefined) { draft=saved; dirty=true; structureChanged(); validateDraft(); SettingsCatalog.saveDraft(setting.path,draft); } else sync(); }
    onCurrentValueChanged:if (!dirty) sync()
    function change(index,key,value) {
        const next=SettingsCatalog.copy(draft);
        if (key === "") next[index]=value;
        else next[index][key]=value;
        draft=next; dirty=true; SettingsCatalog.saveDraft(setting.path,draft); setError(index+"."+key,false);
    }
    function fields(index) {
        const item=draft[index];
        if (item === null || typeof item !== "object") return [{key:"",type:typeof item === "boolean" ? "bool" : typeof item === "number" ? "real" : "string"}];
        const known=setting.itemFields || [];
        return known.concat(Object.keys(item).filter(k => !known.some(f => f.key === k)).map(k => ({key:k,type:typeof item[k] === "boolean" ? "bool" : typeof item[k] === "number" ? "real" : "string"})));
    }
    function value(index,key) { const item=draft[index]; if (item === null || item === undefined) return ""; return key === "" ? item : (item[key] === undefined ? "" : item[key]); }
    function readable(text) {
        const words=String(text || "").replace(/([a-z])([A-Z])/g,"$1 $2").replace(/_/g," ").trim();
        return words ? words[0].toUpperCase()+words.slice(1) : "";
    }
    readonly property var quickToggleIcons:({
        network:"wifi",bluetooth:"bluetooth",idleInhibitor:"keep_screen_on",mic:"mic",
        audio:"volume_up",nightLight:"nightlight",darkMode:"dark_mode",notifications:"notifications",
        screenSnip:"screenshot_region",colorPicker:"colorize",screenRecord:"screen_record",
        gameMode:"sports_esports",onScreenKeyboard:"keyboard",powerProfile:"battery_charging_full",
        musicRecognition:"music_note",cloudflareWarp:"cloud",easyEffects:"equalizer"
    })
    function fieldChoices(descriptor) {
        return (descriptor.choices || []).map(value => ({
            name:readable(value),value:value,
            icon:setting.path==="sidebar.quickToggles.android.toggles" && descriptor.key==="type" ? quickToggleIcons[value] || "" : ""
        }));
    }
    function entryLabel(index) {
        const item=draft[index];
        if (applicationList) { const app=AppSearch.list.find(a => a.id===item); return app ? LauncherLabels.displayName(app,AppSearch.list,AppSearch.launcherLabels) : String(item || Translation.tr("New application")); }
        if (typeof item === "string") return item || Translation.tr("New entry");
        if (item && typeof item === "object") {
            const name=item.name || item.title || item.label || item.type || item.model || item.id;
            if (name) return readable(name);
        }
        return Translation.tr("Entry %1").arg(index+1);
    }
    function move(index,delta) { const next=SettingsCatalog.copy(draft); const item=next.splice(index,1)[0]; next.splice(index+delta,0,item); draft=next; dirty=true; structureChanged(); validateDraft(); SettingsCatalog.saveDraft(setting.path,draft); }
    function remove(index) { draft=draft.filter((v,i) => i!==index); dirty=true; structureChanged(); validateDraft(); SettingsCatalog.saveDraft(setting.path,draft); }
    function add() {
        const item={};
        if (setting.itemFields) for (const field of setting.itemFields) item[field.key]=field.type === "bool" ? false : field.type === "int" ? 1 : field.choices ? field.choices[0] : "";
        draft=draft.concat([setting.itemFields ? item : ""]); dirty=true; structureChanged(); SettingsCatalog.saveDraft(setting.path,draft);
    }
    StyledText {
        Layout.fillWidth:true
        visible:!root.applicationList && !root.draft.length
        text:root.displayList ? Translation.tr("Shown on all displays. Add displays to restrict where the bar appears.") : Translation.tr("No entries yet. Add one below.")
        color:Appearance.colors.colSubtext
        wrapMode:Text.Wrap
    }
    Loader {
        active:root.applicationList
        visible:active
        Layout.fillWidth:true
        sourceComponent:SettingsAppListGrid {
            applicationIds:root.draft
            listKey:root.setting.path
            removalLabel:root.setting.path==="launcher.hiddenApps" ? Translation.tr("Unhide") : Translation.tr("Unpin")
            onMoveRequested:(from,to) => root.move(from,to-from)
            onRemoveRequested:index => root.remove(index)
            onAddRequested:applicationPicker.open()
        }
    }
    Repeater {
        model:root.applicationList ? 0 : root.draft.length
        delegate:Rectangle {
            id:entry
            required property int index
            property var fieldDescriptors:[]
            Component.onCompleted:fieldDescriptors=root.fields(index)
            Connections { target:root; function onStructureChanged() { entry.fieldDescriptors=root.fields(entry.index); } }
            Layout.fillWidth:true
            implicitHeight:entryContent.implicitHeight+20
            radius:Appearance.rounding.small
            color:Appearance.colors.colLayer2
            ColumnLayout {
                id:entryContent
                anchors { left:parent.left; right:parent.right; top:parent.top; margins:10 }
                spacing:6
                RowLayout {
                    Layout.fillWidth:true
                    AdaptiveAppIcon { visible:root.applicationList; implicitSize:28; appId:String(root.draft[entry.index] || ""); iconName:AppSearch.list.find(a => a.id===root.draft[entry.index])?.icon || ""; appName:root.entryLabel(entry.index) }
                    StyledText { Layout.fillWidth:true; text:root.entryLabel(entry.index); color:Appearance.colors.colSubtext; font.pixelSize:Appearance.font.pixelSize.smaller; elide:Text.ElideRight }
                    IconToolbarButton { implicitWidth:28; implicitHeight:28; text:"arrow_upward"; enabled:entry.index>0; Accessible.name:Translation.tr("Move up"); onClicked:root.move(entry.index,-1); StyledToolTip { text:Translation.tr("Move up") } }
                    IconToolbarButton { implicitWidth:28; implicitHeight:28; text:"arrow_downward"; enabled:entry.index<root.draft.length-1; Accessible.name:Translation.tr("Move down"); onClicked:root.move(entry.index,1); StyledToolTip { text:Translation.tr("Move down") } }
                    IconToolbarButton { implicitWidth:28; implicitHeight:28; text:"delete"; Accessible.name:Translation.tr("Remove entry"); onClicked:root.remove(entry.index); StyledToolTip { text:Translation.tr("Remove entry") } }
                }
                Repeater {
                    model:root.applicationList ? [] : entry.fieldDescriptors
                    delegate:RowLayout {
                        id:field
                        required property var modelData
                        Layout.fillWidth:true
                        StyledText { visible:field.modelData.key!==""; Layout.preferredWidth:120; text:root.readable(field.modelData.key); wrapMode:Text.Wrap; color:Appearance.colors.colSubtext }
                        StyledSwitch {
                            visible:field.modelData.type==="bool"
                            checked:!!root.value(entry.index,field.modelData.key)
                            onClicked:root.change(entry.index,field.modelData.key,checked)
                        }
                        SettingsChoiceEditor {
                            visible:!!field.modelData.choices && field.modelData.choices.length<=4
                            Layout.fillWidth:true
                            choices:root.fieldChoices(field.modelData)
                            value:root.value(entry.index,field.modelData.key)
                            label:root.readable(field.modelData.key)
                            onChosen:value => root.change(entry.index,field.modelData.key,value)
                        }
                        RowLayout {
                            visible:!!field.modelData.choices && field.modelData.choices.length>4
                            Layout.fillWidth:true
                            spacing:6
                            MaterialSymbol {
                                visible:root.setting.path==="sidebar.quickToggles.android.toggles" && field.modelData.key==="type"
                                text:root.quickToggleIcons[root.value(entry.index,field.modelData.key)] || "widgets"
                                iconSize:20
                                color:Appearance.colors.colOnLayer2
                            }
                            SettingsChoicePicker {
                                Layout.fillWidth:true
                                choices:root.fieldChoices(field.modelData)
                                value:root.value(entry.index,field.modelData.key)
                                label:root.readable(field.modelData.key)
                                onChosen:value => root.change(entry.index,field.modelData.key,value)
                            }
                        }
                        RowLayout {
                            visible:root.setting.path==="sidebar.quickToggles.android.toggles" && field.modelData.key==="size"
                            Layout.fillWidth:true
                            spacing:4
                            Repeater {
                                model:[1,2,3,4,5]
                                delegate:RippleButton {
                                    id:sizeButton
                                    required property int modelData
                                    implicitWidth:Math.max(48,Math.min(64,(field.width-130)/5))
                                    implicitHeight:40
                                    buttonRadius:Appearance.rounding.small
                                    toggled:Number(root.value(entry.index,"size"))===modelData
                                    colBackground:Appearance.colors.colLayer3
                                    colBackgroundToggled:Appearance.colors.colSecondaryContainer
                                    Accessible.role:Accessible.RadioButton
                                    Accessible.checked:toggled
                                    Accessible.name:Translation.tr("Tile width: %1 columns").arg(modelData)
                                    onClicked:root.change(entry.index,"size",modelData)
                                    contentItem:ColumnLayout {
                                        spacing:2
                                        Rectangle {
                                            Layout.alignment:Qt.AlignHCenter
                                            implicitWidth:8+sizeButton.modelData*7
                                            implicitHeight:8
                                            radius:3
                                            color:sizeButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                        }
                                        StyledText {
                                            Layout.alignment:Qt.AlignHCenter
                                            text:String(sizeButton.modelData)
                                            color:sizeButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                                            font.pixelSize:Appearance.font.pixelSize.smaller
                                        }
                                    }
                                }
                            }
                        }
                        MaterialTextArea {
                            visible:field.modelData.type!=="bool" && !field.modelData.choices && !(root.setting.path==="sidebar.quickToggles.android.toggles" && field.modelData.key==="size")
                            Layout.fillWidth:true
                            clip:true
                            wrapMode:TextEdit.NoWrap
                            text:String(root.value(entry.index,field.modelData.key))
                            Accessible.name:root.readable(field.modelData.key) || Translation.tr("Entry")
                            placeholderText:root.readable(field.modelData.key) || Translation.tr("Value")
                            onTextChanged:if (activeFocus) {
                                if (["int","real"].includes(field.modelData.type)) {
                                    const n=Number(text);
                                    if (!text.trim() || !Number.isFinite(n) || (field.modelData.type==="int" && !Number.isInteger(n)) || (field.modelData.min!==undefined && n<field.modelData.min) || (field.modelData.max!==undefined && n>field.modelData.max)) { root.change(entry.index,field.modelData.key,text); root.setError(entry.index+"."+field.modelData.key,true); return; }
                                    root.change(entry.index,field.modelData.key,n);
                                } else root.change(entry.index,field.modelData.key,text);
                            }
                            Keys.onReturnPressed:event => { event.accepted=true; }
                        }
                    }
                }
            }
        }
    }
    SettingsAppPicker {
        id:applicationPicker
        visible:false
        entries:root.availableApplications
        value:""
        label:Translation.tr("Application")
        onChosen:value => root.addApplication(value)
    }
    SettingsChoicePicker {
        id:displayPicker
        visible:false
        choices:root.availableDisplays
        value:""
        label:Translation.tr("Display")
        onChosen:value => root.addDisplay(value)
    }
    StyledText { visible:root.error.length>0; text:root.error; color:Appearance.colors.colError; wrapMode:Text.Wrap; Layout.fillWidth:true }
    RowLayout {
        visible:!root.applicationList
        Layout.fillWidth:true
        RippleButtonWithIcon { materialIcon:"add"; visible:!root.applicationList; mainText:root.displayList ? Translation.tr("Add display") : Translation.tr("Add entry"); onClicked:root.applicationList ? applicationPicker.open() : root.displayList && root.availableDisplays.length ? displayPicker.open() : root.add() }
        Item { Layout.fillWidth:true }
        DialogButton { visible:root.dirty; buttonText:Translation.tr("Discard"); onClicked:{ root.sync(); SettingsCatalog.clearDraft(root.setting.path); } }
    }
}
