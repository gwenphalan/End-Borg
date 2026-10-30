import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ToolbarTabButton {
    id:root
    current:false
    activeFocusOnTab:false
    focusPolicy:Qt.ClickFocus
    colBackgroundToggled:Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover:Appearance.colors.colSecondaryContainerHover
    opacity:enabled ? 1 : 0.4
    property real iconSize:18
    property real labelPixelSize:Appearance.font.pixelSize.smaller
    implicitHeight:28
    horizontalPadding:10
    contentItem:Row {
        anchors.centerIn:parent
        spacing:6
        MaterialSymbol {anchors.verticalCenter:parent.verticalCenter;text:root.materialSymbol;iconSize:root.iconSize}
        StyledText {anchors.verticalCenter:parent.verticalCenter;text:root.text;font.pixelSize:root.labelPixelSize}
    }
    Layout.fillWidth:false
    Layout.fillHeight:false
}
