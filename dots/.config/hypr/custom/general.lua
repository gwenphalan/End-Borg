hl.config({
    general = {
        resize_on_border = false,
    },
    cursor = {
        no_warps = true,
        no_hardware_cursors = true,
    },
    render = {
        direct_scanout = false,
    }
})

hl.monitor({
    output = "DP-2",
    mode = "1920x1080@100",
    position = "0x0",
    scale = 1,
})

hl.monitor({
    output = "HDMI-A-1",
    mode = "1920x1080@60",
    position = "1920x0",
    scale = 1,
})
