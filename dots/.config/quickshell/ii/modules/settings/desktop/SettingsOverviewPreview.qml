pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    readonly property int revision: SettingsCatalog.revision
    readonly property int rows: { const observed=revision; return Math.max(1,Math.round(Number(SettingsCatalog.get("overview.rows")) || 1)); }
    readonly property int columns: { const observed=revision; return Math.max(1,Math.round(Number(SettingsCatalog.get("overview.columns")) || 1)); }
    readonly property bool reverseColumns: { const observed=revision; return !!SettingsCatalog.get("overview.orderRightLeft"); }
    readonly property bool reverseRows: { const observed=revision; return !!SettingsCatalog.get("overview.orderBottomUp"); }
    // Limit only the illustrative sample, never silently clamp the saved setting.
    readonly property int visibleRows: Math.min(rows,4)
    readonly property int visibleColumns: Math.min(columns,8)
    implicitHeight: Math.min(120,visibleRows*28)+24
    Accessible.name: Translation.tr("Workspace grid preview: %1 rows and %2 columns").arg(rows).arg(columns)
    Grid {
        anchors.horizontalCenter:parent.horizontalCenter
        columns:root.visibleColumns
        spacing:4
        Repeater {
            model:root.visibleRows*root.visibleColumns
            delegate:Rectangle {
                required property int index
                readonly property int row:Math.floor(index/root.visibleColumns)
                readonly property int col:index%root.visibleColumns
                readonly property int workspace:(root.reverseRows ? root.rows-1-row : row)*root.columns+(root.reverseColumns ? root.columns-col : col+1)
                width:Math.max(24,Math.min(58,(root.width-4*(root.visibleColumns-1))/root.visibleColumns))
                height:26
                radius:6
                color:Appearance.colors.colSecondaryContainer
                StyledText { anchors.centerIn:parent; text:parent.workspace; color:Appearance.colors.colOnSecondaryContainer; font.pixelSize:11 }
            }
        }
    }
    StyledText {
        anchors.horizontalCenter:parent.horizontalCenter
        anchors.bottom:parent.bottom
        text:root.rows>root.visibleRows || root.columns>root.visibleColumns ? Translation.tr("Showing part of %1 workspaces").arg(root.rows*root.columns) : Translation.tr("%1 workspaces").arg(root.rows*root.columns)
        color:Appearance.colors.colSubtext
        font.pixelSize:Appearance.font.pixelSize.smaller
    }
}
