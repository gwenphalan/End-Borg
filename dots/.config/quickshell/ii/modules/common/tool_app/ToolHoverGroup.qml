import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// One shared moving fill for direct-composition buttons. Separators preserve the
// last hover target; disabled controls clear it. Compound inputs are excluded.
Item {
    id:root
    objectName:"toolHoverGroup"
    property Item container:parent
    property var buttons:[]
    property Item hoveredButton:null
    readonly property Item selectedButton:buttons.find(button=>button.visible && button.enabled && (("current" in button && button.current) || ("toggled" in button && button.toggled))) || null
    anchors.fill:parent
    function collect(item,result) {
        // Declarative strips already supply their own shared indicator.
        if(item!==container && "hoveredButton" in item && "selectedButton" in item) return;
        if("clicked" in item && "colBackgroundHover" in item) {result.push(item);return;}
        for(const child of item.children || []) if(child!==root) collect(child,result);
    }
    function refresh() {
        const found=[];collect(container,found);
        for(const button of found) if(!buttons.includes(button)) {
            button.colBackgroundHover="transparent";
            if("colBackgroundToggledHover" in button) button.colBackgroundToggledHover="transparent";
            if("colBackgroundToggled" in button) button.colBackgroundToggled="transparent";
        }
        buttons=found;
        if(hoveredButton && (!buttons.includes(hoveredButton) || !hoveredButton.enabled || !hoveredButton.visible)) hoveredButton=null;
    }
    function updateHover(position) {
        refresh();
        for(const button of buttons) {
            const point=button.mapFromItem(root,position.x,position.y);
            if(button.visible && point.x>=0 && point.y>=0 && point.x<button.width && point.y<button.height) {
                hoveredButton=button.enabled ? button : null;return;
            }
        }
        // Keep the last target while crossing a separator/gap inside the strip.
    }
    onWidthChanged:Qt.callLater(refresh)
    onHeightChanged:Qt.callLater(refresh)
    Component.onCompleted:Qt.callLater(refresh)
    HoverHandler {
        id:hover
        parent:root.container
        blocking:false
        onPointChanged:if(hovered) root.updateHover(point.position)
        onHoveredChanged:if(!hovered) root.hoveredButton=null;else root.updateHover(point.position)
    }
    SelectionIndicator {
        anchors.fill:parent
        container:root.container
        selectedItem:root.selectedButton
        hoveredItem:root.hoveredButton && root.hoveredButton.enabled ? root.hoveredButton : null
        selectedColor:Appearance.colors.colSecondaryContainer
        hoverColor:Appearance.colors.colSecondaryContainer
    }
}
