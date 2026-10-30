pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath
    // A Settings window is a separate Quickshell process. Its override never
    // touches the generated file or the shell process, and file reloads retain
    // their own baseline while a draft is being previewed.
    signal colorsLoaded()
    property var committedColors: ({})
    property var fallbackColors: ({})
    property bool hasCommittedColors: false
    property bool committedDarkMode: true
    property bool settingsPreviewEnabled: false
    property var settingsPreviewColors: null
    onSettingsPreviewColorsChanged: applyEffectiveColors()

    function initializeColors() {
        if (Object.keys(fallbackColors).length) return;
        const colors = {};
        for (const key in Appearance.m3colors) {
            if (!key.startsWith("m3")) continue;
            const value = String(Appearance.m3colors[key]);
            if (!/^#[0-9a-f]{6,8}$/i.test(value)) continue;
            const role = key.slice(2).replace(/[A-Z]/g, letter => "_" + letter.toLowerCase());
            colors[role] = value;
        }
        fallbackColors = colors;
        if (!hasCommittedColors) {
            committedColors = colors;
            committedDarkMode = Appearance.m3colors.darkmode;
        }
    }
    Component.onCompleted: initializeColors()

    function applyEffectiveColors() {
        initializeColors();
        const colors = Object.assign({}, committedColors, settingsPreviewColors || {});
        for (const key of Object.keys(colors)) {
            const camelCaseKey = key.replace(/_([a-z])/g, (match, letter) => letter.toUpperCase());
            const m3Key = "m3" + camelCaseKey;
            if (m3Key in Appearance.m3colors) Appearance.m3colors[m3Key] = colors[key];
        }
        Appearance.m3colors.darkmode = Appearance.m3colors.m3background.hslLightness < 0.5;
    }

    function reapplyTheme() {
        themeFileView.reload()
    }

    function applyColors(fileContent) {
        let json;
        try { json = JSON.parse(fileContent); }
        catch (error) { return; } // Keep the last complete theme during atomic writes.
        if (!json || !json.background || !json.primary) return;
        initializeColors();
        committedColors = Object.assign({}, fallbackColors, json);
        committedDarkMode = Qt.color(json.background).hslLightness < 0.5;
        hasCommittedColors = true;
        applyEffectiveColors();
        colorsLoaded();
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            root.applyColors(themeFileView.text())
        }
    }

	FileView {
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            const fileContent = themeFileView.text()
            root.applyColors(fileContent)
        }
        onLoadFailed: root.resetFilePathNextTime();
    }

    function toggleLightDark() {
        const currentlyDark = Appearance.m3colors.darkmode;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", currentlyDark ? "light" : "dark", "--noswitch"]);
    }

    GlobalShortcut {
        name: "toggleLightDark"
        description: "Toggles between dark theme and light theme"

        onPressed: {
            root.toggleLightDark();
        }
    }

    IpcHandler {
        target: "theme"

        function toggleLightDark(): void {
            root.toggleLightDark();
        }
    }
}
