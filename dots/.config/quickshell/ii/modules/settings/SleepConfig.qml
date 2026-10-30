pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.desktop
import qs.services
import "sleep_schedule.js" as Sleep

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760
    horizontalContentPadding: 0
    topContentPadding: 0
    bottomContentPadding: 32

    property var groups: []
    property string groupId: ""
    readonly property bool tonightMode: groupId === "sleep.tonight"
    readonly property bool editorMode: groupId === "sleep.schedule" || tonightMode
    signal navigate(string category, string group)
    property bool editing: false
    property int editIndex: -1
    property var draftDays: []
    property int draftBed: 22 * 60
    property int draftWake: 6 * 60
    property bool saving: false
    property bool numberSaving: false
    property string feedback: ""
    property bool feedbackError: false
    property var nowDate: new Date()
    readonly property var sleepItem: HomeAssistant.sleepScheduleItems.find(item => item.id === "sleep_schedule")
    readonly property var windItem: HomeAssistant.sleepScheduleItems.find(item => item.id === "wind_down")
    readonly property bool canEdit: HomeAssistant.connected && !!sleepItem && !!windItem
                              && !HomeAssistant.sleepScheduleLoading && !saving
    readonly property bool canOpenEditor: HomeAssistant.connected && !saving
    readonly property bool tonightActive: !!HomeAssistant.sleepPlan.tonight_override
    readonly property var tonightBedtime: tonightActive ? planDate(HomeAssistant.sleepPlan.tonight_override?.bedtime) : null
    readonly property var tonightWake: tonightActive ? planDate(HomeAssistant.sleepPlan.tonight_override?.wakeup) : null
    readonly property bool allDaysUsed: groups.reduce((count, group) => count + group.days.length, 0) >= 7
    readonly property int windMinutes: Number(HomeAssistant.sleepPlan.weekly?.[Sleep.days[nowDate.getDay()]]?.wind_down_minutes ?? 30)
    readonly property int delayMinutes: Number(HomeAssistant.sleepPlan.delay_minutes ?? 30)
    readonly property int maxDelays: Number(HomeAssistant.sleepPlan.max_delays ?? 3)
    readonly property int delaysUsed: Number(HomeAssistant.sleepPlan.delays_used ?? 0)
    readonly property var nextBaseline: Sleep.nextPeriod(groups, nowDate)
    readonly property var nextBedtime: {
        if (tonightWake && tonightWake > nowDate && tonightBedtime) return tonightBedtime;
        const remote = Date.parse(HomeAssistant.sleepPlan.bedtime || "");
        return Number.isFinite(remote) && remote > nowDate.getTime()
                ? new Date(remote) : nextBaseline?.bed || null;
    }
    readonly property var nextWake: {
        const effective=planDate(HomeAssistant.sleepPlan.wakeup);
        const effectiveBed=planDate(HomeAssistant.sleepPlan.bedtime);
        if(effective && effectiveBed && nextBedtime?.getTime()===effectiveBed.getTime() && effective>nowDate)return effective;
        if (tonightWake && tonightWake > nowDate) return tonightWake;
        const scheduled = Sleep.wakeForBedtime(groups, nextBedtime,
                                                Math.max(maxDelays, delaysUsed) * delayMinutes);
        if (scheduled) return scheduled;
        return nextBaseline && nextBedtime?.getTime() === nextBaseline.bed.getTime()
                ? nextBaseline.wake : null;
    }

    function planDate(value) {
        value = value || "";
        const date = new Date(value.replace(" ", "T"));
        return Number.isFinite(date.getTime()) ? date : null;
    }
    function localDateTime(date) {
        return Qt.formatDateTime(date, "yyyy-MM-dd HH:mm:ss");
    }
    function showFeedback(message, isError) {
        feedback = message;
        feedbackError = isError;
    }
    function refreshGroups() {
        if (editing || saving) return;
        let source = sleepItem;
        if (!source) {
            try { source = JSON.parse(HomeAssistant.sleepCache.sleepScheduleJson); }
            catch (error) { source = null; }
        }
        if (!source) return;
        const parsed = Sleep.readGroups(source);
        groups = parsed.groups;
        if (parsed.error) showFeedback(parsed.error, true);
        else if (feedbackError) showFeedback("", false);
    }
    function assignedElsewhere(day) {
        return groups.some((group, index) => index !== editIndex && group.days.includes(day));
    }
    function beginEdit(index) {
        if (!canOpenEditor) return;
        editIndex = index;
        const group = index >= 0 ? groups[index] : null;
        draftDays = group ? group.days.slice() : [];
        draftBed = group ? group.bed : 22 * 60;
        draftWake = group ? group.wake : 6 * 60;
        editing = true;
        showFeedback("", false);
        navigate("sleep", "sleep.schedule");
    }
    function beginTonightEdit() {
        if (!canOpenEditor) return;
        const bed = tonightBedtime && tonightWake && tonightWake > nowDate
                  ? tonightBedtime : nextBedtime;
        const wake = tonightWake && tonightWake > nowDate ? tonightWake : nextWake;
        if (!bed || !wake) {
            showFeedback(Translation.tr("Refresh your sleep schedule before editing tonight."), true);
            return;
        }
        draftBed = bed.getHours() * 60 + bed.getMinutes();
        draftWake = wake.getHours() * 60 + wake.getMinutes();
        editing = true;
        showFeedback("", false);
        navigate("sleep", "sleep.tonight");
    }
    function saveTonightDraft() {
        const duration = Sleep.duration(draftBed, draftWake);
        if (duration < 60 || duration > 960) {
            showFeedback(Translation.tr("Choose a sleep period between 1 and 16 hours."), true);
            return;
        }
        const baselineWake = tonightWake && tonightWake > nowDate ? tonightWake : nextWake;
        if (!baselineWake) {
            showFeedback(Translation.tr("Refresh your sleep schedule before saving tonight."), true);
            return;
        }
        const wake = new Date(baselineWake);
        wake.setHours(Math.floor(draftWake / 60), draftWake % 60, 0, 0);
        const bed = new Date(wake);
        bed.setMinutes(bed.getMinutes() - duration);
        if (wake <= nowDate) {
            showFeedback(Translation.tr("Tonight's wake time must be in the future."), true);
            return;
        }
        saving = true;
        HomeAssistant.saveTonightSleepSchedule(localDateTime(bed), localDateTime(wake),
                                                (success, error) => {
            saving = false;
            if (success) {
                editing = false;
                showFeedback(Translation.tr("Tonight's sleep schedule saved."), false);
                navigate("sleep", "");
            } else showFeedback(error || Translation.tr("Could not save tonight's schedule."), true);
        });
    }
    function clearTonightDraft() {
        saving = true;
        HomeAssistant.clearTonightSleepSchedule((success, error) => {
            saving = false;
            if (success) {
                editing = false;
                showFeedback(Translation.tr("Tonight's override removed."), false);
                navigate("sleep", "");
            } else showFeedback(error || Translation.tr("Could not remove tonight's override."), true);
        });
    }
    function toggleDay(day) {
        if (assignedElsewhere(day)) return;
        const next = draftDays.slice();
        const index = next.indexOf(day);
        if (index >= 0) next.splice(index, 1);
        else next.push(day);
        draftDays = next;
    }
    function writeSchedules(nextGroups, nextWind, callback) {
        const built = Sleep.buildItems(nextGroups, nextWind, sleepItem, windItem);
        if (built.error) {
            showFeedback(built.error, true);
            if (callback) callback(false);
            return;
        }
        saving = true;
        HomeAssistant.saveSleepSchedules(built.sleep, built.wind, (success, error) => {
            saving = false;
            if (success) {
                groups = nextGroups;
                editing = false;
                showFeedback(Translation.tr("Sleep schedule saved."), false);
                navigate("sleep", "");
            } else showFeedback(error || Translation.tr("Could not save the sleep schedule."), true);
            if (callback) callback(success);
        });
    }
    function saveDraft() {
        const next = groups.map(group => ({bed: group.bed, wake: group.wake, days: group.days.slice()}));
        const group = {bed: draftBed, wake: draftWake, days: draftDays.slice()};
        if (editIndex >= 0) next[editIndex] = group;
        else next.push(group);
        writeSchedules(next, windMinutes);
    }
    function removeDraft() {
        if (editIndex < 0) return;
        const next = groups.map(group => ({bed: group.bed, wake: group.wake, days: group.days.slice()}));
        next.splice(editIndex, 1);
        writeSchedules(next, windMinutes);
    }
    function setNumber(entityId, value) {
        if (!canEdit || numberSaving) return;
        numberSaving = true;
        HomeAssistant.setSleepNumber(entityId, value, (success, error) => {
            numberSaving = false;
            showFeedback(success ? Translation.tr("Sleep setting saved.")
                                 : error || Translation.tr("Could not save this setting."), !success);
        });
    }
    function setWindMinutes(value) {
        if (!canEdit || numberSaving || value === windMinutes) return;
        const next=groups.map(group=>({bed:group.bed,wake:group.wake,days:group.days.slice()}));
        writeSchedules(next,value);
    }
    function dateText(date) {
        if (!date) return "—";
        const today = new Date(nowDate.getFullYear(), nowDate.getMonth(), nowDate.getDate());
        const tomorrow = new Date(today);
        tomorrow.setDate(tomorrow.getDate() + 1);
        const dayAfter = new Date(tomorrow);
        dayAfter.setDate(dayAfter.getDate() + 1);
        if (date >= today && date < tomorrow)
            return date.getHours() < 18 ? Translation.tr("Today") : Translation.tr("Tonight");
        if (date >= tomorrow && date < dayAfter) return Translation.tr("Tomorrow");
        return Qt.formatDateTime(date, "ddd, MMM d");
    }
    function timeText(date) {
        return date ? Qt.formatDateTime(date, "h:mm AP") : "—";
    }
    function pickDial(x, y) {
        const center = dial.width / 2;
        let angle = Math.atan2(y - center, x - center) + Math.PI / 2;
        if (angle < 0) angle += 2 * Math.PI;
        return (Math.round(angle / (2 * Math.PI) * 1440 / 5) * 5) % 1440;
    }
    function dialDistance(a, b) {
        const diff = Math.abs(a - b);
        return Math.min(diff, 1440 - diff);
    }

    onSleepItemChanged: refreshGroups()
    Connections {
        target: HomeAssistant
        function onSleepScheduleItemsChanged() { root.refreshGroups(); }
        function onConnectedChanged() {
            if (HomeAssistant.connected) HomeAssistant.loadSleepSchedules();
        }
    }
    Connections {
        target: HomeAssistant.sleepCache
        function onSleepScheduleJsonChanged() { root.refreshGroups(); }
    }
    Component.onCompleted: {
        if (HomeAssistant.connected) HomeAssistant.loadSleepSchedules(null, true);
        refreshGroups();
        if (groupId === "sleep.schedule" && canOpenEditor) beginEdit(groups.length ? 0 : -1);
        else if (tonightMode && canOpenEditor) beginTonightEdit();
    }
    onGroupIdChanged: {
        if (!editorMode) editing = false;
        else if (!editing && canOpenEditor) {
            if (tonightMode) beginTonightEdit();
            else beginEdit(groups.length ? 0 : -1);
        }
    }
    onCanOpenEditorChanged: {
        if (editorMode && canOpenEditor && !editing) {
            if (tonightMode) beginTonightEdit();
            else beginEdit(groups.length ? 0 : -1);
        }
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.nowDate = new Date() }

    ColumnLayout {
        visible: !root.editorMode
        Layout.fillWidth: true
        spacing: 14

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Your schedule")
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Medium
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: nextColumn.implicitHeight + 32
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.normal
            ColumnLayout {
                id: nextColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: root.tonightActive ? Translation.tr("Tonight · temporary") : Translation.tr("Next")
                        color: Appearance.colors.colPrimary
                        font.weight: Font.Medium
                    }
                    DialogButton {
                        buttonText: Translation.tr("Edit")
                        implicitHeight: 24
                        padding: 8
                        enabled: root.canOpenEditor && !!root.nextWake
                        onClicked: root.beginTonightEdit()
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 28
                    ColumnLayout {
                        Layout.fillWidth: false
                        spacing: 2
                        RowLayout {
                            spacing: 4
                            MaterialSymbol { text: "bed"; iconSize: 18; color: Appearance.colors.colPrimary }
                            StyledText { text: Translation.tr("BEDTIME"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.Bold }
                        }
                        StyledText { text: root.timeText(root.nextBedtime); font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.Medium }
                        StyledText { text: root.dateText(root.nextBedtime); color: Appearance.colors.colSubtext }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: 4
                            MaterialSymbol { text: "alarm"; iconSize: 18; color: Appearance.colors.colPrimary }
                            StyledText { text: Translation.tr("WAKE UP"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.Bold }
                        }
                        StyledText { text: root.timeText(root.nextWake); font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.Medium }
                        StyledText { text: root.dateText(root.nextWake); color: Appearance.colors.colSubtext }
                    }
                }
            }
        }
        StyledText {
            visible: !HomeAssistant.connected || HomeAssistant.sleepScheduleLoading || !!HomeAssistant.sleepScheduleError
            Layout.fillWidth: true
            text: !HomeAssistant.connected ? root.groups.length
                    ? Translation.tr("Showing your saved schedule. Connect Home Assistant to edit.")
                    : Translation.tr("Connect Home Assistant to edit your sleep schedule.")
                  : HomeAssistant.sleepScheduleLoading ? root.groups.length
                    ? Translation.tr("Refreshing your schedule…")
                    : Translation.tr("Loading your schedule…")
                  : HomeAssistant.sleepScheduleError
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }
        StyledText {
            visible: !!root.feedback
            Layout.fillWidth: true
            text: root.feedback
            color: root.feedbackError ? Appearance.colors.colError : Appearance.colors.colPrimary
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Full schedule")
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
            }
            RippleButtonWithIcon {
                materialIcon: "refresh"
                mainText: Translation.tr("Refresh")
                enabled: HomeAssistant.connected && !HomeAssistant.sleepScheduleLoading && !root.saving
                onClicked: HomeAssistant.loadSleepSchedules(null, true)
            }
        }
        StyledText {
            visible: !root.groups.length && !HomeAssistant.sleepScheduleLoading
            Layout.fillWidth: true
            text: Translation.tr("No sleep days are scheduled.")
            color: Appearance.colors.colSubtext
        }
        Repeater {
            model: root.groups
            delegate: Rectangle {
                id: scheduleCard
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: scheduleColumn.implicitHeight + 32
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.normal
                ColumnLayout {
                    id: scheduleColumn
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: Sleep.dayLabel(scheduleCard.modelData.days)
                            color: Appearance.colors.colPrimary
                            font.weight: Font.Medium
                        }
                        DialogButton {
                            buttonText: Translation.tr("Edit")
                            implicitHeight: 24
                            padding: 8
                            enabled: root.canOpenEditor
                            onClicked: root.beginEdit(scheduleCard.index)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 28
                        ColumnLayout {
                            Layout.fillWidth: false
                            spacing: 2
                            RowLayout {
                                spacing: 4
                                MaterialSymbol { text: "bed"; iconSize: 18; color: Appearance.colors.colPrimary }
                                StyledText { text: Translation.tr("BEDTIME"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.Bold }
                            }
                            StyledText { text: Sleep.clockLabel(scheduleCard.modelData.bed); font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.Medium }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                spacing: 4
                                MaterialSymbol { text: "alarm"; iconSize: 18; color: Appearance.colors.colPrimary }
                                StyledText { text: Translation.tr("WAKE UP"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.Bold }
                            }
                            StyledText { text: Sleep.clockLabel(scheduleCard.modelData.wake); font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.Medium }
                        }
                    }
                }
            }
        }
        RippleButtonWithIcon {
            visible: !root.allDaysUsed
            Layout.alignment: Qt.AlignLeft
            materialIcon: "add"
            mainText: Translation.tr("Add schedule")
            implicitHeight: 42
            horizontalPadding: 16
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            contentColor: Appearance.colors.colOnPrimary
            enabled: root.canOpenEditor && !root.editing
            onClicked: root.beginEdit(-1)
        }
        StyledText {
            visible: root.allDaysUsed
            Layout.fillWidth: true
            text: Translation.tr("All seven wake days are scheduled. Edit a group to move a day.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Sleep options")
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Medium
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: optionsColumn.implicitHeight + 32
            color: Appearance.colors.colLayer2
            radius: Appearance.rounding.normal
            ColumnLayout {
                id: optionsColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Wind Down"); wrapMode: Text.Wrap }
                    NumberInput {
                        number: root.windMinutes
                        minimum: 0
                        maximum: 120
                        increment: 5
                        integral: true
                        unit: Translation.tr("min")
                        Accessible.name: Translation.tr("Wind Down")
                        enabled: root.canEdit && !root.numberSaving && !root.saving
                        onEdited: number => root.setWindMinutes(number)
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Starts before each scheduled bedtime.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Delay length"); wrapMode: Text.Wrap }
                    NumberInput {
                        number: root.delayMinutes
                        minimum: 5
                        maximum: 120
                        increment: 5
                        integral: true
                        unit: Translation.tr("min")
                        Accessible.name: Translation.tr("Delay length")
                        enabled: root.canEdit && !root.numberSaving && !root.saving
                        onEdited: number => root.setNumber("delay_minutes", number)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Maximum delays"); wrapMode: Text.Wrap }
                    NumberInput {
                        number: root.maxDelays
                        minimum: 0
                        maximum: 10
                        increment: 1
                        integral: true
                        Accessible.name: Translation.tr("Maximum delays")
                        enabled: root.canEdit && !root.numberSaving && !root.saving
                        onEdited: number => root.setNumber("max_delays", number)
                    }
                }
                ConfigSwitch {
                    text: Translation.tr("Bed Lock")
                    buttonIcon: "bedtime"
                    checked: Config.options.lock.bedtimeEnabled
                    onCheckedChanged: if (Config.options.lock.bedtimeEnabled !== checked)
                                          Config.options.lock.bedtimeEnabled = checked
                }
            }
        }
    }
    Rectangle {
        visible: root.editorMode && root.editing
        Layout.fillWidth: true
        implicitHeight: editColumn.implicitHeight + 40
        color: Appearance.colors.colLayer2
        radius: Appearance.rounding.normal
        ColumnLayout {
            id: editColumn
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16
            StyledText {
                visible: !root.tonightMode
                text: Translation.tr("Wake days")
                color: Appearance.colors.colSubtext
            }
            RowLayout {
                visible: !root.tonightMode
                Layout.fillWidth: true
                spacing: 5
                Repeater {
                    model: [1, 2, 3, 4, 5, 6, 0]
                    delegate: Button {
                        id: dayButton
                        required property int modelData
                        Layout.fillWidth: true
                        implicitHeight: 48
                        implicitWidth: 44
                        enabled: !root.assignedElsewhere(modelData)
                        checkable: true
                        checked: root.draftDays.includes(modelData)
                        onClicked: root.toggleDay(modelData)
                        Accessible.name: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][modelData]
                        Accessible.description: enabled ? Translation.tr("Toggle wake day") : Translation.tr("Already scheduled")
                        contentItem: StyledText {
                            text: Sleep.shortDays[dayButton.modelData].slice(0, 1)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: dayButton.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                        background: Rectangle {
                            radius: Appearance.rounding.full
                            color: dayButton.checked ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                            opacity: dayButton.enabled ? 1 : 0.38
                        }
                    }
                }
            }
            StyledText {
                visible: !root.tonightMode
                text: Translation.tr("Already scheduled days are unavailable.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: 4
                        MaterialSymbol { text: "bed"; iconSize: 18; color: Appearance.colors.colPrimary }
                        StyledText { text: Translation.tr("BEDTIME"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.Bold }
                    }
                    SettingsTimeInput {
                        value: Sleep.clock(root.draftBed)
                        label: Translation.tr("Bedtime")
                        onChosen: value => root.draftBed = Sleep.timeMinutes(value)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: 4
                        MaterialSymbol { text: "alarm"; iconSize: 18; color: Appearance.colors.colPrimary }
                        StyledText { text: Translation.tr("WAKE UP"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.Bold }
                    }
                    SettingsTimeInput {
                        value: Sleep.clock(root.draftWake)
                        label: Translation.tr("Wake up")
                        onChosen: value => root.draftWake = Sleep.timeMinutes(value)
                    }
                }
            }
            StyledText {
                visible: root.tonightMode
                Layout.fillWidth: true
                text: Translation.tr("This change applies to the next sleep period and clears after wake up.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
            }
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(420, editColumn.width - 16)
                Layout.preferredHeight: width
                Canvas {
                    id: dial
                    anchors.fill: parent
                    Connections {
                        target: root
                        function onDraftBedChanged() { dial.requestPaint(); }
                        function onDraftWakeChanged() { dial.requestPaint(); }
                    }
                    onPaint: {
                        const ctx = getContext("2d");
                        const c = width / 2;
                        const r = c - 34;
                        ctx.clearRect(0, 0, width, height);
                        const start = -Math.PI / 2 + root.draftBed / 1440 * Math.PI * 2;
                        const span = Sleep.duration(root.draftBed, root.draftWake) / 1440 * Math.PI * 2;
                        const end = start + span;
                        const handleRadius = Math.max(12, Math.min(21, r * Math.sin(Math.min(span, Math.PI * 2 - span) / 2) - 2));
                        ctx.lineWidth = 36;
                        ctx.strokeStyle = Appearance.colors.colLayer1;
                        ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.stroke();
                        ctx.lineWidth = 36;
                        ctx.strokeStyle = Appearance.colors.colPrimary;
                        ctx.beginPath(); ctx.arc(c, c, r, start, end); ctx.stroke();
                        // Each 6px fillet is tangent to both the circular handle
                        // recess and an edge of the annular track. This makes a
                        // concave notch with rounded shoulders on both tracks.
                        const recessRadius = handleRadius + 4;
                        const filletRadius = 6;
                        function fillet(outer) {
                            const railRadius = outer ? r + 18 : r - 18;
                            const centerRadius = outer ? railRadius - filletRadius
                                                       : railRadius + filletRadius;
                            const tangentRadius = recessRadius + filletRadius;
                            const y = (r * r + tangentRadius * tangentRadius
                                       - centerRadius * centerRadius) / (2 * r);
                            const x = Math.sqrt(Math.max(0, tangentRadius * tangentRadius - y * y));
                            return {
                                center: {x: x, y: y},
                                rail: {x: railRadius * x / centerRadius,
                                       y: r + railRadius * (y - r) / centerRadius},
                                recess: {x: recessRadius * x / tangentRadius,
                                         y: recessRadius * y / tangentRadius}
                            };
                        }
                        function reflected(point) { return {x: -point.x, y: point.y}; }
                        function arcBetween(center, radius, from, to) {
                            const a = Math.atan2(from.y - center.y, from.x - center.x);
                            const b = Math.atan2(to.y - center.y, to.x - center.x);
                            const turn = ((b - a) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
                            ctx.arc(center.x, center.y, radius, a, b, turn > Math.PI);
                        }
                        const outerFillet = fillet(true);
                        const innerFillet = fillet(false);
                        ctx.save();
                        ctx.globalCompositeOperation = "destination-out";
                        for (const minute of [root.draftBed, root.draftWake]) {
                            const a = -Math.PI / 2 + minute / 1440 * Math.PI * 2;
                            ctx.save();
                            ctx.translate(c + Math.cos(a) * r, c + Math.sin(a) * r);
                            ctx.rotate(a + Math.PI / 2);
                            ctx.beginPath();
                            ctx.moveTo(outerFillet.rail.x, outerFillet.rail.y);
                            arcBetween(outerFillet.center, filletRadius,
                                       outerFillet.rail, outerFillet.recess);
                            arcBetween({x: 0, y: 0}, recessRadius,
                                       outerFillet.recess, innerFillet.recess);
                            arcBetween(innerFillet.center, filletRadius,
                                       innerFillet.recess, innerFillet.rail);
                            ctx.lineTo(innerFillet.rail.x, 40);
                            ctx.lineTo(-innerFillet.rail.x, 40);
                            ctx.lineTo(-innerFillet.rail.x, innerFillet.rail.y);
                            arcBetween(reflected(innerFillet.center), filletRadius,
                                       reflected(innerFillet.rail), reflected(innerFillet.recess));
                            arcBetween({x: 0, y: 0}, recessRadius,
                                       reflected(innerFillet.recess), reflected(outerFillet.recess));
                            arcBetween(reflected(outerFillet.center), filletRadius,
                                       reflected(outerFillet.recess), reflected(outerFillet.rail));
                            ctx.lineTo(-outerFillet.rail.x, -40);
                            ctx.lineTo(outerFillet.rail.x, -40);
                            ctx.closePath();
                            ctx.fill();
                            ctx.restore();
                        }
                        ctx.restore();
                        ctx.fillStyle = Appearance.colors.colLayer3;
                        ctx.beginPath(); ctx.arc(c, c, r - 27, 0, Math.PI * 2); ctx.fill();
                        ctx.save();
                        ctx.strokeStyle = Appearance.colors.colOnLayer3;
                        for (let tick = 0; tick < 96; tick++) {
                            const hourly = tick % 4 === 0;
                            const a = -Math.PI / 2 + tick / 96 * Math.PI * 2;
                            const outer = r - 31;
                            const inner = outer - (hourly ? 13 : 6);
                            ctx.globalAlpha = hourly ? 0.60 : 0.22;
                            ctx.lineWidth = hourly ? 2 : 1;
                            ctx.beginPath();
                            ctx.moveTo(c + Math.cos(a) * inner, c + Math.sin(a) * inner);
                            ctx.lineTo(c + Math.cos(a) * outer, c + Math.sin(a) * outer);
                            ctx.stroke();
                        }
                        ctx.fillStyle = Appearance.colors.colOnLayer3;
                        ctx.textAlign = "center";
                        ctx.textBaseline = "middle";
                        const labelRadius = r - 77;
                        for (let hour = 0; hour < 24; hour += 2) {
                            const a = -Math.PI / 2 + hour / 24 * Math.PI * 2;
                            const cardinal = hour % 6 === 0;
                            const label = hour === 0 ? "12 AM" : hour === 6 ? "6 AM"
                                        : hour === 12 ? "12 PM" : hour === 18 ? "6 PM"
                                        : String(hour % 12);
                            ctx.font = cardinal ? "600 15px sans-serif" : "500 15px sans-serif";
                            ctx.globalAlpha = cardinal ? 0.92 : 0.70;
                            ctx.fillText(label, c + Math.cos(a) * labelRadius,
                                               c + Math.sin(a) * labelRadius);
                        }
                        ctx.restore();
                        for (const handle of [{minute: root.draftBed, color: Appearance.colors.colPrimaryContainer},
                                              {minute: root.draftWake, color: Appearance.colors.colSecondaryContainer}]) {
                            const a = -Math.PI / 2 + handle.minute / 1440 * Math.PI * 2;
                            ctx.fillStyle = handle.color;
                            ctx.beginPath();
                            ctx.arc(c + Math.cos(a) * r, c + Math.sin(a) * r, handleRadius, 0, Math.PI * 2);
                            ctx.fill();
                        }
                    }
                    onWidthChanged: requestPaint()
                }
                MaterialSymbol {
                    width: 42; height: 42
                    x: dial.width / 2 + Math.cos(-Math.PI / 2 + root.draftBed / 1440 * Math.PI * 2) * (dial.width / 2 - 34) - width / 2
                    y: dial.height / 2 + Math.sin(-Math.PI / 2 + root.draftBed / 1440 * Math.PI * 2) * (dial.width / 2 - 34) - height / 2
                    text: "bed"
                    iconSize: 23
                    color: Appearance.colors.colOnPrimaryContainer
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                MaterialSymbol {
                    width: 42; height: 42
                    x: dial.width / 2 + Math.cos(-Math.PI / 2 + root.draftWake / 1440 * Math.PI * 2) * (dial.width / 2 - 34) - width / 2
                    y: dial.height / 2 + Math.sin(-Math.PI / 2 + root.draftWake / 1440 * Math.PI * 2) * (dial.width / 2 - 34) - height / 2
                    text: "alarm"
                    iconSize: 23
                    color: Appearance.colors.colOnSecondaryContainer
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 51
                    text: "dark_mode"
                    iconSize: 27
                    color: Appearance.colors.colPrimary
                }
                MaterialSymbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 + 25
                    text: "sunny"
                    iconSize: 27
                    color: Appearance.colors.colTertiary
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    property bool bedHandle: true
                    onPressed: mouse => {
                        const selected = root.pickDial(mouse.x, mouse.y);
                        bedHandle = root.dialDistance(selected, root.draftBed)
                                    <= root.dialDistance(selected, root.draftWake);
                    }
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        const selected = root.pickDial(mouse.x, mouse.y);
                        if (bedHandle) root.draftBed = selected;
                        else root.draftWake = selected;
                    }
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Math.floor(Sleep.duration(root.draftBed, root.draftWake) / 60)
                      + " hr" + (Sleep.duration(root.draftBed, root.draftWake) % 60
                                 ? " " + String(Sleep.duration(root.draftBed, root.draftWake) % 60).padStart(2, "0") + " min" : "")
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "check"
                    mainText: root.saving ? Translation.tr("Saving…") : root.tonightMode ? Translation.tr("Save tonight") : Translation.tr("Save schedule")
                    enabled: root.tonightMode ? root.canOpenEditor
                                             : root.canEdit && root.draftDays.length > 0 && !root.saving
                    onClicked: if (root.tonightMode) root.saveTonightDraft(); else root.saveDraft()
                }
                RippleButtonWithIcon {
                    visible: root.tonightMode ? root.tonightActive : root.editIndex >= 0
                    materialIcon: "delete"
                    mainText: root.tonightMode ? Translation.tr("Clear override") : Translation.tr("Remove")
                    enabled: root.tonightMode ? root.canOpenEditor : root.canEdit && !root.saving
                    onClicked: if (root.tonightMode) root.clearTonightDraft(); else root.removeDraft()
                }
            }
        }
    }
    StyledText {
        visible: root.editorMode && !root.editing
        Layout.fillWidth: true
        text: HomeAssistant.sleepScheduleError
              ? HomeAssistant.sleepScheduleError
              : HomeAssistant.connected
                ? Translation.tr("Loading your schedule…")
                : Translation.tr("Connect Home Assistant to edit your sleep schedule.")
        color: HomeAssistant.sleepScheduleError ? Appearance.colors.colError : Appearance.colors.colSubtext
        wrapMode: Text.Wrap
    }
}
