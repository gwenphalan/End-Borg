pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.common.functions
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.services

Item {
    id: root
    required property string value
    property string label: Translation.tr("Super key symbol")
    signal chosen(string value)
    implicitWidth: Math.max(78, glyphMetrics.advanceWidth(value) + 42)
    implicitHeight: 40
    property bool customOpen: false
    property Item selectedFamilyButton:null
    property Item hoveredFamilyButton:null
    property Item selectedSymbolButton:null
    property Item hoveredSymbolButton:null
    property var symbols: []
    property var families: []
    property string loadedFontFamily: ""
    property string requestedFontFamily: Appearance.font.family.iconNerd
    property string loadedFontRequest: ""
    property string loadError: ""
    property string searchQuery: ""
    property string selectedFamily: ""
    readonly property var filterOptions: [
        {
            id: "",
            name: Translation.tr("All families"),
            count: symbols.length
        }
    ].concat(families)
    readonly property var matches: {
        const terms = searchQuery.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
        return symbols.filter(symbol => (!selectedFamily || symbol.family === selectedFamily) && terms.every(term => symbol.search.includes(term)));
    }
    readonly property string selectedName: symbols.find(symbol => symbol.glyph === value)?.name || Translation.tr("Custom character")
    readonly property string selectedFamilyName: families.find(family => family.id === selectedFamily)?.name || Translation.tr("All families")
    onRequestedFontFamilyChanged: {
        symbols = [];
        families = [];
        loadedFontRequest = "";
        selectedFamily = "";
        if (picker.visible)
            loadSymbols();
    }
    function selectFamily(family) {
        familyPicker.close();
        selectedFamily = family;
        grid.currentIndex = matches.length ? 0 : -1;
        grid.positionViewAtBeginning();
        search.forceActiveFocus();
    }
    function loadSymbols() {
        if (fontSymbols.running || loadedFontRequest === requestedFontFamily)
            return;
        loadError = "";
        fontSymbols.fontRequest = requestedFontFamily;
        fontSymbols.running = true;
    }
    Timer {
        id: searchDelay
        interval: 100
        onTriggered: {
            root.searchQuery = search.text;
            grid.currentIndex = root.matches.length ? 0 : -1;
            grid.positionViewAtBeginning();
        }
    }
    Timer {
        id: reopenGuard
        interval: 240
    }
    Process {
        id: fontSymbols
        property string fontRequest: ""
        property string output: ""
        command: ["python3", FileUtils.trimFileProtocol(Directories.scriptPath + "/settings/nerd_symbols.py"), "--font", fontRequest]
        onStarted: output = ""
        stdout: StdioCollector {
            onStreamFinished: fontSymbols.output = text
        }
        onExited: (exitCode, exitStatus) => {
            if (fontRequest !== root.requestedFontFamily) {
                Qt.callLater(() => root.loadSymbols());
                return;
            }
            try {
                const result = JSON.parse(output);
                if (exitCode !== 0 || result.error)
                    throw new Error(result.error || "Font symbols could not be read");
                root.symbols = result.symbols;
                root.families = result.families;
                root.loadedFontFamily = result.fontFamily || fontRequest;
                root.loadedFontRequest = fontRequest;
                grid.currentIndex = Math.max(0, root.matches.findIndex(symbol => symbol.glyph === root.value));
            } catch (error) {
                root.loadError = Translation.tr("Could not read symbols from this font.");
            }
        }
    }
    FontMetrics {
        id: glyphMetrics
        font.family: Appearance.font.family.iconNerd
        font.pixelSize: 24
    }
    function open() {
        if (!reopenGuard.running)
            picker.open();
    }
    function choose(value) {
        if (reopenGuard.running)
            return;
        reopenGuard.restart();
        familyPicker.close();
        picker.close();
        // Closing first prevents a row refresh from leaving the old picker open.
        Qt.callLater(() => root.chosen(value));
    }
    Connections {
        target: SettingsCatalog
        function onDismissPopups() {
            familyPicker.close();
            picker.close();
        }
    }
    RippleButton {
        id: button
        anchors.fill: parent
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer3
        Accessible.name: root.label + ": " + root.selectedName
        onClicked: root.open()
        contentItem: RowLayout {
            spacing: 6
            StyledText {
                Layout.fillWidth: true
                text: root.value
                font.family: Appearance.font.family.iconNerd
                font.variableAxes: ({})
                font.pixelSize: 24
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnLayer2
            }
            MaterialSymbol {
                text: "expand_more"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
        }
        StyledToolTip {
            text: Translation.tr(root.selectedName)
        }
    }
    Popup {
        enter: OverlayTransition {}
        exit: OverlayTransition { entering: false }
        id: picker
        parent: Overlay.overlay
        width: Math.min(560, parent ? parent.width - 40 : 560)
        height: Math.min(root.customOpen ? 590 : 540, parent ? parent.height - 48 : 540)
        x: parent ? (parent.width - width) / 2 : 0
        y: parent ? (parent.height - height) / 2 : 0
        padding: 16
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
            searchDelay.stop();
            root.searchQuery = "";
            root.customOpen = false;
            root.loadSymbols();
            customCharacter.text = root.value;
            grid.currentIndex = Math.max(0, root.matches.findIndex(symbol => symbol.glyph === root.value));
            search.forceActiveFocus();
        }
        onClosed: familyPicker.close()
        Popup {
            enter: OverlayTransition {}
            exit: OverlayTransition { entering: false }
            id: familyPicker
            parent: picker.contentItem
            width: Math.min(284, parent.width)
            height: Math.min(360, Math.max(120, parent.height - 52))
            x: parent.width - width
            y: Math.max(0, parent.height - height - (root.customOpen ? 98 : 46))
            padding: 8
            modal: false
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            background: Rectangle {
                color: Appearance.m3colors.m3surfaceContainerHighest
                radius: Appearance.rounding.normal
            }
            contentItem: ListView {
                id: familyList
                clip: true
                model: root.filterOptions
                currentIndex: Math.max(0, root.filterOptions.findIndex(family => family.id === root.selectedFamily))
                boundsBehavior: Flickable.StopAtBounds
                spacing: 2
                ScrollBar.vertical: SpotlightScrollBar {
                    scrolling: familyList.moving
                }
                Keys.onReturnPressed: event => {
                    if (currentIndex >= 0)
                        root.selectFamily(root.filterOptions[currentIndex].id);
                    event.accepted = true;
                }
                SelectionIndicator {
                    parent:familyList.contentItem
                    container:familyList.contentItem
                    selectedItem:root.selectedFamilyButton
                    hoveredItem:root.hoveredFamilyButton || (familyList.activeFocus ? familyList.currentItem : null)
                    radius:Appearance.rounding.small
                    animate:familyPicker.opened
                }
                delegate: RippleButton {
                    id: familyButton
                    required property var modelData
                    width: familyList.width - 8
                    implicitHeight: 40
                    leftPadding: 12
                    rightPadding: 12
                    toggled: root.selectedFamily === modelData.id
                    background:Item {}
                    onToggledChanged:{
                        if (toggled) root.selectedFamilyButton=familyButton;
                        else if (root.selectedFamilyButton===familyButton) root.selectedFamilyButton=null;
                    }
                    Component.onCompleted:if (toggled) root.selectedFamilyButton=familyButton
                    onIsHoveredChanged:{
                        if (isHovered) root.hoveredFamilyButton=familyButton;
                        else if (root.hoveredFamilyButton===familyButton) root.hoveredFamilyButton=null;
                    }
                    buttonRadius: Appearance.rounding.small
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: toggled
                    Accessible.name: Translation.tr(modelData.name)
                    onClicked: root.selectFamily(modelData.id)
                    contentItem: RowLayout {
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr(familyButton.modelData.name)
                            elide: Text.ElideRight
                            color: familyButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: familyButton.modelData.count
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: familyButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
        contentItem: ColumnLayout {
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.maximumHeight: implicitHeight
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Choose key symbol")
                    font.pixelSize: Appearance.font.pixelSize.large
                }
                IconToolbarButton {
                    text: "close"
                    Accessible.name: Translation.tr("Close symbol picker")
                    onClicked: picker.close()
                }
            }
            SearchField {
                id: search
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.maximumHeight: implicitHeight
                placeholderText: Translation.tr("Search symbols")
                onTextChanged: searchDelay.restart()
                Keys.onDownPressed: event => {
                    searchDelay.stop();
                    root.searchQuery = search.text;
                    if (grid.count)
                        grid.forceActiveFocus();
                    event.accepted = true;
                }
                Keys.onReturnPressed: event => {
                    searchDelay.stop();
                    root.searchQuery = search.text;
                    if (root.matches.length)
                        root.choose(root.matches[0].glyph);
                    event.accepted = true;
                }
            }
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 96
                clip: true
                model: picker.visible ? root.matches : []
                readonly property int columns: Math.max(1, Math.floor(width / 84))
                cellWidth: width / columns
                cellHeight: 84
                cacheBuffer: cellHeight
                reuseItems: true
                keyNavigationEnabled: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: SpotlightScrollBar {
                    scrolling: grid.moving
                }
                Keys.onReturnPressed: event => {
                    if (currentIndex >= 0)
                        root.choose(root.matches[currentIndex].glyph);
                    event.accepted = true;
                }
                SelectionIndicator {
                    parent:grid.contentItem
                    container:grid.contentItem
                    selectedItem:root.selectedSymbolButton
                    hoveredItem:root.hoveredSymbolButton || (grid.activeFocus ? grid.currentItem : null)
                    selectedColor:Appearance.colors.colSecondaryContainer
                    hoverColor:Appearance.colors.colLayer3
                    radius:Appearance.rounding.small
                    animate:picker.opened
                }
                delegate: RippleButton {
                    id: symbolButton
                    required property var modelData
                    required property int index
                    width: grid.cellWidth - 6
                    height: grid.cellHeight - 6
                    buttonRadius: Appearance.rounding.small
                    toggled: root.value === modelData.glyph
                    onToggledChanged:{
                        if (toggled) root.selectedSymbolButton=symbolButton;
                        else if (root.selectedSymbolButton===symbolButton) root.selectedSymbolButton=null;
                    }
                    Component.onCompleted:if (toggled) root.selectedSymbolButton=symbolButton
                    onIsHoveredChanged:{
                        if (isHovered) root.hoveredSymbolButton=symbolButton;
                        else if (root.hoveredSymbolButton===symbolButton) root.hoveredSymbolButton=null;
                    }
                    GridView.onPooled:{
                        if (root.selectedSymbolButton===symbolButton) root.selectedSymbolButton=null;
                        if (root.hoveredSymbolButton===symbolButton) root.hoveredSymbolButton=null;
                    }
                    GridView.onReused:if (toggled) root.selectedSymbolButton=symbolButton
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: toggled
                    Accessible.name: Translation.tr(modelData.name)
                    onClicked: root.choose(modelData.glyph)
                    onActiveFocusChanged: if (activeFocus)
                        grid.currentIndex = index
                    StyledToolTip {
                        text: symbolButton.modelData.name + " · " + symbolButton.modelData.code + "\n" + (root.families.find(family => family.id === symbolButton.modelData.family)?.name || "")
                    }
                    contentItem: ColumnLayout {
                        spacing: 4
                        StyledText {
                            Layout.fillWidth: true
                            text: symbolButton.modelData.glyph
                            font.family: root.loadedFontFamily || Appearance.font.family.iconNerd
                            font.variableAxes: ({})
                            font.pixelSize: 28
                            horizontalAlignment: Text.AlignHCenter
                            color: symbolButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            text: Translation.tr(symbolButton.modelData.name)
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            color: symbolButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                        }
                    }
                    background: Rectangle {
                        radius: Appearance.rounding.small
                        color:"transparent"
                        border.width:0
                    }
                }
                StyledText {
                    anchors.centerIn: parent
                    width: Math.max(0, parent.width - 24)
                    visible: !root.matches.length
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: fontSymbols.running ? Translation.tr("Loading installed symbols…") : root.loadError || Translation.tr("No matching symbols")
                    color: Appearance.colors.colSubtext
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                DialogButton {
                    Layout.fillHeight: false
                    buttonText: Translation.tr("Custom character")
                    onClicked: {
                        root.customOpen = !root.customOpen;
                        if (root.customOpen)
                            customCharacter.forceActiveFocus();
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                RippleButtonWithIcon {
                    id: filterButton
                    Layout.fillHeight: false
                    materialIcon: "filter_list"
                    mainText: root.selectedFamily ? Translation.tr(root.selectedFamilyName) : Translation.tr("Filters")
                    toggled: !!root.selectedFamily
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    enabled: root.families.length > 0
                    Accessible.name: Translation.tr("Filter icon families") + ": " + Translation.tr(root.selectedFamilyName)
                    onClicked: familyPicker.open()
                }
            }
            RowLayout {
                visible: root.customOpen
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 40
                CompactTextField {
                    id: customCharacter
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Paste a character")
                    font.family: Appearance.font.family.iconNerd
                    font.variableAxes: ({})
                    font.pixelSize: 22
                    Accessible.name: Translation.tr("Custom key character")
                    Keys.onReturnPressed: event => {
                        if (text.trim())
                            root.choose(text);
                        event.accepted = true;
                    }
                }
                IconToolbarButton {
                    text: "check"
                    enabled: !!customCharacter.text.trim()
                    Accessible.name: Translation.tr("Use custom character")
                    onClicked: root.choose(customCharacter.text)
                    StyledToolTip {
                        text: Translation.tr("Use custom character")
                    }
                }
            }
        }
    }
}
