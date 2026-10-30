pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property string searchingText: LauncherSearch.query
    property real animProgress: 1.0

    signal moveFocusDown()
    signal showClipboard()
    signal showWorkspaces()

    implicitWidth: searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: searchWidgetContent.implicitHeight + Appearance.sizes.elevationMargin * 2

    transform: [
        Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            xScale: 0.96 + 0.04 * root.animProgress
            yScale: 0.96 + 0.04 * root.animProgress
        },
        Translate {
            y: (1.0 - root.animProgress) * -8
        }
    ]
    opacity: Math.min(1.0, root.animProgress * 2.0)

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
        searchBar.setQueryText("");
        LauncherSearch.query = "";
    }

    function cancelSearch() {
        searchBar.animateWidth = false;
        searchBar.setQueryText("");
        LauncherSearch.query = "";
        animEnableTimer.restart();
    }

    Timer {
        id: animEnableTimer
        interval: 100
        onTriggered: searchBar.animateWidth = true
    }

    function setSearchingText(text) {
        searchBar.setQueryText(text);
        LauncherSearch.query = text;
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape)
            return;

        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            return;
        }

        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20)
        {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
            }
        }
    }

    StyledRectangularShadow {
        target: searchWidgetContent
    }

    Rectangle {
        id: searchWidgetContent
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: Appearance.sizes.elevationMargin
        }
        // Directly synchronized with searchBar width — no redundant animation to avoid lagging behind buttons
        implicitWidth: searchBar.implicitWidth + 24
        implicitHeight: searchBar.implicitHeight + 8

        radius: height / 2
        color: Appearance.colors.colBackgroundSurfaceContainer

        MouseArea {
            anchors.fill: parent
        }

        SearchBar {
            id: searchBar
            anchors.centerIn: parent
            Synchronizer on searchingText {
                property alias source: root.searchingText
            }
            onMoveFocusDown: {
                root.moveFocusDown();
            }
            onShowClipboard: root.showClipboard()
            onShowWorkspaces: root.showWorkspaces()
        }
    }
}
