import QtQuick
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "LauncherLabels.js" as LauncherLabels
import "SpotlightLogic.js" as Logic

Item {
    id: root
    required property var controller
    required property Item menuLayer
    readonly property int columns: Math.max(1, Math.floor((width - 86) / 100))
    readonly property real cellWidth: (width - 86) / columns
    readonly property real cellHeight: 110
    readonly property var allApps: Array.from(AppSearch.list ?? []).filter(app => app && app.name && !app.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))
    readonly property var pins: Config.options.launcher.pinnedApps
    readonly property var hiddenIds: Config.options.launcher.hiddenApps
    readonly property var pinnedApps: pins.map(id => allApps.find(app => app.id === id))
        .filter(app => app && !hiddenIds.includes(app.id))
    readonly property var normalApps: allApps.filter(app => !hiddenIds.includes(app.id) && !pins.includes(app.id))
    readonly property var hiddenApps: allApps.filter(app => hiddenIds.includes(app.id))
    readonly property var rows: {
        const rows = [];
        function header(title, icon, section, letter, hidden) {
            rows.push({kind: "header", title, icon, section, letter: letter || "", hidden: !!hidden, height: 42});
        }
        function apps(values, hidden, section) {
            for (let i = 0; i < values.length; i += columns)
                rows.push({kind: "apps", apps: values.slice(i, i + columns), hidden: !!hidden, section: section || "", height: cellHeight});
        }
        if (pinnedApps.length) { header("Pinned", "push_pin", "pinned"); apps(pinnedApps); }
        header("All Apps", "apps", "apps");
        apps(normalApps, false, "apps");
        if (hiddenApps.length) {
            rows.push({kind: "show", height: 40});
            header("Hidden", "visibility", "hidden", "", true);
            apps(hiddenApps, true);
            rows.push({kind: "close", height: 40, hidden: true});
        }
        return rows;
    }
    function rowHeight(row) {
        if (row.kind === "show") return controller.hiddenExpanded ? 0 : row.height;
        return row.hidden && !controller.hiddenExpanded ? 0 : row.height;
    }
    readonly property var sectionPositions: {
        let position = 0;
        const sections = [];
        const letters = new Set();
        rows.forEach(row => {
            if (row.kind === "header" && (!row.hidden || controller.hiddenExpanded))
                sections.push({section: row.section, label: row.title, icon: row.icon, letter: row.letter, y: position});
            if (row.kind === "apps" && row.section === "apps") {
                row.apps.forEach(app => {
                    const letter = Logic.letter(app.name);
                    if (letters.has(letter)) return;
                    letters.add(letter);
                    sections.push({section: "apps", label: letter, icon: "", letter, y: position});
                });
            }
            position += rowHeight(row);
        });
        return sections;
    }
    property int selectedIndex: -1
    readonly property bool navigationActive: list.activeFocus
    function inspect() {
        return {scrollY: list.contentY, destination: scrollMotion.destination,
            scrolling: scrollMotion.running, selectedIndex, contentOffset: contentMotion.offset,
            wheelEvents: scrollMotion.wheelEvents, viewportParent: scrollMotion.parent === list,
            scrollAreaWidth: scrollMotion.width, scrollAreaHeight: scrollMotion.height,
            rail: rail.inspect()};
    }
    readonly property var visibleApps: pinnedApps.concat(normalApps).concat(controller.hiddenExpanded ? hiddenApps : [])
    function focusFirst() {
        selectedIndex = visibleApps.length ? 0 : -1;
        list.forceActiveFocus();
    }
    function launch(app) {
        if (!app) return;
        controller.close();
        if (!app.runInTerminal) app.execute();
        else Quickshell.execDetached(["bash", "-c", `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(app.command.join(' '))}'`]);
    }
    function jump(position) {
        scrollMotion.scrollTo(position);
    }
    function ensureSelectedVisible() {
        const app = visibleApps[selectedIndex];
        let position = 0;
        for (const row of rows) {
            if (row.apps?.some(entry => entry.id === app?.id)) {
                if (position < list.contentY) jump(position);
                else if (position + cellHeight > list.contentY + list.height) jump(position + cellHeight - list.height);
                break;
            }
            position += rowHeight(row);
        }
    }
    SpotlightContentMotion {
        id: contentMotion
        shown: root.controller.panelsReady && root.controller.mode === "apps" && !root.controller.resultsExpanded
        reducedMotion: root.controller.reducedMotion
    }
    SpotlightSectionRail {
        id: rail
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 8 }
        width: 46
        sections: root.sectionPositions
        scrollY: list.contentY
        motionDuration: root.controller.fastDuration
        keyRouter: root.controller.keyRouter
        reducedMotion: root.controller.reducedMotion
        transform: Translate { y: contentMotion.offset }
        onJump: position => root.jump(position)
    }
    ListView {
        id: list
        anchors { left: parent.left; leftMargin: 62; right: parent.right; rightMargin: 24; top: parent.top; bottom: parent.bottom; topMargin: 8; bottomMargin: 8 }
        clip: true
        cacheBuffer: root.cellHeight
        maximumFlickVelocity: 3500
        boundsBehavior: Flickable.DragOverBounds
        Behavior on contentY {
            enabled: !root.controller.reducedMotion
            NumberAnimation {
                id: sidebarScrollAnimation
                duration: Appearance.animation.scroll.duration
                easing.type: Appearance.animation.scroll.type
                easing.bezierCurve: Appearance.animation.scroll.bezierCurve
            }
        }
        model: root.rows
        Keys.forwardTo: [root.controller.keyRouter]
        onContentYChanged: {
            root.controller.saveScroll("apps", contentY);
            root.controller.dismissMenus();
        }
        onMovementStarted: root.controller.dismissMenus()
        SpotlightScrollMotion {
            id: scrollMotion
            flickable: list
            animation: sidebarScrollAnimation
            reducedMotion: root.controller.reducedMotion
        }
        ScrollBar.vertical: SpotlightScrollBar {
            parent: root
            anchors { top: list.top; bottom: list.bottom; topMargin: 16; bottomMargin: 16; right: parent.right; rightMargin: 6 }
            scrolling: scrollMotion.running || sidebarScrollAnimation.running || list.moving
            motionDuration: root.controller.fastDuration
            reducedMotion: root.controller.reducedMotion
            onPressedChanged: if (pressed) scrollMotion.stop()
        }
        delegate: Item {
            id: rowItem
            required property var modelData
            width: list.width
            transform: Translate { y: contentMotion.offset }
            property real reveal: root.rowHeight(modelData) > 0 ? 1 : 0
            height: modelData.height * reveal
            clip: true
            enabled: reveal > 0.98
            Behavior on reveal {
                NumberAnimation {
                    duration: root.controller.motionDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.controller.entranceCurve
                }
            }
            Loader {
                width: rowItem.width
                height: rowItem.modelData.height
                opacity: rowItem.reveal
                sourceComponent: rowItem.modelData.kind === "header" ? headerComponent
                    : rowItem.modelData.kind === "apps" ? appsComponent : actionComponent
            }
            Component {
                id: headerComponent
                SpotlightSectionHeader {
                    title: Translation.tr(rowItem.modelData.title)
                    icon: rowItem.modelData.icon
                }
            }
            Component {
                id: appsComponent
                Row {
                    Repeater {
                        model: rowItem.modelData.apps
                        delegate: SpotlightAppTile {
                            required property var modelData
                            app: modelData
                            width: root.cellWidth
                            height: root.cellHeight
                            label: LauncherLabels.displayName(modelData, root.allApps, AppSearch.launcherLabels)
                            selected: root.visibleApps[root.selectedIndex]?.id === modelData.id && list.activeFocus
                            controller: root.controller
                            onLaunch: root.launch(app)
                            onContextRequested: root.controller.openMenu(app, mapToItem(root.menuLayer, width / 2 + 24, 54))
                        }
                    }
                }
            }
            Component {
                id: actionComponent
                RippleButton {
                    buttonRadius: Appearance.rounding.normal
                    colBackground: "transparent"
                    Keys.forwardTo: [root.controller.keyRouter]
                    onClicked: {
                        root.controller.hiddenExpanded = rowItem.modelData.kind === "show";
                        root.controller.dismissMenus();
                    }
                    contentItem: StyledText {
                        text: rowItem.modelData.kind === "show" ? Translation.tr("Show Hidden") : Translation.tr("Close Hidden")
                        color: Appearance.colors.colOnSurface
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
        Keys.onPressed: event => {
            let delta = 0;
            if (event.key === Qt.Key_Right) delta = 1;
            else if (event.key === Qt.Key_Left) delta = -1;
            else if (event.key === Qt.Key_Down) delta = root.columns;
            else if (event.key === Qt.Key_Up) delta = -root.columns;
            else if (event.key === Qt.Key_PageDown) delta = root.columns * 3;
            else if (event.key === Qt.Key_PageUp) delta = -root.columns * 3;
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.launch(root.visibleApps[root.selectedIndex]);
                event.accepted = true;
                return;
            }
            if (delta) {
                root.selectedIndex = Math.max(0, Math.min(root.visibleApps.length - 1, root.selectedIndex + delta));
                root.ensureSelectedVisible();
                event.accepted = true;
            }
        }
    }
}
