pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    required property int value
    signal chosen(int value)
    property Item selectedButton:null
    property Item hoveredButton:null
    implicitWidth:positionsRow.implicitWidth
    implicitHeight:34
    readonly property var positions: [
        {name: Translation.tr("Top"), icon: "vertical_align_top", value: 0},
        {name: Translation.tr("Left"), icon: "align_horizontal_left", value: 2},
        {name: Translation.tr("Bottom"), icon: "vertical_align_bottom", value: 1},
        {name: Translation.tr("Right"), icon: "align_horizontal_right", value: 3}
    ]
    SelectionIndicator {
        anchors.fill:parent
        container:positionsRow
        selectedItem:root.selectedButton
        hoveredItem:root.hoveredButton
    }
    RowLayout {
        id:positionsRow
        anchors.fill:parent
        spacing:6
        Repeater {
            model: root.positions
            delegate: RippleButton {
                id:positionButton
                required property var modelData
                Layout.preferredWidth:52
                Layout.minimumWidth:52
                Layout.maximumWidth:52
                implicitHeight:34
                buttonRadius:Appearance.rounding.full
                toggled:root.value===modelData.value
                background:Rectangle {
                    color:"transparent"
                    radius:height/2
                    border.width:positionButton.visualFocus ? 2 : 0
                    border.color:positionButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                }
                onToggledChanged:{
                    if (toggled) root.selectedButton=positionButton;
                    else if (root.selectedButton===positionButton) root.selectedButton=null;
                }
                Component.onCompleted:if (toggled) root.selectedButton=positionButton
                onIsHoveredChanged:{
                    if (isHovered) root.hoveredButton=positionButton;
                    else if (root.hoveredButton===positionButton) root.hoveredButton=null;
                }
                Accessible.role:Accessible.RadioButton
                Accessible.checked:toggled
                Accessible.name:Translation.tr("Bar position: %1").arg(modelData.name)
                onClicked:root.chosen(modelData.value)
                contentItem:MaterialSymbol {
                    text:positionButton.modelData.icon
                    iconSize:24
                    fill:positionButton.toggled ? 1 : 0
                    color:positionButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    horizontalAlignment:Text.AlignHCenter
                    verticalAlignment:Text.AlignVCenter
                }
                StyledToolTip {text:positionButton.modelData.name}
            }
        }
    }
}
