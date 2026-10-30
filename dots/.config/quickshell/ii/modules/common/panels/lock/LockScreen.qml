pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    required property Component lockSurface
    property bool startupInitialized: false
    property alias context: lockContext
    readonly property bool bedtimeEnabled: Config.ready && Config.options.lock.bedtimeEnabled
        && !Config.options.lock.useHyprlock
    readonly property bool bedtimeStateReady: Persistent.ready
    readonly property real bedtimeNightEpoch: HomeAssistant.bedLockNightStartEpoch
    readonly property real bedtimeEpoch: HomeAssistant.bedLockBedtimeEpoch
    readonly property real bedtimeWakeEpoch: HomeAssistant.bedLockWakeEpoch
    readonly property bool bedtimeActive: GlobalStates.screenLocked && GlobalStates.bedtimeLockActive
    readonly property string bedtimeDeadlineText: activeBedtimeNightEpoch > 0 && activeBedtimeWakeEpoch > 0
        ? new Date(activeBedtimeWakeEpoch * 1000).toLocaleTimeString(Qt.locale(), "h:mm AP")
        : HomeAssistant.bedLockDeadlineText
    readonly property string bedtimeDelayUntilText: HomeAssistant.bedLockDelayUntilText
    readonly property int bedtimeDelaysRemaining: HomeAssistant.bedLockDelaysRemaining
    readonly property bool bedtimeDelayAllowed: HomeAssistant.bedLockDelayAllowed
        && !HomeAssistant.bedLockDelayPending
    property string armedBedtimeIso: ""
    property bool reconcileAfterUnlock: false
    property bool bedtimeWasActiveAtUnlock: false
    property real reconcileUnlockEpoch: 0
    property real cachedBedtimeAtUnlock: 0
    property real cachedWakeAtUnlock: 0
    property real cachedNightAtUnlock: 0
    property real activeBedtimeNightEpoch: 0
    property real activeBedtimeEpoch: 0
    property real activeBedtimeWakeEpoch: 0
    property bool activeBedtimeWakeReleased: false
    property bool activeBedtimePhoneDelayReleased: false
    property bool relockAfterPhoneDelayUnlock: false
    property bool pendingEndpointRelock: false
    property bool bedtimeSecureSyncRequested: false
    property bool localBedtimeDelayPending: false
    property bool bedtimeSettingObserved: false
    property bool previousBedtimeEnabled: false
    property bool bedtimeEnableCheckPending: false

    function observeBedtimeSetting() {
        if (!Config.ready || !Persistent.ready || root.bedtimeSettingObserved) return;
        root.previousBedtimeEnabled = root.bedtimeEnabled;
        root.bedtimeSettingObserved = true;
    }

    function checkEnabledBedtimeAgainstServer() {
        if (!root.bedtimeEnabled) return;
        root.bedtimeEnableCheckPending = true;
        HomeAssistant.refreshBedLockLan();
    }

    function clearActiveBedtime() {
        root.activeBedtimeNightEpoch = 0;
        root.activeBedtimeEpoch = 0;
        root.activeBedtimeWakeEpoch = 0;
        root.activeBedtimeWakeReleased = false;
        root.activeBedtimePhoneDelayReleased = false;
        root.bedtimeSecureSyncRequested = false;
        root.localBedtimeDelayPending = false;
    }

    function lockBedtime() {
        if (!root.bedtimeEnabled || !root.bedtimeStateReady || GlobalStates.screenLocked) return false;
        HomeAssistant.refreshBedLockLan();
        const now = Date.now() / 1000;
        const night = root.bedtimeNightEpoch;
        const bedtime = root.bedtimeEpoch;
        const wake = root.bedtimeWakeEpoch;
        const updated = HomeAssistant.bedLockCacheUpdatedEpoch;
        if (!isFinite(night) || night <= 0 || !isFinite(bedtime) || bedtime <= 0
                || !isFinite(wake) || wake <= bedtime || wake <= now
                || !isFinite(updated) || updated <= 0 || updated > now + 120
                || now < bedtime || now - night > 86400
                || bedtime < night - 21600 || wake > night + 86400
                || now - updated > 129600) return false;
        root.activeBedtimeNightEpoch = night;
        root.activeBedtimeEpoch = bedtime;
        root.activeBedtimeWakeEpoch = wake;
        root.activeBedtimeWakeReleased = false;
        root.activeBedtimePhoneDelayReleased = false;
        root.bedtimeSecureSyncRequested = false;
        GlobalStates.bedtimeLockActive = true;
        GlobalStates.bedtimeLockDeadlineText = root.bedtimeDeadlineText;
        GlobalStates.bedtimePasswordRevealed = false;
        root.lock();
        return true;
    }

    function updateBedtimeLockState() {
        if (!root.bedtimeActive || !lock.locked || !lock.secure
                || root.activeBedtimeWakeReleased) return;
        if (!root.bedtimeSecureSyncRequested) {
            root.bedtimeSecureSyncRequested = true;
            HomeAssistant.refreshBedLockLan();
        }
        root.checkBedtimeWake();
    }

    function syncActiveBedtimeFromHomeAssistant() {
        if (!root.bedtimeActive || !lock.locked || !lock.secure
                || (root.activeBedtimeWakeReleased && !root.activeBedtimePhoneDelayReleased)
                || !HomeAssistant.bedLockFresh) return;
        const remoteNight = root.bedtimeNightEpoch;
        const cachedBedtime = root.bedtimeEpoch;
        const cachedWake = root.bedtimeWakeEpoch;
        const night = root.activeBedtimeNightEpoch;
        const now = Date.now() / 1000;
        // Only a validated, fresh endpoint response for this lock's night may
        // change a secure session. The WebSocket cache is not consulted.
        if (!isFinite(remoteNight) || Math.abs(remoteNight - night) >= 60
                || !isFinite(cachedBedtime) || !isFinite(cachedWake)
                || cachedBedtime < night - 21600 || cachedBedtime > night + 86400
                || now > night + 86400) return;

        // A fresh same-night null wake (normalized to zero by the LAN
        // validator) authoritatively ends the sleep window. Its bedtime may
        // have reverted to the earlier base value after an override cleared.
        // Release only the bedtime gate; WlSessionLock still requires auth.
        if (cachedWake === 0) {
            root.activeBedtimeWakeEpoch = 0;
            root.activeBedtimeWakeReleased = true;
            root.activeBedtimePhoneDelayReleased = false;
            root.localBedtimeDelayPending = false;
            localBedtimeDelayTimeout.stop();
            root.reconcileAfterUnlock = false;
            root.relockAfterPhoneDelayUnlock = false;
            root.pendingEndpointRelock = false;
            root.armedBedtimeIso = "";
            Persistent.states.lock.lastBedtimeIso = new Date(root.activeBedtimeEpoch * 1000).toISOString();
            GlobalStates.bedtimePasswordRevealed = true;
            return;
        }
        if (cachedBedtime < root.activeBedtimeEpoch || cachedWake <= cachedBedtime
                || cachedWake > night + 86400 || cachedBedtime < night - 21600
                || now > night + 86400) return;

        // A schedule replacement may change both ends of the window. Refresh
        // the deadline before the future-bedtime branch returns to password UI.
        root.activeBedtimeWakeEpoch = cachedWake;

        if (cachedBedtime > root.activeBedtimeEpoch && cachedBedtime > now) {
            if (root.localBedtimeDelayPending) {
                // A physical click requested this delay. Wait for endpoint
                // confirmation, then retain the previous local-button unlock.
                root.localBedtimeDelayPending = false;
                localBedtimeDelayTimeout.stop();
                root.armedBedtimeIso = "";
                GlobalStates.bedtimeLockActive = false;
                GlobalStates.bedtimeLockDeadlineText = "";
                GlobalStates.bedtimePasswordRevealed = false;
                GlobalStates.screenLocked = false;
                lockContext.reset();
                root.clearActiveBedtime();
                root.armBedtime();
                return;
            }
            // A phone delay postpones bedtime. Keep WlSessionLock secure and
            // let the user authenticate through its normal password input.
            root.activeBedtimeEpoch = cachedBedtime;
            root.activeBedtimeWakeReleased = true;
            root.activeBedtimePhoneDelayReleased = true;
            root.armedBedtimeIso = "";
            root.armBedtime();
            GlobalStates.bedtimePasswordRevealed = true;
            return;
        }

        root.checkBedtimeWake();
    }

    function reengageBedtimeAfterPhoneDelay(iso) {
        if (!root.activeBedtimePhoneDelayReleased || !root.bedtimeActive
                || !lock.locked || !lock.secure) return false;
        const night = root.activeBedtimeNightEpoch;
        const bedtime = root.bedtimeEpoch;
        const wake = root.bedtimeWakeEpoch;
        const now = Date.now() / 1000;
        if (!isFinite(night) || !isFinite(bedtime) || !isFinite(wake)
                || Math.abs(Date.parse(iso) / 1000 - bedtime) >= 2
                || Math.abs(root.bedtimeNightEpoch - night) >= 60
                || now < bedtime || now >= wake || now > night + 86400
                || wake <= bedtime || wake > night + 86400) return false;
        root.activeBedtimeEpoch = bedtime;
        root.activeBedtimeWakeEpoch = wake;
        root.activeBedtimeWakeReleased = false;
        root.activeBedtimePhoneDelayReleased = false;
        Persistent.states.lock.lastBedtimeIso = iso;
        root.armedBedtimeIso = "";
        GlobalStates.bedtimePasswordRevealed = false;
        lockContext.reset();
        return true;
    }

    function checkBedtimeWake() {
        if (!root.bedtimeActive || !lock.locked || !lock.secure
                || root.activeBedtimeWakeReleased) return;
        const now = Date.now() / 1000;
        const night = root.activeBedtimeNightEpoch;
        const bedtime = root.activeBedtimeEpoch;
        const deadline = root.activeBedtimeWakeEpoch;
        // Only release the bedtime gate of a real, securely acquired bedtime
        // lock with a valid, snapshotted same-night deadline. The session
        // remains locked until the user authenticates normally.
        if (!isFinite(night) || night <= 0 || !isFinite(bedtime) || bedtime <= 0
                || !isFinite(deadline) || deadline <= bedtime
                || deadline > night + 86400 || bedtime < night - 21600
                || now < deadline || now > night + 86400) return;
        root.activeBedtimeWakeReleased = true;
        Persistent.states.lock.lastBedtimeIso = new Date(bedtime * 1000).toISOString();
        root.reconcileAfterUnlock = false;
        root.armedBedtimeIso = "";
        GlobalStates.bedtimePasswordRevealed = true;
    }

    function requestBedtimeDelay() {
        if (!root.bedtimeActive || !root.bedtimeDelayAllowed
                || !HomeAssistant.requestBedLockDelay()) return;
        root.localBedtimeDelayPending = true;
        localBedtimeDelayTimeout.restart();
    }

    // Keep the current night's deadline armed through suspend/restart.
    // Authentication remains in the existing lock surface and LockContext.
    function armBedtime() {
        root.armedBedtimeIso = "";
        if (!root.bedtimeEnabled || !root.bedtimeStateReady)
            return;
        if (!isFinite(root.bedtimeEpoch) || root.bedtimeEpoch <= 0
                || !isFinite(root.bedtimeWakeEpoch) || root.bedtimeWakeEpoch <= root.bedtimeEpoch)
            return;
        const target = new Date(root.bedtimeEpoch * 1000);
        if (Date.now() >= root.bedtimeWakeEpoch * 1000)
            return;
        const iso = target.toISOString();
        if (Persistent.states.lock.lastBedtimeIso !== iso)
            root.armedBedtimeIso = iso;
    }

    function checkBedtime() {
        if (!root.armedBedtimeIso || !root.bedtimeEnabled || !root.bedtimeStateReady)
            return;
        const target = Date.parse(root.armedBedtimeIso);
        const now = Date.now();
        const updated = HomeAssistant.bedLockCacheUpdatedEpoch;
        if (now < target) return;
        const iso = root.armedBedtimeIso;
        if (root.activeBedtimePhoneDelayReleased) {
            root.reengageBedtimeAfterPhoneDelay(iso);
            return;
        }
        root.armedBedtimeIso = "";
        // A resumed shell may have missed the precise alarm, but must never
        // lock from a previous night or a stale schedule cache.
        if (Persistent.states.lock.lastBedtimeIso === iso
                || now >= root.bedtimeWakeEpoch * 1000
                || now / 1000 - root.bedtimeNightEpoch > 86400
                || !isFinite(updated) || updated <= 0 || updated > now / 1000 + 120
                || now / 1000 - updated > 129600)
            return;
        if (root.lockBedtime())
            Persistent.states.lock.lastBedtimeIso = iso;
    }

    onBedtimeEnabledChanged: {
        if (!bedtimeSettingObserved) {
            observeBedtimeSetting();
        } else {
            const turnedOn = bedtimeEnabled && !previousBedtimeEnabled;
            previousBedtimeEnabled = bedtimeEnabled;
            if (turnedOn) checkEnabledBedtimeAgainstServer();
        }
        if (!bedtimeEnabled) {
            reconcileAfterUnlock = false;
            relockAfterPhoneDelayUnlock = false;
            pendingEndpointRelock = false;
            bedtimeEnableCheckPending = false;
        }
        armBedtime();
        checkBedtime();
    }
    onBedtimeStateReadyChanged: { observeBedtimeSetting(); armBedtime(); checkBedtime(); }
    Component.onCompleted: { observeBedtimeSetting(); armBedtime(); checkBedtime(); initIfReady(); }
    Connections {
        target: Config
        function onReadyChanged() { root.observeBedtimeSetting(); }
    }
    onBedtimeDeadlineTextChanged: if (GlobalStates.bedtimeLockActive)
        GlobalStates.bedtimeLockDeadlineText = root.bedtimeDeadlineText
    Connections {
        target: HomeAssistant
        function onBedLockScheduleRefreshed(active, nightEpoch, wakeEpoch) {
            if (root.bedtimeEnableCheckPending) {
                root.bedtimeEnableCheckPending = false;
                if (active && root.lockBedtime())
                    Persistent.states.lock.lastBedtimeIso = new Date(root.activeBedtimeEpoch * 1000).toISOString();
            }
            root.syncActiveBedtimeFromHomeAssistant();
            root.armBedtime();
            root.checkBedtime();
            if (!root.reconcileAfterUnlock) return;
            // Only reconcile the night in progress when the password was
            // entered. A later night's refresh cannot relock that session.
            const cacheWasOutOfSync = !root.bedtimeWasActiveAtUnlock
                || Math.abs(root.cachedNightAtUnlock - nightEpoch) >= 60
                || Math.abs(root.cachedBedtimeAtUnlock - root.bedtimeEpoch) >= 60
                || Math.abs(root.cachedWakeAtUnlock - wakeEpoch) >= 60;
            const shouldRelock = active && (cacheWasOutOfSync || root.relockAfterPhoneDelayUnlock)
                    && !GlobalStates.screenLocked
                    && nightEpoch <= root.reconcileUnlockEpoch
                    && root.reconcileUnlockEpoch < wakeEpoch
                    && Date.now() / 1000 < wakeEpoch;
            root.pendingEndpointRelock = shouldRelock;
            if (shouldRelock) {
                phoneDelayRelockTimer.interval = 250;
                phoneDelayRelockTimer.restart();
            }
            root.reconcileAfterUnlock = false;
            root.relockAfterPhoneDelayUnlock = false;
        }
    }
    Timer {
        interval: 15000
        repeat: true
        running: root.bedtimeEnabled
        onTriggered: root.checkBedtime()
    }
    Timer {
        id: localBedtimeDelayTimeout
        interval: 30000
        repeat: false
        onTriggered: root.localBedtimeDelayPending = false
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.bedtimeActive
        onTriggered: root.updateBedtimeLockState()
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.reconcileAfterUnlock
        onTriggered: {
            if (Date.now() / 1000 - root.reconcileUnlockEpoch >= 43200)
                root.reconcileAfterUnlock = false;
        }
    }
    Timer {
        id: phoneDelayRelockTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if ((!root.relockAfterPhoneDelayUnlock && !root.pendingEndpointRelock)
                    || !root.bedtimeEnabled) return;
            if (GlobalStates.screenLocked) {
                root.relockAfterPhoneDelayUnlock = false;
                root.pendingEndpointRelock = false;
                return;
            }
            if (lock.locked) {
                restart();
                return;
            }
            // A lost HA connection must not skip an already confirmed delay.
            // lockBedtime validates the current night, cache age and wake time.
            if (root.lockBedtime())
                root.reconcileAfterUnlock = false;
            root.relockAfterPhoneDelayUnlock = false;
            root.pendingEndpointRelock = false;
        }
    }
    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        color: "transparent"
        Connections {
            target: GlobalStates
            function onLockSnapshotDirectoryChanged() {
                const directory = GlobalStates.lockSnapshotDirectory;
                if (!directory || !lock.locked || !lock.secure) return;
                const name = sessionLockSurface.screen.name.replace(/[^a-zA-Z0-9_-]/g, "_");
                if (!lockVisual.grabToImage(result => {
                    if (!result.saveToFile(`${directory}/${name}-surface.png`))
                        console.warn(`Lock snapshot: failed to save surface for ${name}`);
                })) console.warn(`Lock snapshot: failed to start surface grab for ${name}`);
            }
        }
        Loader {
            id: lockVisual
            focus: true
            active: GlobalStates.screenLocked
            anchors.fill: parent
            opacity: active ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            sourceComponent: root.lockSurface
        }
    }

    Timer {
        id: lockFocusTimer
        interval: 60
        repeat: false
        onTriggered: {
            lockContext.shouldReFocus();
        }
    }

    Process {
        id: unlockKeyringProc
        onExited: (exitCode, exitStatus) => {
            KeyringStorage.fetchKeyringData();
        }
    }
    function unlockKeyring() {
        unlockKeyringProc.exec({
            environment: ({
                "UNLOCK_PASSWORD": lockContext.currentText
            }),
            command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/unlock.sh")]
        })
    }

    // This stores all the information shared between the lock surfaces on each screen.
    // https://github.com/quickshell-mirror/quickshell-examples/tree/master/lockscreen
    LockContext {
        id: lockContext

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    lockContext.reset();
                    lockContext.tryFingerUnlock();
                    Quickshell.execDetached(["bash", "-c", "ydotool mousemove -- 1 0 && ydotool mousemove -- -1 0"]);
                    lockFocusTimer.restart();
                }
            }
        }

        onUnlocked: (targetAction) => {
            // Perform the target action if it's not just unlocking
            if (targetAction == LockContext.ActionEnum.Poweroff) {
                Session.poweroff();
                return;
            } else if (targetAction == LockContext.ActionEnum.Reboot) {
                Session.reboot();
                return;
            }

            // Unlock the keyring if configured to do so
            if (Config.options.lock.security.unlockKeyring) root.unlockKeyring(); // Async

            // A fresh state response after any unlock can reveal that the
            // cached schedule missed bedtime while credentials were locked.
            root.bedtimeWasActiveAtUnlock = HomeAssistant.bedLockActive;
            root.cachedNightAtUnlock = root.bedtimeNightEpoch;
            root.cachedBedtimeAtUnlock = root.bedtimeEpoch;
            root.cachedWakeAtUnlock = root.bedtimeWakeEpoch;
            root.relockAfterPhoneDelayUnlock = root.activeBedtimePhoneDelayReleased
                && root.bedtimeEpoch <= Date.now() / 1000;
            root.reconcileAfterUnlock = root.bedtimeEnabled;
            root.reconcileUnlockEpoch = Date.now() / 1000;
            if (root.reconcileAfterUnlock) {
                HomeAssistant.refreshBedLockLan();
            }

            // Unlock the screen before exiting, or the compositor will display a
            // fallback lock you can't interact with.
            GlobalStates.screenLocked = false;
            GlobalStates.bedtimeLockActive = false;
            GlobalStates.bedtimeLockDeadlineText = "";
            GlobalStates.bedtimePasswordRevealed = false;
            root.clearActiveBedtime();
            if (root.relockAfterPhoneDelayUnlock) {
                phoneDelayRelockTimer.interval = 1500;
                phoneDelayRelockTimer.restart();
            }

            // Reset
            lockContext.reset();

            // Post-unlock actions
            if (lockContext.alsoInhibitIdle) {
                lockContext.alsoInhibitIdle = false;
                Idle.toggleInhibit(true);
            }
        }
    }

    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
        onSecureStateChanged: root.updateBedtimeLockState()
        onLockStateChanged: root.updateBedtimeLockState()
    }

    // A private marker arms one snapshot 10 seconds after a secure Quickshell lock.
    // Leave it armed if capture fails.
    Timer {
        interval: 10000
        repeat: false
        running: lock.locked && lock.secure
        onTriggered: lockSnapshotProc.running = true
    }
    Process {
        id: lockSnapshotProc
        command: [Quickshell.shellPath("scripts/lock-snapshot-once.sh")]
        stdout: StdioCollector {
            id: lockSnapshotPathCollector
            onStreamFinished: {
                const directory = lockSnapshotPathCollector.text.trim();
                if (!directory || !lock.locked || !lock.secure) return;
                GlobalStates.lockSnapshotDirectory = directory;
                Quickshell.execDetached([Quickshell.shellPath("scripts/assemble-lock-snapshot.sh"), directory]);
            }
        }
    }

    function lock() {
        // Refresh the keyless LAN bedtime source before every lock. The last
        // validated current-night snapshot remains available if HA is offline.
        HomeAssistant.refreshBedLockLan();
        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/hyprlock/launch.sh"]);
            return;
        }
        GlobalStates.screenLocked = true;
    }

    IpcHandler {
        target: "lock"

        function checkEnabledBedtime(): void {
            root.checkEnabledBedtimeAgainstServer();
        }

        function activate(): void {
            root.lock();
        }
        function focus(): void {
            lockContext.shouldReFocus();
        }
        function unlock(): void {
            GlobalStates.screenLocked = false;
            GlobalStates.bedtimeLockActive = false;
            GlobalStates.bedtimeLockDeadlineText = "";
            GlobalStates.bedtimePasswordRevealed = false;
            root.clearActiveBedtime();
            lockContext.reset();
        }
        function getLength(): int {
            return lockContext.currentText.length;
        }
        function isSecure(): bool {
            return lock.locked && lock.secure;
        }
        function bedtimeStatus(): string {
            return JSON.stringify({enabled:root.bedtimeEnabled,
                screenLocked:GlobalStates.screenLocked, secure:lock.locked && lock.secure,
                bedtimeActive:root.bedtimeActive,
                passwordRevealed:GlobalStates.bedtimePasswordRevealed,
                activeBedtimeEpoch:root.activeBedtimeEpoch,
                activeWakeEpoch:root.activeBedtimeWakeEpoch,
                deadlineText:root.bedtimeDeadlineText,
                restrictionReleased:root.activeBedtimeWakeReleased,
                postponed:root.activeBedtimePhoneDelayReleased,
                armedBedtimeIso:root.armedBedtimeIso});
        }
    }

    GlobalShortcut {
        name: "lock"
        description: "Locks the screen"

        onPressed: {
            root.lock()
        }
    }

    GlobalShortcut {
        name: "lockFocus"
        description: "Re-focuses the lock screen. This is because Hyprland after waking up for whatever reason"
            + "decides to keyboard-unfocus the lock screen"

        onPressed: {
            lockContext.shouldReFocus();
        }
    }

    function initIfReady() {
        if (!Config.ready || !Persistent.ready || root.startupInitialized) return;
        root.startupInitialized = true;
        if (Config.options.lock.launchOnStartup && Persistent.isNewHyprlandInstance) {
            root.lock();
        } else {
            KeyringStorage.fetchKeyringData();
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.initIfReady();
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.initIfReady();
        }
    }
}
