import QtQuick
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    required property var controller
    required property Item menuLayer
    signal moveFocusUp()
    readonly property string scrollKey: controller.mode === "clipboard" ? "clipboard" : "results"
    readonly property bool navigationActive: list.activeFocus || (list.currentItem?.activeFocus ?? false)
    property int selectedIndex: -1
    property bool positioning: false
    function inspect() {
        const item = list.itemAtIndex(selectedIndex);
        return {count: list.count, selectedIndex, scrollY: list.contentY,
            destination: scrollMotion.destination, scrolling: scrollMotion.running,
            contentOffset: contentMotion.offset, selectionProgress: item?.engagement ?? 0};
    }
    function select(index) {
        if (!list.count) { selectedIndex = -1; return; }
        selectedIndex = Math.max(0, Math.min(list.count - 1, index));
        Qt.callLater(() => {
            scrollMotion.stop();
            const start = list.contentY;
            root.positioning = true;
            list.positionViewAtIndex(selectedIndex, ListView.Contain);
            const destination = list.contentY;
            list.contentY = start;
            root.positioning = false;
            scrollMotion.scrollTo(destination);
        });
    }
    function focusFirst() {
        list.forceActiveFocus();
        if (list.count) select(0);
        else selectedIndex = -1;
    }
    SpotlightContentMotion {
        id: contentMotion
        shown: root.controller.panelsReady && (root.controller.resultsExpanded || root.controller.mode === "clipboard")
        reducedMotion: root.controller.reducedMotion
    }
    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 10; rightMargin: 14 }
        clip: true
        spacing: 2
        maximumFlickVelocity: 3500
        boundsBehavior: Flickable.DragOverBounds
        Behavior on contentY {
            enabled: !root.controller.reducedMotion && !root.positioning
            NumberAnimation {
                id: sidebarScrollAnimation
                duration: Appearance.animation.scroll.duration
                easing.type: Appearance.animation.scroll.type
                easing.bezierCurve: Appearance.animation.scroll.bezierCurve
            }
        }
        highlightMoveDuration: root.controller.fastDuration
        currentIndex: -1
        keyNavigationEnabled: false
        Keys.forwardTo: [root.controller.keyRouter]
        model: ScriptModel { values: LauncherSearch.results }
        onContentYChanged: root.controller.saveScroll(root.scrollKey, contentY)
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
        delegate: SearchItem {
            required property var modelData
            required property int index
            width: list.width
            rightContentMargin: 8
            entry: modelData
            query: root.controller.query
            keyboardSelected: root.selectedIndex === index && list.activeFocus
            reducedMotion: root.controller.reducedMotion
            contextMenuOpen: root.controller.menuOpen && root.controller.menuApp?.id === entry?.id
            onContextRequested: point => {
                const app = AppSearch.list.find(app => app.id === entry?.id);
                if (app) root.controller.openMenu(app, mapToItem(root.menuLayer, point.x, point.y));
            }
            transform: Translate { y: contentMotion.offset }
            Keys.forwardTo: [root.controller.keyRouter]
        }
        Keys.onUpPressed: event => {
            if (root.selectedIndex <= 0) root.moveFocusUp();
            else root.select(root.selectedIndex - 1);
            event.accepted = true;
        }
        Keys.onReturnPressed: {
            const entry = LauncherSearch.results[root.selectedIndex];
            if (entry) { root.controller.close(); entry.execute(); }
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Delete && event.modifiers === Qt.ShiftModifier) {
                const entry = LauncherSearch.results[root.selectedIndex];
                const action = (entry?.actions ?? []).find(action => action.name === Translation.tr("Delete"));
                if (action) action.execute();
            } else if (event.key === Qt.Key_Enter) {
                const entry = LauncherSearch.results[root.selectedIndex];
                if (entry) { root.controller.close(); entry.execute(); }
            } else if (event.key === Qt.Key_Down) root.select(root.selectedIndex + 1);
            else if (event.key === Qt.Key_Home) root.select(0);
            else if (event.key === Qt.Key_End) root.select(count - 1);
            else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
                root.select(root.selectedIndex + (event.key === Qt.Key_PageDown ? 8 : -8));
            else return;
            event.accepted = true;
        }
    }
    Connections {
        target: LauncherSearch
        function onResultsChanged() {
            root.selectedIndex = list.count ? Math.max(0, Math.min(root.selectedIndex, list.count - 1)) : -1;
        }
    }
    Connections {
        target: root.controller
        function onModeChanged() {
            Qt.callLater(() => list.contentY = Math.max(0, Math.min(list.contentHeight - list.height,
                root.controller.scrollPositions[root.scrollKey] ?? 0)));
        }
    }
    StyledText {
        anchors.centerIn: parent
        visible: list.count === 0
        text: root.controller.mode === "clipboard" && !root.controller.query
            ? Translation.tr("Clipboard history is empty") : Translation.tr("No results")
        color: Appearance.colors.colOnSurfaceVariant
    }
}
