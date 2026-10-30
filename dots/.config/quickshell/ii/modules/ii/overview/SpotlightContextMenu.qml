import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    required property var controller
    // Alternate actions let other app grids reuse Spotlight's menu without mutating launcher state.
    property var actions:null
    signal actionTriggered(string action,var app)
    readonly property var menuActions:actions!==null ? actions : [
        {icon:controller.menuApp && LauncherApps.isPinned(controller.menuApp.id) ? "keep_off" : "push_pin",label:controller.menuApp && LauncherApps.isPinned(controller.menuApp.id) ? "Unpin" : "Pin",action:"pin"},
        {icon:controller.menuApp && LauncherApps.isHidden(controller.menuApp.id) ? "visibility" : "visibility_off",label:controller.menuApp && LauncherApps.isHidden(controller.menuApp.id) ? "Unhide" : "Hide",action:"hide"},
        {icon:"open_in_new",label:"Open",action:"open"},
        {icon:"delete",label:"Uninstall…",action:"uninstall"}
    ]
    property bool focusWhenReady:false
    function focusFirstAction() {
        if (!card.enabled) { focusWhenReady=true;return; }
        focusWhenReady=false;
        const button=menuItems.itemAt(0);
        if (button) button.forceActiveFocus(Qt.PopupFocusReason);
    }
    Connections { target:root.controller;function onMenuOpenChanged() { if (!root.controller.menuOpen) root.focusWhenReady=false; } }
    Connections { target:card;function onEnabledChanged() { if (card.enabled && root.focusWhenReady) root.focusFirstAction(); } }
    function triggerAction(action) {
        const app=controller.menuApp;
        controller.dismissMenus();
        if (!app) return;
        if (actions!==null) { actionTriggered(action,app);return; }
        if (action==="pin") LauncherApps.togglePin(app.id);
        else if (action==="hide") LauncherApps.toggleHidden(app.id);
        else if (action==="uninstall") {
            controller.close();
            LauncherApps.uninstall(app);
        }
        else {
            controller.close();
            if (!app.runInTerminal) app.execute();
            else Quickshell.execDetached(["bash","-c",`${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(app.command.join(' '))}'`]);
        }
    }
    visible: controller.menuOpen || card.progress !== 0
    function inspect() {
        const origin = card.mapToItem(null, 0, 0);
        return {visible: root.visible, cardVisible: card.visible, progress: card.progress,
            x: origin.x, y: origin.y, width: card.width, height: card.height};
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.controller.menuOpen
        onClicked: root.controller.dismissMenus()
    }
    SpotlightSurface {
        id: card
        controller: root.controller
        shown: root.controller.open && root.controller.menuOpen
        targetWidth: 200
        targetHeight:root.menuActions.length*40+12
        surfaceRadius: Appearance.rounding.normal
        surfaceColor: Appearance.m3colors.m3surfaceContainerHigh
        x: Math.max(8, Math.min(root.width - targetWidth - 8, root.controller.menuAnchor.x))
        y: Math.max(8, Math.min(root.height - targetHeight - 8, root.controller.menuAnchor.y))
        Column {
            anchors.fill: parent
            anchors.margins: 6
            Repeater {
                id:menuItems
                model:root.menuActions
                delegate: RippleButton {
                    required property var modelData
                    width: parent.width
                    height: 40
                    buttonRadius: Appearance.rounding.small
                    Keys.forwardTo: [root.controller.keyRouter]
                    onClicked:root.triggerAction(modelData.action)
                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol { text: modelData.icon; iconSize: 20; color: Appearance.colors.colPrimary }
                        StyledText { text: Translation.tr(modelData.label); Layout.fillWidth: true }
                    }
                }
            }
        }
    }
}
