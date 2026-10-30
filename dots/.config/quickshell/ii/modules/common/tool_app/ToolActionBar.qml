import QtQuick
import QtQuick.Layouts
import "ToolDefinition.js" as Definition

ToolActionStrip {
    required property var groups
    items:Definition.flattenToolbar(groups.map(group=>group.stretch ? group : {actions:group.actions.filter(id=>controller.visibleFor(id))}))
    orientation:Qt.Horizontal
    labeled:true
    Layout.fillWidth:true
}
