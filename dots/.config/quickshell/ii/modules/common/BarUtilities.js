.pragma library

// Shared by the bar and its settings preview. Keys are existing enable flags.
var definitions = [
    {key:"showScreenSnip", name:"Screenshot", icon:"screenshot_region"},
    {key:"showScreenRecord", name:"Screen recording", icon:"videocam"},
    {key:"showColorPicker", name:"Color picker", icon:"colorize"},
    {key:"showBedModeToggle", name:"Bed mode", icon:"bed"},
    {key:"showKeyboardToggle", name:"Keyboard", icon:"keyboard"},
    {key:"showMicToggle", name:"Microphone", icon:"mic"},
    {key:"showDarkModeToggle", name:"Theme", icon:"dark_mode"},
    {key:"showPerformanceProfileToggle", name:"Power profile", icon:"battery_charging_full"}
];

function ordered(order) {
    const known=definitions.map(item => item.key);
    const result=[];
    for (const key of order || []) if (known.includes(key) && !result.includes(key)) result.push(key);
    return result.concat(known.filter(key => !result.includes(key)));
}
function item(key) { return definitions.find(item => item.key===key); }
