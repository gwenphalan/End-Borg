pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs
import Quickshell
import Quickshell.Io
import qs.modules.common
import "home_assistant.js" as HA

Singleton {
    id: root
    readonly property var settings: Config.options.homeAssistant
    property real mediaClock: Date.now()
    property bool connected: false
    property string error: ""
    property string credentialMessage: ""
    property string token: ""
    property bool authFailed: false
    property bool reconnecting: false
    property int nextId: 1
    property var pending: ({})
    property int refreshGeneration:0
    property var stateDeltas:({})
    readonly property bool savingToken:save.running
    signal tokenSaveFinished(bool succeeded)
    property var states: ({})
    property var sleepScheduleItems: []
    property bool sleepScheduleLoading: false
    property bool sleepScheduleSaving: false
    property string sleepScheduleError: ""
    property var sleepScheduleWaiters: []
    property bool tonightSaveBusy: false
    property var tonightVerifyExpected: null
    property var tonightVerifyCallback: null
    property int tonightVerifyAttempts: 0
    readonly property var sleepCache: Persistent.states.homeAssistant
    property real sleepClock: Date.now() / 1000
    readonly property int bedtimeDelaySeconds: sleepCache.sleepDelayMinutes * 60
    // Bed Lock reads only the independently validated public LAN snapshot.
    // Authenticated HA websocket updates never write these fields.
    readonly property bool bedLockEnabled: Config.ready && Config.options.lock.bedtimeEnabled
        && !Config.options.lock.useHyprlock
    readonly property real bedLockNightStartEpoch: sleepCache.bedLockNightStartEpoch
    readonly property real bedLockBedtimeEpoch: sleepCache.bedLockBedtimeEpoch
    readonly property real bedLockWakeEpoch: sleepCache.bedLockWakeEpoch
    readonly property int bedLockDelaysRemaining: sleepCache.bedLockDelaysRemaining
    readonly property int bedLockDelaysUsed: sleepCache.bedLockDelaysUsed
    readonly property int bedLockMaxDelays: sleepCache.bedLockMaxDelays
    readonly property int bedLockDelaySeconds: sleepCache.bedLockDelayMinutes * 60
    readonly property real bedLockCacheUpdatedEpoch: sleepCache.bedLockCacheUpdatedEpoch
    readonly property bool bedLockFresh: Persistent.ready && bedLockCacheUpdatedEpoch > 0
        && sleepClock >= bedLockCacheUpdatedEpoch - 5
        && sleepClock - bedLockCacheUpdatedEpoch <= 90
    readonly property bool bedLockActive: bedLockFresh && bedLockBedtimeEpoch > 0
        && bedLockWakeEpoch > bedLockBedtimeEpoch
        && sleepClock >= bedLockBedtimeEpoch && sleepClock < bedLockWakeEpoch
    readonly property string bedLockDeadlineText: bedLockWakeEpoch > 0
        ? new Date(bedLockWakeEpoch * 1000).toLocaleTimeString(Qt.locale(), "h:mm AP") : ""
    readonly property string bedLockDelayUntilText: bedLockBedtimeEpoch > 0 && bedLockDelaySeconds > 0
        ? new Date((bedLockBedtimeEpoch + bedLockDelaySeconds) * 1000).toLocaleTimeString(Qt.locale(), "h:mm AP") : ""
    property bool bedLockDelayPending: false
    property int bedLockPendingUsed: 0
    readonly property bool bedLockDelayAllowed: bedLockActive && !bedLockDelayPending
        && bedLockDelaysRemaining > 0 && bedLockDelaySeconds > 0
        && bedLockBedtimeEpoch + bedLockDelaySeconds > sleepClock
    signal bedLockScheduleRefreshed(bool active, real nightEpoch, real wakeEpoch)
    readonly property int bedtimeDelaysRemaining: sleepCache.sleepDelaysRemaining
    readonly property int bedtimeDelaysUsed: sleepCache.sleepDelaysUsed
    readonly property int bedtimeMaxDelays: sleepCache.sleepMaxDelays
    readonly property string bedtimeDeadlineText: sleepCache.sleepWakeEpoch > 0
        ? new Date(sleepCache.sleepWakeEpoch * 1000).toLocaleTimeString(Qt.locale(), "h:mm AP") : ""
    readonly property string bedtimeDelayUntilText: sleepCache.sleepBedtimeEpoch > 0 && bedtimeDelaySeconds > 0
        ? new Date((sleepCache.sleepBedtimeEpoch + bedtimeDelaySeconds) * 1000).toLocaleTimeString(Qt.locale(), "h:mm AP") : ""
    readonly property bool cachedBedtimeActive: sleepCache.sleepBedtimeEpoch > 0
        && sleepCache.sleepWakeEpoch > sleepCache.sleepBedtimeEpoch
        && sleepClock >= sleepCache.sleepBedtimeEpoch && sleepClock < sleepCache.sleepWakeEpoch
    readonly property bool bedtimeDelayAllowed: Persistent.ready && cachedBedtimeActive
        && sleepCache.sleepDelaysRemaining > 0 && bedtimeDelaySeconds > 0
        && sleepCache.sleepBedtimeEpoch + bedtimeDelaySeconds > sleepClock
        && sleepClock - sleepCache.sleepNightStartEpoch <= 86400
        && sleepClock - sleepCache.sleepCacheUpdatedEpoch <= 129600
    signal sleepScheduleRefreshed(bool active, real nightEpoch, real wakeEpoch)

    function scheduledWakeEpoch(bedtime) {
        let schedule;
        try { schedule = JSON.parse(sleepCache.sleepScheduleJson); }
        catch (e) { return 0; }
        if (!schedule || typeof schedule !== "object") return 0;
        const days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
        const target = bedtime * 1000;
        const firstDay = new Date(target);
        firstDay.setHours(0, 0, 0, 0);
        const intervals = [];
        for (let offset = -1; offset <= 2; offset++) {
            const day = new Date(firstDay);
            day.setDate(day.getDate() + offset);
            const blocks = schedule[days[day.getDay()]] || [];
            for (const block of blocks) {
                const start = String(block.from || "").split(":").map(Number);
                const end = String(block.to || "").split(":").map(Number);
                if (start.length < 2 || end.length < 2 || !start.every(Number.isFinite) || !end.every(Number.isFinite)) continue;
                const from = new Date(day); from.setHours(start[0], start[1], start[2] || 0, 0);
                const to = new Date(day); to.setHours(end[0], end[1], end[2] || 0, 0);
                if (to <= from) to.setDate(to.getDate() + 1);
                intervals.push([from.getTime(), to.getTime()]);
            }
        }
        intervals.sort((a, b) => a[0] - b[0]);
        let wake = 0;
        for (const interval of intervals) {
            // HA's computed bedtime can precede the Sleep schedule block.
            // Associate it with the next block when that starts tonight.
            if (!wake && interval[0] <= target && target < interval[1]) wake = interval[1];
            else if (!wake && interval[0] > target && interval[0] - target <= 6 * 3600000)
                wake = interval[1];
            else if (wake && interval[0] - wake <= 60000) wake = Math.max(wake, interval[1]);
            else if (wake) break;
        }
        return wake / 1000;
    }

    // Keep only nonsecret schedule data on disk. It remains usable when the
    // login keyring is locked and the websocket token cannot be reloaded.
    function cacheSleepSchedule() {
        if (!connected || !Persistent.ready) return;
        const nightState = states["input_datetime.bedtime_night_started"];
        const night = Number(nightState?.attributes?.timestamp)
            || Date.parse(nightState?.state || "") / 1000;
        const bedtime = Date.parse(states["sensor.current_bedtime"]?.state || "") / 1000;
        const overrideActive = states["input_boolean.tonight_sleep_override_active"]?.state === "on";
        const overrideWake = overrideActive
            ? Date.parse((states["input_text.tonight_wake_up"]?.state || "").replace(" ", "T")) / 1000
            : NaN;
        const wake = states["schedule.sleep_schedule"]?.state === "on"
            ? Date.parse(states["schedule.sleep_schedule"]?.attributes?.next_event || "") / 1000 : NaN;
        const rawRemaining = Number(states["sensor.current_bedtime"]?.attributes?.delays_remaining);
        const rawUsed = Number(states["sensor.current_bedtime"]?.attributes?.delays_used);
        const maxDelays = Number(states["sensor.current_bedtime"]?.attributes?.max_delays);
        const delayMinutes = states["sensor.current_bedtime"]?.attributes?.delay_minutes;
        if (!isFinite(night) || night <= 0 || !isFinite(bedtime) || bedtime <= 0
                || !Number.isInteger(rawUsed) || rawUsed < 0 || rawUsed > 10
                || !Number.isInteger(maxDelays) || maxDelays < 0 || maxDelays > 10
                || !Number.isInteger(rawRemaining) || rawRemaining !== Math.max(0, maxDelays - rawUsed)
                || !Number.isInteger(delayMinutes) || delayMinutes < 5 || delayMinutes > 120) return;

        const isNewNight = Math.abs(night - sleepCache.sleepNightStartEpoch) > 60;
        if (isNewNight) {
            sleepCache.sleepNightStartEpoch = night;
            sleepCache.sleepPendingDelayCount = 0;
            sleepCache.sleepWakeEpoch = 0;
        }
        const localUsed = sleepCache.sleepDelaysUsed;
        if (isNewNight || sleepCache.sleepPendingDelayCount === 0 || rawUsed >= localUsed) {
            sleepCache.sleepBedtimeEpoch = bedtime;
            sleepCache.sleepDelaysRemaining = rawRemaining;
            sleepCache.sleepDelaysUsed = rawUsed;
            sleepCache.sleepPendingDelayCount = 0;
        } else {
            // A local delay is pending: an older HA state must not move the
            // lock back to the original bedtime or restore a spent delay.
            sleepCache.sleepBedtimeEpoch = Math.max(sleepCache.sleepBedtimeEpoch, bedtime);
            sleepCache.sleepDelaysRemaining = Math.max(0, maxDelays - localUsed);
        }
        sleepCache.sleepMaxDelays = maxDelays;
        sleepCache.sleepDelayMinutes = delayMinutes;
        const scheduledWake = scheduledWakeEpoch(sleepCache.sleepBedtimeEpoch);
        // HA's next_event can be the midnight boundary of a split overnight
        // block. The contiguous schedule interval carries the actual wake time.
        sleepCache.sleepWakeEpoch = isFinite(overrideWake) && overrideWake > sleepCache.sleepBedtimeEpoch
            ? overrideWake
            : Math.max(isFinite(wake) && wake > sleepCache.sleepBedtimeEpoch ? wake : 0,
                       scheduledWake > sleepCache.sleepBedtimeEpoch ? scheduledWake : 0);
        sleepCache.sleepCacheUpdatedEpoch = sleepClock;
        const activeNow = sleepCache.sleepBedtimeEpoch > 0
            && sleepCache.sleepWakeEpoch > sleepCache.sleepBedtimeEpoch
            && sleepClock >= sleepCache.sleepBedtimeEpoch && sleepClock < sleepCache.sleepWakeEpoch;
        flushPendingBedtimeDelay();
        return activeNow;
    }

    function delayBedtime() {
        if (!bedtimeDelayAllowed)
            return false;
        sleepCache.sleepBedtimeEpoch += bedtimeDelaySeconds;
        sleepCache.sleepDelaysUsed += 1;
        sleepCache.sleepDelaysRemaining = Math.max(0, sleepCache.sleepMaxDelays - sleepCache.sleepDelaysUsed);
        sleepCache.sleepPendingDelayCount += 1;
        flushPendingBedtimeDelay();
        return true;
    }

    function flushPendingBedtimeDelay() {
        if (!Persistent.ready || sleepCache.sleepPendingDelayCount <= 0
                || sleepCache.sleepNightStartEpoch <= 0 || delaySync.running) return;
        delaySync.command = ["python3", Quickshell.shellPath("scripts/sleep_delay_webhook.py"),
            String(sleepCache.sleepDelaysUsed), String(sleepCache.sleepNightStartEpoch)];
        delaySync.running = true;
    }

    function refreshBedLockLan() {
        if (!Persistent.ready || lanStatus.running) return;
        lanStatus.command = ["python3", Quickshell.shellPath("scripts/bedlock_lan_status.py"),
            String(bedLockNightStartEpoch), String(bedLockCacheUpdatedEpoch),
            String(bedLockDelaysUsed)];
        lanStatus.running = true;
    }

    function requestBedLockDelay() {
        if (!bedLockDelayAllowed || bedLockDelaySync.running) return false;
        bedLockPendingUsed = bedLockDelaysUsed + 1;
        bedLockDelayPending = true;
        bedLockDelaySync.command = ["python3", Quickshell.shellPath("scripts/sleep_delay_webhook.py"),
            String(bedLockPendingUsed), String(bedLockNightStartEpoch)];
        bedLockDelaySync.running = true;
        bedLockPendingTimeout.restart();
        return true;
    }

    function acceptBedLockLanSnapshot(snapshot) {
        if (!Persistent.ready) return;
        const now = Date.now() / 1000;
        if (!snapshot || !isFinite(snapshot.nightStartEpoch)
                || !isFinite(snapshot.generatedAtEpoch)
                || !isFinite(snapshot.bedtimeEpoch) || !isFinite(snapshot.wakeEpoch)
                || !Number.isInteger(snapshot.delaysRemaining)
                || !Number.isInteger(snapshot.delaysUsed)
                || !Number.isInteger(snapshot.maxDelays)
                || snapshot.delaysUsed < 0 || snapshot.delaysUsed > 10
                || snapshot.maxDelays < 0 || snapshot.maxDelays > 10
                || snapshot.delaysRemaining !== Math.max(0, snapshot.maxDelays - snapshot.delaysUsed)
                || !Number.isInteger(snapshot.delayMinutes)
                || snapshot.delayMinutes < 5 || snapshot.delayMinutes > 120
                || snapshot.generatedAtEpoch < now - 90 || snapshot.generatedAtEpoch > now + 5)
            return;
        // Make intermediate writes non-authoritative until the whole snapshot
        // is in place; individual QML property handlers may fire between them.
        sleepCache.bedLockCacheUpdatedEpoch = 0;
        sleepCache.bedLockNightStartEpoch = snapshot.nightStartEpoch;
        sleepCache.bedLockBedtimeEpoch = snapshot.bedtimeEpoch;
        sleepCache.bedLockWakeEpoch = snapshot.wakeEpoch;
        sleepCache.bedLockDelaysRemaining = snapshot.delaysRemaining;
        sleepCache.bedLockDelaysUsed = snapshot.delaysUsed;
        sleepCache.bedLockMaxDelays = snapshot.maxDelays;
        sleepCache.bedLockDelayMinutes = snapshot.delayMinutes;
        sleepCache.bedLockCacheUpdatedEpoch = snapshot.generatedAtEpoch;
        if (bedLockDelayPending && snapshot.delaysUsed >= bedLockPendingUsed) {
            bedLockDelayPending = false;
            bedLockPendingTimeout.stop();
        }
        const activeNow = snapshot.wakeEpoch > snapshot.bedtimeEpoch
            && now >= snapshot.bedtimeEpoch && now < snapshot.wakeEpoch;
        bedLockScheduleRefreshed(activeNow, snapshot.nightStartEpoch, snapshot.wakeEpoch);
    }

    onStatesChanged: cacheSleepSchedule()
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) { root.cacheSleepSchedule(); root.refreshBedLockLan(); }
        }
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.sleepClock = Date.now() / 1000 }
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.flushPendingBedtimeDelay() }
    Timer {
        interval: 15000; running: root.bedLockEnabled || GlobalStates.screenLocked; repeat: true
        onTriggered: root.refreshBedLockLan()
    }
    Timer { id: bedLockPendingTimeout; interval: 30000; onTriggered: root.bedLockDelayPending = false }
    Timer { id: bedLockPostDelayRefresh; interval: 1000; onTriggered: root.refreshBedLockLan() }
    Process {
        id: lanStatus
        stdout: StdioCollector { id: lanStatusOutput }
        onExited: (code, status) => {
            if (code !== 0) return;
            try { root.acceptBedLockLanSnapshot(JSON.parse(lanStatusOutput.text)); }
            catch (error) { console.warn("Bed Lock LAN response was not valid JSON"); }
        }
    }
    Process {
        id: bedLockDelaySync
        onExited: (code, status) => {
            if (code === 0) bedLockPostDelayRefresh.restart();
            else { root.bedLockDelayPending = false; bedLockPendingTimeout.stop(); }
        }
    }
    // Refresh the full bedtime and weekly schedule cache while the HA session
    // is available; state-change events alone can miss a computed rollover.
    Timer { interval: 15 * 60 * 1000; running: root.connected; repeat: true; onTriggered: root.refresh() }
    Timer { id: scheduleRefreshTimer; interval: 250; onTriggered: root.loadSleepSchedules(null, true) }
    Timer { id: tonightVerifyTimer; interval: 250; onTriggered: root.verifyTonightState() }
    Timer { id: delayRefresh; interval: 1500; onTriggered: root.refresh() }
    Process {
        id: delaySync
        onExited: (code, status) => {
            if (code === 0 && root.connected) delayRefresh.restart();
        }
    }
    property var areas: []
    property var entityRegistry: []
    property var devices: []
    property var services: ({})
    property var busy: ({})
    readonly property var entities: Object.values(states).sort((a,b) => HA.name(a).localeCompare(HA.name(b)))
    readonly property var areaChoices: [{area_id:"", name:Translation.tr("All rooms")}, ...areas.map(area => Object.assign({},area,{icon:HA.roomIcon(area.icon)})), {area_id:"unassigned", name:Translation.tr("Unassigned")}]
    readonly property var mediaPlayers: connected && settings.showMediaPlayers ? entities.filter(e => HA.domain(e) === "media_player" && HA.available(e) && !settings.hiddenEntities.includes(e.entity_id)) : []
    readonly property var quickControls: {
        const pinned = Array.from(settings.quickToggleEntities);
        const suggestions = entities.filter(e => HA.available(e) && !settings.hiddenEntities.includes(e.entity_id) && canActivate(e));
        const preferred = suggestions.filter(e => settings.favoriteEntities.includes(e.entity_id));
        const defaults = preferred.length ? preferred : suggestions.filter(e => ["light","switch","input_boolean","scene","script","automation"].includes(domain(e)));
        return (pinned.length ? pinned.map(id => states[id]).filter(e => e && canActivate(e)) : (settings.suggestQuickControls ? defaults : [])).filter(e => !settings.hiddenEntities.includes(e.entity_id)).slice(0,settings.quickControlLimit);
    }
    readonly property var barControls: (settings.barControlEntities.length ? settings.barControlEntities.map(id => states[id]).filter(e => e && canActivate(e) && !settings.hiddenEntities.includes(e.entity_id)) : quickControls).slice(0,settings.barControlLimit)
    readonly property string selectedMediaId: Persistent.states.homeAssistant.mediaEntityId
    readonly property var barPlayer: mediaPlayers.find(e => e.entity_id === selectedMediaId) || mediaPlayers.find(e => e.state === "playing") || mediaPlayers[0] || null
    readonly property bool configured: /^https?:\/\/[^\s]+$/.test(settings.url) && token.length > 0
    readonly property string connectionLabel: !settings.enabled ? Translation.tr("Home Assistant is off") : !configured ? credentialMessage || Translation.tr("Set up Home Assistant in Settings") : connected ? Translation.tr("Connected") : error || Translation.tr("Connecting…")
    readonly property string websocketUrl: settings.url.replace(/\/+$/, "").replace(/^http/, "ws") + "/api/websocket"

    IpcHandler {
        target: "homeAssistant"
        function cacheBedtime(): void {
            root.cacheSleepSchedule();
            root.refreshBedLockLan();
        }
        function refreshBedLock(): void {
            root.refreshBedLockLan();
        }
        function bedLockStatus(): string {
            return JSON.stringify({fresh:root.bedLockFresh, active:root.bedLockActive,
                nightStartEpoch:root.bedLockNightStartEpoch,
                bedtimeEpoch:root.bedLockBedtimeEpoch,
                wakeEpoch:root.bedLockWakeEpoch,
                delaysRemaining:root.bedLockDelaysRemaining,
                delaysUsed:root.bedLockDelaysUsed, maxDelays:root.bedLockMaxDelays,
                delayMinutes:root.sleepCache.bedLockDelayMinutes,
                generatedAtEpoch:root.bedLockCacheUpdatedEpoch,
                delayPending:root.bedLockDelayPending});
        }
        function status(): string {
            return JSON.stringify({enabled:root.settings.enabled, configured:root.configured,
                connected:root.connected, waitingForUnlock:!root.mayReadCredentials,
                credentialMessage:root.credentialMessage,
                devices:root.entities.length, error:root.error,
                bedtimeEpoch:root.sleepCache.sleepBedtimeEpoch,
                wakeEpoch:root.sleepCache.sleepWakeEpoch,
                delaysRemaining:root.sleepCache.sleepDelaysRemaining,
                delaysUsed:root.sleepCache.sleepDelaysUsed,
                maxDelays:root.sleepCache.sleepMaxDelays,
                delayMinutes:root.sleepCache.sleepDelayMinutes,
                sleepScheduleLoading:root.sleepScheduleLoading,
                sleepScheduleError:root.sleepScheduleError,
                sleepScheduleIds:root.sleepScheduleItems.map(item => item.id),
                tonightActive:root.states["input_boolean.tonight_sleep_override_active"]?.state,
                tonightBedtime:root.states["input_text.tonight_bedtime"]?.state,
                tonightWake:root.states["input_text.tonight_wake_up"]?.state,
                pendingDelays:root.sleepCache.sleepPendingDelayCount});
        }
    }

    function domain(e) { return HA.domain(e); }
    function name(e) { return HA.name(e); }
    function icon(e) { return HA.icon(e); }
    function status(e) {
        return HA.status(e, {
            on:Translation.tr("On"), off:Translation.tr("Off"),
            playing:Translation.tr("Playing"), paused:Translation.tr("Paused"),
            idle:Translation.tr("Idle"), standby:Translation.tr("Standby"),
            buffering:Translation.tr("Buffering"), unavailable:Translation.tr("Unavailable"),
            unknown:Translation.tr("Unknown"), open:Translation.tr("Open"),
            closed:Translation.tr("Closed"), opening:Translation.tr("Opening"), closing:Translation.tr("Closing"),
            locked:Translation.tr("Locked"), unlocked:Translation.tr("Unlocked"),
            locking:Translation.tr("Locking"), unlocking:Translation.tr("Unlocking"),
            heat:Translation.tr("Heat"), cool:Translation.tr("Cool"),
            auto:Translation.tr("Auto"), fan_only:Translation.tr("Fan only"), dry:Translation.tr("Dry"),
            cleaning:Translation.tr("Cleaning"), docked:Translation.tr("Docked"), returning:Translation.tr("Returning"),
            disarmed:Translation.tr("Disarmed"), armed_home:Translation.tr("Armed home"),
            armed_away:Translation.tr("Armed away"), triggered:Translation.tr("Triggered")
        });
    }
    function mediaPosition(e) { return HA.mediaPosition(e,mediaClock); }
    function mediaTimelinePosition(timeline) { return HA.mediaTimelinePosition(timeline,mediaClock); }
    function reconcileMediaTimeline(previous,e) { return HA.reconcileMediaTimeline(previous,e,Date.now()); }
    function available(e) { return connected && HA.available(e); }
    function hasFeature(e, flag) { return HA.hasFeature(e,flag); }
    function entityArea(e) { return HA.areaFor(e,entityRegistry,devices); }
    function visibleEntities(area, editing) {
        return entities.filter(e => (!area || entityArea(e) === area) && (editing || !settings.hiddenEntities.includes(e.entity_id)));
    }
    function changeList(key, id) {
        const list = Array.from(settings[key]);
        settings[key] = list.includes(id) ? list.filter(v => v !== id) : list.concat([id]);
    }
    function failPending(reason) {
        const requests=pending; pending=({}); busy=({});
        for (const id of Object.keys(requests)) {
            try { if (requests[id].callback) requests[id].callback(null,reason); }
            catch (e) { console.warn("Home Assistant request callback failed"); }
        }
    }
    function clearState() {
        refreshGeneration++; states=({}); stateDeltas=({});
        services=({}); areas=[]; entityRegistry=[]; devices=[];
    }
    function connectionLost(reason) {
        connected=false;
        failPending(reason || Translation.tr("Connection closed"));
        if (settings.enabled && configured && !authFailed && !reconnecting) {
            error=reason || Translation.tr("Connection lost. Retrying…");
            retryTimer.restart();
        }
    }
    function recordState(data) {
        if (!data?.entity_id) return;
        stateDeltas[data.entity_id]=data.new_state || null;
        const updated=Object.assign({},states);
        if (data.new_state) updated[data.entity_id]=data.new_state;
        else delete updated[data.entity_id];
        states=updated;
        if ((data.entity_id === "schedule.sleep_schedule" || data.entity_id === "schedule.wind_down")
                && !sleepScheduleSaving) scheduleRefreshTimer.restart();
    }
    function send(type, data, callback) {
        if (!connected) { if (callback) callback(null,Translation.tr("Home Assistant is not connected")); return; }
        const id = nextId++;
        pending[id] = {type:type, callback: callback, time: Date.now()};
        socket.sendTextMessage(JSON.stringify(Object.assign({id:id,type:type},data || {})));
    }
    function loadSleepSchedules(callback, force) {
        if (!connected) {
            sleepScheduleError = Translation.tr("Home Assistant is not connected");
            if (callback) callback(false, sleepScheduleError);
            return;
        }
        if (!force && sleepScheduleItems.length === 2) {
            if (callback) callback(true, "");
            return;
        }
        if (callback) sleepScheduleWaiters.push(callback);
        if (sleepScheduleLoading) return;
        sleepScheduleLoading = true;
        sleepScheduleError = "";
        send("schedule/list", {}, (result, failure) => {
            sleepScheduleLoading = false;
            const finish = (success, message) => {
                const waiters = sleepScheduleWaiters;
                sleepScheduleWaiters = [];
                for (const waiter of waiters) waiter(success, message);
            };
            if (failure || !Array.isArray(result)) {
                sleepScheduleError = failure || Translation.tr("Could not read the sleep schedule.");
                finish(false, sleepScheduleError);
                return;
            }
            const sleep = result.find(item => item.id === "sleep_schedule");
            const wind = result.find(item => item.id === "wind_down");
            if (!sleep || !wind) {
                sleepScheduleError = Translation.tr("Sleep or Wind Down schedule is missing.");
                finish(false, sleepScheduleError);
                return;
            }
            sleepScheduleItems = [sleep, wind];
            if (Persistent.ready) {
                const days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
                const blocks = ({});
                for (const day of days) blocks[day] = sleep[day] || [];
                sleepCache.sleepScheduleJson = JSON.stringify(blocks);
                cacheSleepSchedule();
            }
            if (error.includes("schedule.get_schedule")) error = "";
            finish(true, "");
        });
    }
    function saveTonightSleepSchedule(bed, wake, callback) {
        if (!connected || tonightSaveBusy) {
            if (callback) callback(false, connected ? Translation.tr("Tonight's schedule save is already running.")
                                                    : Translation.tr("Home Assistant is not connected"));
            return;
        }
        const times = [bed, wake].map(value => Date.parse(String(value).replace(" ", "T")));
        if (times.some(value => !Number.isFinite(value)) || times[0] >= times[1]
                || times[1] <= Date.now()
                || times[1] - times[0] < 60 * 60000
                || times[1] - times[0] > 960 * 60000) {
            if (callback) callback(false, Translation.tr("Choose valid bedtime and wake times for tonight."));
            return;
        }
        tonightSaveBusy = true;
        send("call_service", {domain:"script", service:"set_tonight_sleep_schedule",
            service_data:{bedtime:bed, wake_up:wake}}, (result, failure) => {
            if (failure) {
                tonightSaveBusy = false;
                if (callback) callback(false, failure);
            } else beginTonightVerification({active:"on", bed:bed, wake:wake}, callback);
        });
    }
    function clearTonightSleepSchedule(callback) {
        if (!connected || tonightSaveBusy) {
            if (callback) callback(false, connected ? Translation.tr("Tonight's schedule save is already running.")
                                                    : Translation.tr("Home Assistant is not connected"));
            return;
        }
        tonightSaveBusy = true;
        send("call_service", {domain:"script", service:"clear_tonight_sleep_schedule"}, (result, failure) => {
            if (failure) {
                tonightSaveBusy = false;
                if (callback) callback(false, failure);
            } else beginTonightVerification({active:"off", bed:"", wake:""}, callback);
        });
    }
    function beginTonightVerification(expected, callback) {
        tonightVerifyExpected = expected;
        tonightVerifyCallback = callback;
        tonightVerifyAttempts = 0;
        tonightVerifyTimer.start();
    }
    function verifyTonightState() {
        const expected = tonightVerifyExpected;
        if (!expected) return;
        tonightVerifyAttempts++;
        send("get_states", {}, (result, failure) => {
            const get = id => Array.isArray(result)
                ? result.find(item => item.entity_id === id)?.state : undefined;
            const matches = !failure && get("input_boolean.tonight_sleep_override_active") === expected.active
                && get("input_text.tonight_bedtime") === expected.bed
                && get("input_text.tonight_wake_up") === expected.wake;
            if (matches || failure || tonightVerifyAttempts >= 5) {
                const callback = tonightVerifyCallback;
                tonightVerifyExpected = null;
                tonightVerifyCallback = null;
                tonightSaveBusy = false;
                if (callback) callback(matches, failure || (matches ? ""
                    : Translation.tr("Home Assistant did not apply tonight's schedule. Check its script log.")));
            } else tonightVerifyTimer.restart();
        });
    }
    function saveSleepSchedules(sleepItem, windItem, callback) {
        if (sleepScheduleSaving || sleepScheduleLoading) { if (callback) callback(false, Translation.tr("Schedule refresh or save is already running.")); return; }
        const previousSleep = sleepScheduleItems.find(item => item.id === "sleep_schedule");
        const previousWind = sleepScheduleItems.find(item => item.id === "wind_down");
        if (!connected || !previousSleep || !previousWind || sleepItem?.id !== "sleep_schedule" || windItem?.id !== "wind_down") {
            if (callback) callback(false, Translation.tr("Refresh the sleep schedule before saving."));
            return;
        }
        const days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
        const payload = item => {
            const data = {schedule_id:item.id, name:item.name};
            if (item.icon) data.icon = item.icon;
            for (const day of days) data[day] = item[day] || [];
            return data;
        };
        const matches = (actual, wanted) => actual && days.every(day => JSON.stringify(actual[day] || []) === JSON.stringify(wanted[day] || []));
        sleepScheduleSaving = true;
        scheduleRefreshTimer.stop();
        sleepScheduleError = "";
        send("schedule/update", payload(sleepItem), (sleepResult, sleepFailure) => {
            if (sleepFailure) {
                sleepScheduleSaving = false;
                sleepScheduleError = sleepFailure;
                if (callback) callback(false, sleepFailure);
                return;
            }
            send("schedule/update", payload(windItem), (windResult, windFailure) => {
                if (windFailure) {
                    send("schedule/update", payload(previousSleep), (rollbackResult, rollbackFailure) => {
                        sleepScheduleSaving = false;
                        const saveError = rollbackFailure
                            ? Translation.tr("Wind Down save failed and Sleep rollback failed: ") + rollbackFailure
                            : windFailure;
                        loadSleepSchedules(null, true);
                        sleepScheduleError = saveError;
                        if (callback) callback(false, saveError);
                    });
                    return;
                }
                loadSleepSchedules((loaded, readError) => {
                    sleepScheduleSaving = false;
                    const currentSleep = sleepScheduleItems.find(item => item.id === "sleep_schedule");
                    const currentWind = sleepScheduleItems.find(item => item.id === "wind_down");
                    if (!loaded || !matches(currentSleep, sleepItem) || !matches(currentWind, windItem)) {
                        sleepScheduleError = readError || Translation.tr("Schedule saved but readback did not match. Refresh before editing again.");
                        if (callback) callback(false, sleepScheduleError);
                        return;
                    }
                    refresh();
                    if (callback) callback(true, "");
                }, true);
            });
        });
    }
    function setSleepNumber(entityId, value, callback) {
        if (!connected || !["input_number.bedtime_delay_length", "input_number.bedtime_max_delays", "input_number.bedtime_wind_down_minutes"].includes(entityId)) {
            if (callback) callback(false, Translation.tr("Sleep setting is not available."));
            return;
        }
        send("call_service", {domain:"input_number", service:"set_value", service_data:{value:value}, target:{entity_id:entityId}}, (result, failure) => {
            if (callback) callback(!failure, failure || "");
        });
    }
    function refresh() {
        if (!connected) return;
        const generation=++refreshGeneration;
        stateDeltas=({});
        send("get_states", {}, result => {
            if (!result || generation!==refreshGeneration) return;
            states=HA.mergeStates(result,stateDeltas);
            cacheSleepSchedule();
            loadSleepSchedules(() => {
                if (generation !== refreshGeneration) return;
                const now = Date.now() / 1000;
                const active = sleepCache.sleepBedtimeEpoch > 0
                    && sleepCache.sleepWakeEpoch > sleepCache.sleepBedtimeEpoch
                    && now >= sleepCache.sleepBedtimeEpoch && now < sleepCache.sleepWakeEpoch;
                sleepScheduleRefreshed(active,
                    sleepCache.sleepNightStartEpoch, sleepCache.sleepWakeEpoch);
            }, true);
        });
        send("get_services", {}, result => { if (result && generation===refreshGeneration) services=result; });
        send("config/area_registry/list", {}, result => { if (result && generation===refreshGeneration) areas=result.sort((a,b) => a.name.localeCompare(b.name)); });
        send("config/entity_registry/list", {}, result => { if (result && generation===refreshGeneration) entityRegistry=result; });
        send("config/device_registry/list", {}, result => { if (result && generation===refreshGeneration) devices=result; });
    }
    function callService(entity, service, data, targetDomain) {
        if (!available(entity) || busy[entity.entity_id]) return;
        const d = targetDomain || domain(entity);
        if (!services[d]?.[service]) { error = Translation.tr("This control is not supported by your server"); return; }
        error="";
        busy = Object.assign({},busy,{[entity.entity_id]:true});
        send("call_service", {domain:d,service:service,service_data:data || {},target:{entity_id:entity.entity_id}}, (result, failure) => {
            const updated = Object.assign({},busy); delete updated[entity.entity_id]; busy = updated;
            if (failure) error = Translation.tr("Action failed") + ": " + failure;
        });
    }
    function canActivate(entity) { return HA.primaryAction(entity) !== null; }
    function activate(entity) {
        const action = HA.primaryAction(entity);
        if (action) callService(entity,action.service,{},action.domain);
    }
    function favoriteColors(entity) { return HA.favoriteColors(entity,entityRegistry); }
    function colorPreview(color,entity) { const rgb=HA.lightColorRgb(color,entity?.attributes); return Qt.rgba(rgb[0]/255,rgb[1]/255,rgb[2]/255,1); }
    function applyLightColor(entity,color) {
        if (!HA.validFavorite(color)) return;
        const data={};
        for (const key of ["color_temp_kelvin","hs_color","rgb_color","rgbw_color","rgbww_color"])
            if (color[key]!==undefined) data[key]=color[key];
        callService(entity,"turn_on",data);
    }
    function setHue(entity, hue) { callService(entity,"turn_on",{rgb_color:HA.rgbFromHue(hue)}); }
    function openSettings() { Quickshell.execDetached(["env","QS_SETTINGS_PAGE=homeAssistant","qs","-p",Quickshell.shellPath("settings.qml")]); }
    function openEntity(entity) { Qt.openUrlExternally(settings.url.replace(/\/+$/,"") + "/lovelace?entity_id=" + encodeURIComponent(entity.entity_id)); }
    function reconnect() {
        reconnecting = true;
        connected = false;
        authFailed = false;
        error = "";
        retryTimer.stop(); refreshTimer.stop();
        failPending(Translation.tr("Connection restarted"));
        refreshGeneration++;
        connectTimer.restart();
    }
    property bool credentialLookupPending: true
    // The helper only reads unlocked items and never opens an unlock dialog.
    // Use the current lock state: a lazy singleton can miss the login event.
    readonly property bool mayReadCredentials: Config.ready && Persistent.ready
        && settings.enabled && !GlobalStates.screenLocked
    onBedLockEnabledChanged: if (bedLockEnabled) refreshBedLockLan()
    onMayReadCredentialsChanged: if (mayReadCredentials) credentialTimer.restart(); else credentialTimer.stop()
    function lookupToken() {
        credentialLookupPending = true;
        if (mayReadCredentials) credentialTimer.restart();
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) root.refreshBedLockLan();
            else root.lookupToken();
        }
    }
    Timer {
        id: credentialTimer
        interval: 1000
        onTriggered: {
            if (!root.mayReadCredentials || lookup.running || save.running) return;
            root.credentialLookupPending = false;
            lookup.running = true;
        }
    }
    Timer {
        interval: 5000; repeat: true
        running: root.mayReadCredentials && (!root.token.length || root.authFailed || root.credentialLookupPending)
        onTriggered: root.lookupToken()
    }
    function saveToken(value) {
        if (!mayReadCredentials || save.running || !value.trim()) return;
        save.secret = value.trim();
        save.stdinEnabled = true;
        save.running = true;
    }
    Component.onCompleted: { lookupToken(); refreshBedLockLan(); }
    Connections {
        target: root.settings
        function onUrlChanged() { root.clearState(); root.reconnect(); root.lookupToken(); }
        function onEnabledChanged() { root.reconnect(); if (root.settings.enabled) root.lookupToken(); else root.clearState(); }
        function onCredentialRevisionChanged() { root.lookupToken(); }
    }
    Process {
        id: lookup
        command: ["python3",Quickshell.shellPath("scripts/home_assistant_token.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                const savedToken = text.trim();
                if (savedToken) {
                    root.credentialMessage = "";
                    if (savedToken !== root.token) {
                        root.token = savedToken;
                        root.reconnect();
                    }
                }
            }
        }
        onExited: (code, status) => {
            if (code === 3) root.credentialMessage = Translation.tr("Waiting for your keyring to unlock");
            else if (code === 2) root.credentialMessage = Translation.tr("Could not read your keyring. Retrying…");
            else if (code === 1) root.credentialMessage = Translation.tr("No saved Home Assistant token found");
        }
    }
    Process {
        id: save
        property string secret: ""
        command: ["python3",Quickshell.shellPath("scripts/home_assistant_token.py"),"--store"]
        onRunningChanged: if (running) { write(secret); stdinEnabled = false; }
        onExited: (code, status) => {
            if (code === 0) {
                root.token = secret;
                root.settings.credentialRevision += 1;
                root.credentialMessage = Translation.tr("Token saved in your keyring");
                root.reconnect();
            } else root.credentialMessage = Translation.tr("Token could not be saved. Unlock your keyring and check secret-tool.");
            root.tokenSaveFinished(code===0);
            secret = "";
        }
    }
    Timer { id: connectTimer; interval: 250; onTriggered: root.reconnecting = false }
    Timer { id:refreshTimer; interval:150; onTriggered:root.refresh() }
    Timer { id: retryTimer; interval: 5000; onTriggered: root.reconnect() }
    Timer {
        interval: 1000; running: root.connected; repeat: true
        onTriggered: {
            for (const id of Object.keys(root.pending)) {
                const request = root.pending[id];
                if (Date.now() - request.time < 15000) continue;
                delete root.pending[id];
                if (request.callback) request.callback(null, Translation.tr("Request timed out"));
                if (request.type === "ping") { root.reconnect(); break; }
            }
        }
    }
    Timer {
        interval:250
        running:root.connected && root.mediaPlayers.some(e => e.state === "playing")
        repeat:true
        onTriggered:root.mediaClock = Date.now()
    }
    Timer { interval: 30000; running: root.connected; repeat: true; onTriggered: root.send("ping", {}) }
    function handleMessage(message) {
            let msg;
            try { msg = JSON.parse(message); } catch (e) { return; }
            if (msg.type === "auth_required") socket.sendTextMessage(JSON.stringify({type:"auth",access_token:root.token}));
            else if (msg.type === "auth_invalid") { root.authFailed = true; root.error = Translation.tr("Authentication failed. Replace your access token in Settings."); }
            else if (msg.type === "auth_ok") {
                root.clearState(); root.nextId = 1; root.connected = true; root.error = ""; retryTimer.stop();
                root.send("subscribe_events", {event_type:"state_changed"});
                for (const type of ["area_registry_updated","entity_registry_updated","device_registry_updated"]) root.send("subscribe_events", {event_type:type});
                root.refresh();
                root.loadSleepSchedules(null, true);
            } else if (msg.type === "result" || msg.type === "pong") {
                const request = root.pending[msg.id]; delete root.pending[msg.id];
                const failure = msg.success === false ? (msg.error?.message || msg.error?.code || "Unknown error") : null;
                if (request?.callback) request.callback(msg.result, failure);
                if (failure) root.error = failure;
            } else if (msg.type === "event") {
                const data = msg.event?.data;
                if (msg.event?.event_type === "state_changed" && data) {
                    root.recordState(data);
                } else refreshTimer.restart();
            }
    }
    // The QML WebSocket API cannot set HTTP headers. Use the configured
    // User-Agent for reverse proxies that reject clients without one.
    Process {
        id:socket
        property string failure:""
        property bool active:Config.ready && root.settings.enabled && root.configured && !root.authFailed && !root.reconnecting
        running:active
        stdinEnabled:true
        command:["python3",Quickshell.shellPath("scripts/home_assistant_socket.py"),root.websocketUrl,Config.options.networking.userAgent || "Mozilla/5.0"]
        function sendTextMessage(message) { if (running) write(message+"\n"); }
        onRunningChanged:if (running) failure=""
        stdout:SplitParser {
            onRead:line => {
                let event; try { event=JSON.parse(line); } catch (e) { return; }
                if (event.event==="message") root.handleMessage(event.message);
                else if (event.event==="error") { socket.failure=event.detail; root.connectionLost(event.detail); }
            }
        }
        onExited:root.connectionLost(failure)
    }
}
