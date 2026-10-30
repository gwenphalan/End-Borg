import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import "../../common/BarUtilities.js" as Utilities
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

    readonly property var utilityKeys: Utilities.ordered(Config.options.bar.utilButtons.order).filter(key => Config.options.bar.utilButtons[key])
    property int utilityRevision: 0
    readonly property real extraWidth: {
        const observed=utilityRevision;
        let recordingWidth=0;
        for (let i=0;i<utilityRepeater.count;i++) recordingWidth+=utilityRepeater.itemAt(i)?.item?.extraWidth ?? 0;
        return recordingWidth + (Config.options.homeAssistant.enabled && Config.options.homeAssistant.showBarControls ? 30 * ((Config.options.homeAssistant.showBarHomeButton ? 1 : 0) + HomeAssistant.barControls.length) : 0);
    }

    RowLayout {
        id: rowLayout

        spacing: 4
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        Loader {
            active: Config.options.homeAssistant.enabled && Config.options.homeAssistant.showBarControls && Config.options.homeAssistant.showBarHomeButton
            visible: active
            sourceComponent: CircleUtilButton {
                id: homeButton
                toggled: GlobalStates.sidebarRightOpen && Persistent.states.sidebar.bottomGroup.tab === 0
                onClicked: {
                    const closeHome = toggled;
                    Persistent.states.sidebar.bottomGroup.tab = 0;
                    Persistent.states.sidebar.bottomGroup.collapsed = false;
                    GlobalStates.sidebarRightOpen = !closeHome;
                }
                altAction: () => HomeAssistant.openSettings()
                content: Item {
                    MaterialSymbol { anchors.centerIn:parent; text:"home"; fill:homeButton.toggled ? 1 : 0; iconSize:Appearance.font.pixelSize.large; color:Appearance.colors.colOnLayer2 }
                    StyledToolTip { text:Translation.tr("Home controls · Right-click for settings"); extraVisibleCondition:homeButton.isHovered }
                }
            }
        }
        Repeater {
            model: ScriptModel {
                values:Config.options.homeAssistant.enabled && Config.options.homeAssistant.showBarControls ? HomeAssistant.barControls : []
                objectProp:"entity_id"
            }
            delegate: CircleUtilButton {
                id: quickHomeButton
                required property var modelData
                enabled: HomeAssistant.available(modelData) && !HomeAssistant.busy[modelData.entity_id]
                toggled: ["on","playing"].includes(modelData.state)
                onClicked: HomeAssistant.activate(modelData)
                altAction: () => {
                    Persistent.states.sidebar.bottomGroup.tab = 0;
                    Persistent.states.sidebar.bottomGroup.collapsed = false;
                    GlobalStates.sidebarRightOpen = true;
                }
                Accessible.name: HomeAssistant.name(modelData) + ", " + HomeAssistant.status(modelData)
                content: Item {
                    MaterialSymbol { anchors.centerIn:parent; text:HomeAssistant.icon(quickHomeButton.modelData); fill:quickHomeButton.toggled ? 1 : 0; iconSize:Appearance.font.pixelSize.large; color:quickHomeButton.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2 }
                    StyledToolTip { text:HomeAssistant.name(quickHomeButton.modelData) + " · " + HomeAssistant.status(quickHomeButton.modelData); extraVisibleCondition:quickHomeButton.isHovered }
                }
            }
        }

        Repeater {
            id: utilityRepeater
            model: root.utilityKeys
            onItemAdded: root.utilityRevision++
            onItemRemoved: root.utilityRevision++
            delegate: Loader {
                required property string modelData
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: {
                    switch (modelData) {
                    case "showScreenSnip": return snipComponent;
                    case "showScreenRecord": return recordComponent;
                    case "showColorPicker": return pickerComponent;
                    case "showBedModeToggle": return bedComponent;
                    case "showKeyboardToggle": return keyboardComponent;
                    case "showMicToggle": return micComponent;
                    case "showDarkModeToggle": return themeComponent;
                    case "showPerformanceProfileToggle": return powerComponent;
                    default: return null;
                    }
                }
            }
        }
    }
    Component {
        id: snipComponent
        CircleUtilButton {
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
    Component {
        id: recordComponent
        RecordingUtilButton {
            Layout.alignment: Qt.AlignVCenter
        }
    }
    Component {
        id: pickerComponent
        CircleUtilButton {
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
    Component {
        id: bedComponent
        CircleUtilButton {
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
    Component {
        id: keyboardComponent
        CircleUtilButton {
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
    Component {
        id: micComponent
        CircleUtilButton {
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
    Component {
        id: themeComponent
        CircleUtilButton {
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
    Component {
        id: powerComponent
        CircleUtilButton {
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
