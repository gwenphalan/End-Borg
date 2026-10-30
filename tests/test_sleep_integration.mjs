import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

function library(relative) {
    const source = fs.readFileSync(new URL(relative, import.meta.url), "utf8")
        .replace(/^\.pragma library\s*/u, "");
    const context = vm.createContext({});
    vm.runInContext(source, context);
    return context;
}
const integration = library("../dots/.config/quickshell/ii/services/sleep_integration.js");
const editor = library("../dots/.config/quickshell/ii/modules/settings/sleep_schedule.js");
const plain = value => JSON.parse(JSON.stringify(value));
const weekly = Object.fromEntries(integration.days.map((day, index) => [day, {
    bedtime: index === 0 ? "21:00" : "22:00", wakeup: index === 0 ? "05:00" : "06:00",
    wind_down_minutes: 30,
}]));
let count = 0;
function check(name, fn) { fn(); count++; console.log(`PASS ${name}`); }

check("wake-day Sunday interval begins Saturday", () => {
    const [sleep, wind] = integration.weeklyToItems(weekly, "wake");
    assert.ok(sleep.saturday.some(p => p.from === "21:00:00" && p.to === "24:00:00"));
    assert.ok(sleep.sunday.some(p => p.from === "00:00:00" && p.to === "05:00:00"));
    assert.ok(wind.saturday.some(p => p.from === "20:30:00" && p.to === "21:00:00"));
});
check("bedtime-day Sunday interval ends Monday", () => {
    const [sleep] = integration.weeklyToItems(weekly, "bedtime");
    assert.ok(sleep.sunday.some(p => p.from === "21:00:00" && p.to === "24:00:00"));
    assert.ok(sleep.monday.some(p => p.from === "00:00:00" && p.to === "05:00:00"));
});
for (const basis of ["wake", "bedtime"]) {
    check(`${basis}-day plan survives editor roundtrip`, () => {
        const [sleep] = integration.weeklyToItems(weekly, basis);
        const parsed = editor.readGroups(sleep);
        assert.equal(parsed.error, "");
        assert.deepEqual(plain(integration.groupsToWeekly(parsed.groups, 30, basis)), weekly);
    });
}
check("missing contract keys are rejected and unscheduled editor days remain off", () => {
    const short = {...weekly}; delete short.friday;
    assert.throws(() => integration.weeklyToItems(short, "wake"), /weekday/u);
    const partial = integration.groupsToWeekly([{bed:1320,wake:360,days:[1]}], 30, "wake");
    assert.equal(partial.sunday, null);
    assert.equal(partial.monday.bedtime, "22:00");
});
check("duplicate weekdays are rejected", () => {
    assert.throws(() => integration.groupsToWeekly([
        {bed:1320,wake:360,days:[0,1,2,3,4,5,6]},
        {bed:1380,wake:420,days:[0]},
    ], 30, "wake"), /two bedtime periods/u);
});
check("invalid clock values and sleep durations are rejected", () => {
    for (const bedtime of ["24:00", "22:60", "bad"]) {
        assert.throws(() => integration.weeklyToItems({...weekly,sunday:{...weekly.sunday,bedtime}}, "wake"), /HH:MM/u);
    }
    for (const wakeup of ["21:00", "21:30", "14:00"]) {
        assert.throws(() => integration.weeklyToItems({...weekly,sunday:{...weekly.sunday,wakeup}}, "wake"), /1–16 hours/u);
    }
});
check("zero wind-down leaves every wind interval empty", () => {
    const zero = Object.fromEntries(Object.entries(weekly).map(([d,p]) => [d,{...p,wind_down_minutes:0}]));
    assert.ok(integration.days.every(day => integration.weeklyToItems(zero, "wake")[1][day].length === 0));
});
check("plan acknowledgement requires dates and coherent counters", () => {
    const plan = {weekly,bedtime:"2026-10-30T22:00:00-07:00",wakeup:"2026-10-31T06:00:00-07:00",
        night:"2026-10-30",delays_used:2,max_delays:6,delay_minutes:30,delays_remaining:4};
    assert.ok(integration.validPlan(plan));
    for (const changes of [{bedtime:"bad"},{night:null},{delays_remaining:5},{delay_minutes:0},{delay_minutes:121}]) {
        assert.ok(!integration.validPlan({...plan,...changes}));
    }
    assert.ok(integration.sameWeekly(plain(weekly),weekly));
    const edited = plain(weekly); edited.friday.wakeup = "07:00";
    assert.ok(!integration.sameWeekly(edited,weekly));
    assert.ok(!integration.sameWeekly(null,weekly));
});

check("disabled days and fully disabled plans roundtrip", () => {
    const partial = {...weekly, sunday:null, saturday:null};
    const [sleep] = integration.weeklyToItems(partial,"wake");
    const parsed = editor.readGroups(sleep);
    assert.equal(parsed.error, "");
    assert.deepEqual(plain(integration.groupsToWeekly(parsed.groups,30,"wake")),partial);
    const off = Object.fromEntries(integration.days.map(day=>[day,null]));
    const plan = {phase:"off",weekly:off,night:null,bedtime:null,wakeup:null,
        delays_used:0,delays_remaining:0,max_delays:6,delay_minutes:30};
    assert.ok(integration.validPlan(plan));
    assert.ok(integration.sameWeekly(off,plain(off)));
    assert.ok(!integration.sameWeekly(off,{}));
    assert.ok(!integration.validPlan({...plan,delays_used:1}));
    assert.ok(!integration.validPlan({...plan,weekly}));
    assert.ok(integration.days.every(day=>integration.weeklyToItems(off,"wake")[0][day].length===0));
});

console.log(`Sleep integration: ${count} cases passed`);
