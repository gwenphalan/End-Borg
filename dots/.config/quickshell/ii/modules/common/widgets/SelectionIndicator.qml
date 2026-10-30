import QtQuick
import qs.modules.common
import qs.modules.common.models

// Place behind a set of single-selection controls. Targets may be descendants of container.
Item {
    id: root
    property Item container: parent
    property Item selectedItem: null
    property Item hoveredItem: null
    property real radius: 999
    property real inset: 0
    property color selectedColor: Appearance.m3colors.m3primary
    property real selectedBorderWidth: 0
    property color selectedBorderColor: Appearance.m3colors.m3primary
    property color hoverColor: Appearance.m3colors.m3secondaryContainer
    property bool reducedMotion: Config.options.launcher.reducedMotion
    property bool animate: true
    property bool animateHover: true
    property bool settling: false
    property rect lastSelectedBounds: Qt.rect(0, 0, 0, 0)
    property rect lastHoverBounds: Qt.rect(0, 0, 0, 0)
    readonly property rect selectedBounds: selectedItem ? boundsFor(selectedItem) : lastSelectedBounds
    readonly property rect hoverBounds: hoveredItem ? boundsFor(hoveredItem) : lastHoverBounds
    onSelectedBoundsChanged: if (selectedItem) lastSelectedBounds = selectedBounds
    onHoverBoundsChanged: if (hoveredItem) lastHoverBounds = hoverBounds
    function boundsFor(item) {
        // Read ancestor geometry to keep bindings live without a frame timer or polling.
        let ancestor = item;
        let geometryDependency = 0;
        while (ancestor && ancestor !== container) {
            geometryDependency += ancestor.x + ancestor.y + ancestor.width + ancestor.height;
            ancestor = ancestor.parent;
        }
        const point = item.mapToItem(container, inset, inset);
        return Qt.rect(point.x, point.y, Math.max(0, item.width - inset * 2), Math.max(0, item.height - inset * 2));
    }
    onAnimateChanged:if (!animate) settle()
    onAnimateHoverChanged:if (!animateHover) settleHover()
    onReducedMotionChanged:if (reducedMotion) settle()
    function settle() {
        settling=true;
        if (hoverPill) hoverPill.settle();
        if (selectedPill) selectedPill.settle();
        settling=false;
    }
    function settleHover() {
        if (hoverPill) hoverPill.settle();
    }
    component MovingPill: Rectangle {
        id: pill
        required property rect bounds
        required property bool shown
        property bool channelEnabled: true
        property bool initialized: false
        property int settledFrames: 0
        readonly property bool motionEnabled: initialized && channelEnabled && root.animate && !root.reducedMotion && !root.settling
        onMotionEnabledChanged:if (!motionEnabled) settle()
        onBoundsChanged:if (!initialized) {
            settledFrames=0;
            settle();
        }
        // A Loader's first target can arrive after completion, and a layout can
        // still resize it on the following frame. Start at that final geometry.
        FrameAnimation {
            running:!pill.initialized && pill.shown && pill.bounds.width>0 && pill.bounds.height>0
            onTriggered: {
                pill.settle();
                pill.settledFrames++;
                if (pill.settledFrames>=2) pill.initialized=true;
            }
        }
        // Reuse Workspaces' exact 100/300 ms OutSine pair and min/max geometry.
        // Paired trailing edges also accommodate controls with different sizes.
        AnimatedTabIndexPair { id: leftEdge; index: pill.bounds.x; enabled: pill.motionEnabled }
        AnimatedTabIndexPair { id: rightEdge; index: pill.bounds.x + pill.bounds.width; enabled: pill.motionEnabled }
        AnimatedTabIndexPair { id: topEdge; index: pill.bounds.y; enabled: pill.motionEnabled }
        AnimatedTabIndexPair { id: bottomEdge; index: pill.bounds.y + pill.bounds.height; enabled: pill.motionEnabled }
        x: Math.min(leftEdge.idx1, leftEdge.idx2)
        y: Math.min(topEdge.idx1, topEdge.idx2)
        width: Math.max(0, Math.max(rightEdge.idx1, rightEdge.idx2) - x)
        height: Math.max(0, Math.max(bottomEdge.idx1, bottomEdge.idx2) - y)
        radius: Math.min(root.radius, bounds.width / 2, bounds.height / 2)
        opacity: shown ? 1 : 0
        function settle() {
            leftEdge.settle();rightEdge.settle();topEdge.settle();bottomEdge.settle();
            opacity=Qt.binding(() => shown ? 1 : 0);
        }
        Behavior on opacity { id:opacityBehavior; enabled: pill.motionEnabled; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    }
    MovingPill {
        id:hoverPill
        objectName: "settingsHoverIndicator"
        channelEnabled:root.animateHover
        bounds: root.hoverBounds
        shown: !!root.hoveredItem
        color: root.hoverColor
    }
    MovingPill {
        id:selectedPill
        objectName: "settingsSelectedIndicator"
        bounds: root.selectedBounds
        shown: !!root.selectedItem
        color: root.selectedColor
        border.width: root.selectedBorderWidth
        border.color: root.selectedBorderColor
    }
}
