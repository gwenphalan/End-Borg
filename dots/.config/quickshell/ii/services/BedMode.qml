pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.modules.common

/**
 * Bed Mode Service: toggles stereo audio channel swapping (L <-> R)
 * when watching the bed TV opposite the desk monitors.
 */
Singleton {
    id: root

    readonly property bool active: Pipewire.defaultAudioSink?.name === "reverse-stereo" || 
        ((Pipewire.defaultAudioSink?.description ?? "").toLowerCase().indexOf("bed mode") !== -1)

    function toggle() {
        Quickshell.execDetached(["/home/gwenp/.config/hypr/custom/scripts/toggle-bed-mode.sh", "toggle"]);
    }

    function enable() {
        Quickshell.execDetached(["/home/gwenp/.config/hypr/custom/scripts/toggle-bed-mode.sh", "on"]);
    }

    function disable() {
        Quickshell.execDetached(["/home/gwenp/.config/hypr/custom/scripts/toggle-bed-mode.sh", "off"]);
    }

    IpcHandler {
        target: "bedMode"

        function toggle(): void {
            root.toggle();
        }

        function enable(): void {
            root.enable();
        }

        function disable(): void {
            root.disable();
        }
    }

    GlobalShortcut {
        name: "bedModeToggle"
        description: "Toggle bed mode (reverse audio channels)"
        onPressed: root.toggle()
    }
}
