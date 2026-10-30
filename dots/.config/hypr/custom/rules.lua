hl.window_rule({
    match = { class = "^(org.gnome.Calculator)$" },
    float = true,
    size = { 400, 550 },
    center = true
})

hl.window_rule({
    match = {
        class = "^(blender)$",
        title = "^(File Browser|Blender File View)$"
    },
    float = true,
    size = { "(monitor_w*0.65)", "(monitor_h*0.65)" },
    center = true
})

-- Switcheroo (io.gitlab.adhami3310.Converter)
hl.window_rule({
    match = { class = "^(io\\.gitlab\\.adhami3310\\.Converter)$" },
    float = true,
    size = { 800, 650 },
    center = true
})

-- HandBrake (fr.handbrake.ghb or ghb)
hl.window_rule({
    match = { class = "^(fr\\.handbrake\\.ghb)$" },
    float = true,
    size = { 1050, 720 },
    center = true
})

hl.window_rule({
    match = { class = "^(ghb)$" },
    float = true,
    size = { 1050, 720 },
    center = true
})

-- Fit the complete Settings sidebar without extra vertical space.
hl.window_rule({
    match = { class = "^org\\.quickshell$", title = "^Settings$" },
    float = true,
    size = { 1080, 874 },
    center = true
})

-- Lens Cap's native Files picker; ordinary Files windows remain tiled.
hl.window_rule({
    match = {
        class = "^org\\.gnome\\.Nautilus$",
        title = "^Lens Cap - (Open|Save)$"
    },
    float = true,
    size = { "(monitor_w*0.60)", "(monitor_h*0.70)" },
    center = true
})

-- Gradia's GTK color chooser is a separate dialog.
hl.window_rule({
    match = { class = "^gradia$", title = "^Choose Color$" },
    float = true,
    size = { 440, 360 },
    center = true
})
