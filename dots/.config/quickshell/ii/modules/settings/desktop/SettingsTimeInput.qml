pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common.widgets

// Keep Settings draft state at the boundary; TimeInput is shared with other UIs.
TimeInput {
    id:root
    timeFormat: {
        const revision=SettingsCatalog.revision;
        return String(SettingsCatalog.get("time.format") || "hh:mm");
    }
    Connections {
        target:SettingsCatalog
        function onDismissPopups() { root.close(); }
    }
}
