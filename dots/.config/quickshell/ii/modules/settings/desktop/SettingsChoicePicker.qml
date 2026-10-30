pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.services

// A compact row control for choice sets too large to show as inline buttons.
// The setting row owns its label and storage; choices contain { name, value }.
RowLayout {
    id: root
    property Item selectedButton:null
    property Item hoveredButton:null
    Connections {
        target: SettingsCatalog
        function onDismissPopups() { picker.close(); }
    }
    required property var choices
    required property var value
    property string label: Translation.tr("Option")
    property string displayText: ""
    signal chosen(var value)
    function open() { picker.open(); }

    readonly property var selectedChoice: choices.find(choice => choice.value === value)
    readonly property var matches: {
        const query = search.text.trim().toLocaleLowerCase();
        return query ? choices.filter(choice => String(choice.name).toLocaleLowerCase().includes(query)) : choices;
    }

    spacing: 8
    StyledText {
        Layout.fillWidth: true
        Layout.maximumWidth: 190
        text: root.displayText || (root.selectedChoice ? root.selectedChoice.name : Translation.tr("Not set"))
        color: Appearance.colors.colOnLayer1
        wrapMode: Text.Wrap
    }
    DialogButton {
        buttonText: Translation.tr("Choose")
        Accessible.name: Translation.tr("Choose %1").arg(root.label)
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
        height: parent ? Math.min(parent.height - 32, 136 + Math.max(4, root.choices.length) * 50, 520) : 520
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
            const selected = root.matches.findIndex(choice => choice.value === root.value);
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
                    text: Translation.tr("Choose %1").arg(root.label)
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.large
                    elide: Text.ElideRight
                }
                IconToolbarButton {
                    text: "close"
                    Accessible.name: Translation.tr("Close choices")
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
                    placeholderText: Translation.tr("Search choices")
                    Accessible.name: Translation.tr("Search %1 choices").arg(root.label)
                    Accessible.searchEdit: true
                    wrapMode: TextInput.NoWrap
                    onTextChanged: {
                        list.currentIndex = root.matches.length ? 0 : -1;
                        list.positionViewAtBeginning();
                    }
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
                            root.chosen(root.matches[0].value);
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
                        root.chosen(root.matches[currentIndex].value);
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
                    id: choiceButton
                    required property var modelData
                    width: list.width
                    implicitHeight: Math.max(48,choiceContent.implicitHeight+16)
                    buttonRadius: Appearance.rounding.small
                    toggled: root.value === modelData.value
                    background:Rectangle {
                        color:"transparent"
                        radius:Appearance.rounding.small
                        border.width:choiceButton.visualFocus ? 2 : 0
                        border.color:choiceButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                    }
                    onToggledChanged:if (toggled) root.selectedButton=choiceButton
                    Component.onCompleted:if (toggled) root.selectedButton=choiceButton
                    onIsHoveredChanged:{
                        if (isHovered) root.hoveredButton=choiceButton;
                        else if (root.hoveredButton===choiceButton) root.hoveredButton=null;
                    }
                    Component.onDestruction:{
                        if (root.selectedButton===choiceButton) root.selectedButton=null;
                        if (root.hoveredButton===choiceButton) root.hoveredButton=null;
                    }
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: toggled
                    Accessible.name: Translation.tr("Choose %1").arg(modelData.name)
                    onClicked: {
                        picker.close();
                        root.chosen(modelData.value);
                    }
                    contentItem: RowLayout {
                        id:choiceContent
                        spacing: 8
                        MaterialSymbol {
                            visible: !!choiceButton.modelData.icon
                            text: choiceButton.modelData.icon || ""
                            iconSize: 20
                            color: choiceButton.toggled
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String(choiceButton.modelData.name)
                            color: choiceButton.toggled
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer2
                            wrapMode: Text.Wrap
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
                    text: Translation.tr("No matching choices")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
