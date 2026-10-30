pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import "settings_schema.js" as Schema
import "settings_layout.js" as Layout
import "../../common/BarUtilities.js" as Utilities

Singleton {
    id: root
    readonly property var categories: Schema.categories.map(category => Object.assign({},category,{description:Layout.categoryDescriptions[category.id] || category.description,navGroup:(Layout.navigationGroups[category.id] || ["More"])[0],navGroupIcon:(Layout.navigationGroups[category.id] || ["","more_horiz"])[1]}))
    readonly property var entries: Schema.entries
    // Schema and layout metadata are immutable. Decorate once rather than
    // rebuilding every record for every row as a page's sections are expanded.
    // Availability and values remain live checks against the current drafts.
    readonly property var decoratedEntries: entries.map(decorate)
    readonly property var entryIndex: decoratedEntries.reduce((index,e) => { index[e.path]=e;return index; },{})
    readonly property var visibleCatalogEntries: decoratedEntries.filter(e => !e.readOnly && !toolPaths.includes(e.path) && !Layout.hiddenPaths.includes(e.path))
    // These preferences have a dedicated, richer editor. Keep the schema for
    // validation and writes, but give every control one home in navigation.
    readonly property var toolPaths: ["appearance.steamGridDb.enabled", "homeAssistant.url", "homeAssistant.hiddenEntities", "homeAssistant.favoriteEntities", "homeAssistant.quickToggleEntities", "homeAssistant.barControlEntities", "borgIntelligence.enabled", "borgIntelligence.endpoint", "borgIntelligence.textModel", "borgIntelligence.visionModel", "borgIntelligence.timeoutSeconds", "borgIntelligence.iconAssistance", "background.wallpaperPath"]
    function iconFor(e) {
        if (Layout.pathIcons[e.path]) return Layout.pathIcons[e.path];
        return "";
    }
    function decorate(e) {
        if (!e) return e;
        const label=Layout.labels[e.path] || {};
        const conditions=(Layout.conditionOverrides[e.path] || e.conditions || []).concat(Layout.extraConditions[e.path] || [],
            Layout.quickshellLockPaths.includes(e.path) ? ["lock.quickshellActive"] : [],
            Layout.manualClockPaths.includes(e.path) ? ["background.widgets.clock.freePlacement"] : [],
            Layout.manualWeatherPaths.includes(e.path) ? ["background.widgets.weather.freePlacement"] : []);
        return Object.assign({},e,label,{category:Layout.categoryOverrides[e.path] || e.category,group:e.path.startsWith("background.widgets.clock.digital.font.") ? "background.widgets.clock.digital.font" : e.group,groupTitle:e.path.startsWith("background.widgets.clock.digital.font.") ? "Clock appearance" : e.groupTitle,conditions:conditions,icon:iconFor(e)});
    }
    function visibleEntries() {
        return visibleCatalogEntries;
    }
    function promotedPaths(categoryId) {
        const definitions=(Layout.pages[categoryId] || []).concat(Layout.advanced[categoryId] || [],...Object.values(Layout.subpages));
        return definitions.reduce((all,s) => all.concat(s.items),[]).filter(p => !p.startsWith("@") && !p.startsWith(">"));
    }
    signal dismissPopups()
    // Scrubbing previews never enter pending changes, history or live configuration.
    property real transientClockFontSize: NaN
    property int revision: 0
    signal saved()
    // Feedback is emitted at the outcome boundary, never when Save is only requested.
    signal feedbackRequested(string text, string kind, string action, string settingPath)
    property string errorPath:""
    property string errorAction:"edit"
    onErrorChanged: {
        if (!error) return;
        const detail=error;
        const path=errorPath;
        const action=errorAction;
        const label=path ? Translation.tr(entry(path)?.label || path) : "";
        feedbackRequested(label ? label+": "+detail : detail,"error",action,path);
    }
    signal discarded()
    property bool committing:false
    property var submitted: ({})
    property var submittedBaseline: ({})
    property var submittedDrafts: ({})
    property bool submittedTheme:false
    readonly property string actualAppearanceMode:MaterialThemeLoader.committedDarkMode ? "dark" : "light"
    property string savedAppearanceMode:actualAppearanceMode
    onActualAppearanceModeChanged:savedAppearanceMode=actualAppearanceMode
    property string pendingAppearanceMode:""
    property string submittedMode:""
    readonly property string appearanceMode:pendingAppearanceMode || savedAppearanceMode
    function setAppearanceMode(mode,record) {
        if (!["light","dark"].includes(mode)) return false;
        if (record!==false && mode!==appearanceMode) history=history.concat([{appearanceMode:true,value:appearanceMode}]).slice(-40);
        pendingAppearanceMode=mode===savedAppearanceMode ? "" : mode;
        return true;
    }
    function finishCommit() {
        committing=false;
        const next=Object.assign({},pending);
        for (const path of Object.keys(submitted)) if (JSON.stringify(next[path])===JSON.stringify(submitted[path])) delete next[path];
        pending=next;
        const remaining=Object.assign({},drafts);
        for (const path of Object.keys(submittedDrafts)) if (JSON.stringify(remaining[path])===JSON.stringify(submittedDrafts[path])) delete remaining[path];
        drafts=remaining;
        if (submittedMode) {
            savedAppearanceMode=submittedMode;
            if (pendingAppearanceMode===submittedMode) pendingAppearanceMode="";
        }
        const errors=Object.assign({},draftErrors);
        for (const path of Object.keys(errors)) if (remaining[path]===undefined) delete errors[path];
        history=[]; draftErrors=errors; revision++; error=""; message=Translation.tr("All changes saved");
        feedbackRequested(unappliedCount ? Translation.tr("Changes saved. New edits are still unsaved.") : Translation.tr("Settings saved"),"success","","");
        saved();
    }
    function afterPersisted(success) {
        if (!committing || themeProcess.running) return;
        if (!success) {
            Config.restoreOptions(submittedBaseline,submitted);
            submittedBaseline=({});
            committing=false; errorPath=""; errorAction="retry"; error=Config.lastError || Translation.tr("Settings could not be saved. Your edits are kept; try again."); return;
        }
        submittedBaseline=({});
        if (!submittedTheme || Quickshell.env("QS_SETTINGS_PREVIEW")==="1") { finishCommit(); return; }
        // Read the persisted path and preserve the accent selected in the draft.
        let args=[Directories.wallpaperSwitchScriptPath,"--noswitch"];
        if (submittedMode) args.push("--mode",submittedMode);
        themeProcess.command=args;
        themeProcess.running=true;
    }
    Connections {
        target:Config
        function onWriteFinished(success) { root.afterPersisted(success); }
    }
    Process {
        id:themeProcess
        onExited:(exitCode,exitStatus) => {
            if (exitCode===0) root.finishCommit();
            else { root.committing=false; root.errorPath=""; root.errorAction="retry"; root.error=Translation.tr("Wallpaper and colors could not be applied. Your edits are kept; try Save again."); }
        }
    }
    property var pending: ({})
    property var drafts: ({})
    readonly property int unappliedCount:new Set(Object.keys(pending).concat(Object.keys(drafts))).size+(pendingAppearanceMode ? 1 : 0)
    function saveDraft(path,value) { const next=Object.assign({},drafts); next[path]=copy(value); drafts=next; }
    property var draftErrors: ({})
    function setDraftError(path,message) { const next=Object.assign({},draftErrors); if (message) next[path]=message; else delete next[path]; draftErrors=next; }
    function clearDraft(path) { const next=Object.assign({},drafts); delete next[path]; drafts=next; setDraftError(path,""); }
    property var history: []
    property string message: ""
    property string error: ""
    readonly property var actions: [
        {path:"tools.steamgriddb", category:"appearance", group:"__advanced__", groupTitle:"SteamGridDB", label:"SteamGridDB game icons", description:"Enable dedicated game icons, save a key in the desktop keyring, test the connection and refresh cached artwork", type:"action"},
        {path:"tools.borg", category:"services", group:"tools.borg", groupTitle:"Borg intelligence", label:"Borg intelligence setup", description:"Dedicated gateway key, HTTPS endpoint, discover models and optional public icon assistance", type:"action"},
        {path:"tools.wallpaper", category:"appearance", group:"", groupTitle:"Wallpaper & Colors", label:"Wallpaper & Colors", description:"Choose a wallpaper, switch light or dark appearance and regenerate application colors", type:"action"},
        {path:"tools.translation", category:"language", group:"__advanced__", groupTitle:"Generate translations", label:"Generate translations", description:"Generate a language translation with Gemini", type:"action"},
        {path:"tools.home", category:"home", group:"tools.home", groupTitle:"Connection & devices", label:"Home Assistant connection and devices", description:"Server address URL, access token, connect, refresh and manage hidden devices, favorites, shortcut order and top-bar pins", type:"action"},
        {path:"tools.about", category:"about", group:"tools.about", groupTitle:"System & support", label:"System information and support", description:"Distribution, documentation, credits and support", type:"action"}
    ]
    function get(path, source) {
        if (path==="lock.quickshellActive") return !get("lock.useHyprlock",source);
        if (path==="background.widgets.clock.freePlacement") return get("background.widgets.clock.placementStrategy",source)==="free";
        if (path==="background.widgets.weather.freePlacement") return get("background.widgets.weather.placementStrategy",source)==="free";
        if (!source && Object.prototype.hasOwnProperty.call(pending,path)) return pending[path];
        let object = source || Config.options;
        for (const key of path.split(".")) {
            if (object === null || object === undefined) return undefined;
            object = object[key];
        }
        return object;
    }
    function copy(value) { return value === undefined ? undefined : JSON.parse(JSON.stringify(value)); }
    function entry(path) {
        if (path==="lock.quickshellActive") return {label:"Quickshell lock selected"};
        if (path==="background.widgets.clock.freePlacement" || path==="background.widgets.weather.freePlacement") return {label:"Free placement selected"};
        return entryIndex[path];
    }
    function category(id) { return categories.find(c => c.id === id) || categories[0]; }
    function groups(categoryId) {
        const result = [];
        for (const e of actions.concat(visibleEntries()).filter(e => e.category === categoryId && e.group && e.group !== Layout.advancedId))
            if (!result.some(g => g.id === e.group)) result.push({id:e.group, title:(Layout.links[e.group] || {}).title || e.groupTitle, count:entries.filter(s => s.group === e.group).length});
        if ((Layout.advanced[categoryId] || []).length) result.push({id:Layout.advancedId,title:"Advanced",count:0});
        return result;
    }
    function parentGroup(group) {
        if (group === "sleep.schedule" || group === "sleep.tonight") return "";
        if (Layout.parentGroups[group]!==undefined) return Layout.parentGroups[group];
        for (const parent of Object.keys(Layout.families)) if (Layout.families[parent].includes(group)) return parent;
        return "";
    }
    function linkAvailable(categoryId,group) {
        const observed=revision;
        return !(group===Layout.advancedId && !sections(categoryId,group).length)
            && !(Layout.linkConditions[group] || []).some(condition => !conditionMet(condition));
    }
    function link(categoryId,group,includeUnavailable) {
        if (!includeUnavailable && !linkAvailable(categoryId,group)) return null;
        const source=groups(categoryId).find(g => g.id===group);
        if (!source) return null;
        const detail=Layout.links[group] || {};
        return {kind:"link",group:group,title:detail.title || source.title,icon:detail.icon || category(categoryId).icon,summary:detail.summary || "",valuePath:detail.valuePath || "",emptyValue:detail.emptyValue || ""};
    }
    function sections(categoryId,groupId,includeUnavailable) {
        const promoted=new Set(promotedPaths(categoryId));
        const definitions=groupId===Layout.advancedId ? Layout.advanced[categoryId] || [] : groupId ? Layout.subpages[groupId] || [{title:"",items:["@"+groupId]}] : (Layout.pages[categoryId] || []).concat((Layout.advanced[categoryId] || []).length ? [{title:"",items:[">"+Layout.advancedId]}] : []);
        const direct=new Set();
        function expand(path) {
            if (path.startsWith(">")) {
                const item=link(categoryId,path.slice(1),includeUnavailable);
                return item ? [item] : [];
            }
            if (!path.startsWith("@")) {
                const e=visibleEntries().find(e => e.path===path && e.category===categoryId);
                if (!e || direct.has(path) || (!includeUnavailable && !available(e))) return [];
                direct.add(path);return [{kind:"preference",setting:e}];
            }
            const group=path.slice(1);
            const options=preferences(categoryId,group).filter(e => !promoted.has(e.path) && !direct.has(e.path) && (includeUnavailable || available(e)));
            return options.map(e => { direct.add(e.path);return {kind:"preference",setting:e}; });
        }
        function resetPathsFor(section) {
            const paths=(section.resetPaths || []).slice();
            for (const item of section.items) {
                if (item.startsWith(">")) continue;
                if (item.startsWith("@")) {
                    const group=item.slice(1);
                    for (const e of preferences(categoryId,group)) if (!promoted.has(e.path)) paths.push(e.path);
                } else paths.push(item);
            }
            return Array.from(new Set(paths));
        }
        return definitions.map(section => ({
            category:categoryId,
            title:section.title,
            icon:section.icon || Layout.sectionIcons[section.title] || "",
            tool:section.tool || "",
            editor:section.editor || "",
            resetEnabled:section.reset!==false,
            resetPaths:resetPathsFor(section),
            resetPrefix:section.resetPrefix || "",
            items:section.items.reduce((all,path) => all.concat(expand(path)),[]).filter(item => (section.editor!=="barUtilities" || item.kind!=="preference" || !item.setting.path.startsWith("bar.utilButtons.")) && section.editor!=="clockAppearance")
        })).filter(section => section.tool || section.editor || section.items.length);
    }
    function sectionEntries(section) {
        const paths=new Set((section.items || []).filter(item => item.kind==="preference").map(item => item.setting.path).concat(section.resetPaths || []));
        if (section.resetPrefix) for (const e of visibleEntries()) if (e.path.startsWith(section.resetPrefix)) paths.add(e.path);
        if (paths.has("bar.bottom")) paths.add("bar.vertical");
        return Array.from(paths).map(path => entry(path)).filter(e => e && !e.readOnly);
    }
    function sectionChanged(section) {
        const observed=revision;
        return sectionEntries(section).some(e => changed(e));
    }
    function resetSection(section) {
        for (const e of sectionEntries(section)) if (changed(e)) reset(e);
    }
    function preferences(categoryId, groupId) { return visibleEntries().filter(e => e.category === categoryId && (!groupId || e.group === groupId)); }
    // Search links open the page where the preference is visibly presented.
    function destination(e) {
        const top=sections(e.category,"");
        if (top.some(s => s.items.some(i => i.kind==="preference" && i.setting.path===e.path))) return "";
        const candidates=[Layout.advancedId].concat(Object.keys(Layout.subpages),groups(e.category).map(g => g.id));
        for (const group of candidates) if (sections(e.category,group).some(s => s.items.some(i => i.kind==="preference" && i.setting.path===e.path))) return group;
        return "";
    }
    function canonicalGroup(categoryId,groupId) {
        if (groupId==="background.widgets.clock.digital.font") return "";
        if (categoryId === "sleep" && (groupId === "sleep.schedule" || groupId === "sleep.tonight")) return groupId;
        if (!groupId || categoryId==="about") return "";
        if (groupId===Layout.advancedId) return sections(categoryId,groupId).length ? groupId : "";
        if (actions.some(a => a.category===categoryId && a.group===groupId)) return groupId;
        const visited=new Set();
        const visit=parent => {
            if (visited.has(parent)) return false;
            visited.add(parent);
            for (const section of sections(categoryId,parent)) for (const item of section.items) {
                if (item.kind!=="link" || item.group.startsWith("tools.")) continue;
                if (item.group===groupId || visit(item.group)) return true;
            }
            return false;
        };
        return visit("") ? groupId : "";
    }
    function toolActionFor(path) {
        if (path.startsWith("borgIntelligence.")) return "tools.borg";
        if (path.startsWith("homeAssistant.")) return "tools.home";
        if (path==="background.wallpaperPath") return "tools.wallpaper";
        if (path==="appearance.steamGridDb.enabled") return "tools.steamgriddb";
        return "";
    }
    function declaredDestination(e) {
        const promoted=promotedPaths(e.category);
        const contains=sections => sections.some(section => section.items.some(path => path===e.path || (path==="@"+e.group && !promoted.includes(e.path))));
        if (contains(Layout.pages[e.category] || [])) return "";
        if (contains(Layout.advanced[e.category] || [])) return Layout.advancedId;
        for (const group of Object.keys(Layout.subpages)) if (contains(Layout.subpages[group])) return group;
        return "";
    }
    function search(query) {
        const terms=query.toLowerCase().trim().split(/\s+/).filter(Boolean);
        if (!terms.length) return [];
        return visibleEntries().concat(actions).filter(e => {
            const owned=toolPaths.filter(path => toolActionFor(path)===e.path).map(path => entry(path)).filter(Boolean);
            const text=[e.label,e.description,e.groupTitle,category(e.category).title,e.path].concat(owned.reduce((all,item) => all.concat([item.path,item.label,item.description]),[])).map(value => Translation.tr(value || "")).join(" ").toLowerCase();
            return terms.every(term => text.includes(term));
        }).map(e => {
            if (e.path.startsWith("background.widgets.clock.digital.font.") && available(e))
                return Object.assign({},e,{type:"action",group:""});
            if (available(e) || e.type==="action") return e;
            const unmet=(e.conditions || []).find(condition => !conditionMet(condition));
            const prerequisitePath=String(unmet || "").split("||")[0].trim().replace(/^!/,"").split("=")[0];
            const prerequisite=visibleEntries().find(item => item.path===prerequisitePath) || e;
            return Object.assign({},e,{type:"action",category:prerequisite.category,group:declaredDestination(prerequisite),description:Translation.tr("Requires: %1").arg(Translation.tr(prerequisite.label))});
        });
    }
    function choices(e) {
        if (e.dynamicChoices === "language") return [{name:Translation.tr("Auto (System)"),value:"auto"}].concat(Translation.allAvailableLanguages.map(v => ({name:v,value:v})));
        if (e.dynamicChoices === "musicPlayer") return [{name:Translation.tr("Selected media player"),value:""}].concat(MusicAssistant.availablePlayers.map(p=>({name:p.name,value:p.player_id})));
        if (e.dynamicChoices === "area") return HomeAssistant.areaChoices.map(a => ({name:a.name,value:a.area_id}));
        return (e.choices || []).map(c => ({name:Translation.tr(c.name),value:c.value}));
    }
    function conditionMet(condition) {
        if (condition.includes("||")) return condition.split("||").some(part => conditionMet(part.trim()));
        if (condition.startsWith("!")) return !get(condition.slice(1));
        const equals=condition.indexOf("=");
        if (equals!==-1) return String(get(condition.slice(0,equals)))===condition.slice(equals+1);
        return !!get(condition);
    }
    function available(e) { const observed=revision; return (e.conditions || []).every(conditionMet); }
    function changed(e) { const observed = revision; return JSON.stringify(get(e.path)) !== JSON.stringify(get(e.path, SettingsDefaults.options)); }
    function valid(path,value) {
        errorPath=path; errorAction="edit";
        const e = entry(path);
        if (!e || e.readOnly || !Config.ready) { error=Translation.tr("This setting is unavailable."); return false; }
        if (e.type === "bool" && typeof value !== "boolean") return false;
        if (e.type === "string" && typeof value !== "string") return false;
        if (e.type.startsWith("list") && !Array.isArray(value)) return false;
        if (path==="bar.utilButtons.order" && (value.some(key => !Utilities.item(key)) || new Set(value).size!==value.length)) { error=Translation.tr("Choose each bar button once."); return false; }
        if (path==="ai.extraModels" && value.some(item => !item || typeof item!=="object" || !String(item.name || "").trim() || !String(item.model || "").trim() || !/^https?:\/\//.test(item.endpoint || ""))) { error=Translation.tr("Each model needs a name, model ID and http:// or https:// endpoint."); return false; }
        if (path==="sidebar.quickToggles.android.toggles" && value.some(item => !item || typeof item!=="object" || !item.type || !Number.isInteger(item.size) || item.size<1 || item.size>5)) { error=Translation.tr("Each quick toggle needs a type and a size between 1 and 5."); return false; }
        if (e.type.startsWith("list<string>") && value.some(v => typeof v !== "string")) return false;
        if (["int","real"].includes(e.type) && (!Number.isFinite(value) || (e.type === "int" && !Number.isInteger(value)) || value < e.min || value > e.max)) {
            error = Translation.tr("Enter a value between %1 and %2.").arg(e.min).arg(e.max); return false;
        }
        if (["light.night.from","light.night.to"].includes(path) && !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) { error=Translation.tr("Use a 24-hour time, such as 19:00."); return false; }
        if (path==="homeAssistant.url" && value && !/^https?:\/\//.test(value)) { error=Translation.tr("Use an http:// or https:// server address."); return false; }
        if (e.picker==="color" && value && !/^#[a-f\d]{6}$/i.test(value)) { error=Translation.tr("Use a six-digit color, such as #4f8c79."); return false; }
        if (e.choices?.length && !e.choices.some(choice => choice.value===value)) { error=Translation.tr("Choose a listed option."); return false; }
        return true;
    }
    function write(path,value,record) {
        if (!valid(path,value)) return false;
        const old=copy(get(path));
        if (record!==false && JSON.stringify(old)!==JSON.stringify(value)) history=history.concat([{path:path,value:old}]).slice(-40);
        const next=Object.assign({},pending);
        if (JSON.stringify(get(path,Config.options))===JSON.stringify(value)) delete next[path];
        else next[path]=copy(value);
        pending=next;
        clearDraft(path);
        revision++;
        error="";
        return true;
    }
    // A designer gesture changes several axes as one validated undo transaction.
    function writeBatch(changes,record) {
        const paths=Object.keys(changes);
        for (const path of paths) if (!valid(path,changes[path])) return false;
        const previous={};
        const next=Object.assign({},pending);
        for (const path of paths) {
            const old=copy(get(path));
            if (JSON.stringify(old)!==JSON.stringify(changes[path])) previous[path]=old;
            if (JSON.stringify(get(path,Config.options))===JSON.stringify(changes[path])) delete next[path];
            else next[path]=copy(changes[path]);
        }
        if (record!==false && Object.keys(previous).length)
            history=history.concat([{changes:previous}]).slice(-40);
        pending=next;
        for (const path of paths) clearDraft(path);
        revision++;
        error="";
        return true;
    }
    function discardAll() {
        transientClockFontSize=NaN;
        pending=({}); drafts=({}); draftErrors=({}); pendingAppearanceMode=""; history=[]; error=""; revision++;
        discarded();
    }
    function saveAll() {
        if (committing) return false;
        error=""; errorPath=""; errorAction="edit";
        if (Object.keys(draftErrors).length) { errorPath=Object.keys(draftErrors)[0]; error=draftErrors[errorPath]; return false; }
        const changes=Object.assign({},pending);
        for (const path of Object.keys(drafts)) {
            let value=copy(drafts[path]);
            const e=entry(path);
            if (path==="bar.utilButtons.order" && value?.utilityToolbar) {
                const keys=value.keys;
                changes[path]=keys.concat(Utilities.ordered(get(path)).filter(key => !keys.includes(key)));
                for (const utility of Utilities.definitions) changes["bar.utilButtons."+utility.key]=keys.includes(utility.key);
                continue;
            }
            if (!e) { errorPath=path; error=Translation.tr("An edit could not be saved."); return false; }
            if (["int","real"].includes(e.type) && typeof value==="string") value=value.trim() ? Number(value) : NaN;
            changes[path]=value;
        }
        for (const path of Object.keys(changes)) if (!valid(path,changes[path])) {
            if (!error) error=Translation.tr("Check %1 before saving.").arg(Translation.tr(entry(path)?.label || path));
            return false;
        }
        errorPath=""; errorAction="retry";
        if (Config.invalidFile) { error=Translation.tr("The settings file could not be read. Your edits are kept; fix the file, then try again."); return false; }
        if (!Config.ready) { error=Translation.tr("Settings are still loading. Your edits are kept; try again in a moment."); return false; }
        if (Config.blockWrites) { error=Translation.tr("Settings writes are temporarily blocked. Your edits are kept."); return false; }
        const needsWrite=Object.keys(changes).some(path => JSON.stringify(get(path,Config.options))!==JSON.stringify(changes[path]));
        const value=path => Object.prototype.hasOwnProperty.call(changes,path) ? changes[path] : get(path);
        if (value("battery.critical")>value("battery.low") || (value("battery.automaticSuspend") && value("battery.suspend")>value("battery.critical"))) {
            errorPath="battery.low"; errorAction="edit"; error=Translation.tr("Battery thresholds must be ordered: suspend ≤ critical ≤ low."); return false;
        }
        const baseline={};
        for (const path of Object.keys(changes)) baseline[path]=copy(get(path,Config.options));
        submittedBaseline=baseline;
        submitted=copy(changes);
        try {
            for (const path of Object.keys(changes)) {
                const keys=path.split("."); let object=Config.options;
                for (let i=0;i<keys.length-1;i++) object=object[keys[i]];
                object[keys[keys.length-1]]=copy(changes[path]);
            }
        } catch (err) { Config.restoreOptions(submittedBaseline,submitted);submittedBaseline=({});errorPath=""; errorAction="retry"; error=Translation.tr("Settings could not be updated. Your edits are kept.")+" "+String(err); return false; }
        submitted=copy(changes); submittedDrafts=copy(drafts); submittedMode=pendingAppearanceMode;
        submittedTheme=!!submittedMode || Object.keys(changes).some(path => path==="background.wallpaperPath" || path.startsWith("appearance.palette.") || path.startsWith("appearance.wallpaperTheming."));
        committing=true;
        if (needsWrite) Config.flush();
        else Qt.callLater(() => root.afterPersisted(true));
        return true;
    }
    function reset(e) { return write(e.path, copy(get(e.path,SettingsDefaults.options))); }
    function undo() {
        if (!history.length) return;
        const change = history[history.length-1];
        const restored=change.changes ? writeBatch(change.changes,false)
            : change.appearanceMode ? setAppearanceMode(change.value,false) : write(change.path,change.value,false);
        if (restored) history=history.slice(0,-1);
    }
}
