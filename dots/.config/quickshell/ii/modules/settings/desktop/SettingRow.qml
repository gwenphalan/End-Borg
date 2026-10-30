pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "SettingsPresentation.js" as Presentation
import "../../ii/overview/LauncherLabels.js" as LauncherLabels

Rectangle {
    id:root
    Connections { target:root.valueStore ? null : SettingsCatalog; function onSaved() { if (!root.valueStore && SettingsCatalog.drafts[root.setting.path]===undefined) root.sync(); } function onDiscarded() { if(!root.valueStore) root.sync(); } }
    Connections {
        target:root.valueStore
        ignoreUnknownSignals:true
        function onResetRequested() {root.localNumericDraft=undefined;root.validation="";root.sync();}
    }
    property var valueStore:null
    property var localNumericDraft:undefined
    required property var setting
    property bool compact:false
    property bool grouped:false
    property bool showBreadcrumb:false
    property bool expanded:!valueStore && SettingsCatalog.drafts[setting.path] !== undefined
    property bool manualEntry:false
    readonly property string appCategory:setting.path==="apps.terminal" ? "TerminalEmulator" : setting.path==="apps.update" ? "PackageManager" : setting.path==="apps.taskManager" ? "System" : "Settings"
    readonly property bool fractionSetting:setting.type==="real" && setting.max===1 && setting.min>=0
    readonly property bool barPosition:setting.path==="bar.bottom"
    readonly property bool presetDropdown:setting.path==="appearance.palette.type"
    readonly property string displayLabel:barPosition ? Translation.tr("Bar position") : setting.path==="apps.terminal" ? Translation.tr("Terminal") : Translation.tr(setting.label)
    readonly property string displayDescription:barPosition ? Translation.tr("Choose which screen edge holds the bar.") : Translation.tr(setting.description || "")
    readonly property bool timeSetting:["light.night.from","light.night.to"].includes(setting.path)
    readonly property bool appSetting:setting.path.startsWith("apps.")
    readonly property bool iconCharacterSetting:setting.path==="cheatsheet.superKey"
    readonly property bool oskLayoutSetting:setting.path==="osk.layout"
    readonly property bool localeSetting:setting.path==="calendar.locale"
    readonly property bool displaySetting:setting.path==="notifications.monitor.name"
    readonly property var displayChoices: {
        if (!displaySetting) return [];
        const choices=Quickshell.screens.map(screen => ({name:screen.name,value:screen.name}));
        const saved=String(currentValue || "");
        if (saved && !choices.some(choice => choice.value===saved)) choices.push({name:saved,value:saved});
        return choices;
    }
    readonly property bool specializedString:!!setting.picker || timeSetting || appSetting || formatSetting || iconCharacterSetting || localeSetting || oskLayoutSetting || displaySetting
    readonly property var appKeywords:({
        "apps.bluetooth":/bluetooth|blueman/i,
        "apps.changePassword":/password|users?|accounts?|systemsettings/i,
        "apps.network":/network|connection|systemsettings/i,
        "apps.manageUser":/users?|accounts?|systemsettings/i,
        "apps.networkEthernet":/network|connection|ethernet|systemsettings/i,
        "apps.taskManager":/monitor|process|task.manager/i,
        "apps.terminal":/terminal|konsole|kitty|alacritty|foot|warp/i,
        "apps.update":/update|package|software|discover|pacman/i,
        "apps.volumeMixer":/volume|mixer|audio|pavucontrol/i
    })
    function appCommand(app) {
        const command=String(app.execString || "");
        if (!command) return "";
        const cleaned=command.replace(/(?:^|\s)%[fFuUiIckKdDnNvVmM](?=\s|$)/g,"").replace(/%%/g,"%").trim();
        return /%[a-zA-Z]/.test(cleaned) ? "" : cleaned;
    }
    readonly property var appChoices: {
        if (!appSetting) return [];
        const installed=AppSearch.list.map(app => ({
            id:app.id,
            name:app.name,
            icon:app.icon || "",
            value:root.appCommand(app),
            recommended:(app.categories || []).includes(root.appCategory)
                || (root.appKeywords[root.setting.path]?.test(app.id+" "+app.name) ?? false)
        })).filter(app => !!app.value).sort((a,b) =>
            a.recommended===b.recommended ? a.name.localeCompare(b.name) : a.recommended ? -1 : 1);
        return installed.filter((app,index) => installed.findIndex(other => other.value===app.value)===index);
    }
    readonly property var currentApp:appSetting ? appChoices.find(app => app.value===currentValue) : null
    readonly property var currentAppDisplay: {
        if (!appSetting || !currentValue) return null;
        if (currentApp) return currentApp;
        const command=String(currentValue).trim();
        if (/^kcmshell6(?:\s|$)/.test(command))
            return {name:Translation.tr("System Settings"),icon:"preferences-system",id:"",custom:true};
        if (/^kitty(?:\s|$)/.test(command))
            return {name:Translation.tr("Kitty"),icon:"kitty",id:"",custom:true};
        if (/^plasma-systemmonitor(?:\s|$)/.test(command))
            return {name:Translation.tr("System Monitor"),icon:"org.kde.plasma-systemmonitor",id:"",custom:true};
        if (/launch_first_available\.sh/.test(command) && /pavucontrol/.test(command))
            return {name:Translation.tr("Volume mixer"),icon:"multimedia-volume-control",id:"",custom:true};
        const executable=command.match(/^\s*(?:env\s+)?([^\s]+)/)?.[1]?.split("/").pop() || "";
        const installed=appChoices.find(app => app.value===executable || app.value.startsWith(executable+" "));
        if (installed) return {name:installed.name,icon:installed.icon,id:installed.id,custom:true};
        return {name:Translation.tr("Custom action"),icon:"application-x-executable",id:"",custom:true};
    }
    readonly property var pickerAppChoices:{
        if (!appSetting || !currentValue || currentApp) return appChoices;
        const display=currentAppDisplay;
        if (!display) return appChoices;
        const match=appChoices.find(app => app.id===display.id || app.name===display.name || app.icon && app.icon===display.icon);
        const id=display.id || match?.id || "settings-current-selection";
        return [{id:id,name:display.name,icon:display.icon,value:String(currentValue),recommended:true}].concat(appChoices.filter(app => app.id!==id));
    }
    function openAppPicker() { if (appPickerLoader.active) appPickerLoader.item.open(); else appPickerLoader.active=true; }
    function writeValue(value) { if(valueStore) {valueStore.write(setting.path,value);localNumericDraft=undefined;validation="";dirty=false;sync();return;} if (SettingsCatalog.write(setting.path,value)) { dirty=false;sync(); } }
    property bool highlighted:false
    readonly property var currentValue: { const observed=SettingsCatalog.revision; return valueStore ? valueStore.get(setting.path) : SettingsCatalog.get(setting.path); }
    readonly property bool available:(valueStore ? setting.enabled!==false : SettingsCatalog.available(setting)) && !setting.readOnly
    readonly property bool formatSetting:["time.shortDateFormat","time.dateWithYearFormat","time.dateFormat"].includes(setting.path)
    readonly property var dateFormats:setting.path==="time.shortDateFormat" ? ["dd/MM","MM/dd","MMM d","d MMM"] : setting.path==="time.dateWithYearFormat" ? ["dd/MM/yyyy","MM/dd/yyyy","yyyy-MM-dd","d MMM yyyy"] : ["ddd, dd/MM","ddd, MMM d","dddd, d MMMM"]
    readonly property var choices:displaySetting ? displayChoices : formatSetting ? dateFormats.concat(dateFormats.includes(currentValue) ? [] : [String(currentValue)]).map(f => ({name:Qt.formatDateTime(new Date(),f),value:f})) : valueStore ? (setting.choices || []) : SettingsCatalog.choices(setting)
    property string draft:""
    property bool dirty:false
    property string validation:""
    signal navigate(string category,string group)
    function sync() { draft=String(currentValue===undefined ? "" : currentValue); dirty=false; validation=""; }
    Component.onCompleted: { const saved=valueStore ? undefined : SettingsCatalog.drafts[setting.path]; if (typeof saved === "string") { draft=saved; dirty=true; validation=SettingsCatalog.draftErrors[setting.path] || ""; } else sync(); }
    onCurrentValueChanged:if (!dirty) sync()
    function apply() {
        let value=draft;
        if (["int","real"].includes(setting.type)) {
            value=Number(draft);
            if (!draft.trim() || !Number.isFinite(value) || value<setting.min || value>setting.max || (setting.type==="int" && !Number.isInteger(value))) {
                validation=Translation.tr("Enter a value between %1 and %2.").arg(setting.min).arg(setting.max); return;
            }
        }
        if (setting.path.startsWith("light.night.") && ["light.night.from","light.night.to"].includes(setting.path) && !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) { validation=Translation.tr("Use a 24-hour time, such as 19:00."); return; }
        if (setting.path==="homeAssistant.url" && value && !/^https?:\/\//.test(value)) { validation=Translation.tr("Use an http:// or https:// server address."); return; }
        if (setting.picker==="color" && value && !/^#[a-f\d]{6}$/i.test(value)) { validation=Translation.tr("Use a six-digit color, such as #4f8c79."); return; }
        if(valueStore) writeValue(value);else if (SettingsCatalog.write(setting.path,value)) { dirty=false; validation=""; }
    }
    function editText(text) {
        draft=text;
        dirty=text!==String(currentValue ?? "");
        validation="";
        if(valueStore) return;
        if (dirty) SettingsCatalog.saveDraft(setting.path,text);
        else SettingsCatalog.clearDraft(setting.path);
    }
    readonly property var numericRawDraft: {
        const value=valueStore ? localNumericDraft : SettingsCatalog.drafts[setting.path];
        if (!isNumber || value===undefined) return undefined;
        const text=String(value);
        return text.trim() && Number.isFinite(Number(text)) ? String(Number(text)*numericPresentation.displayScale) : text;
    }
    function invalidNumber(text) {
        const parsed=text.trim() ? Number(text) : NaN;
        const stored=Number.isFinite(parsed) ? String(parsed/numericPresentation.displayScale) : text;
        if(valueStore) localNumericDraft=stored;else SettingsCatalog.saveDraft(setting.path,stored);
        validation=Number.isFinite(numericPresentation.max) ? Translation.tr("Enter a valid value between %1 and %2.").arg(numericPresentation.min*numericPresentation.displayScale).arg(numericPresentation.max*numericPresentation.displayScale) : Translation.tr("Enter a valid value of at least %1.").arg(numericPresentation.min*numericPresentation.displayScale);
        if(valueStore) {if(valueStore.invalid) valueStore.invalid(setting.path,validation);} else SettingsCatalog.setDraftError(setting.path,validation);
    }
    function cancelNumber() { if(valueStore) {localNumericDraft=undefined;if(valueStore.invalid) valueStore.invalid(setting.path,"");}else SettingsCatalog.clearDraft(setting.path); validation=""; }
    function chooseFile() {
        if (setting.picker==="folder") folderDialog.open();
        else fileDialog.open();
    }
    property alias headerButton:rowButton
    readonly property bool editable:!setting.readOnly
    readonly property bool isList:setting.type.startsWith("list")
    readonly property bool isNumber:["int","real"].includes(setting.type)
    readonly property var numericPresentation:Presentation.numeric(setting)
    readonly property bool batteryFull:setting.path==="battery.full"
    readonly property bool batteryFullOff:batteryFull && Number(currentValue)>100
    property real lastBatteryThreshold:100
    readonly property bool inlineSlider:isNumber && !choices.length && numericPresentation.control==="slider" && !batteryFullOff
    FontMetrics { id:choiceMetrics; font.family:Appearance.font.family.main; font.pixelSize:Appearance.font.pixelSize.small; font.variableAxes:Appearance.font.variableAxes.main }
    function conciseChoiceName(choice) { return setting.path==="bar.cornerStyle" && choice.value===2 ? Translation.tr("Rect") : String(choice.name); }
    function naturalChoiceWidth(name) { return Math.max(64,Math.ceil(choiceMetrics.advanceWidth(String(name)))+24+(setting.path.startsWith("background.widgets.clock.style") ? 34 : 0)); }
    function choiceWidth(name) { return Math.min(148,naturalChoiceWidth(name)); }
    readonly property bool inlineChoices:!specializedString && choices.length>=2 && choices.length<=5 && choices.every(choice => naturalChoiceWidth(conciseChoiceName(choice))<=148) && choices.reduce((width,choice) => width+choiceWidth(conciseChoiceName(choice))+6,0)<=width*.62
    readonly property bool longChoices:!displaySetting && choices.length>0 && !inlineChoices && Presentation.searchable(setting,choices)
    readonly property bool dropdownChoices:displaySetting || (choices.length>0 && !inlineChoices && !longChoices && !(formatSetting && manualEntry))
    readonly property bool canExpand:editable && isList
    readonly property bool pathSetting:["file","folder"].includes(setting.picker)
    readonly property bool colorSetting:setting.picker==="color"
    readonly property string accentLabel:{
        const value=String(currentValue || "");
        const preset=colorPicker.presets.find(item => item.hex.toLowerCase()===value.toLowerCase());
        return value ? preset ? Translation.tr(preset.name) : value.toUpperCase() : Translation.tr("Wallpaper");
    }
    readonly property real accentButtonWidth:Math.max(140,Math.ceil(colorPicker.presets.map(item => Translation.tr(item.name)).concat([Translation.tr("Wallpaper"),"#FFFFFF"]).reduce((width,text) => Math.max(width,choiceMetrics.advanceWidth(text)),0))+64)
    readonly property bool textSetting:setting.type==="string" && !isList && !appSetting && !timeSetting && !iconCharacterSetting && !localeSetting && !oskLayoutSetting && !displaySetting && !setting.picker && (!choices.length || formatSetting && manualEntry)
    readonly property int barPositionValue: {
        const observed=SettingsCatalog.revision;
        return (SettingsCatalog.get("bar.bottom") ? 1 : 0) | (SettingsCatalog.get("bar.vertical") ? 2 : 0);
    }
    function writeBarPosition(position) {
        if(valueStore) {valueStore.write("bar.bottom",(position & 1)!==0);valueStore.write("bar.vertical",(position & 2)!==0);return;}
        SettingsCatalog.write("bar.bottom",(position & 1)!==0);
        SettingsCatalog.write("bar.vertical",(position & 2)!==0);
    }
    readonly property string summary: {
        if (isList) return setting.path==="bar.screenList" && !(currentValue || []).length ? Translation.tr("All displays") : Translation.tr("%1 items").arg((currentValue || []).length);
        if (appSetting) return currentAppDisplay ? LauncherLabels.displayName(currentAppDisplay,AppSearch.list,AppSearch.launcherLabels) : Translation.tr("Not set");
        if (choices.length) return choices.find(c => c.value===currentValue)?.name || String(currentValue);
        return String(currentValue===undefined || currentValue==="" ? Translation.tr("Not set") : currentValue);
    }
    Layout.fillWidth:true
    implicitHeight:content.implicitHeight
    color:highlighted ? Appearance.colors.colSecondaryContainer : grouped ? "transparent" : Appearance.colors.colLayer1
    radius:grouped ? 0 : Appearance.rounding.normal
    ColumnLayout {
        id:content
        width:root.width
        spacing:0
        RowLayout {
            visible:root.showBreadcrumb
            Layout.fillWidth:true; Layout.leftMargin:20; Layout.rightMargin:16; Layout.topMargin:12
            StyledText { Layout.fillWidth:true; text:Translation.tr(SettingsCatalog.category(root.setting.category).title)+"  ›  "+Translation.tr(root.setting.groupTitle); font.pixelSize:Appearance.font.pixelSize.smaller; color:Appearance.colors.colSubtext; elide:Text.ElideRight }
            IconToolbarButton { implicitWidth:28; implicitHeight:28; text:"arrow_outward"; Accessible.name:Translation.tr("Open section"); onClicked:root.navigate(root.setting.category,SettingsCatalog.destination(root.setting)) }
        }
        RippleButton {
            id:rowButton
            Layout.fillWidth:true
            implicitHeight:Math.max(60,rowContent.implicitHeight+24)
            padding:0; buttonRadius:0
            enabled:root.available || !!root.setting.readOnly
            pointingHandCursor:root.setting.type==="bool" && !root.barPosition || root.canExpand || root.appSetting
            rippleEnabled:pointingHandCursor
            Accessible.name:root.displayLabel
            onClicked: {
                if (!root.editable) return;
                if (root.setting.type==="bool" && !root.barPosition) root.writeValue(!root.currentValue);
                else if (root.appSetting) root.openAppPicker();
                else if (root.canExpand) root.expanded=!root.expanded;
            }
            contentItem:RowLayout {
                id:rowContent
                spacing:12
                Item { implicitWidth:8 }
                MaterialSymbol {
                    visible:!!root.setting.icon
                    text:root.setting.icon || ""
                    iconSize:18
                    color:Appearance.colors.colSubtext
                    HoverHandler { id:settingIconHover }
                    StyledToolTip {
                        extraVisibleCondition:settingIconHover.hovered && !!root.displayDescription
                        text:root.displayDescription
                        delay:650
                    }
                }
                StyledText {
                    Layout.fillWidth:true
                    Layout.minimumWidth:80
                    text:root.displayLabel
                    textFormat:Text.PlainText
                    wrapMode:Text.Wrap
                    color:root.available || root.setting.readOnly ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }
                StyledText {
                    visible:root.setting.readOnly || root.isList
                    Layout.maximumWidth:root.width*.3
                    text:root.summary; elide:Text.ElideMiddle
                    color:Appearance.colors.colSubtext
                }
                RowLayout {
                    visible:root.appSetting
                    Layout.preferredWidth:Math.min(250,root.width*.42)
                    spacing:12
                    StyledText { Layout.fillWidth:true; horizontalAlignment:Text.AlignRight; text:root.summary; elide:Text.ElideRight; color:Appearance.colors.colSubtext }
                    Item {
                        implicitWidth:28; implicitHeight:28
                        AdaptiveAppIcon { anchors.centerIn:parent; visible:!!root.currentAppDisplay; implicitSize:28; appId:root.currentAppDisplay?.id || ""; iconName:root.currentAppDisplay?.icon || ""; appName:root.currentAppDisplay?.name || "" }
                        MaterialSymbol { anchors.centerIn:parent; visible:!root.currentAppDisplay; text:"block"; iconSize:20; color:Appearance.colors.colSubtext }
                    }
                }
                Loader {
                    active:root.setting.picker==="font"
                    visible:active
                    Layout.maximumWidth:root.width*.48
                    sourceComponent:SettingsFontPicker {
                        value:String(root.currentValue || "")
                        accessibleLabel:root.displayLabel
                        enabled:root.available
                        onChosen:family => root.writeValue(family)
                    }
                }
                Loader {
                    active:root.presetDropdown
                    visible:active
                    Layout.preferredWidth:57
                    Layout.preferredHeight:12
                    sourceComponent:presetDropdownLoader.item ? presetDropdownLoader.item.selectedSwatchPreview : null
                }
                Loader {
                    id:presetDropdownLoader
                    active:root.dropdownChoices
                    visible:active
                    Layout.preferredWidth:Math.min(root.presetDropdown ? 168 : 230,root.width*.4)
                    sourceComponent:SettingsPresetDropdown {
                        choices:root.choices; value:root.currentValue; label:root.displayLabel
                        settingPath:root.setting.path
                        previewSurroundingColor:root.grouped ? Appearance.colors.colLayer2 : root.color
                        displayText:root.displaySetting && currentIndex<0 ? Translation.tr(choices.length ? "Choose display" : "No displays connected") : currentText
                        enabled:root.available && (!root.displaySetting || choices.length>0)
                        onChosen:value => root.writeValue(value)
                    }
                }
                Loader {
                    active:root.longChoices
                    visible:active
                    Layout.maximumWidth:root.width*.48
                    sourceComponent:SettingsChoicePicker { choices:root.choices; value:root.currentValue; label:root.displayLabel; enabled:root.available; onChosen:value => root.writeValue(value) }
                }
                Loader {
                    active:root.barPosition; visible:active
                    sourceComponent:SettingsPositionEditor { value:root.barPositionValue; enabled:root.available; onChosen:value => root.writeBarPosition(value) }
                }
                Loader {
                    active:root.isNumber && !root.choices.length && !root.inlineSlider && !root.batteryFull && root.numericPresentation.control!=="unboundedNumber"
                    visible:active
                    sourceComponent:NumberInput {
                    enabled:root.available
                    number:(Number(root.currentValue) || 0)*root.numericPresentation.displayScale
                    minimum:(root.numericPresentation.min ?? 0)*root.numericPresentation.displayScale
                    maximum:(root.numericPresentation.max ?? 1000000)*root.numericPresentation.displayScale
                    increment:root.numericPresentation.step*root.numericPresentation.displayScale
                    integral:root.numericPresentation.displayIntegral
                    unit:root.numericPresentation.displayUnit
                    rawDraft:root.numericRawDraft
                    onInvalidEdited:text => root.invalidNumber(text)
                    onCancelled:root.cancelNumber()
                    Accessible.name:root.displayLabel
                    onEdited:number => root.writeValue(root.setting.type==="int" ? Math.round(number/root.numericPresentation.displayScale) : number/root.numericPresentation.displayScale)
                }
                }
                Loader {
                    active:root.isNumber && root.numericPresentation.control==="unboundedNumber"
                    visible:active
                    Layout.preferredWidth:180
                    sourceComponent:UnboundedNumberInput {
                        number:Number(root.currentValue || 0)
                        minimum:root.numericPresentation.min
                        increment:root.numericPresentation.step
                        unit:root.numericPresentation.displayUnit
                        rawDraft:root.numericRawDraft
                        Accessible.name:root.displayLabel
                        onEdited:number => root.writeValue(number)
                        onInvalidEdited:text => root.invalidNumber(text)
                        onCancelled:root.cancelNumber()
                    }
                }
                RowLayout {
                    visible:root.batteryFull
                    StyledText { visible:root.batteryFullOff; text:Translation.tr("Off"); color:Appearance.colors.colSubtext }
                    StyledSwitch {
                        checked:!root.batteryFullOff
                        Accessible.name:Translation.tr("Full battery notification")
                        onClicked: {
                            if (!checked) { root.lastBatteryThreshold=Number(root.currentValue); root.writeValue(101); }
                            else root.writeValue(root.lastBatteryThreshold);
                        }
                    }
                }
                Item {
                    visible:root.inlineChoices
                    implicitWidth:choiceButtons.implicitWidth
                    implicitHeight:36
                    SelectionIndicator {
                        anchors.fill:parent
                        container:choiceButtons
                        selectedItem:choiceButtons.selectedChoice
                        hoveredItem:choiceButtons.hoveredChoice
                    }
                    RowLayout {
                    id:choiceButtons
                    anchors.fill:parent
                    property Item selectedChoice:null
                    property Item hoveredChoice:null
                    spacing:6
                    Repeater {
                        model:root.inlineChoices ? root.choices : []
                        delegate:RippleButton {
                            id:choiceButton
                            required property var modelData
                            implicitHeight:36
                            implicitWidth:Math.ceil(choiceText.implicitWidth)+24+(clockChoice ? 34 : 0)
                            Layout.minimumWidth:implicitWidth
                            leftPadding:12
                            rightPadding:12
                            topPadding:0
                            bottomPadding:0
                            readonly property bool clockChoice:root.setting.path.startsWith("background.widgets.clock.style")
                            buttonRadius:Appearance.rounding.full
                            toggled:root.currentValue===modelData.value
                            colBackground:"transparent"
                            colBackgroundHover:"transparent"
                            colBackgroundToggled:"transparent"
                            colBackgroundToggledHover:"transparent"
                            onToggledChanged:if (toggled) choiceButtons.selectedChoice=choiceButton
                            onIsHoveredChanged:if (isHovered) choiceButtons.hoveredChoice=choiceButton;else if (choiceButtons.hoveredChoice===choiceButton) choiceButtons.hoveredChoice=null
                            Component.onCompleted:if (toggled) choiceButtons.selectedChoice=choiceButton
                            enabled:root.available
                            Accessible.role:Accessible.RadioButton
                            Accessible.checked:toggled
                            Accessible.name:root.displayLabel+": "+modelData.name
                            onClicked:root.writeValue(modelData.value)
                            StyledToolTip { text:choiceButton.modelData.name }
                            contentItem:Item {
                                RowLayout {
                                    anchors.centerIn:parent
                                    width:parent.width
                                    spacing:6
                                    SettingsClockThumbnail { visible:choiceButton.clockChoice; style:String(choiceButton.modelData.value); foreground:choiceButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2 }
                                    StyledText { id:choiceText; Layout.fillWidth:true; Layout.minimumWidth:0; text:root.conciseChoiceName(choiceButton.modelData); horizontalAlignment:Text.AlignHCenter; verticalAlignment:Text.AlignVCenter; wrapMode:Text.NoWrap; elide:Text.ElideNone; color:choiceButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2 }
                                }
                            }
                        }
                    }
                }
                    }
                Loader {
                    active:root.oskLayoutSetting
                    visible:active
                    Layout.maximumWidth:root.width*.48
                    sourceComponent:SettingsOskLayoutPicker { value:String(root.currentValue || "");label:root.displayLabel;enabled:root.available;onChosen:value => root.writeValue(value) }
                }
                Loader {
                    active:root.localeSetting
                    visible:active
                    Layout.maximumWidth:root.width*.48
                    sourceComponent:SettingsLocalePicker { value:String(root.currentValue || "");label:root.displayLabel;separator:"-";allowSystemDefault:true;enabled:root.available;onChosen:value => root.writeValue(value) }
                }
                Loader {
                    active:root.timeSetting
                    visible:active
                    Layout.preferredWidth:140
                    sourceComponent:SettingsTimeInput { value:String(root.currentValue || "00:00");label:root.displayLabel;enabled:root.available;onChosen:value => root.writeValue(value) }
                }
                Loader {
                    active:root.iconCharacterSetting
                    visible:active
                    Layout.maximumWidth:root.width*.45
                    sourceComponent:SettingsIconCharacterPicker { value:String(root.currentValue || "");label:root.displayLabel;enabled:root.available;onChosen:value => root.writeValue(value) }
                }
                CompactTextField {
                    visible:root.textSetting && !root.setting.multiline
                    Layout.preferredWidth:root.timeSetting ? 140 : Math.min(300,root.width*.44)
                    Layout.preferredHeight:40
                    enabled:root.available
                    text:root.draft
                    Accessible.name:root.displayLabel
                    placeholderText:root.timeSetting ? "HH:mm" : ""
                    invalid:!!root.validation || (!root.valueStore && !!SettingsCatalog.draftErrors[root.setting.path])
                    wrapMode:TextInput.NoWrap
                    onTextEdited:root.editText(text)
                    Keys.onReturnPressed:event => { root.apply(); event.accepted=true; }
                    Keys.onEscapePressed:event => { root.sync(); if(!root.valueStore) SettingsCatalog.clearDraft(root.setting.path); event.accepted=true; }
                }
                RowLayout {
                    visible:root.pathSetting
                    Layout.maximumWidth:root.width*.5
                    StyledText { Layout.fillWidth:true; Layout.maximumWidth:180; text:root.summary; elide:Text.ElideMiddle; color:Appearance.colors.colSubtext }
                    RippleButtonWithIcon { materialIcon:"folder_open"; mainText:root.setting.picker==="folder" ? Translation.tr("Choose folder") : Translation.tr("Choose file"); enabled:root.available; onClicked:root.chooseFile() }
                }
                RippleButton {
                    visible:root.colorSetting
                    implicitWidth:root.accentButtonWidth; implicitHeight:36
                    Layout.minimumWidth:root.accentButtonWidth
                    Layout.maximumWidth:root.accentButtonWidth
                    leftPadding:12;rightPadding:12
                    topPadding:0;bottomPadding:0
                    buttonRadius:Appearance.rounding.full
                    colBackground:Appearance.colors.colLayer3
                    colBackgroundHover:Appearance.colors.colSecondaryContainer
                    onClicked:colorPicker.open()
                    Accessible.name:Translation.tr("Choose accent color")
                    Accessible.description:root.accentLabel
                    contentItem:RowLayout {
                        spacing:8
                        Rectangle { implicitWidth:20; implicitHeight:20; radius:10; color:root.colorSetting ? String(root.currentValue || Appearance.colors.colPrimary) : "transparent" }
                        StyledText { Layout.fillWidth:true; text:root.accentLabel; elide:Text.ElideNone; color:Appearance.colors.colOnLayer2 }
                    }
                }
                IconToolbarButton {
                    visible:root.formatSetting
                    text:root.manualEntry ? "close" : "code"
                    implicitWidth:32; implicitHeight:32
                    Accessible.name:Translation.tr("Custom date format")
                    onClicked:root.manualEntry=!root.manualEntry
                    StyledToolTip { text:Translation.tr("Custom date format") }
                }
                StyledSwitch { visible:root.setting.type==="bool" && !root.barPosition; enabled:root.available; checked:!!root.currentValue; Accessible.name:root.displayLabel; onClicked:root.writeValue(checked) }
                MaterialSymbol { visible:root.canExpand || root.appSetting; text:root.appSetting ? "chevron_right" : root.expanded ? "expand_less" : "chevron_right"; iconSize:20; color:Appearance.colors.colSubtext }
                Item { implicitWidth:8 }
            }
        }
        Loader {
            active:root.inlineSlider
            visible:active
            Layout.fillWidth:true; Layout.leftMargin:20; Layout.rightMargin:20; Layout.bottomMargin:12
            sourceComponent:SettingsNumericEditor {
                setting:root.setting; value:Number(root.currentValue || 0); rawDraft:root.numericRawDraft; enabled:root.available
                onEdited:value => root.writeValue(value)
                onInvalidEdited:text => root.invalidNumber(text)
                onCancelled:root.cancelNumber()
                onPreviewed:value => {if(!root.valueStore) SettingsCatalog.transientClockFontSize=value;}
                onPreviewEnded:if (!root.valueStore && previewsClockSize) SettingsCatalog.transientClockFontSize=NaN
            }
        }
        Loader {
            active:root.setting.path==="overview.columns" && root.available
            visible:active
            Layout.fillWidth:true; Layout.leftMargin:50; Layout.rightMargin:20; Layout.bottomMargin:12
            sourceComponent:SettingsOverviewPreview {}
        }
        MaterialTextArea {
            visible:root.textSetting && root.setting.multiline
            Layout.fillWidth:true; Layout.leftMargin:20; Layout.rightMargin:20; Layout.bottomMargin:12
            Layout.preferredHeight:110
            text:root.draft
            wrapMode:TextEdit.Wrap
            Accessible.name:root.displayLabel
            onTextChanged:if (activeFocus) root.editText(text)
        }
        StyledText {
            visible:!!root.validation
            Layout.fillWidth:true; Layout.leftMargin:50; Layout.rightMargin:20; Layout.bottomMargin:12
            text:root.validation; color:Appearance.colors.colError; wrapMode:Text.Wrap
        }
        ExpandingLoader {
            expanded:root.isList && root.expanded
            Layout.fillWidth:true; Layout.leftMargin:20; Layout.rightMargin:20; Layout.bottomMargin:12
            sourceComponent:SettingsListEditor { setting:root.setting; currentValue:root.currentValue; enabled:root.available }
        }
    }
    Loader {
        id:appPickerLoader
        active:false; visible:false
        onLoaded:item.open()
        sourceComponent:SettingsAppPicker { entries:root.pickerAppChoices; value:String(root.currentValue || ""); label:root.displayLabel; allowCustom:true; onChosen:command => root.writeValue(command); onDismissed:Qt.callLater(() => { appPickerLoader.active=false; }) }
    }
    SettingsAccentPicker {
        id:colorPicker
        value:String(root.currentValue || "")
        onChosen:value => root.writeValue(value)
    }
    Connections { target:SettingsCatalog; function onDismissPopups() { colorPicker.close(); fileDialog.close(); folderDialog.close(); } }
    FileDialog { id:fileDialog; title:Translation.tr("Choose file"); onAccepted:root.writeValue(decodeURIComponent(String(selectedFile).replace(/^file:\/\//,""))) }
    FolderDialog { id:folderDialog; title:Translation.tr("Choose folder"); onAccepted:root.writeValue(decodeURIComponent(String(selectedFolder).replace(/^file:\/\//,""))) }
}
