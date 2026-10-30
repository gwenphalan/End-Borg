.pragma library

function normalized(entries, count) {
    return (Array.isArray(entries) ? entries : []).filter(entry => entry && Number.isInteger(entry.curve) && entry.curve >= 0 && entry.curve < count && ["error","warning","ignored"].includes(entry.status) && typeof entry.message === "string" && entry.message.trim()).map(entry => Object.assign({},entry));
}
function forCurve(entries,index) {
    return entries.filter(entry=>entry.curve===index);
}
function description(entries,index) {
    const messages=forCurve(entries,index).map(entry=> {
        let detail=entry.message;
        if(Number.isFinite(entry.rms)) {
            detail+=" ("+entry.rms.toFixed(2)+" px RMS";
            if(Number.isFinite(entry.othersRms)) detail+="; other traces "+entry.othersRms.toFixed(2)+" px";
            detail+=")";
        }
        return detail;
    });
    return messages.length ? "Trace "+(index+1)+": "+messages.join(" · ") : "";
}
function summary(entries) {
    return [...new Set(entries.map(entry=>entry.curve))].map(index=>description(entries,index)).join("\n");
}
