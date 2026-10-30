import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.ii.bar as Bar
import Quickshell
import Quickshell.Services.SystemTray

MouseArea {
    id: root
    focus: !previewMode
    required property LockContext context
    // Render the production controls in a standalone preview without input.
    property bool previewMode: false
    property bool bedtimeActive: false
    property string bedtimeDeadlineText: ""
    property string bedtimeDelayUntilText: ""
    property int bedtimeDelaysRemaining: 0
    property bool bedtimeDelayAllowed: true
    readonly property int bedtimeDelayMinutes: previewMode ? 30
        : Math.round(HomeAssistant.bedLockDelaySeconds / 60)
    signal bedtimeDelayRequested()
    property bool passwordRevealed: false
    readonly property bool showBedtimeToolbar: bedtimeActive && !passwordRevealed
        && context.targetAction === LockContext.ActionEnum.Unlock
    // One theme color drives the supporting toolbar foreground in both
    // states. The filled delay/submit button retains its own contrast colors.
    property color toolbarForegroundColor: showBedtimeToolbar
        ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
    Behavior on toolbarForegroundColor {
        ColorAnimation { duration: 350; easing.type: Easing.InOutCubic }
    }
    // The password field expands leftward and carries the bed glyph beyond
    // the fixed pill edge, where it is clipped by the pill-shaped viewport.
    // OutBack follows the target in either direction, so returning to bedtime
    // briefly passes its endpoint too before settling.
    property real passwordTransition: showBedtimeToolbar ? 0 : 1
    // Keep the active button footprint when a shorter disabled label appears.
    // The fixed shell and bed position must not react to delay availability.
    readonly property real delayButtonRestWidth: Math.max(150,
        Math.max(delayContent.implicitWidth, fullDelayLabel.implicitWidth + 28) + 24) + 6
    readonly property real bedtimeShellWidth: 57 + delayButtonRestWidth
    readonly property real passwordShellWidth: 260 + (fingerprintLoader.active ? fingerprintLoader.implicitWidth + 20 : 0)
    readonly property real bedtimeInnerRightMargin: Math.max(-6, Math.min(20,
        Math.max(0, (passwordShellWidth - bedtimeShellWidth) / 2) - 4))
    // The bed's reserved layout slot is 28px plus 6/9px margins; at the
    // bedtime endpoint it follows the original Toolbar padding and spacing.
    readonly property real bedHomeX: passwordShellWidth - bedtimeInnerRightMargin
        - (63 + delayButtonRestWidth) + 14
    property real bedSlideProgress: showBedtimeToolbar ? 0 : 1
    Behavior on bedSlideProgress {
        // OutBack reaches its endpoint before its settle phase. Have the bed
        // complete its smooth slide by then, so it never trails the button.
        NumberAnimation { duration: 140; easing.type: Easing.InOutCubic }
    }
    property real fieldProgress: showBedtimeToolbar ? 0 : 1
    Behavior on fieldProgress {
        NumberAnimation {
            duration: root.showBedtimeToolbar ? 270 : 340
            easing.type: root.showBedtimeToolbar ? Easing.InOutCubic : Easing.OutBack
            easing.overshoot: 1.4
        }
    }
    Behavior on passwordTransition {
        NumberAnimation {
            duration: 340
            easing.type: Easing.OutBack
            easing.overshoot: 1.4
        }
    }
    onPasswordRevealedChanged: {
        if (!previewMode) GlobalStates.bedtimePasswordRevealed = bedtimeActive && passwordRevealed;
    }
    Connections {
        target: GlobalStates
        function onBedtimePasswordRevealedChanged() {
            if (!root.previewMode && root.bedtimeActive
                    && root.passwordRevealed !== GlobalStates.bedtimePasswordRevealed)
                root.passwordRevealed = GlobalStates.bedtimePasswordRevealed;
        }
    }
    property bool active: false
    property bool showInputField: active || context.currentText.length > 0
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower

    StyledText {
        id: fullDelayLabel
        visible: false
        text: Translation.tr("Delay Until %1").arg(root.bedtimeDelayUntilText)
        font.pixelSize: Appearance.font.pixelSize.small
    }

    // Force focus on entry
    function forceFieldFocus() {
        if (root.previewMode || root.showBedtimeToolbar) return;
        if (!passwordBox.activeFocus) {
            passwordBox.forceActiveFocus();
        }
    }
    Connections {
        target: context
        function onShouldReFocus() {
            forceFieldFocus();
        }
    }

    Timer {
        id: initialFocusTimer
        interval: 50
        repeat: true
        running: !root.previewMode && GlobalStates.screenLocked && !root.showBedtimeToolbar && !passwordBox.activeFocus
        property int attempts: 0
        onTriggered: {
            forceFieldFocus();
            attempts++;
            if (passwordBox.activeFocus || attempts > 30) {
                running = false;
            }
        }
    }

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => {
        if (!root.showBedtimeToolbar) forceFieldFocus();
    }
    onPositionChanged: mouse => {
        if (!root.showBedtimeToolbar) forceFieldFocus();
    }
    onShowBedtimeToolbarChanged: {
        if (root.previewMode) return;
        if (root.showBedtimeToolbar) root.forceActiveFocus();
        else forceFieldFocus();
    }
    onBedtimeActiveChanged: {
        if (root.previewMode) return;
        if (!root.bedtimeActive) root.passwordRevealed = false;
        else if (GlobalStates.bedtimePasswordRevealed) root.passwordRevealed = true;
    }

    // Keep the outer capsules at their exact sizes, including on entry.
    readonly property real toolbarScale: 1
    property real toolbarOpacity: 0
    Behavior on toolbarOpacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Init
    Component.onCompleted: {
        if (!root.previewMode) forceFieldFocus();
        toolbarOpacity = 1;
    }

    // Key presses
    property bool ctrlHeld: false
    Keys.onPressed: event => {
        if (root.previewMode) return;
        if (root.showBedtimeToolbar) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    || (event.text.length > 0 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))) {
                root.passwordRevealed = true;
                forceFieldFocus();
                if (event.text.length > 0) passwordBox.text += event.text;
                event.accepted = true;
            }
            return;
        }
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = true;
        }
        if (event.key === Qt.Key_Escape) { // Esc to clear
            root.context.currentText = "";
        }
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (root.previewMode) return;
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = false;
        }
        forceFieldFocus();
    }

    // RippleButton {
    //     anchors {
    //         top: parent.top
    //         left: parent.left
    //         leftMargin: 10
    //         topMargin: 10
    //     }
    //     implicitHeight: 40
    //     colBackground: Appearance.colors.colLayer2
    //     onClicked: {
    //         context.unlocked(LockContext.ActionEnum.Unlock);
    //         GlobalStates.screenLocked = false;
    //     }
    //     contentItem: StyledText {
    //         text: "[[ DEBUG BYPASS ]]"
    //     }
    // }

    // The outer pill keeps the password width in both modes. Bedtime content
    // is centered inside it; only the inner controls change geometry.
    Toolbar {
        id: centerShell
        width: root.passwordShellWidth
        height: 56
        opacity: root.toolbarOpacity
        scale: root.toolbarScale
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
    }

    // This viewport shares the active fixed shell's silhouette. Its right edge
    // holds the submit/delay action in place while the field pushes the bed
    // glyph left and out of view.
    Item {
        id: centerViewport
        width: centerShell.width
        height: 56
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: centerViewport.width
                height: centerViewport.height
                radius: height / 2
            }
        }

    // The bedtime action contracts into submit as the password field reveals
    // to its left. This layout-only toolbar has no drawn background or shadow.
    Toolbar {
        id: centerIsland
        colBackground: "transparent"
        enableShadow: false
        anchors {
            right: parent.right
            rightMargin: Math.max(-6, Math.min(20,
                root.bedtimeInnerRightMargin * (1 - root.passwordTransition)))
            bottom: parent.bottom
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        Item {
            id: bedSlot
            visible: root.bedtimeActive
            Layout.leftMargin: 6
            Layout.rightMargin: 9
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
        }

        // Fingerprint
        Loader {
            id: fingerprintLoader
            visible: active && root.fieldProgress > 0
            opacity: root.fieldProgress
            Layout.leftMargin: 10
            Layout.rightMargin: 6
            Layout.alignment: Qt.AlignVCenter
            active: root.context.fingerprintsConfigured

            sourceComponent: MaterialSymbol {
                id: fingerprintIcon
                fill: 1
                text: "fingerprint"
                iconSize: Appearance.font.pixelSize.hugeass
                color: root.toolbarForegroundColor
            }
        }

        ToolbarTextField {
            id: passwordBox
            focus: !root.previewMode
            Layout.preferredWidth: Math.max(0, Math.min(220, 200 * root.fieldProgress))
            opacity: root.fieldProgress
            visible: root.fieldProgress > 0
            Layout.rightMargin: -Layout.leftMargin
            placeholderText: GlobalStates.screenUnlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Enter password")

            // Style
            clip: true
            font.pixelSize: Appearance.font.pixelSize.small
            selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
            selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

            // Password
            enabled: !root.context.unlockInProgress
            readOnly: root.previewMode
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData

            // Synchronizing (across monitors) and unlocking
            onTextChanged: root.context.currentText = this.text
            onAccepted: {
                if (root.previewMode) return;
                root.context.tryUnlock(ctrlHeld);
            }
            Connections {
                target: root.context
                function onCurrentTextChanged() {
                    passwordBox.text = root.context.currentText;
                }
            }

            Keys.onPressed: event => {
                if (root.previewMode) return;
                root.context.resetClearTimer();
            }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: passwordBox.width - 8
                    height: passwordBox.height
                    radius: height / 2
                }
            }

            // Shake when wrong password
            ErrorShakeAnimation {
                id: wrongPasswordShakeAnim
                target: passwordBox
            }
            Connections {
                target: GlobalStates
                function onScreenUnlockFailedChanged() {
                    if (GlobalStates.screenUnlockFailed) wrongPasswordShakeAnim.restart();
                }
            }

            // We're drawing dots manually
            property bool materialShapeChars: Config.options.lock.materialShapeChars
            color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
            Loader {
                active: passwordBox.materialShapeChars
                anchors {
                    fill: parent
                    leftMargin: passwordBox.padding
                    rightMargin: passwordBox.padding
                }
                sourceComponent: PasswordChars {
                    length: root.context.currentText.length
                    selectionStart: passwordBox.selectionStart
                    selectionEnd: passwordBox.selectionEnd
                    cursorPosition: passwordBox.cursorPosition
                }
            }
        }

        ToolbarButton {
            id: actionButton
            Layout.alignment: Qt.AlignVCenter
            Layout.fillHeight: false
            // Leave the bed's reserved gap clear even at the return overshoot.
            Layout.preferredWidth: Math.max(40, Math.min(root.delayButtonRestWidth + 6,
                40 + (root.delayButtonRestWidth - 40) * (1 - root.passwordTransition)))
            Layout.preferredHeight: 40
            toggled: true
            enabled: root.passwordTransition > 0.5
                ? !root.context.unlockInProgress : root.bedtimeDelayAllowed
            colBackgroundToggled: Appearance.colors.colPrimary
            buttonColor: root.showBedtimeToolbar && !root.bedtimeDelayAllowed
                ? Appearance.colors.colLayer4Base : Appearance.colors.colPrimary
            Accessible.name: root.showBedtimeToolbar ? delayLabel.text : Translation.tr("Unlock")

            onClicked: {
                if (root.previewMode) return;
                if (root.showBedtimeToolbar) root.bedtimeDelayRequested();
                else root.context.tryUnlock();
            }

            contentItem: Item {
                clip: true
                RowLayout {
                    id: delayContent
                    width: implicitWidth
                    anchors.centerIn: parent
                    spacing: 6
                    opacity: Math.max(0, 1 - root.passwordTransition * 2)
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "more_time"
                        iconSize: 18
                        color: actionButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        id: delayLabel
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: false
                        text: root.bedtimeDelaysRemaining <= 0
                            ? Translation.tr("Delay limit reached")
                            : root.bedtimeDelayAllowed && root.bedtimeDelayMinutes > 0
                                ? Translation.tr("Delay %1 minutes").arg(root.bedtimeDelayMinutes)
                                : Translation.tr("Delay unavailable")
                        horizontalAlignment: Text.AlignLeft
                        color: actionButton.enabled ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    opacity: Math.max(0, root.passwordTransition * 2 - 1)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    iconSize: 24
                    text: {
                        if (root.context.targetAction === LockContext.ActionEnum.Unlock)
                            return root.ctrlHeld ? "coffee" : "arrow_right_alt";
                        if (root.context.targetAction === LockContext.ActionEnum.Poweroff)
                            return "power_settings_new";
                        if (root.context.targetAction === LockContext.ActionEnum.Reboot)
                            return "restart_alt";
                        return "arrow_right_alt";
                    }
                    color: actionButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                }
            }
        }
    }
        MaterialSymbol {
            id: bedIcon
            visible: root.bedtimeActive
            x: root.bedHomeX + (-36 - root.bedHomeX) * root.bedSlideProgress
            anchors.verticalCenter: parent.verticalCenter
            text: "bed"
            iconSize: 28
            color: root.toolbarForegroundColor
            opacity: root.toolbarOpacity
        }
    }

    // Left toolbar
    Toolbar {
        id: leftIsland
        anchors {
            right: centerShell.left
            top: centerShell.top
            bottom: centerShell.bottom
            rightMargin: 10
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        // Username
        IconAndTextPair {
            Layout.leftMargin: 8
            icon: "account_circle"
            text: SystemInfo.username
        }

        // Keyboard layout (Xkb)
        Loader {
            Layout.rightMargin: 8
            Layout.fillHeight: true

            active: true
            visible: active

            sourceComponent: Row {
                spacing: 8

                MaterialSymbol {
                    id: keyboardIcon
                    anchors.verticalCenter: parent.verticalCenter
                    fill: 1
                    text: "keyboard_alt"
                    iconSize: Appearance.font.pixelSize.huge
                    color: root.toolbarForegroundColor
                }
                Loader {
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: StyledText {
                        text: HyprlandXkb.currentLayoutCode
                        color: root.toolbarForegroundColor
                        animateChange: true
                    }
                }
            }
        }

        // Keyboard layout (Fcitx)
        Bar.SysTray {
            Layout.rightMargin: 10
            Layout.alignment: Qt.AlignVCenter
            showSeparator: false
            showOverflowMenu: false
            pinnedItems: SystemTray.items.values.filter(i => i.id == "Fcitx")
            visible: pinnedItems.length > 0
        }
    }

    // Right toolbar
    Toolbar {
        id: rightIsland
        anchors {
            left: centerShell.right
            top: centerShell.top
            bottom: centerShell.bottom
            leftMargin: 10
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        IconAndTextPair {
            visible: Battery.available
            icon: Battery.isCharging ? "bolt" : "battery_android_full"
            text: Math.round(Battery.percentage * 100)
            color: (Battery.isLow && !Battery.isCharging) ? Appearance.colors.colError : root.toolbarForegroundColor
        }

        IconToolbarButton {
            id: sleepButton
            colText: root.toolbarForegroundColor
            onClicked: {
                if (!root.previewMode) Session.suspend();
            }
            text: "dark_mode"
        }

        PasswordGuardedIconToolbarButton {
            id: powerButton
            text: "power_settings_new"
            targetAction: LockContext.ActionEnum.Poweroff
        }

        PasswordGuardedIconToolbarButton {
            id: rebootButton
            text: "restart_alt"
            targetAction: LockContext.ActionEnum.Reboot
        }
    }

    component PasswordGuardedIconToolbarButton: IconToolbarButton {
        id: guardedBtn
        required property var targetAction

        toggled: root.context.targetAction === guardedBtn.targetAction
        colText: toggled ? Appearance.colors.colOnSecondaryContainer : root.toolbarForegroundColor

        onClicked: {
            if (root.previewMode) return;
            if (!root.requirePasswordToPower) {
                root.context.unlocked(guardedBtn.targetAction);
                return;
            }
            if (root.context.targetAction === guardedBtn.targetAction) {
                root.context.resetTargetAction();
            } else {
                root.context.targetAction = guardedBtn.targetAction;
                root.context.shouldReFocus();
            }
        }
    }

    component IconAndTextPair: Row {
        id: pair
        required property string icon
        required property string text
        property color color: root.toolbarForegroundColor

        spacing: 4
        Layout.fillHeight: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10


        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            fill: 1
            text: pair.icon
            iconSize: Appearance.font.pixelSize.huge
            animateChange: true
            color: pair.color
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: pair.text
            color: pair.color
        }
    }
}
