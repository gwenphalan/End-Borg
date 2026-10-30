.pragma library

// Presentation is semantic: storage range alone does not decide whether a slider is useful.
var percentFractions = [
    "appearance.transparency.backgroundTransparency", "appearance.transparency.contentTransparency",
    "appearance.wallpaperTheming.terminalGenerationProps.harmony", "appearance.wallpaperTheming.terminalGenerationProps.termFgBoost",
    "overlay.clickthroughOpacity", "overview.scale", "regionSelector.targetRegions.opacity", "regionSelector.targetRegions.contentRegionOpacity"
];
var percentageThresholds = [
    "audio.protection.maxAllowedIncrease", "audio.protection.maxAllowed",
    "bar.resources.memoryWarningThreshold", "bar.resources.swapWarningThreshold", "bar.resources.cpuWarningThreshold",
    "battery.low", "battery.critical", "battery.full", "battery.suspend"
];
var pixelValues = [
    "dock.height", "dock.hoverRegionHeight", "bar.autoHide.hoverRegionWidth",
    "sidebar.cornerOpen.cornerRegionWidth", "sidebar.cornerOpen.cornerRegionHeight", "sidebar.cornerOpen.clicklessCornerVerticalOffset",
    "regionSelector.targetRegions.selectionPadding", "regionSelector.circle.strokeWidth", "regionSelector.circle.padding",
    "lock.blur.radius", "cheatsheet.fontSize.key", "cheatsheet.fontSize.comment", "background.widgets.clock.digital.font.size",
    "background.widgets.clock.x", "background.widgets.clock.y", "background.widgets.weather.x", "background.widgets.weather.y"
];
var scaleValues = ["background.parallax.workspaceZoom", "background.parallax.widgetsFactor", "lock.blur.extraZoom", "overlay.floatingImage.scale"];
var fontAxes = ["background.widgets.clock.digital.font.weight", "background.widgets.clock.digital.font.width", "background.widgets.clock.digital.font.roundness"];
function numeric(setting) {
    const p = setting.path;
    const result = Object.assign({}, setting, {
        control: "number", displayScale: 1, displayUnit: setting.unit === "seconds" ? "s" : setting.unit === "minutes" ? "min" : setting.unit || "",
        sliderStep: setting.type === "int" ? 1 : 0,
        displayIntegral: setting.type === "int"
    });
    if (percentFractions.includes(p)) Object.assign(result, {control:"slider", displayScale:100, displayUnit:"%", step:.01, sliderStep:0, displayIntegral:true});
    if (percentageThresholds.includes(p)) Object.assign(result, {control:"slider", displayUnit:"%", step:1, sliderStep:1, displayIntegral:true});
    if (pixelValues.includes(p)) Object.assign(result, {displayUnit:"px", step:1, displayIntegral:true});
    if (scaleValues.includes(p)) Object.assign(result, {displayUnit:"×", step:.01});
    if (fontAxes.includes(p)) Object.assign(result, {control:"slider", sliderStep:0});
    if (p === "background.widgets.clock.digital.font.size") Object.assign(result, {control:"slider", step:1, sliderStep:1, unboundedSlider:true, fontSizeSteps:true});
    if (p === "light.night.colorTemperature") Object.assign(result, {control:"slider", displayUnit:"K", sliderStep:100});
    if (p === "appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold") Object.assign(result, {control:"slider", sliderStep:0});
    if (p === "battery.full") result.max = 100; // 101 is presented as Off by the owning row.
    if (p.startsWith("time.pomodoro.") && p !== "time.pomodoro.cyclesBeforeLongBreak") Object.assign(result, {displayScale:1/60, displayUnit:"min", step:60, displayIntegral:false});
    if (p === "notifications.timeout" || p === "osd.timeout") Object.assign(result, {displayScale:1/1000, displayUnit:"s", step:100, displayIntegral:false});
    if (p === "borgIntelligence.timeoutSeconds") result.displayUnit = "s";
    return result;
}
function searchable(setting, choices) {
    return setting.dynamicChoices === "language" || choices.length > 12;
}

// A stable editor-style range: larger clocks remain available through exact entry.
function fontSizes(current) {
    return [8,9,10,11,12,14,16,18,20,22,24,26,28,36,48,72,96,120,144,192,240];
}
function nearestFontSizeIndex(current,sizes) {
    return sizes.reduce((best,size,index) => Math.abs(size-current)<Math.abs(sizes[best]-current) ? index : best,0);
}
