pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    readonly property bool settingsPreview: Quickshell.env("QS_SETTINGS_PREVIEW") === "1" || MaterialThemeLoader.settingsPreviewEnabled
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var iconsMeta: ({})
    property var launcherLabels: ({})
    property bool iconBuildPending: false
    property bool iconSwitchPending: false
    property string iconRegistrySignature: ""
    function scheduleIconRegistryCheck() {
        if (settingsPreview) return;
        // Generated desktop overrides may notify the model without adding an app.
        const signature = JSON.stringify(Array.from(root.list).map(app => app.id).sort());
        if (signature === root.iconRegistrySignature) return;
        root.iconRegistrySignature = signature;
        iconDebounce.restart();
    }
    Connections {
        target: Config.options.appearance.steamGridDb
        function onEnabledChanged() { if (Config.ready && !root.settingsPreview) iconDebounce.restart(); }
    }
    Connections {
        target: BorgIntelligence
        function onFinished(operation, succeeded, result, error) {
            if (operation === "refresh_launcher" && succeeded) {
                labelCache.reload();
                iconsMetaFile.reload();
            }
        }
    }
    FileView {
        id: labelCache
        path: Directories.state + "/borg-intelligence/launcher-labels.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            try { root.launcherLabels = JSON.parse(text()).labels || {}; } catch (error) {}
        }
        onFileChanged: reload()
    }
    Timer {
        id: iconDebounce
        interval: 1800
        running: !root.settingsPreview
        onTriggered: {
            if (iconBuilder.running) root.iconBuildPending = true;
            else iconBuilder.running = true;
        }
    }
    Process {
        id: globalIconSwitcher
        command: [FileUtils.trimFileProtocol(Directories.home) + "/.local/state/quickshell/.venv/bin/python",
                  Directories.scriptPath + "/global_app_icons.py",
                  "--mode", Appearance.m3colors.darkmode ? "dark" : "light"]
        onExited: (exitCode, exitStatus) => {
            if (root.settingsPreview) { root.iconSwitchPending = false; root.iconBuildPending = false; return; }
            if (exitCode !== 0) {
                root.iconSwitchPending = false;
                return;
            }
            if (root.iconSwitchPending && !iconBuilder.running) {
                root.iconSwitchPending = false;
                globalIconSwitcher.running = true;
            }
        }
    }
    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() {
            if (root.settingsPreview) return;
            if (!Object.keys(root.iconsMeta).length) return;
            if (iconBuilder.running || globalIconSwitcher.running) root.iconSwitchPending = true;
            else globalIconSwitcher.running = true;
        }
    }
    Process {
        id: iconBuilder
        command: ["nice", "-n", "15", "env", "OPENBLAS_NUM_THREADS=1", "OMP_NUM_THREADS=1",
                  FileUtils.trimFileProtocol(Directories.home) + "/.local/state/quickshell/.venv/bin/python",
                  Directories.scriptPath + "/process_all_icons.py", "--no-publish"]
        onExited: (exitCode, exitStatus) => {
            if (root.settingsPreview) { root.iconSwitchPending = false; root.iconBuildPending = false; return; }
            if (exitCode !== 0) {
                root.iconBuildPending = false;
                return;
            }
            if (globalIconSwitcher.running) root.iconSwitchPending = true;
            else globalIconSwitcher.running = true;
            if (root.iconBuildPending) {
                root.iconBuildPending = false;
                iconDebounce.restart();
            }
        }
    }
    onListChanged: scheduleIconRegistryCheck()
    function resolveAdaptiveIcon(appId, iconName, appName) {
        const entry = getMetaEntry(appId) || getMetaEntry(iconName) || getMetaEntry(appName);
        const resolved = (Appearance.m3colors.darkmode ? entry?.path_dark : entry?.path_light)
            || (iconName && (iconName.startsWith("/") || iconExists(iconName))
            ? iconName : guessIcon(appId || iconName || appName));
        return {
            source: resolved.startsWith("/") ? "file://" + resolved
                : Quickshell.iconPath(resolved, "application-x-executable"),
            fill: entry?.fill ?? shouldFill(resolved)
        };
    }

    FileView {
        id: iconsMetaFile
        path: Qt.resolvedUrl("file:///home/gwenp/.cache/quickshell/game_icons/app_icons_meta.json")
        watchChanges: true
        onLoaded: {
            try {
                root.iconsMeta = JSON.parse(iconsMetaFile.text());
            } catch(e) {}
        }
        onFileChanged: reload()
    }

    function getMetaEntry(str) {
        if (!str || !root.iconsMeta) return null;
        if (root.iconsMeta[str]) return root.iconsMeta[str];
        let lower = str.toLowerCase();
        if (root.iconsMeta[lower]) return root.iconsMeta[lower];
        let stripped = lower.replace(".desktop", "").replace(/\s+/g, "");
        if (root.iconsMeta[stripped]) return root.iconsMeta[stripped];
        return null;
    }

    function shouldFill(str) {
        let entry = getMetaEntry(str);
        if (entry && entry.fill !== undefined) return entry.fill;
        return false;
    }

    function isGame(str) {
        let entry = getMetaEntry(str);
        if (entry && entry.is_game !== undefined) return entry.is_game;
        return false;
    }

    function contrastRole(str) {
        let entry = getMetaEntry(str);
        if (entry && entry.bg_role) return entry.bg_role;
        return "default";
    }

    function containerColor(str, isHovered, isSelected) {
        if (isSelected || isHovered) return Appearance.colors.colPrimaryContainerActive;
        let role = contrastRole(str);
        if (role === "highContrast") return Appearance.colors.colSurfaceContainerHighest;
        return Appearance.colors.colSecondaryContainer;
    }

    // DesktopEntries reports a new values snapshot after launcher changes. Keep
    // its order while removing duplicate IDs in one pass.
    readonly property list<DesktopEntry> list: {
        const seen = new Set();
        return Array.from(DesktopEntries.applications.values).filter(app => {
            if (seen.has(app.id)) return false;
            seen.add(app.id);
            return true;
        });
    }

    // The model provides a whole list, not a changed-entry signal. Rebuild the
    // lightweight wrapper list but only prepare fuzzy text for new/renamed apps.
    property var preparedNameCache: new Map()
    property var preparedIconCache: new Map()
    function prepareEntries(entries, field, cache) {
        const activeIds = new Set();
        const prepared = entries.map(entry => {
            const id = entry.id;
            const value = `${entry[field]} `;
            activeIds.add(id);
            let cached = cache.get(id);
            if (!cached || cached.value !== value) {
                cached = { value: value, name: Fuzzy.prepare(value) };
                cache.set(id, cached);
            }
            return { name: cached.name, entry: entry };
        });
        for (const id of cache.keys()) {
            if (!activeIds.has(id)) cache.delete(id);
        }
        return prepared;
    }
    readonly property var preppedNames: prepareEntries(list, "name", preparedNameCache)
    readonly property var preppedIcons: prepareEntries(list, "icon", preparedIconCache)

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        if (root.sloppySearch) {
            const results = list.map(obj => ({
                entry: obj,
                score: Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preppedNames, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0)
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        // Check studio/analyzed metadata first
        let meta = getMetaEntry(str);
        if (meta && (meta.path_dark || meta.path_light)) {
            return (Appearance.m3colors.darkmode ? meta.path_dark : meta.path_light)
                || meta.path_dark || meta.path_light;
        }

        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) {
            if (entry.icon && entry.icon.startsWith("/")) return entry.icon;
            let entryMeta = getMetaEntry(entry.id) || getMetaEntry(entry.icon) || getMetaEntry(entry.name);
            if (entryMeta && (entryMeta.path_dark || entryMeta.path_light))
                return (Appearance.m3colors.darkmode ? entryMeta.path_dark : entryMeta.path_light)
                    || entryMeta.path_dark || entryMeta.path_light;
            return entry.icon;
        }


        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }
}
