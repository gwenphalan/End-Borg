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
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var iconsMeta: ({})
    property var launcherLabels: ({})
    property bool iconBuildPending: false
    property bool iconSwitchPending: false
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
        onLoadedChanged: {
            try { root.launcherLabels = JSON.parse(text()).labels || {}; } catch (error) {}
        }
        onFileChanged: reload()
    }
    Timer {
        id: iconDebounce
        interval: 1200
        running: true
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
        onExited: {
            if (root.iconSwitchPending && !iconBuilder.running) {
                root.iconSwitchPending = false;
                globalIconSwitcher.running = true;
            }
        }
    }
    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() {
            if (!Object.keys(root.iconsMeta).length) return;
            if (iconBuilder.running || globalIconSwitcher.running) root.iconSwitchPending = true;
            else globalIconSwitcher.running = true;
        }
    }
    Process {
        id: iconBuilder
        command: [FileUtils.trimFileProtocol(Directories.home) + "/.local/state/quickshell/.venv/bin/python",
                  Directories.scriptPath + "/process_all_icons.py"]
        onExited: {
            if (globalIconSwitcher.running) root.iconSwitchPending = true;
            else globalIconSwitcher.running = true;
            if (root.iconBuildPending) {
                root.iconBuildPending = false;
                iconDebounce.restart();
            }
        }
    }
    onListChanged: iconDebounce.restart()
    function resolveAdaptiveIcon(appId, iconName, appName) {
        const nativeIcons = {
            "alacritty": "/usr/share/pixmaps/Alacritty.svg",
            "btop": "/usr/share/icons/hicolor/scalable/apps/btop.svg"
        };
        const native = nativeIcons[String(appId || "").replace(/\.desktop$/i, "").toLowerCase()];
        const entry = getMetaEntry(appId) || getMetaEntry(iconName) || getMetaEntry(appName);
        if (native && !(entry?.policy_version >= 6)) return {
            source: "file://" + native,
            fill: false,
            bg_color: Appearance.colors.colSecondaryContainer
        };
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
        onLoadedChanged: {
            try {
                root.iconsMeta = JSON.parse(iconsMetaFile.text());
            } catch(e) {}
        }
        onFileChanged: {
            this.reload();
            try {
                root.iconsMeta = JSON.parse(iconsMetaFile.text());
            } catch(e) {}
        }
    }

    function getMetaEntry(str) {
        if (!str || !root.iconsMeta) return null;
        if (root.iconsMeta[str]) return root.iconsMeta[str];
        let lower = str.toLowerCase();
        if (root.iconsMeta[lower]) return root.iconsMeta[lower];
        let stripped = lower.replace(".desktop", "").replace(/\s+/g, "");
        if (root.iconsMeta[stripped]) return root.iconsMeta[stripped];
        let steamMatch = str.match(/steam_(?:icon|app)_(\d+)/);
        if (steamMatch && root.iconsMeta[steamMatch[1]]) {
            return root.iconsMeta[steamMatch[1]];
        }
        return null;
    }

    function shouldFill(str) {
        let entry = getMetaEntry(str);
        if (entry && entry.fill !== undefined) return entry.fill;
        if (str && (str.includes("game_icons") || str.includes("steam_app") || str.includes("steam_icon") || str.includes("_fill.png"))) return true;
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
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // Deduped list to fix double icons
    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .filter((app, index, self) => 
            index === self.findIndex((t) => (
                t.id === app.id
            ))
    )
    
    readonly property var preppedNames: list.map(a => ({
        name: Fuzzy.prepare(`${a.name} `),
        entry: a
    }))

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))

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
        if (meta && meta.path) {
            return meta.path;
        }

        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) {
            if (entry.icon && entry.icon.startsWith("/")) return entry.icon;
            let entryMeta = getMetaEntry(entry.id) || getMetaEntry(entry.icon) || getMetaEntry(entry.name);
            if (entryMeta && entryMeta.path) return entryMeta.path;
            return entry.icon;
        }

        // Normal substitutions
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
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
