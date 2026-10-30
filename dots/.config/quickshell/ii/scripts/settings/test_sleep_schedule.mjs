import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(
    new URL("../../modules/settings/sleep_schedule.js", import.meta.url), "utf8"
).replace(/^\.pragma library\s*/u, "");
const schedule = vm.createContext({});
vm.runInContext(source, schedule);

const sleep = {
    id: "sleep_schedule", name: "Sleep", icon: "mdi:bed",
    monday: [{from: "00:00:00", to: "06:00:00"}],
    tuesday: [{from: "01:00:00", to: "09:00:00"}, {from: "22:00:00", to: "23:59:00"}],
    wednesday: [{from: "00:00:00", to: "06:00:00"}, {from: "22:00:00", to: "23:59:00"}],
    thursday: [{from: "00:00:00", to: "06:00:00"}],
    friday: [{from: "02:30:00", to: "10:30:00"}],
    saturday: [{from: "02:30:00", to: "10:30:00"}],
    sunday: [{from: "02:30:00", to: "10:30:00"}, {from: "22:00:00", to: "23:59:00"}],
};
const wind = {id: "wind_down", name: "Wind Down", icon: "mdi:bed-clock"};
const expected = [
    {bed: 1320, wake: 360, days: [1, 3, 4]},
    {bed: 60, wake: 540, days: [2]},
    {bed: 150, wake: 630, days: [0, 5, 6]},
];
const parsed = schedule.readGroups(sleep);
assert.equal(parsed.error, "");
assert.equal(JSON.stringify(parsed.groups), JSON.stringify(expected));

const generated = schedule.buildItems(parsed.groups, 30, sleep, wind);
assert.equal(generated.error, "");
assert.equal(JSON.stringify(schedule.readGroups(generated.sleep).groups), JSON.stringify(expected));
assert.deepEqual(JSON.parse(JSON.stringify(generated.wind.tuesday)), [
    {from: "00:30:00", to: "01:00:00"},
    {from: "21:30:00", to: "22:00:00"},
]);

const duplicate = schedule.buildItems(
    [...parsed.groups, {bed: 1200, wake: 420, days: [2]}], 30, sleep, wind
);
assert.match(duplicate.error, /only one schedule/u);

const sundayWake = schedule.buildItems(
    [{bed: 1380, wake: 420, days: [0]}], 60, sleep, wind
);
assert.equal(sundayWake.error, "");
assert.equal(sundayWake.sleep.saturday[0].to, "24:00:00");
assert.equal(sundayWake.sleep.sunday[0].from, "00:00:00");

const noWind = schedule.buildItems(parsed.groups, 0, sleep, wind);
assert.equal(noWind.error, "");
assert.ok(schedule.days.every(day => noWind.wind[day].length === 0));

console.log("Sleep schedule conversion: 5 cases passed");
