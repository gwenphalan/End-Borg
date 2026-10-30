.pragma library

// Adapt the consolidated Sleep contract to the existing wake-day editor.
var days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
function minutes(value) {
    const match = String(value || "").match(/^([01]\d|2[0-3]):([0-5]\d)$/);
    if (!match) throw new Error("Sleep time must be HH:MM.");
    return Number(match[1]) * 60 + Number(match[2]);
}
function clock(value) {
    const n = ((value % 1440) + 1440) % 1440;
    return String(Math.floor(n / 60)).padStart(2,"0") + ":" + String(n % 60).padStart(2,"0");
}
function append(item, from, to) {
    while (from < to) {
        const cycle = ((from % 10080) + 10080) % 10080;
        const index = Math.floor(cycle / 1440), minute = cycle % 1440;
        const end = Math.min(to, from + 1440 - minute);
        const last = minute + end - from;
        item[days[index]].push({from:clock(minute)+":00",to:last===1440?"24:00:00":clock(last)+":00"});
        from = end;
    }
}
function weeklyToItems(weekly, dayBasis) {
    const sleep = {id:"sleep_schedule",name:"Sleep",icon:"mdi:bed"};
    const wind = {id:"wind_down",name:"Wind Down",icon:"mdi:bed-clock"};
    for (const day of days) {sleep[day]=[];wind[day]=[];}
    for (let index=0; index<7; index++) {
        const row=weekly?.[days[index]];
        if (!Object.prototype.hasOwnProperty.call(weekly || {},days[index])) throw Error("The Sleep plan is missing a weekday.");
        if (row===null) continue;
        const bed=minutes(row.bedtime),wake=minutes(row.wakeup),duration=(wake-bed+1440)%1440;
        if (duration<60 || duration>960) throw Error("A sleep period must last 1–16 hours.");
        let start=index*1440+bed;
        if (dayBasis==="wake" && wake<=bed) start-=1440;
        append(sleep,start,start+duration);
        if (row.wind_down_minutes>0) append(wind,start-row.wind_down_minutes,start);
    }
    for (const item of [sleep,wind]) for(const day of days) item[day].sort((a,b)=>a.from.localeCompare(b.from));
    return [sleep,wind];
}
function groupsToWeekly(groups, windMinutes, dayBasis) {
    const weekly={};
    for(const day of days) weekly[day]=null;
    for(const group of groups) for(const wakeDay of group.days) {
        const overnight=group.wake<=group.bed;
        const index=dayBasis==="wake"?wakeDay:overnight?(wakeDay+6)%7:wakeDay;
        const key=days[index];
        if(weekly[key]!==null) throw Error("This plan has two bedtime periods on "+key+". Sleep cannot represent it with bedtime-day rows.");
        weekly[key]={bedtime:clock(group.bed),wakeup:clock(group.wake),wind_down_minutes:windMinutes};
    }
    return weekly;
}
function sameWeekly(actual,wanted) {
    return !!actual && !!wanted && days.every(day=>Object.prototype.hasOwnProperty.call(actual,day)
        && Object.prototype.hasOwnProperty.call(wanted,day) && (actual[day]===null || wanted[day]===null
            ?actual[day]===wanted[day]
            :actual[day] && wanted[day] && actual[day].bedtime===wanted[day].bedtime
                && actual[day].wakeup===wanted[day].wakeup && actual[day].wind_down_minutes===wanted[day].wind_down_minutes));
}
function validPlan(plan) {
    if(!plan || !plan.weekly || !days.every(day=>Object.prototype.hasOwnProperty.call(plan.weekly,day))
            || !Number.isInteger(plan.delays_used) || !Number.isInteger(plan.max_delays)
            || plan.max_delays<0 || plan.max_delays>10
            || !Number.isInteger(plan.delay_minutes) || plan.delay_minutes<1 || plan.delay_minutes>120) return false;
    if(plan.phase==="off") return days.every(day=>plan.weekly[day]===null)
        && plan.night===null && plan.bedtime===null && plan.wakeup===null
        && plan.delays_used===0 && plan.delays_remaining===0;
    return Number.isFinite(Date.parse(plan.bedtime)) && Number.isFinite(Date.parse(plan.wakeup))
        && typeof plan.night==="string" && plan.delays_used>=0 && plan.delays_used<=10
        && plan.delays_remaining===Math.max(0,plan.max_delays-plan.delays_used);
}
