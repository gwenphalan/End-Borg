.pragma library

function nextMode(mode) {
    const modes = ["apps", "overview", "clipboard"];
    return modes[(modes.indexOf(mode) + 1) % modes.length];
}

function advance(index, count, reverse) {
    return count ? (Math.max(0, index) + (reverse ? count - 1 : 1)) % count : -1;
}

function windowOrder(windows) {
    return windows.filter(window => window.mapped !== false && !window.hidden
        && window.workspace?.id >= 1 && window.workspace.id <= 100)
        .slice().sort((a, b) => (a.focusHistoryID ?? 99999) - (b.focusHistoryID ?? 99999)
            || a.address.localeCompare(b.address)).map(window => window.address);
}

function letter(name) {
    const value = name.trim().charAt(0).toLocaleUpperCase();
    return /^[A-Z]$/.test(value) ? value : "#";
}
