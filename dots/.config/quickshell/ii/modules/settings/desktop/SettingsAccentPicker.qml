pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services


Popup {
    id: root
    enter:OverlayTransition {}
    exit:OverlayTransition { entering:false }
    property string value: ""
    signal chosen(string value)

    readonly property var presets: [
        { name: "Ruby", hex: "#b3261e" },
        { name: "Coral", hex: "#bf542b" },
        { name: "Amber", hex: "#9a6700" },
        { name: "Lime", hex: "#71851e" },
        { name: "Emerald", hex: "#287b50" },
        { name: "Teal", hex: "#006b6b" },
        { name: "Sky", hex: "#00639b" },
        { name: "Blue", hex: "#315daa" },
        { name: "Indigo", hex: "#5c5db7" },
        { name: "Violet", hex: "#7b4ea3" },
        { name: "Magenta", hex: "#9c3d84" }
    ]
    property string lastCustomColor: ""
    readonly property bool customSelected: validColor(value) && !isPreset(value)
    readonly property color customColor: lastCustomColor || Appearance.colors.colSubtext
    function validColor(color) {
        return /^#[0-9a-fA-F]{6}$/.test(color);
    }
    function isPreset(color) {
        return presets.some(preset => preset.hex === color.toLowerCase());
    }
    function rememberCustom(color) {
        if (validColor(color) && !isPreset(color)) lastCustomColor = color.toLowerCase();
    }
    onValueChanged: rememberCustom(value)
    function select(value) {
        chosen(value);
        close();
    }

    parent: Overlay.overlay
    width: Math.min(360, parent ? parent.width - 32 : 360)
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 2 : 0
    modal: true
    focus: true
    padding: 20
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    Overlay.modal: Rectangle { color: Appearance.colors.colScrim }
    background: Rectangle {
        color: Appearance.m3colors.m3surfaceContainerHigh
        radius: Appearance.rounding.normal
    }
    onOpened: rememberCustom(value)
    onClosed: customPicker.close()

    ColorPickerDialog {
        id: customPicker
        objectName: "accentCustomColorPicker"
        z: root.z + 1
        initialColor: root.lastCustomColor || (root.validColor(root.value) ? root.value : Appearance.colors.colPrimary)
        onChosen: value => {
            root.lastCustomColor = value;
            root.select(value);
        }
    }

    contentItem: ColumnLayout {
        spacing: 18
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Accent color")
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer2
            }
            IconToolbarButton {
                text: "close"
                Accessible.name: Translation.tr("Close accent picker")
                onClicked: root.close()
            }
        }
        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: 6
            rowSpacing: 8
            columnSpacing: 8
            Repeater {
                model: root.presets
                delegate: RippleButton {
                    id: swatch
                    required property var modelData
                    implicitWidth: 42
                    implicitHeight: 42
                    buttonRadius: 21
                    colBackground: modelData.hex
                    colBackgroundHover: modelData.hex
                    colBackgroundToggled: modelData.hex
                    colBackgroundToggledHover: modelData.hex
                    toggled: root.value.toLowerCase() === modelData.hex
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: Translation.tr(modelData.name) + ", " + modelData.hex
                    Accessible.checked: toggled
                    onClicked: root.select(modelData.hex)
                    contentItem: Item {}
                    Rectangle {
                        anchors.fill:parent
                        anchors.margins:-3
                        radius:width/2
                        color:"transparent"
                        border.width:swatch.toggled ? 2 : 0
                        border.color:Appearance.colors.colOnSurface
                        Behavior on border.width {
                            enabled:!Config.options.launcher.reducedMotion
                            NumberAnimation { duration:100;easing.type:Easing.OutSine }
                        }
                    }
                    StyledToolTip { text: Translation.tr(swatch.modelData.name) }
                }
            }
            RippleButton {
                id: customSwatch
                implicitWidth: 42
                implicitHeight: 42
                buttonRadius: 21
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colBackgroundToggled: Appearance.colors.colLayer3
                colBackgroundToggledHover: Appearance.colors.colLayer3Hover
                toggled: root.customSelected
                Accessible.role: Accessible.RadioButton
                Accessible.name: Translation.tr("Custom color")
                Accessible.checked: toggled
                onClicked: customPicker.open()
                contentItem: MaterialSymbol {
                    text: "colorize"
                    iconSize: 24
                    color: root.customColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: customSwatch.toggled ? -3 : 0
                    radius: width / 2
                    color: "transparent"
                    border.width: customSwatch.toggled ? 2 : 1
                    border.color: root.customColor
                    Behavior on anchors.margins {
                        enabled: !Config.options.launcher.reducedMotion
                        NumberAnimation { duration: 100; easing.type: Easing.OutSine }
                    }
                }
                StyledToolTip { text: Translation.tr("Custom color") }
            }
        }
        DialogButton {
            buttonText: Translation.tr("Wallpaper")
            Accessible.name: Translation.tr("Use wallpaper color")
            onClicked: root.select("")
        }
    }
}
