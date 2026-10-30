import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// One moving indicator across the whole strip, including separator boundaries.
Item {
    id:root
    required property var controller
    property var items:[]
    property bool labeled:false
    property int orientation:Qt.Vertical
    property real buttonSize:labeled ? 28 : 40
    property Item hoveredButton:null
    property Item selectedButton:null
    implicitWidth:grid.implicitWidth
    implicitHeight:grid.implicitHeight
    readonly property int visibleActionCount:items.filter(item=>item.action && controller.visibleFor(item.action)).length
    function updateSelection() {
        let selected=null;
        for(let i=0;i<delegates.count;i++) {
            const slot=delegates.itemAt(i);
            if(slot && slot.button && slot.button.visible && slot.button.toggled && slot.button.enabled) {selected=slot.button;break;}
        }
        selectedButton=selected;
        if(hoveredButton && (!hoveredButton.enabled || !hoveredButton.visible)) hoveredButton=null;
    }
    HoverHandler {id:stripHover;onHoveredChanged:if(!hovered) root.hoveredButton=null}
    SelectionIndicator {
        anchors.fill:parent
        container:root
        selectedItem:root.selectedButton
        hoveredItem:root.hoveredButton
        selectedColor:Appearance.colors.colPrimary
        hoverColor:Appearance.colors.colSecondaryContainer
    }
    GridLayout {
        id:grid
        anchors.fill:parent
        columns:root.orientation===Qt.Horizontal ? Math.max(1,root.items.length) : 1
        rowSpacing:4;columnSpacing:6
        Repeater {
            id:delegates
            model:root.items
            delegate:Item {
                id:slot
                required property var modelData
                readonly property Item button:buttonLoader.item
                Layout.fillWidth:!!modelData.stretch
                Layout.preferredWidth:modelData.separator ? 13 : modelData.stretch ? 0 : button ? button.implicitWidth : 0
                Layout.preferredHeight:modelData.separator ? 18 : button ? button.implicitHeight : 0
                visible:!modelData.action || root.controller.visibleFor(modelData.action)
                HoverHandler {
                    onHoveredChanged:if(hovered && slot.button) root.hoveredButton=slot.button.enabled ? slot.button : null
                }
                Rectangle {
                    visible:!!slot.modelData.separator
                    anchors.centerIn:parent
                    width:1;height:18;color:Appearance.colors.colOutlineVariant
                }
                Loader {
                    id:buttonLoader
                    anchors.fill:parent
                    active:!!slot.modelData.action
                    sourceComponent:ToolActionButton {
                        id:actionButton
                        actionId:slot.modelData.action
                        controller:root.controller
                        labeled:root.labeled
                        buttonSize:root.buttonSize
                        onToggledChanged:Qt.callLater(root.updateSelection)
                        onEnabledChanged:root.updateSelection()
                        onVisibleChanged:root.updateSelection()
                        onVisualFocusChanged:if(visualFocus && enabled) root.hoveredButton=actionButton
                        // A disabled button clears hover, while separators retain the last target.
                        HoverHandler {
                            onHoveredChanged:if(hovered) root.hoveredButton=actionButton.enabled ? actionButton : null
                        }
                        Component.onCompleted:Qt.callLater(root.updateSelection)
                        Component.onDestruction:{if(root.selectedButton===actionButton) root.selectedButton=null;if(root.hoveredButton===actionButton) root.hoveredButton=null;}
                    }
                }
            }
        }
    }
}
