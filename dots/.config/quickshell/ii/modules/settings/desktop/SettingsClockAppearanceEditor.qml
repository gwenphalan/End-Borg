pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// The designer owns transient gestures. Only their release reaches the draft.
ClockAppearanceEditor {
    id:root
    readonly property string prefix:"background.widgets.clock.digital.font."
    readonly property var names:["family","italic","size","weight","width","roundness","letterSpacing"]
    clockFont:{
        const observed=SettingsCatalog.revision;
        const values={};
        for (const name of names) values[name]=SettingsCatalog.get(prefix+name);
        return values;
    }
    wallpaperPath:{
        const observed=SettingsCatalog.revision;
        return String(SettingsCatalog.get("background.wallpaperPath") || "");
    }
    timeFormat:{
        const observed=SettingsCatalog.revision;
        return String(SettingsCatalog.get("time.format") || "hh:mm");
    }
    verticalClock:{
        const observed=SettingsCatalog.revision;
        return !!SettingsCatalog.get("background.widgets.clock.digital.vertical");
    }
    function writeChanges(changes) {
        const paths={};
        for (const name of Object.keys(changes)) if (names.includes(name)) paths[prefix+name]=changes[name];
        return SettingsCatalog.writeBatch(paths);
    }
    onCommitted:changes => {
        if (!writeChanges(changes)) displayFont=clockFont;
    }
    onResetRequested:{
        const paths={};
        for (const name of names) paths[prefix+name]=SettingsCatalog.copy(SettingsCatalog.get(prefix+name,SettingsDefaults.options));
        SettingsCatalog.writeBatch(paths);
    }
}
