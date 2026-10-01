import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    implicitWidth: rowLayout.implicitWidth
    implicitHeight: rowLayout.implicitHeight

    readonly property real extraWidth: (recordLoader.item?.extraWidth ?? 0)

    RowLayout {
        id: rowLayout

        spacing: 4
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        // 1. Screen Snip
        Loader {
            id: snipLoader
            active: Config.options.bar.utilButtons.showScreenSnip
            visible: Config.options.bar.utilButtons.showScreenSnip
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);
                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    fill: 1
                    text: "screenshot_region"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        // 2. Screen Record
        Loader {
            id: recordLoader
            active: Config.options.bar.utilButtons.showScreenRecord
            visible: Config.options.bar.utilButtons.showScreenRecord
            sourceComponent: RecordingUtilButton {
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // 3. Color Picker
        Loader {
            id: pickerLoader
            active: Config.options.bar.utilButtons.showColorPicker
            visible: Config.options.bar.utilButtons.showColorPicker
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: Quickshell.execDetached(["hyprpicker", "-a"])
                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    fill: 1
                    text: "colorize"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        // 4. Bed Mode Toggle
        Loader {
            id: bedLoader
            active: Config.options.bar.utilButtons.showBedModeToggle
            visible: Config.options.bar.utilButtons.showBedModeToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                toggled: BedMode.active
                onClicked: BedMode.toggle()
                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    fill: BedMode.active ? 1 : 0
                    text: BedMode.active ? "bed" : "single_bed"
                    iconSize: Appearance.font.pixelSize.large
                    color: BedMode.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2

                    Behavior on color {
                        animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }

        // 5. On-Screen Keyboard Toggle
        Loader {
            id: oskLoader
            active: Config.options.bar.utilButtons.showKeyboardToggle
            visible: Config.options.bar.utilButtons.showKeyboardToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                toggled: GlobalStates.oskOpen
                onClicked: GlobalStates.oskOpen = !GlobalStates.oskOpen
                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    fill: GlobalStates.oskOpen ? 1 : 0
                    text: "keyboard"
                    iconSize: Appearance.font.pixelSize.large
                    color: GlobalStates.oskOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2

                    Behavior on color {
                        animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }

        // 6. Microphone Mute Toggle
        Loader {
            id: micLoader
            active: Config.options.bar.utilButtons.showMicToggle
            visible: Config.options.bar.utilButtons.showMicToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                toggled: Pipewire.defaultAudioSource?.audio?.muted ?? false
                colBackgroundToggled: ColorUtils.transparentize(Appearance.colors.colError, 0.75)
                colBackgroundToggledHover: ColorUtils.transparentize(Appearance.colors.colError, 0.6)
                onClicked: Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_SOURCE@", "toggle"])
                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    fill: (Pipewire.defaultAudioSource?.audio?.muted ?? false) ? 1 : 0
                    text: (Pipewire.defaultAudioSource?.audio?.muted ?? false) ? "mic_off" : "mic"
                    iconSize: Appearance.font.pixelSize.large
                    color: (Pipewire.defaultAudioSource?.audio?.muted ?? false) ? Appearance.colors.colError : Appearance.colors.colOnLayer2

                    Behavior on color {
                        animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }

        // 7. Dark Mode Toggle
        Loader {
            id: darkModeLoader
            active: Config.options.bar.utilButtons.showDarkModeToggle
            visible: Config.options.bar.utilButtons.showDarkModeToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: event => {
                    if (Appearance.m3colors.darkmode) {
                        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode light --noswitch`])
                    } else {
                        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode dark --noswitch`])
                    }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    fill: 0
                    text: Appearance.m3colors.darkmode ? "light_mode" : "dark_mode"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        // 8. Performance Profile Toggle
        Loader {
            id: performanceLoader
            active: Config.options.bar.utilButtons.showPerformanceProfileToggle
            visible: Config.options.bar.utilButtons.showPerformanceProfileToggle
            sourceComponent: CircleUtilButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: event => {
                    if (PowerProfiles.hasPerformanceProfile) {
                        switch(PowerProfiles.profile) {
                            case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced
                            break;
                            case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance
                            break;
                            case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver
                            break;
                        }
                    } else {
                        PowerProfiles.profile = PowerProfiles.profile == PowerProfile.Balanced ? PowerProfile.PowerSaver : PowerProfile.Balanced
                    }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    fill: PowerProfiles.profile === PowerProfile.Performance ? 1 : 0
                    text: switch(PowerProfiles.profile) {
                        case PowerProfile.PowerSaver: return "energy_savings_leaf"
                        case PowerProfile.Balanced: return "airwave"
                        case PowerProfile.Performance: return "local_fire_department"
                    }
                    iconSize: Appearance.font.pixelSize.large
                    color: switch(PowerProfiles.profile) {
                        case PowerProfile.PowerSaver: return Appearance.colors.colPrimary
                        case PowerProfile.Balanced: return Appearance.colors.colSecondary
                        case PowerProfile.Performance: return Appearance.colors.colError
                        default: return Appearance.colors.colOnLayer2
                    }

                    Behavior on color {
                        animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
