import QtQuick
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import "SpotlightLogic.js" as Logic

Item {
    id: root
    property var keyRouter: null
    property bool superArmed: false
    property bool superChordUsed: false
    property bool overviewInitialized: false
    property bool panelsReady: false
    property bool barExpanded: false
    property bool closeCleanupPending: false
    property int createdAppTiles: 0
    property string mode: "apps"
    readonly property string nextMode: Logic.nextMode(mode)
    readonly property string nextIcon: ({apps: "apps", overview: "view_cozy", clipboard: "content_paste"})[nextMode]
    readonly property string modeIcon: ({apps: "apps", overview: "view_cozy", clipboard: "content_paste"})[mode]
    readonly property string query: LauncherSearch.query
    property bool inputFocused: false
    property bool resultsExpanded: false
    property bool hiddenExpanded: false
    property var scrollPositions: ({})
    property var menuApp: null
    property point menuAnchor: Qt.point(0, 0)
    property bool menuOpen: false
    readonly property bool open: GlobalStates.overviewOpen
    property bool searchShown: false
    property real presence: searchShown ? 1 : 0
    property real barReveal: barExpanded ? 1 : 0
    readonly property bool presented: open || searchShown || presence !== 0 || barReveal !== 0
    readonly property bool reducedMotion: Config.options.launcher.reducedMotion
        || (Qt.styleHints.accessibility?.reduceMotion ?? false)
    readonly property int motionDuration: reducedMotion ? 0 : 240
    readonly property int fastDuration: reducedMotion ? 0 : 120
    readonly property int searchEntranceDuration: reducedMotion ? 0 : 360
    readonly property int panelEntranceDuration: reducedMotion ? 0 : Appearance.animation.clickBounce.duration
    readonly property int exitDuration: reducedMotion ? 0 : 220
    readonly property var entranceCurve: Appearance.animationCurves.expressiveDefaultSpatial
    readonly property var exitCurve: Appearance.animationCurves.emphasizedAccel
    onPresenceChanged: {
        if (!open && presence === 0) finishClose();
    }
    onBarRevealChanged: {
        if (!open && barReveal === 0) finishClose();
    }
    signal focusRequested(bool intentional)
    signal dismissed()

    Behavior on presence {
        id: presenceBehavior
        NumberAnimation {
            duration: presenceBehavior.targetValue === 1 ? root.searchEntranceDuration : root.exitDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: presenceBehavior.targetValue === 1 ? root.entranceCurve : root.exitCurve
        }
    }
    Behavior on barReveal {
        id: barRevealBehavior
        NumberAnimation {
            duration: root.reducedMotion ? 0 : barRevealBehavior.targetValue === 1 ? Appearance.animation.elementMoveSmall.duration : root.exitDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: barRevealBehavior.targetValue === 1 ? Appearance.animation.elementMoveSmall.bezierCurve : root.exitCurve
        }
    }
    Timer {
        id: panelEntrance
        interval: root.searchEntranceDuration / 3
        onTriggered: {
            root.barExpanded = root.open;
            panelFollow.restart();
        }
    }
    Timer {
        id: panelFollow
        interval: root.reducedMotion ? 0 : 28
        onTriggered: root.panelsReady = root.open
    }
    Timer {
        id: barExit
        interval: root.reducedMotion ? 0 : 28
        onTriggered: {
            root.barExpanded = false;
            searchExit.restart();
        }
    }
    Timer {
        id: searchExit
        interval: root.reducedMotion ? 0 : 40
        onTriggered: root.searchShown = false
    }
    function closeMenu() { menuOpen = false; }
    function openMenu(app, point) {
        if (menuOpen) {
            closeMenu();
            pendingMenu.app = app;
            pendingMenu.point = point;
            pendingMenu.restart();
        } else {
            menuApp = app;
            menuAnchor = point;
            menuOpen = true;
        }
    }
    Timer {
        id: pendingMenu
        property var app: null
        property point point
        interval: root.exitDuration
        onTriggered: {
            root.menuApp = app;
            root.menuAnchor = point;
            root.menuOpen = true;
        }
    }
    function dismissMenus() { pendingMenu.stop(); closeMenu(); }
    function finishClose() {
        if (open || searchShown || presence !== 0 || barReveal !== 0) return;
        inputFocused = false;
        resultsExpanded = false;
        LauncherSearch.query = "";
        if (closeCleanupPending) {
            closeCleanupPending = false;
            dismissed();
        }
    }
    function setMode(value) {
        if (!["apps", "overview", "clipboard"].includes(value)) return;
        dismissMenus();
        mode = value;
        if (value === "overview") overviewInitialized = true;
        resultsExpanded = false;
        inputFocused = false;
        if (mode === "clipboard") Cliphist.refresh();
        focusRequested(false);
    }
    function cycleMode() {
        if (!GlobalStates.superDown) setMode(nextMode);
    }
    function show(value) {
        if (!(presented && mode === value)) setMode(value);
        GlobalStates.overviewOpen = true;
        focusRequested(inputFocused);
    }
    function toggle(value) {
        superChordUsed = true;
        GlobalStates.superReleaseMightTrigger = false;
        if (!open && presented) show(mode);
        else if (open && mode === value) close();
        else show(value);
    }
    function close() {
        dismissMenus();
        GlobalStates.overviewOpen = false;
    }
    function engageSearch() {
        inputFocused = true;
        resultsExpanded = query.length > 0;
    }
    function edit(text) {
        LauncherSearch.query = text;
        engageSearch();
        dismissMenus();
    }
    function saveScroll(key, position) {
        const positions = Object.assign({}, scrollPositions);
        positions[key] = position;
        scrollPositions = positions;
    }
    function pressSuper() {
        GlobalStates.superDown = true;
        superArmed = true;
        superChordUsed = false;
        GlobalStates.superReleaseMightTrigger = true;
    }
    function releaseSuper() {
        if (!GlobalStates.screenLocked && superArmed && !superChordUsed && GlobalStates.superReleaseMightTrigger)
            toggle(presented ? mode : "apps");
        superArmed = false;
        GlobalStates.superDown = false;
    }
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (!root.open) {
                panelEntrance.stop();
                panelFollow.stop();
                root.panelsReady = false;
                barExit.restart();
                root.dismissMenus();
                root.closeCleanupPending = true;
                root.finishClose();
            } else {
                root.closeCleanupPending = false;
                barExit.stop();
                searchExit.stop();
                const reversing = root.presented;
                root.searchShown = true;
                root.focusRequested(root.inputFocused);
                if (root.presence > 0 || (reversing && root.barReveal > 0)) {
                    root.barExpanded = true;
                    root.panelsReady = true;
                } else panelEntrance.restart();
            }
        }
    }
}
