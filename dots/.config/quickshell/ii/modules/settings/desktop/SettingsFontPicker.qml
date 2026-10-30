pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.services

// The settings row owns the label and persistence. This control only presents
// the selected family and lets the user choose another installed family.
RowLayout {
    id: root
    property Item selectedButton:null
    property Item hoveredButton:null
    Connections {
        target: SettingsCatalog
        function onDismissPopups() { picker.close(); }
    }
    required property string value
    property string accessibleLabel: Translation.tr("Font")
    signal chosen(string family)

    readonly property var families: Qt.fontFamilies().sort((a, b) => a.localeCompare(b))
    readonly property var matches: {
        const query = search.text.trim().toLocaleLowerCase();
        return query ? families.filter(family => family.toLocaleLowerCase().includes(query)) : families;
    }

    spacing: 8
    StyledText {
        Layout.fillWidth: true
        Layout.maximumWidth: 220
        text: root.value || Translation.tr("Default font")
        font.family: root.value || Appearance.font.family.main
        font.variableAxes: ({})
        color: Appearance.colors.colOnLayer1
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
    DialogButton {
        buttonText: Translation.tr("Choose font")
        Accessible.name: Translation.tr("Choose %1 font").arg(root.accessibleLabel)
        onClicked: picker.open()
    }

    Popup {

        enter: OverlayTransition {}

        exit: OverlayTransition { entering: false }
        id: picker
        parent: Overlay.overlay
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        width: parent ? Math.min(480, Math.max(280, parent.width - 32)) : 480
        height: parent ? Math.min(520, Math.max(280, parent.height - 32)) : 520
        padding: 16
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: Appearance.colors.colScrim }
        background: Rectangle {
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
        }
        onOpened: {
            search.text = "";
            search.forceActiveFocus();
            const selected = root.matches.indexOf(root.value);
            if (selected >= 0) list.positionViewAtIndex(selected, ListView.Center);
        }
        contentItem: ColumnLayout {
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: implicitHeight
                Layout.maximumHeight: implicitHeight
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Choose font")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.large
                }
                IconToolbarButton {
                    text: "close"
                    Accessible.name: Translation.tr("Close font picker")
                    onClicked: picker.close()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: implicitHeight
                Layout.maximumHeight: implicitHeight
                SearchField {
                    id: search
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search fonts")
                    Accessible.name: Translation.tr("Search fonts")
                    Accessible.searchEdit: true
                    wrapMode: TextInput.NoWrap
                    Keys.onDownPressed: event => {
                        if (list.count) {
                            list.currentIndex = 0;
                            list.forceActiveFocus();
                            event.accepted = true;
                        }
                    }
                    Keys.onReturnPressed: event => {
                        if (root.matches.length) {
                            picker.close();
                            root.chosen(root.matches[0]);
                        }
                        event.accepted = true;
                    }
                }

            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 100
                visible: root.matches.length > 0
                clip: true
                spacing: 2
                model: root.matches
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: SpotlightScrollBar { scrolling: list.moving }
                Keys.onReturnPressed: event => {
                    if (currentIndex >= 0 && currentIndex < root.matches.length) {
                        picker.close();
                        root.chosen(root.matches[currentIndex]);
                    }
                    event.accepted = true;
                }
                SelectionIndicator {
                    parent:list.contentItem
                    container:list.contentItem
                    selectedItem:root.selectedButton
                    hoveredItem:root.hoveredButton || (list.activeFocus ? list.currentItem : null)
                    radius:Appearance.rounding.small
                    animate:picker.opened
                }
                delegate: RippleButton {
                    id: familyButton
                    required property string modelData
                    width: list.width
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.small
                    toggled: root.value === modelData
                    background:Rectangle {
                        color:"transparent"
                        radius:Appearance.rounding.small
                        border.width:familyButton.visualFocus ? 2 : 0
                        border.color:familyButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                    }
                    onToggledChanged:if (toggled) root.selectedButton=familyButton
                    Component.onCompleted:if (toggled) root.selectedButton=familyButton
                    onIsHoveredChanged:{
                        if (isHovered) root.hoveredButton=familyButton;
                        else if (root.hoveredButton===familyButton) root.hoveredButton=null;
                    }
                    Component.onDestruction:{
                        if (root.selectedButton===familyButton) root.selectedButton=null;
                        if (root.hoveredButton===familyButton) root.hoveredButton=null;
                    }
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: toggled
                    Accessible.name: Translation.tr("Choose %1").arg(modelData)
                    onClicked: {
                        picker.close();
                        root.chosen(modelData);
                    }
                    contentItem: RowLayout {
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            text: familyButton.modelData
                            font.family: familyButton.modelData
                            font.variableAxes: ({})
                            color: familyButton.toggled
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
            Item {
                visible: !root.matches.length
                Layout.fillWidth: true
                Layout.fillHeight: true
                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("No matching fonts")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
