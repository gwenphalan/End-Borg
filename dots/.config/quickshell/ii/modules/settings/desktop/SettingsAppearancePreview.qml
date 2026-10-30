pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

// Instantiate once in the Settings process. The generated file and every other
// Quickshell process retain the committed theme until SettingsCatalog saves.
Item {
    id: root
    visible: false
    property var catalog: SettingsCatalog
    property var themeLoader: MaterialThemeLoader
    readonly property bool hasThemeDraft: Object.keys(catalog.pending).some(path =>
        path === "background.wallpaperPath" || path.startsWith("appearance.palette."))
        || !!catalog.pendingAppearanceMode
    readonly property bool previewRequested: hasThemeDraft || (catalog.committing && catalog.submittedTheme)
    readonly property string mode: catalog.appearanceMode
    readonly property string accent: {
        const revision = catalog.revision;
        return String(catalog.get("appearance.palette.accentColor") || "");
    }
    readonly property string wallpaper: {
        const revision = catalog.revision;
        return FileUtils.trimFileProtocol(String(catalog.get("background.wallpaperPath") || ""));
    }
    readonly property string scheme: {
        const revision = catalog.revision;
        return String(catalog.get("appearance.palette.type") || "auto");
    }
    readonly property string requestKey: JSON.stringify([accent, mode, wallpaper, scheme])
    readonly property string python: (Quickshell.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV")
        || FileUtils.trimFileProtocol(Directories.home) + "/.local/state/quickshell/.venv") + "/bin/python"
    property string runningKey: ""
    property string completedKey: ""
    property var cache: ({})
    property string error: ""
    property bool applied: false
    property bool waitingForSavedTheme: false
    readonly property bool busy: refresh.running || generation.running

    function restore() {
        waitingForSavedTheme = false;
        savedThemeTimeout.stop();
        themeLoader.settingsPreviewColors = null;
        applied = false;
        completedKey = "";
        error = "";
    }
    function apply(colors, key) {
        if (!previewRequested || key !== requestKey) return;
        themeLoader.settingsPreviewColors = colors;
        applied = true;
        completedKey = key;
        error = "";
    }
    function updatePreview() {
        if (!previewRequested) {
            if (!waitingForSavedTheme) restore();
            return;
        }
        if (cache[requestKey]) { apply(cache[requestKey], requestKey); return; }
        if (generation.running || completedKey === requestKey) return;
        runningKey = requestKey;
        generation.command = [python, Directories.scriptPath + "/settings/appearance_preview.py",
            accent, mode, wallpaper, scheme, Directories.scriptPath + "/colors/scheme_for_image.py"];
        generation.running = true;
    }
    onRequestKeyChanged: refresh.restart()
    onPreviewRequestedChanged: {
        // finishCommit clears several fields synchronously before emitting saved.
        // Defer so the successful save can hand off to its generated file first.
        Qt.callLater(() => { if (previewRequested) refresh.restart(); else updatePreview(); });
    }
    Component.onCompleted: {
        themeLoader.settingsPreviewEnabled = true;
        if (previewRequested) refresh.restart();
    }
    Component.onDestruction: themeLoader.settingsPreviewColors = null

    Timer { id: refresh; interval: 65; onTriggered: root.updatePreview() }
    Timer {
        id: savedThemeTimeout
        interval: 2000
        onTriggered: { if (!root.previewRequested) root.restore(); }
    }
    Connections {
        target: root.catalog
        function onDiscarded() { root.restore(); }
        function onSaved() {
            if (!root.catalog.submittedTheme || root.previewRequested || !root.applied) return;
            root.waitingForSavedTheme = true;
            savedThemeTimeout.restart();
            root.themeLoader.reapplyTheme();
        }
    }
    Connections {
        target: root.themeLoader
        function onColorsLoaded() {
            if (root.waitingForSavedTheme && !root.previewRequested) root.restore();
        }
    }
    Process {
        id: generation
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (!result.colors) throw new Error(result.error || "Theme preview could not be generated");
                    const next = Object.assign({}, root.cache);
                    next[root.runningKey] = result.colors;
                    const keys = Object.keys(next);
                    if (keys.length > 12) delete next[keys[0]];
                    root.cache = next;
                    root.apply(result.colors, root.runningKey);
                } catch (failure) {
                    if (root.previewRequested && root.runningKey === root.requestKey) {
                        root.restore();
                        root.error = String(failure);
                    }
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.previewRequested && root.runningKey !== root.requestKey) refresh.restart();
        }
    }
}
