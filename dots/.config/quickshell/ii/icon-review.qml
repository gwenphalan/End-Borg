//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import "modules/ii/iconReview"
import "modules/ii/overview/LauncherLabels.js" as LauncherLabels

AppWindow {
    id: root
    appTitle: "Icon Studio"
    showWindowChrome: false
    width: 1150
    height: 875
    minimumWidth: 860
    minimumHeight: 600
    property var apps: []
    property var reviews: ({})
    property var labels: ({})
    property var theme: ({})
    property var selected: null
    readonly property var labelEntries: apps.map(entry => ({id: entry.app_id, name: entry.name}))
    readonly property var pinnedApps: Config.options?.launcher?.pinnedApps ?? []
    property var filtered: apps.filter(app => {
        const flag = reviews[app.app_id]?.flag || "";
        const query = search.text.toLowerCase().trim();
        return (!query || (app.name + " " + app.app_id + " " + label(app)).toLowerCase().includes(query))
            && (filter.currentIndex === 0 || filter.currentIndex === 1 && !flag
                || filter.currentIndex === 2 && flag === "needs work"
                || filter.currentIndex === 3 && flag === "looks good"
                || filter.currentIndex === 4 && app.is_game);
    }).sort((a, b) => {
        const ai = pinnedApps.indexOf(a.app_id), bi = pinnedApps.indexOf(b.app_id);
        if (ai !== -1 && bi !== -1) return ai - bi;
        if (ai !== -1) return -1;
        if (bi !== -1) return 1;
        return label(a).localeCompare(label(b));
    })
    property string previewPath: ""
    property string presentation: ""
    property string backgroundColor: ""
    property string alternativeIcon: ""
    property string flag: ""
    property bool dirty: false
    property bool loading: false
    property int editRevision: 0
    property int saveRevision: 0
    property string statusMessage: "Loading your launcher…"
    property var queued: null
    property string pendingInput: ""
    closeHandler: () => {
        if (!dirty) return true;
        statusMessage = "Save or discard edits before closing";
        return false;
    }
    FileDialog {
        id: alternativePicker
        title: "Choose alternative icon"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Images (*.png *.svg *.webp *.jpg *.jpeg *.xpm)"]
        onAccepted: {
            const url = selectedFile.toString();
            const match = /^file:\/\/(\/.*)$/.exec(url);
            if (!match) {
                root.statusMessage = "Choose a local image file";
                return;
            }
            try {
                root.alternativeIcon = decodeURIComponent(match[1]);
                root.edit();
            } catch (error) {
                root.statusMessage = "Invalid image path";
            }
        }
    }
    readonly property string effectivePresentation: presentation || selected?.presentation || "fit"
    readonly property string effectiveBackground: backgroundColor || selected?.bg_color || Appearance.colors.colSecondaryContainer
    readonly property int selectedIndex: filtered.findIndex(app => app.app_id === selected?.app_id)
    readonly property int reviewedCount: Object.values(reviews).filter(value => value?.flag).length
    function label(app) {
        return LauncherLabels.displayName({id: app.app_id, name: app.name},
            labelEntries, labels);
    }
    component StudioButton: RippleButton {
        id: control
        implicitHeight: 40
        property bool selected: false
        property bool prominent: false
        buttonRadius: Appearance.rounding.full
        toggled: selected || prominent
        colBackground: Appearance.m3colors.m3surfaceContainer
        colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
        colBackgroundToggled: prominent ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: prominent ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.m3colors.m3surfaceContainerHighest
        colRippleToggled: prominent ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
        contentItem: StyledText {
            text: control.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: control.prominent ? Appearance.colors.colOnPrimary
                : control.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            font.pixelSize: 12
            font.weight: control.selected || control.prominent ? Font.DemiBold : Font.Normal
        }
    }

    function review() {
        return {presentation: presentation, bg_color: backgroundColor, alternate_icon: alternativeIcon, flag: flag,
                note: notes.text, hue_shift: Math.round(hue.value),
                saturation: Math.round(saturation.value) / 100,
                strength: Math.round(strength.value) / 100};
    }
    function invoke(operation, values) {
        const request = Object.assign({operation: operation}, values || {});
        if (backend.running) {
            queued = request;
            return;
        }
        pendingInput = JSON.stringify(request);
        backend.stdinEnabled = true;
        backend.responded = false;
        backend.running = true;
    }
    function preview() {
        if (!selected) return;
        invoke("preview", {id: selected.app_id, review: review()});
    }
    function edit() {
        if (loading || !selected) return;
        editRevision++;
        dirty = true;
        statusMessage = "Unsaved changes · Save before switching icons";
        previewDelay.restart();
    }
    function pick(app, discard) {
        if (!app || dirty && !discard) {
            if (dirty) statusMessage = "Save or discard edits before changing icons";
            return;
        }
        previewDelay.stop();
        loading = true;
        selected = app;
        const saved = reviews[app.app_id] || {};
        presentation = saved.presentation || "";
        backgroundColor = saved.bg_color || "";
        alternativeIcon = saved.alternate_icon || "";
        flag = saved.flag || "";
        hue.value = saved.hue_shift ?? 0;
        saturation.value = Math.round((saved.saturation ?? 1) * 100);
        strength.value = Math.round((saved.strength ?? 1) * 100);
        notes.text = saved.note || "";
        hex.text = (backgroundColor || app.bg_color).toUpperCase();
        previewPath = app.path;
        dirty = false;
        statusMessage = saved.flag ? "Saved · " + saved.flag : "Not reviewed";
        loading = false;
        Qt.callLater(() => {
            if (selectedIndex >= 0) drawer.positionViewAtIndex(selectedIndex, GridView.Contain);
        });
        preview();
    }
    function navigate(delta) {
        const index = selectedIndex;
        if (filtered.length) pick(filtered[Math.max(0, Math.min(filtered.length - 1, index + delta))], false);
    }
    function response(operation, reply) {
        if (!reply.ok) {
            statusMessage = reply.error || "Icon operation failed";
            return;
        }
        const result = reply.result;
        if (operation === "catalog") {
            apps = result.apps;
            reviews = result.reviews;
            labels = result.labels;
            theme = result.theme;
            const current = apps.find(app => app.app_id === selected?.app_id);
            pick(current || filtered[0] || apps[0], true);
        } else if (operation === "preview") {
            // A queued preview supersedes an earlier response.
            if (!queued || queued.operation !== "preview")
                previewPath = result.path;
        } else if (operation === "save") {
            reviews = Object.assign({}, reviews, {[selected.app_id]: result.saved});
            dirty = editRevision !== saveRevision;
            if (!dirty) alternativeIcon = result.saved.alternate_icon || "";
            statusMessage = dirty ? "New edits are not saved yet" : "Review saved · Launcher unchanged";
        }
    }
    Component.onCompleted: invoke("catalog")
    Shortcut { sequence: "Ctrl+W"; onActivated: root.close() }
    Shortcut { sequence: "Ctrl+S"; enabled: root.dirty; onActivated: saveButton.clicked() }
    Shortcut { sequence: "Right"; enabled: !search.activeFocus && !notes.activeFocus && !hex.activeFocus; onActivated: root.navigate(1) }
    Shortcut { sequence: "Left"; enabled: !search.activeFocus && !notes.activeFocus && !hex.activeFocus; onActivated: root.navigate(-1) }
    Timer { id: previewDelay; interval: 220; onTriggered: root.preview() }
    Process {
        id: backend
        command: ["python3", Quickshell.shellPath("scripts/icon_review/bridge.py")]
        stdinEnabled: true
        property string operation: ""
        property bool responded: false
        stdout: StdioCollector {
            onStreamFinished: {
                backend.responded = true;
                const operation = backend.operation;
                try { root.response(operation, JSON.parse(text)); }
                catch (error) { root.statusMessage = "Backend did not return a valid response"; }
                Qt.callLater(() => {
                    if (root.queued && !backend.running) {
                        const next = root.queued;
                        root.queued = null;
                        root.invoke(next.operation, next);
                    }
                });
            }
        }
        onStarted: {
            operation = JSON.parse(root.pendingInput).operation;
            write(root.pendingInput);
            root.pendingInput = "";
            stdinEnabled = false;
        }
        onExited: (code, exitStatus) => {
            if (code && !backend.responded)
                root.statusMessage = "Backend exited with code " + code;
            Qt.callLater(() => {
                if (root.queued && !backend.running) {
                    const next = root.queued;
                    root.queued = null;
                    root.invoke(next.operation, next);
                }
            });
        }
    }
    ColorDialog {
        id: picker
        title: "Squircle color"
        selectedColor: root.effectiveBackground
        onAccepted: {
            root.backgroundColor = selectedColor.toString().substring(0, 7).toUpperCase();
            hex.text = root.backgroundColor;
            root.edit();
        }
    }
    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3surface
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 18
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                Layout.preferredWidth: 42; Layout.preferredHeight: 42
                radius: 14
                color: Appearance.colors.colPrimaryContainer
                MaterialSymbol { anchors.centerIn: parent; text: "palette"; iconSize: 25; color: Appearance.colors.colOnPrimaryContainer }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                StyledText { text: "Icon Studio"; font.family: Appearance.font.family.title; font.pixelSize: 21; font.weight: Font.Medium }
            }
            StyledText { text: root.apps.length + " icons  ·  " + root.reviewedCount + " reviewed"; color: Appearance.colors.colSubtext }
        }
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 20
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.minimumWidth: 540
                ColumnLayout {
                    anchors.fill: parent; spacing: 14
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 44
                        ToolbarTextField {
                            id: search; Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.preferredHeight: 44
                            placeholderText: "Search icons"
                            Accessible.name: "Search icons"
                            colBackground: Appearance.m3colors.m3surfaceContainer
                        }
                        StyledComboBox {
                            id: filter; Layout.preferredWidth: 155
                            Layout.fillWidth: false
                            model: [{text: "All icons"}, {text: "Not reviewed"}, {text: "Needs work"},
                                    {text: "Looks good"}, {text: "Games"}]
                            textRole: "text"
                            Accessible.name: "Filter icons"
                        }
                    }
                    Rectangle {
                        id: drawerSurface
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 520
                        Layout.fillHeight: true
                        radius: Appearance.rounding.large + 10
                        color: Appearance.colors.colBackgroundSurfaceContainer
                        clip: true
                        StyledRectangularShadow { target: drawerSurface }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 0
                            GridView {
                                id: drawer
                                Layout.fillWidth: true; Layout.fillHeight: true
                                cellWidth: 100; cellHeight: 110
                                topMargin: 4; bottomMargin: 8
                                clip: true
                                model: root.filtered
                                ScrollBar.vertical: StyledScrollBar {}
                                delegate: Item {
                                    id: card
                                    required property var modelData
                                    width: drawer.cellWidth; height: drawer.cellHeight
                                    RippleButton {
                                        id: appButton
                                        Accessible.name: card.modelData.name
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        buttonRadius: Appearance.rounding.normal
                                        topPadding: 6; bottomPadding: 6
                                        leftPadding: 4; rightPadding: 4
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.colors.colLayer1Hover
                                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                        toggled: root.selected?.app_id === card.modelData.app_id
                                        onClicked: root.pick(card.modelData, false)
                                        contentItem: ColumnLayout {
                                            spacing: 4
                                            Item {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.preferredWidth: 52; Layout.preferredHeight: 52
                                                ReviewTile {
                                                    anchors.centerIn: parent
                                                    width: 48; height: 48
                                                    tileColor: card.modelData.bg_color
                                                    fill: card.modelData.fill
                                                    imagePath: card.modelData.path
                                                }
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: root.label(card.modelData)
                                                horizontalAlignment: Text.AlignHCenter
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 2
                                                Layout.preferredHeight: 34
                                                Layout.maximumHeight: 34
                                                fontSizeMode: Text.Fit
                                                minimumPixelSize: 10
                                                font.family: "Noto Sans"
                                                font.weight: Font.Medium
                                                font.pixelSize: 12
                                                color: Appearance.colors.colOnSurface
                                            }
                                        }
                                    }
                                    Rectangle {
                                        width: 7; height: 7; radius: 4
                                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 9
                                        visible: !!root.reviews[card.modelData.app_id]?.flag
                                        color: root.reviews[card.modelData.app_id]?.flag === "looks good" ? Appearance.colors.colPrimary : Appearance.colors.colError
                                    }
                                }
                            }
                        }
                    }
                    StyledText { text: root.filtered.length + " shown"; color: Appearance.colors.colSubtext; font.pixelSize: 11 }
                }
            }
            Rectangle {
                Layout.preferredWidth: 420; Layout.fillHeight: true
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainerLow
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 20; spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { Layout.fillWidth: true; text: "Review"; color: Appearance.colors.colOnLayer1; font.pixelSize: 16; font.weight: Font.Medium }
                        StudioButton { text: "←"; implicitWidth: 39; onClicked: root.navigate(-1) }
                        StyledText { text: (root.selectedIndex + 1) + " / " + root.filtered.length; color: Appearance.colors.colSubtext }
                        StudioButton { text: "→"; implicitWidth: 39; onClicked: root.navigate(1) }
                    }
                    StyledText { text: root.selected ? root.label(root.selected) : "Select an icon"; font.family: Appearance.font.family.title; font.pixelSize: 25; elide: Text.ElideRight; Layout.fillWidth: true }
                    StyledText { text: root.selected?.app_id || ""; color: Appearance.colors.colSubtext; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                    ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true
                        ColumnLayout {
                            width: 375; spacing: 12
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 112
                                radius: 18; color: Appearance.m3colors.m3surfaceContainer
                                Column {
                                    anchors.centerIn: parent; spacing: 12
                                    StyledText { text: "Launcher preview · 48 px"; color: Appearance.colors.colSubtext; font.pixelSize: 10 }
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter; spacing: 16
                                        ReviewTile {
                                            width: 48; height: 48
                                            tileColor: root.effectiveBackground
                                            fill: root.effectivePresentation !== "fit" && root.effectivePresentation !== "remove-background"
                                            imagePath: root.previewPath
                                        }
                                        Column {
                                            spacing: 4
                                            StyledText { text: root.selected ? root.label(root.selected) : ""; font.pixelSize: 14 }
                                            StyledText { text: root.effectivePresentation + "  ·  " + root.effectiveBackground; color: Appearance.colors.colSubtext; font.pixelSize: 11 }
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                StyledText { text: "ORIGINAL"; color: Appearance.colors.colSubtext; font.pixelSize: 10 }
                                Image { source: root.selected ? "file://" + root.selected.source : ""; Layout.preferredWidth: 36; Layout.preferredHeight: 36; fillMode: Image.PreserveAspectFit }
                                StyledText { text: "GENERATED"; color: Appearance.colors.colSubtext; font.pixelSize: 10 }
                                Image { source: root.selected ? "file://" + root.selected.path : ""; Layout.preferredWidth: 36; Layout.preferredHeight: 36; fillMode: Image.PreserveAspectFit }
                                StyledText { visible: !!root.alternativeIcon; text: "ALTERNATIVE"; color: Appearance.colors.colSubtext; font.pixelSize: 10 }
                                Image { visible: !!root.alternativeIcon; source: root.alternativeIcon ? "file://" + root.alternativeIcon : ""; Layout.preferredWidth: 36; Layout.preferredHeight: 36; fillMode: Image.PreserveAspectFit }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                StudioButton { text: "Choose alternative"; onClicked: alternativePicker.open() }
                                StudioButton { text: "Clear"; enabled: !!root.alternativeIcon; onClicked: { root.alternativeIcon = ""; root.edit(); } }
                            }
                            StyledText { text: "Fit / fill"; color: Appearance.colors.colPrimary; font.pixelSize: 12 }
                            RowLayout {
                                Layout.fillWidth: true
                                StudioButton { Layout.fillWidth: true; text: "Fit · padded"; selected: root.effectivePresentation === "fit"; onClicked: { root.presentation = "fit"; root.edit(); } }
                                StudioButton { Layout.fillWidth: true; text: "Fill · edge extend"; selected: root.effectivePresentation === "fill"; onClicked: { root.presentation = "fill"; root.edit(); } }
                            }
                            StyledText { text: "Background"; color: Appearance.colors.colPrimary; font.pixelSize: 12 }
                            RowLayout {
                                Layout.fillWidth: true
                                StudioButton { text: "◉  Color wheel"; onClicked: picker.open() }
                                ToolbarTextField {
                                    id: hex
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    Layout.preferredHeight: 40
                                    maximumLength: 7
                                    Accessible.name: "Background hex color"
                                    colBackground: Appearance.m3colors.m3surfaceContainer
                                    onEditingFinished: {
                                        if (/^#[0-9a-fA-F]{6}$/.test(text)) {
                                            root.backgroundColor = text.toUpperCase();
                                            root.edit();
                                        } else text = root.effectiveBackground;
                                    }
                                }
                                StudioButton { text: "Reset"; onClicked: { root.backgroundColor = ""; hex.text = root.selected?.bg_color || ""; root.edit(); } }
                            }
                            RowLayout {
                                Repeater {
                                    model: [root.selected?.bg_color, root.theme.primary, root.theme.secondary, root.theme.tertiary, root.theme.neutral].filter(Boolean)
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 27; height: 27; radius: 14
                                        color: modelData
                                        border.color: Appearance.colors.colOnLayer1
                                        MouseArea { anchors.fill: parent; onClicked: { root.backgroundColor = parent.modelData; hex.text = root.backgroundColor; root.edit(); } }
                                    }
                                }
                            }
                            StyledText { text: "Color correction"; color: Appearance.colors.colPrimary; font.pixelSize: 12 }
                            StyledText { text: "Hue offset   " + Math.round(hue.value) + "°"; font.pixelSize: 12 }
                            StyledSlider { id: hue; Layout.fillWidth: true; from: -90; to: 90; stepSize: 1; onMoved: root.edit() }
                            StyledText { text: "Saturation   " + Math.round(saturation.value) + "%"; font.pixelSize: 12 }
                            StyledSlider { id: saturation; Layout.fillWidth: true; from: 50; to: 150; stepSize: 1; value: 100; onMoved: root.edit() }
                            StyledText { text: "Theme blend   " + Math.round(strength.value) + "%"; font.pixelSize: 12 }
                            StyledSlider { id: strength; Layout.fillWidth: true; from: 0; to: 100; stepSize: 1; value: 100; onMoved: root.edit() }
                            StyledText { text: "Feedback"; color: Appearance.colors.colPrimary; font.pixelSize: 12 }
                            RowLayout {
                                Layout.fillWidth: true
                                StudioButton { Layout.fillWidth: true; text: "✓ Looks good"; selected: root.flag === "looks good"; onClicked: { root.flag = selected ? "" : "looks good"; root.edit(); } }
                                StudioButton { Layout.fillWidth: true; text: "⚑ Needs work"; selected: root.flag === "needs work"; onClicked: { root.flag = selected ? "" : "needs work"; root.edit(); } }
                            }
                            MaterialTextArea {
                                id: notes; Layout.fillWidth: true
                                implicitHeight: 84; wrapMode: TextEdit.Wrap
                                placeholderText: "What should change?"
                                onTextChanged: root.edit()
                            }
                        }
                    }
                    StyledText { Layout.fillWidth: true; text: root.statusMessage; color: Appearance.colors.colSubtext; font.pixelSize: 11; wrapMode: Text.Wrap }
                    RowLayout {
                        Layout.fillWidth: true
                        StudioButton { text: "Discard"; enabled: root.dirty; onClicked: root.pick(root.selected, true) }
                        Item { Layout.fillWidth: true }
                        StudioButton {
                            id: saveButton
                            text: "Save review"
                            enabled: root.dirty && !backend.running && root.selected
                            prominent: true
                            onClicked: {
                                previewDelay.stop();
                                root.saveRevision = root.editRevision;
                                root.statusMessage = "Saving review…";
                                root.invoke("save", {id: root.selected.app_id, review: root.review()});
                            }
                        }
                    }
                }
            }
        }
    }
}
