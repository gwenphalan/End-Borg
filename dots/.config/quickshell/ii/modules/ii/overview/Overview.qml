import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    SpotlightController {
        id: state
        keyRouter: keyboardRoot
        onFocusRequested: intentional => {
            if (intentional) searchBar.focusInput();
            else keyboardRoot.forceActiveFocus();
        }
    }
    Binding { target: LauncherSearch; property: "contextMode"; value: state.mode }
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (state.open) {
                panelWindow.screen = Hyprland.focusedMonitor?.name
                    ? Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0]
                    : Quickshell.screens[0];
                focusGrabDelay.restart();
                Qt.callLater(() => keyboardRoot.forceActiveFocus());
            } else {
                focusGrabDelay.stop();
                focusGrab.active = false;
            }
        }
    }
    Timer {
        id: focusGrabDelay
        interval: 16
        onTriggered: if (state.open) focusGrab.active = true
    }
    HyprlandFocusGrab {
        id: focusGrab
        windows: [panelWindow]
        onCleared: if (state.open) state.close()
    }

    PanelWindow {
        id: panelWindow
        visible: state.presented
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: state.presented ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        MouseArea { anchors.fill: parent; onClicked: state.close() }
        FocusScope {
            id: keyboardRoot
            anchors.fill: parent
            focus: true
            function routeKey(event) {
                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    if (event.modifiers & Qt.MetaModifier)
                        state.toggle("overview");
                    else if (!GlobalStates.superDown)
                        state.cycleMode();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    if (state.menuOpen) state.dismissMenus();
                    else state.close();
                    event.accepted = true;
                } else if (!searchBar.input.activeFocus && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                           && event.text && event.text.charCodeAt(0) >= 32) {
                    searchBar.insertText(event.text);
                    event.accepted = true;
                } else if (!searchBar.input.activeFocus && event.key === Qt.Key_Backspace) {
                    searchBar.focusInput();
                    searchBar.input.remove(Math.max(0, searchBar.input.cursorPosition - 1), searchBar.input.cursorPosition);
                    state.edit(searchBar.input.text);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down && !searchBar.input.activeFocus
                           && !apps.navigationActive && !results.navigationActive) {
                    focusLower();
                    event.accepted = true;
                }
            }
            function focusLower() {
                if (state.resultsExpanded || state.mode === "clipboard") results.focusFirst();
                else if (state.mode === "apps") apps.focusFirst();
            }
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => routeKey(event)
            // ShortcutOverride precedes TextInput, Button, and result-item key handlers.
            Keys.onShortcutOverride: event => {
                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab || event.key === Qt.Key_Escape)
                    event.accepted = true;
            }
            Column {
                id: content
                anchors.top: parent.top
                anchors.topMargin: 0
                anchors.horizontalCenter: parent.horizontalCenter
                width: panelWindow.width - 32
                SpotlightSearchBar {
                    id: searchBar
                    z: 2
                    controller: state
                    availableWidth: content.width
                    anchors.horizontalCenter: parent.horizontalCenter
                    onMoveFocusDown: keyboardRoot.focusLower()
                }
                Item {
                    id: viewHost
                    clip: true
                    width: content.width
                    height: Math.max(120, panelWindow.height - content.y - searchBar.height - 32)
                    readonly property real drawerWidth: Math.min(600, width)
                    readonly property real drawerHeight: Math.min(560, height)
                    readonly property bool overviewActive: state.mode === "overview" && !state.resultsExpanded
                    readonly property bool appsActive: state.mode === "apps" && !state.resultsExpanded
                    readonly property bool resultsActive: state.resultsExpanded || state.mode === "clipboard"
                    SpotlightSurface {
                        id: lowerSurface
                        controller: state
                        anchors.horizontalCenter: parent.horizontalCenter
                        targetWidth: viewHost.overviewActive && overviewLoader.item
                            ? overviewLoader.item.implicitWidth : viewHost.drawerWidth
                        targetHeight: viewHost.overviewActive && overviewLoader.item
                            ? overviewLoader.item.implicitHeight : viewHost.drawerHeight
                        surfaceColor: Appearance.colors.colBackgroundSurfaceContainer
                        surfaceRadius: Appearance.rounding.large + 10
                        shown: state.open && state.panelsReady
                        SpotlightPanel {
                            id: apps
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: viewHost.drawerWidth
                            height: viewHost.drawerHeight
                            opacity: viewHost.appsActive ? 1 : 0
                            visible: opacity > 0
                            enabled: viewHost.appsActive
                            Behavior on opacity {
                                NumberAnimation { duration: state.reducedMotion ? 0 : Appearance.animation.elementMoveFast.duration }
                            }
                            controller: state
                            menuLayer: viewHost
                        }
                        SpotlightResults {
                            id: results
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: viewHost.drawerWidth
                            height: viewHost.drawerHeight
                            opacity: viewHost.resultsActive ? 1 : 0
                            visible: opacity > 0
                            enabled: viewHost.resultsActive
                            Behavior on opacity {
                                NumberAnimation { duration: state.reducedMotion ? 0 : Appearance.animation.elementMoveFast.duration }
                            }
                            controller: state
                            menuLayer: viewHost
                            onMoveFocusUp: searchBar.focusInput()
                        }
                        Loader {
                            id: overviewLoader
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: item?.implicitWidth ?? 0
                            height: item?.implicitHeight ?? 0
                            opacity: viewHost.overviewActive ? 1 : 0
                            visible: opacity > 0
                            enabled: viewHost.overviewActive
                            Behavior on opacity {
                                NumberAnimation { duration: state.reducedMotion ? 0 : Appearance.animation.elementMoveFast.duration }
                            }
                            active: state.overviewInitialized
                            asynchronous: true
                            sourceComponent: SpotlightOverviewView {
                                controller: state
                                screen: panelWindow.screen
                                availableWidth: viewHost.width
                                availableHeight: viewHost.height
                                captureEnabled: lowerSurface.visible && overviewLoader.visible
                                contentShown: lowerSurface.shown && viewHost.overviewActive
                                contentOpacity: 1
                            }
                        }
                    }
                    SpotlightContextMenu {
                        id: contextMenu
                        controller: state
                        width: viewHost.width
                        height: viewHost.height
                        z: 20
                    }
                }
            }
        }
    }

    function emoji() {
        state.show("apps");
        LauncherSearch.ensurePrefix(Config.options.search.prefix.emojis);
        state.engageSearch();
        searchBar.focusInput();
    }
    IpcHandler {
        target: "search"
        function toggle(): void { state.toggle("apps"); }
        function workspacesToggle(): void { state.toggle("overview"); }
        function close(): void { state.close(); }
        function open(): void { state.show("apps"); }
        function toggleReleaseInterrupt(): void { GlobalStates.superReleaseMightTrigger = false; }
        function clipboardToggle(): void { state.toggle("clipboard"); }
        function emojiToggle(): void { root.emoji(); }
        function cycleMode(): void { state.cycleMode(); }
        function setQuery(text: string): void { state.edit(text); }
        function focusSearch(): void { searchBar.focusInput(); }
        function inspect(): string {
            return JSON.stringify({open: state.open, mode: state.mode, nextMode: state.nextMode,
                queryLength: state.query.length, resultsExpanded: state.resultsExpanded,
                inputFocused: state.inputFocused,
                focusGrabActive: focusGrab.active,
                hiddenExpanded: state.hiddenExpanded, menuOpen: state.menuOpen,
                presented: state.presented, presence: state.presence, windowVisible: panelWindow.visible,
                screen: panelWindow.screen?.name, width: panelWindow.width, height: panelWindow.height,
                surfaceWidth: lowerSurface.width, surfaceHeight: lowerSurface.height,
                lowerSurface: lowerSurface.inspect(),
                searchWidth: searchBar.presentedWidth, searchY: searchBar.presentedY,
                searchContentX: searchBar.inputOffset,
                appMotion: apps.inspect(), resultMotion: results.inspect(),
                contextMenu: contextMenu.inspect(),
                panelProgress: lowerSurface.progress, panelContentOpacity: lowerSurface.contentOpacity,
                resultProgress: viewHost.resultsActive ? lowerSurface.progress : 0, panelsReady: state.panelsReady,
                barReveal: state.barReveal, barExpanded: state.barExpanded, searchShown: state.searchShown,
                appRowSizes: apps.rows.filter(row => row.kind === "apps" && row.section === "apps").map(row => row.apps.length),
                indexedLetters: apps.sectionPositions.filter(section => !!section.letter).length,
                overview: overviewLoader.item?.inspect() ?? null,
                overviewMotion: lowerSurface.inspect(),
                createdAppTiles: state.createdAppTiles});
        }
    }
    GlobalShortcut { name: "searchToggle"; onPressed: state.toggle("apps") }
    GlobalShortcut { name: "overviewWorkspacesClose"; onPressed: state.close() }
    GlobalShortcut { name: "overviewWorkspacesToggle"; onPressed: state.toggle("overview") }
    GlobalShortcut { name: "overviewClipboardToggle"; onPressed: state.toggle("clipboard") }
    GlobalShortcut { name: "overviewEmojiToggle"; onPressed: root.emoji() }
    GlobalShortcut { name: "spotlightSuperPressed"; onPressed: state.pressSuper() }
    GlobalShortcut { name: "spotlightSuperReleased"; onPressed: state.releaseSuper() }
    GlobalShortcut {
        name: "searchToggleRelease"
        onPressed: GlobalStates.superReleaseMightTrigger = true
        onReleased: {
            if (GlobalStates.superReleaseMightTrigger) {
                state.toggle("apps");
            }
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        onPressed: GlobalStates.superReleaseMightTrigger = false
    }
}
