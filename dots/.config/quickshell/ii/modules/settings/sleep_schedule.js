.pragma library

// UI days are wake days. Home Assistant's schedule blocks are calendar days.
var days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
var shortDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
var weekMinutes = 7 * 1440;

function timeMinutes(value) {
    const match = String(value || "").match(/^([01]\d|2[0-4]):([0-5]\d)(?::[0-5]\d)?$/);
    if (!match) return -1;
    const minute = Number(match[1]) * 60 + Number(match[2]);
    return minute <= 1440 ? minute : -1;
}

function clock(minutes) {
    const normalized = ((minutes % 1440) + 1440) % 1440;
    return String(Math.floor(normalized / 60)).padStart(2, "0")
        + ":" + String(normalized % 60).padStart(2, "0");
}

function clockLabel(minutes) {
    const hour24 = Math.floor((((minutes % 1440) + 1440) % 1440) / 60);
    const minute = ((minutes % 60) + 60) % 60;
    return String(hour24 % 12 || 12) + ":" + String(minute).padStart(2, "0")
        + (hour24 >= 12 ? " PM" : " AM");
}

function duration(bed, wake) {
    return ((wake - bed) % 1440 + 1440) % 1440;
}

function dayLabel(selected) {
    const order = [1, 2, 3, 4, 5, 6, 0];
    const names = order.filter(day => selected.includes(day)).map(day => shortDays[day]);
    return names.length === 7 ? "Every day" : names.join(", ");
}

function readGroups(item) {
    if (!item) return {groups: [], error: "Sleep schedule is unavailable."};
    const blocks = days.map(day => (item[day] || []).map(block => ({
        from: timeMinutes(block.from), to: timeMinutes(block.to)
    })).sort((a, b) => a.from - b.from));
    if (blocks.some(day => day.some(block => block.from < 0 || block.to < 0 || block.to <= block.from)))
        return {groups: [], error: "The sleep schedule has an unsupported time block."};

    const groups = [];
    for (let wakeDay = 0; wakeDay < 7; wakeDay++) {
        const prior = blocks[(wakeDay + 6) % 7];
        const preceding = prior.find(block => block.to >= 1439 && block.from > 0);
        for (const block of blocks[wakeDay]) {
            // A late block is represented by the following day's morning block.
            if (block.to >= 1439 && block.from > 0
                    && blocks[(wakeDay + 1) % 7].some(next => next.from === 0))
                continue;
            const bed = block.from === 0 && preceding ? preceding.from : block.from;
            const wake = block.to % 1440;
            if (duration(bed, wake) === 0 || duration(bed, wake) > 960)
                return {groups: [], error: "The sleep schedule has an unsupported duration."};
            let group = groups.find(existing => existing.bed === bed && existing.wake === wake);
            if (!group) {
                group = {bed: bed, wake: wake, days: []};
                groups.push(group);
            }
            group.days.push(wakeDay);
        }
    }
    const assigned = [];
    for (const group of groups) {
        for (const day of group.days) {
            if (assigned.includes(day))
                return {groups: [], error: "More than one sleep block ends on the same day."};
            assigned.push(day);
        }
    }
    groups.sort((a, b) => {
        const firstA = a.days.reduce((first, day) => Math.min(first, day === 0 ? 7 : day), 7);
        const firstB = b.days.reduce((first, day) => Math.min(first, day === 0 ? 7 : day), 7);
        return firstA - firstB;
    });
    return {groups: groups, error: ""};
}

function validateGroups(groups, windMinutes) {
    if (!Number.isInteger(windMinutes) || windMinutes < 0 || windMinutes > 120)
        return "Wind Down must be between 0 and 120 minutes.";
    const assigned = [];
    for (const group of groups) {
        if (!Number.isInteger(group.bed) || group.bed < 0 || group.bed >= 1440
                || !Number.isInteger(group.wake) || group.wake < 0 || group.wake >= 1440)
            return "Choose valid bedtime and wake times.";
        const hours = duration(group.bed, group.wake);
        if (hours < 60 || hours > 960)
            return "A sleep period must last between 1 and 16 hours.";
        if (!group.days.length) return "Choose at least one wake day.";
        for (const day of group.days) {
            if (!Number.isInteger(day) || day < 0 || day > 6 || assigned.includes(day))
                return "Each wake day can belong to only one schedule.";
            assigned.push(day);
        }
    }
    return "";
}

function appendRange(out, from, to) {
    while (from < to) {
        const cycle = ((from % weekMinutes) + weekMinutes) % weekMinutes;
        const day = Math.floor(cycle / 1440);
        const minute = cycle % 1440;
        const end = Math.min(to, from + 1440 - minute);
        const endMinute = minute + end - from;
        out[days[day]].push({
            from: clock(minute) + ":00",
            to: endMinute === 1440 ? "24:00:00" : clock(endMinute) + ":00"
        });
        from = end;
    }
}

function emptyItem(source, fallbackName, fallbackIcon) {
    const out = {id: source.id, name: source.name || fallbackName, icon: source.icon || fallbackIcon};
    for (const day of days) out[day] = [];
    return out;
}

function buildItems(groups, windMinutes, sleepSource, windSource) {
    const error = validateGroups(groups, windMinutes);
    if (error) return {error: error};
    if (!sleepSource || !windSource) return {error: "Schedule sources are unavailable."};
    const sleep = emptyItem(sleepSource, "Sleep", "mdi:bed");
    const wind = emptyItem(windSource, "Wind Down", "mdi:bed-clock");
    for (const group of groups) {
        const span = duration(group.bed, group.wake);
        for (const day of group.days) {
            const wake = day * 1440 + group.wake;
            const bed = wake - span;
            appendRange(sleep, bed, wake);
            if (windMinutes > 0) appendRange(wind, bed - windMinutes, bed);
        }
    }
    for (const item of [sleep, wind]) {
        for (const day of days) {
            item[day].sort((a, b) => timeMinutes(a.from) - timeMinutes(b.from));
            let previousEnd = -1;
            for (const block of item[day]) {
                const start = timeMinutes(block.from);
                if (start < previousEnd) return {error: "Schedule periods overlap on " + day + "."};
                previousEnd = timeMinutes(block.to);
            }
        }
    }
    return {sleep: sleep, wind: wind, error: ""};
}

function nextPeriod(groups, current) {
    if (!groups.length) return null;
    const now = current || new Date();
    const base = new Date(now);
    base.setHours(0, 0, 0, 0);
    let best = null;
    for (let offset = 0; offset < 9; offset++) {
        const wakeDate = new Date(base);
        wakeDate.setDate(wakeDate.getDate() + offset);
        for (const group of groups) {
            if (!group.days.includes(wakeDate.getDay())) continue;
            const wake = new Date(wakeDate);
            wake.setMinutes(group.wake);
            const bed = new Date(wake);
            bed.setMinutes(bed.getMinutes() - duration(group.bed, group.wake));
            if (bed < now || best && bed >= best.bed) continue;
            best = {bed: bed, wake: wake};
        }
    }
    return best;
}

function wakeForBedtime(groups, actualBedtime, allowedDelayMinutes) {
    if (!actualBedtime) return null;
    const base = new Date(actualBedtime);
    base.setHours(0, 0, 0, 0);
    let closest = null;
    for (let offset = -1; offset <= 2; offset++) {
        const wakeDate = new Date(base);
        wakeDate.setDate(wakeDate.getDate() + offset);
        for (const group of groups) {
            if (!group.days.includes(wakeDate.getDay())) continue;
            const wake = new Date(wakeDate);
            wake.setMinutes(group.wake);
            const bed = new Date(wake);
            bed.setMinutes(bed.getMinutes() - duration(group.bed, group.wake));
            const delta = (actualBedtime.getTime() - bed.getTime()) / 60000;
            if (delta < 0 || delta > allowedDelayMinutes || actualBedtime >= wake) continue;
            if (!closest || bed > closest.bed) closest = {bed: bed, wake: wake};
        }
    }
    return closest?.wake || null;
}
