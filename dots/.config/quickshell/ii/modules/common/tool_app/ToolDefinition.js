.pragma library

function copy(value) { return JSON.parse(JSON.stringify(value)); }
function evaluate(condition, state) {
    if (typeof condition === "boolean") return condition;
    if (typeof condition === "string") return Object.prototype.hasOwnProperty.call(state, condition) && !!state[condition];
    if (!condition || typeof condition !== "object") return false;
    if (condition.all) return condition.all.every(c => evaluate(c, state));
    if (condition.any) return condition.any.some(c => evaluate(c, state));
    if (Object.prototype.hasOwnProperty.call(condition, "not")) return !evaluate(condition.not, state);
    if (condition.eq) return Object.prototype.hasOwnProperty.call(state, condition.eq[0]) && JSON.stringify(state[condition.eq[0]]) === JSON.stringify(condition.eq[1]);
    return false;
}
function action(definition, id) { return definition && definition.actions ? definition.actions[id] : undefined; }
function validateSetting(setting, value) {
    if (setting.type === "bool" && typeof value !== "boolean") return "Expected a boolean";
    if ((setting.type === "string" || setting.type === "label") && typeof value !== "string") return "Expected text";
    if (setting.type === "int" || setting.type === "real") {
        if (typeof value !== "number" || !Number.isFinite(value) || (setting.type === "int" && !Number.isInteger(value))) return "Expected a finite " + setting.type;
        if (setting.min !== undefined && value < setting.min) return "Minimum: " + setting.min;
        if (setting.max !== undefined && value > setting.max) return "Maximum: " + setting.max;
    }
    if (setting.choices && !setting.choices.some(c => JSON.stringify(c.value) === JSON.stringify(value))) return "Choose an available value";
    return "";
}
function fields(definition) {
    const result = {};
    for (const group of (definition.settings || {}).groups || [])
        for (const item of group.items) if (item.kind === "field") result[item.setting.path] = item.setting;
    return result;
}
function flattenToolbar(groups) {
    const items = [];
    let previousGroup = false;
    for (const group of groups || []) {
        if (group.stretch) { items.push({stretch:true}); previousGroup=false; continue; }
        if (!group.actions.length) continue;
        if (previousGroup) items.push({separator:true});
        for (const id of group.actions) items.push({action:id});
        previousGroup=true;
    }
    return items;
}
