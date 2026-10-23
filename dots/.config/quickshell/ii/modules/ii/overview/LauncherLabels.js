.pragma library

function candidate(entry, labels) {
    const id = String(entry.id || "").replace(/\.desktop$/i, "").toLowerCase();
    const aliases = {
        "cmake-gui": "CMake",
        "a game about digging a hole": "Digging a Hole",
        "appimagelaunchersettings": "AppImage Settings",
        "nm-connection-editor": "Network Connections",
        "blueman-adapters": "Bluetooth Adapters",
        "blueman-manager": "Bluetooth Manager",
        "org.gnome.fileroller": "Archive Manager"
    };
    const cached = labels && (labels[String(entry.id || "")] || labels[String(entry.id || "").replace(/\.desktop$/i, "")]);
    return aliases[id] || (cached && cached.name === entry.name ? cached.label : "")
        || String(entry.name || "").replace(/[™®]/g, "").trim();
}

function displayName(entry, entries, labels) {
    const name = candidate(entry, labels);
    const collision = entries.some(other => other.id !== entry.id
        && candidate(other, labels).toLocaleLowerCase() === name.toLocaleLowerCase());
    return collision ? entry.name || "" : name;
}
