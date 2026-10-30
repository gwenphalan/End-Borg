pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.services

StyledComboBox {
    id: root
    Connections {
        target: SettingsCatalog
        function onDismissPopups() { root.popup.close(); }
    }
    required property var choices
    required property var value
    property string label: ""
    property string settingPath: ""
    property color previewSurroundingColor: Appearance.colors.colLayer1
    function luminance(color) {
        const linear=value => value<=0.04045 ? value/12.92 : Math.pow((value+0.055)/1.055,2.4);
        return 0.2126*linear(color.r)+0.7152*linear(color.g)+0.0722*linear(color.b);
    }
    function contrast(first,second) {
        const a=luminance(first),b=luminance(second);
        return (Math.max(a,b)+0.05)/(Math.min(a,b)+0.05);
    }
    component PaletteSwatch:Rectangle {
        property string roleName:""
        property color surroundingColor:Appearance.m3colors.m3surfaceContainerHigh
        width:16;height:16;radius:width/2
        border.width:root.contrast(color,surroundingColor)<3 ? 1 : 0
        border.color:root.contrast(Qt.rgba(1,1,1,1),color)>root.contrast(Qt.rgba(0,0,0,1),color) ? "white" : "black"
        Behavior on border.width {
            enabled:!Config.options.launcher.reducedMotion
            NumberAnimation { duration:Math.round(Appearance.animation.elementMoveFast.duration/2);easing.type:Appearance.animation.elementMoveFast.type;easing.bezierCurve:Appearance.animation.elementMoveFast.bezierCurve }
        }
        HoverHandler { id:swatchHover }
        StyledToolTip { text:Translation.tr(parent.roleName);extraVisibleCondition:swatchHover.hovered;delay:500 }
    }
    component PaletteSwatchRow:Row {
        id:swatchRow
        property var swatches:[]
        property bool compact:false
        property color surroundingColor:Appearance.m3colors.m3surfaceContainerHigh
        spacing:compact ? 3 : 4
        width:(compact ? 12 : 16)*4+spacing*3
        height:compact ? 12 : 16
        Repeater {
            model:swatchRow.swatches
            delegate:PaletteSwatch {
                required property string modelData
                required property int index
                width:swatchRow.compact ? 12 : 16
                height:width
                color:modelData
                roleName:["Accent","Tonal","Background","Text"][index]
                surroundingColor:swatchRow.surroundingColor
            }
        }
    }
    readonly property Component selectedSwatchPreview:Component {
        PaletteSwatchRow {
            swatches:root.previewPalettes[root.value] || []
            compact:true
            surroundingColor:root.previewSurroundingColor
        }
    }
    readonly property bool paletteChoices: settingPath === "appearance.palette.type"
        || choices.some(choice => String(choice.value).startsWith("scheme-"))
    readonly property string previewAccent: {
        const revision = SettingsCatalog.revision;
        return String(SettingsCatalog.get("appearance.palette.accentColor") || "");
    }
    readonly property bool previewDark: SettingsCatalog.appearanceMode === "dark"
    readonly property string previewWallpaper: {
        const revision = SettingsCatalog.revision;
        return String(SettingsCatalog.get("background.wallpaperPath") || "");
    }
    property var previewPalettes: ({})
    property string previewBasis: ""
    property string previewSource: ""
    property bool autoPreviewDetected: false
    property string completedPreviewKey: ""
    property string runningPreviewKey: ""
    readonly property string previewKey: [previewAccent, previewDark, previewWallpaper].join("|")
    readonly property string palettePython: (Quickshell.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV")
        || FileUtils.trimFileProtocol(Directories.home) + "/.local/state/quickshell/.venv") + "/bin/python"
    // Ask the same color engine used by switchwall for its four displayed roles.
    // Dry runs never write templates, change the wallpaper, or reload applications.
    readonly property string previewProgram: `
import json, pathlib, re, subprocess, sys, tempfile

accent, mode, image_path, detector_path = sys.argv[1:]
sys.path.insert(0, str(pathlib.Path(detector_path).parent.parent / "settings"))
from appearance_preview import mode_wallpaper
schemes = ('content', 'expressive', 'fidelity', 'fruit-salad', 'monochrome',
           'neutral', 'rainbow', 'tonal-spot')
valid_schemes = {'scheme-' + name for name in schemes}
roles = ('primary', 'secondary_container', 'background', 'on_background')
video = pathlib.Path(image_path).suffix.lower() in {'.mp4', '.webm', '.mkv', '.avi', '.mov'}
custom = bool(re.fullmatch(r'#[0-9a-fA-F]{6}', accent))
palettes = {}
seed = ''
basis = 'Palette preview unavailable'
auto_scheme = 'scheme-tonal-spot'
auto_detected = False

try:
    # switchwall detects Auto on the original path before creating video thumbnails.
    # Its image detector cannot decode a video and falls back to tonal spot.
    if image_path and not video and pathlib.Path(image_path).is_file():
        detected = subprocess.run([sys.executable, detector_path, image_path],
                                  check=True, capture_output=True, text=True, timeout=10)
        if detected.stdout.strip() in valid_schemes:
            auto_scheme = detected.stdout.strip()
            auto_detected = True

    with tempfile.TemporaryDirectory(prefix='qs-palette-preview-') as temporary:
        source_path = str(mode_wallpaper(pathlib.Path(image_path), mode))
        if not custom and video:
            source_path = str(pathlib.Path(temporary) / 'frame.jpg')
            subprocess.run(['ffmpeg', '-y', '-i', str(mode_wallpaper(pathlib.Path(image_path), mode)), '-vframes', '1', source_path],
                           check=True, capture_output=True, timeout=15)
        if not custom and not pathlib.Path(source_path).is_file():
            raise FileNotFoundError('Wallpaper source is unavailable')

        for name in schemes:
            scheme = 'scheme-' + name
            command = ['matugen', '--dry-run', '--json', 'hex', '--mode', mode,
                       '--type', scheme]
            command += ['color', 'hex', accent] if custom else ['image', source_path]
            result = subprocess.run(command, check=True, capture_output=True,
                                    text=True, timeout=15)
            generated = json.loads(result.stdout)['colors']
            selected = generated[mode]
            palettes[scheme] = [selected[role].lower() for role in roles]
            if not seed:
                seed = selected.get('source_color') or generated.get('light', {}).get('source_color') or accent
        basis = 'Custom accent' if custom else ('Wallpaper first frame' if video else 'Wallpaper source color')
except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError, json.JSONDecodeError):
    # Empty swatches are honest when a source or matugen cannot be inspected.
    palettes = {}

if palettes:
    palettes['auto'] = palettes[auto_scheme]
print(json.dumps({'palettes': palettes, 'basis': basis, 'seed': seed,
                  'autoDetected': auto_detected}))
`
    function requestPreviews() {
        if (!paletteChoices || paletteProcess.running || completedPreviewKey === previewKey) return;
        runningPreviewKey = previewKey;
        paletteProcess.command = [palettePython, "-c", previewProgram, previewAccent,
            previewDark ? "dark" : "light", FileUtils.trimFileProtocol(previewWallpaper),
            Directories.scriptPath + "/colors/scheme_for_image.py"];
        paletteProcess.running = true;
    }
    onPreviewKeyChanged: if (paletteChoices) refreshPreview.restart()
    Component.onCompleted:if (paletteChoices) refreshPreview.restart()
    Timer {
        id: refreshPreview
        interval: 180
        onTriggered: root.requestPreviews()
    }
    Process {
        id: paletteProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    root.previewPalettes = result.palettes;
                    root.previewBasis = result.basis;
                    root.previewSource = result.seed;
                    root.autoPreviewDetected = !!result.autoDetected;
                    root.completedPreviewKey = root.runningPreviewKey;
                } catch (error) {
                    // Missing preview support leaves ordinary choices fully usable.
                    root.previewPalettes = ({});
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.paletteChoices && root.previewKey !== root.runningPreviewKey) refreshPreview.restart();
        }
    }

    signal chosen(var value)
    implicitWidth: 180
    implicitHeight: 36
    textRole: "name"
    valueRole: "value"
    model: choices
    currentIndex: choices.findIndex(choice => choice.value === value)
    Accessible.name: label
    function choiceEnabled(index) {
        return index >= 0 && index < choices.length && choices[index].enabled !== false;
    }
    function nextEnabled(index, direction) {
        for (let candidate = index + direction; candidate >= 0 && candidate < choices.length; candidate += direction) {
            if (choiceEnabled(candidate)) return candidate;
        }
        return choiceEnabled(index) ? index : -1;
    }
    function chooseIndex(index) {
        if (!choiceEnabled(index)) return;
        popup.close();
        chosen(choices[index].value);
    }
    onActivated: index => {
        if (choiceEnabled(index)) chosen(choices[index].value);
        else currentIndex = choices.findIndex(choice => choice.value === value);
    }
    // Own arrow navigation so disabled choices cannot be activated by ComboBox.
    Keys.onPressed: event => {
        if ([Qt.Key_Up, Qt.Key_Down, Qt.Key_Home, Qt.Key_End].indexOf(event.key) < 0) return;
        const direction = event.key === Qt.Key_Up || event.key === Qt.Key_End ? -1 : 1;
        const start = event.key === Qt.Key_Home ? -1 : event.key === Qt.Key_End ? choices.length : currentIndex;
        if (!popup.visible) popup.open();
        options.currentIndex = nextEnabled(start, direction);
        event.accepted = true;
    }
    leftPadding: 0
    rightPadding: 0
    indicator: MaterialSymbol {
        width: 20
        height: 20
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "keyboard_arrow_down"
        iconSize: 20
        color: Appearance.colors.colOnSecondaryContainer
        rotation: root.popup.visible ? 180 : 0
    }
    readonly property string selectedIcon: currentIndex >= 0 && currentIndex < choices.length ? String(choices[currentIndex].icon || "") : ""
    contentItem:Item {
        implicitHeight:24
        RowLayout {
            anchors.fill:parent
            anchors.leftMargin:12;anchors.rightMargin:34
            MaterialSymbol {
                visible: root.selectedIcon.length > 0
                text: root.selectedIcon
                iconSize: 18
                color: Appearance.colors.colOnSecondaryContainer
                opacity: root.choiceEnabled(root.currentIndex) ? 1 : 0.38
            }
            StyledText {
                Layout.fillWidth:true
                text:root.displayText
                color:Appearance.colors.colOnSecondaryContainer
                opacity: root.choiceEnabled(root.currentIndex) ? 1 : 0.38
                elide:Text.ElideRight
            }
        }
    }
    popup: Popup {
        enter: OverlayTransition {}
        exit: OverlayTransition { entering: false }
        y: root.height + 4
        x: root.width - width
        margins: 8
        width: Math.max(root.paletteChoices ? 280 : 220, root.width)
        height: Math.min(420, options.contentHeight + 16)
        padding: 8
        onOpened: {
            root.requestPreviews();
            Qt.callLater(() => {
                options.currentIndex = root.choiceEnabled(root.currentIndex) ? root.currentIndex : root.nextEnabled(-1, 1);
                options.forceActiveFocus();
            });
        }
        background: Rectangle {
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
        }
        contentItem: ListView {
            id: options
            clip: true
            spacing: 2
            model: root.popup.visible ? root.choices : []
            keyNavigationEnabled: false
            Keys.onPressed: event => {
                if ([Qt.Key_Up, Qt.Key_Down, Qt.Key_Home, Qt.Key_End].indexOf(event.key) < 0) return;
                const direction = event.key === Qt.Key_Up || event.key === Qt.Key_End ? -1 : 1;
                const start = event.key === Qt.Key_Home ? -1 : event.key === Qt.Key_End ? root.choices.length : currentIndex;
                currentIndex = root.nextEnabled(start, direction);
                positionViewAtIndex(currentIndex, ListView.Contain);
                event.accepted = true;
            }
            SelectionIndicator {
                id: selectionIndicator
                animate:root.popup.opened
                parent: options.contentItem
                anchors.fill: parent
                z: -1
                radius: Appearance.rounding.small
            }
            Keys.onSpacePressed: event => {
                root.chooseIndex(currentIndex);
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                root.chooseIndex(currentIndex);
                event.accepted = true;
            }
            Keys.onReturnPressed: event => {
                root.chooseIndex(currentIndex);
                event.accepted = true;
            }
            delegate: Item {
                id: optionRow
                required property var modelData
                required property int index
                readonly property bool separated: index > 0 && !!modelData.separatorBefore
                width: options.width
                implicitHeight: option.implicitHeight + (separated ? 12 : 0)
                height: implicitHeight
                Rectangle {
                    visible: optionRow.separated
                    x: 8
                    y: 5
                    width: parent.width - 16
                    height: 1
                    color: Appearance.m3colors.m3outlineVariant
                }
                RippleButton {
                    id: option
                    readonly property var modelData: optionRow.modelData
                    readonly property int index: optionRow.index
                    y: optionRow.separated ? 12 : 0
                    readonly property var swatches: root.paletteChoices ? (root.previewPalettes[modelData.value] || []) : []
                    width: options.width
                    enabled: modelData.enabled !== false
                    opacity: enabled ? 1 : 0.38
                    activeFocusOnTab: false
                    implicitHeight: 40
                    toggled: root.value === modelData.value
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: "transparent"
                    colBackgroundToggled: "transparent"
                    colBackgroundToggledHover: "transparent"
                    Accessible.name: modelData.name
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: toggled
                    Component.onCompleted: if (toggled && enabled) selectionIndicator.selectedItem = option
                    Component.onDestruction: {
                        if (selectionIndicator.selectedItem === option) selectionIndicator.selectedItem = null;
                        if (selectionIndicator.hoveredItem === option) selectionIndicator.hoveredItem = null;
                    }
                    onEnabledChanged: {
                        if (!enabled && selectionIndicator.selectedItem === option) selectionIndicator.selectedItem = null;
                        if (!enabled && selectionIndicator.hoveredItem === option) selectionIndicator.hoveredItem = null;
                        if (enabled && toggled) selectionIndicator.selectedItem = option;
                    }
                    onToggledChanged: {
                        if (toggled && enabled) selectionIndicator.selectedItem = option;
                        else if (selectionIndicator.selectedItem === option) selectionIndicator.selectedItem = null;
                    }
                    onIsHoveredChanged: {
                        if (isHovered && enabled) selectionIndicator.hoveredItem = option;
                        else if (selectionIndicator.hoveredItem === option) selectionIndicator.hoveredItem = null;
                    }
                    onClicked: {
                        root.chooseIndex(index);
                    }
                    contentItem: RowLayout {
                        spacing: 8
                        PaletteSwatchRow {
                            visible:root.paletteChoices
                            Layout.preferredWidth:width
                            Layout.preferredHeight:height
                            Layout.alignment:Qt.AlignVCenter
                            swatches:option.swatches
                            surroundingColor:option.toggled ? Appearance.m3colors.m3primary : option.isHovered ? Appearance.m3colors.m3secondaryContainer : Appearance.m3colors.m3surfaceContainerHigh
                        }
                        MaterialSymbol {
                            visible: !!option.modelData.icon
                            text: String(option.modelData.icon || "")
                            iconSize: 18
                            color: option.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: option.modelData.name
                            elide: Text.ElideRight
                            color: option.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: SpotlightScrollBar {
                scrolling: options.moving
            }
        }
    }
}
