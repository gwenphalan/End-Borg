pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.services
import "../../ii/overview/LauncherLabels.js" as LauncherLabels

Item {
    id: root
    Connections {
        target: SettingsCatalog
        function onDismissPopups() { picker.close(); }
    }
    required property var entries
    required property string value
    property string label: Translation.tr("Application")
    property bool allowCustom: false
    property bool customOpen: false
    signal chosen(string command)
    signal dismissed
    function open() {
        picker.open();
    }
    function choose(command) {
        chosen(command);
        picker.close();
    }
    readonly property var orderedEntries: entries.slice().sort((a, b) => {
        if ((a.value === value) !== (b.value === value))
            return a.value === value ? -1 : 1;
        if (a.recommended !== b.recommended)
            return a.recommended ? -1 : 1;
        return a.name.localeCompare(b.name);
    })
    readonly property var filteredEntries: {
        const query = search.text.trim().toLocaleLowerCase();
        return query ? orderedEntries.filter(app => [app.name, app.id, app.value].some(text => String(
                                                                                                   text).toLocaleLowerCase(
                                                                                                   ).includes(
                                                                                                   query))) :
                       orderedEntries;
    }
    QtObject {
        id: tileController
        property bool reducedMotion: Config.options.launcher.reducedMotion
        property int createdAppTiles: 0
        property var keyRouter: grid
        property bool menuOpen: false
        property var menuApp: null
    }
    Popup {
        enter: OverlayTransition {}
        exit: OverlayTransition { entering: false }
        id: picker
        parent: Overlay.overlay
        width: parent ? Math.min(680, parent.width - 48) : 680
        height: parent ? Math.min(600, parent.height - 48) : 600
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        padding: 20
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle {
            color: Appearance.colors.colScrim
        }
        background: Rectangle {
            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal
        }
        onOpened: {
            search.text = "";
            root.customOpen = false;
            command.text = root.value;
            grid.currentIndex = Math.max(0, root.filteredEntries.findIndex(app => app.value === root.value));
            search.forceActiveFocus();
        }
        onClosed: root.dismissed()
        contentItem: ColumnLayout {
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.maximumHeight: implicitHeight
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Choose %1 app").arg(root.label)
                    font.pixelSize: Appearance.font.pixelSize.large
                    elide: Text.ElideRight
                }
                IconToolbarButton {
                    text: "close"
                    Accessible.name: Translation.tr("Close app picker")
                    onClicked: picker.close()
                }
            }
            SearchField {
                id: search
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.maximumHeight: implicitHeight
                placeholderText: Translation.tr("Search installed applications")
                Accessible.name: placeholderText
                Accessible.searchEdit: true
                wrapMode: TextInput.NoWrap
                onTextChanged: {
                    grid.currentIndex = root.filteredEntries.length ? 0 : -1;
                    grid.positionViewAtBeginning();
                }
                Keys.onDownPressed: event => {
                    if (grid.count) {
                        grid.forceActiveFocus();
                        event.accepted = true;
                    }
                }
                Keys.onReturnPressed: event => {
                    if (root.filteredEntries.length)
                        root.choose(root.filteredEntries[0].value);
                    event.accepted = true;
                }
            }
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                clip: true
                readonly property int columns: Math.max(1, Math.floor(width / 106))
                cellWidth: width / columns
                cellHeight: 106
                cacheBuffer: 106
                model: picker.visible ? root.filteredEntries : []
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: true
                keyNavigationWraps: true
                ScrollBar.vertical: SpotlightScrollBar {
                    scrolling: grid.moving
                }
                Keys.onReturnPressed: event => {
                    if (currentIndex >= 0 && currentIndex < root.filteredEntries.length)
                        root.choose(root.filteredEntries[currentIndex].value);
                    event.accepted = true;
                }
                delegate: Item {
                    id: appCell
                    required property int index
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight
                    SpotlightAppTile {
                        anchors.fill: parent
                        app: appCell.modelData
                        label: LauncherLabels.displayName(appCell.modelData, AppSearch.list, AppSearch.launcherLabels)
                        controller: tileController
                        labelAlwaysBold:false
                        labelBoldOnSelection:false
                        labelRestWeight:Font.Normal
                        chosen:root.value===appCell.modelData.value
                        selected: grid.activeFocus && grid.currentIndex === appCell.index
                        Accessible.role:Accessible.RadioButton
                        Accessible.checked:chosen
                        Accessible.name: Translation.tr("Choose %1").arg(appCell.modelData.name)
                        onLaunch: root.choose(appCell.modelData.value)
                    }

                }
                StyledText {
                    visible: !root.filteredEntries.length
                    anchors.centerIn: parent
                    text: Translation.tr("No matching applications")
                    color: Appearance.colors.colSubtext
                }
            }
            RowLayout {
                visible: root.allowCustom && root.customOpen
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.maximumHeight: implicitHeight
                MaterialTextField {
                    id: command
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Custom command")
                    Accessible.name: placeholderText
                    wrapMode: TextInput.NoWrap
                    Keys.onReturnPressed: event => {
                        if (text.trim())
                            root.choose(text.trim());
                        event.accepted = true;
                    }
                }
                DialogButton {
                    buttonText: Translation.tr("Use command")
                    enabled: !!command.text.trim()
                    onClicked: root.choose(command.text.trim())
                }
            }
            DialogButton {
                visible: root.allowCustom
                Layout.fillHeight: false
                Layout.maximumHeight: implicitHeight
                buttonText: root.customOpen ? Translation.tr("Hide custom command") : Translation.tr(
                                                  "Custom command…")
                onClicked: {
                    root.customOpen = !root.customOpen;
                    if (root.customOpen)
                        command.forceActiveFocus();
                }
            }
        }
    }
}
