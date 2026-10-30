.pragma library

function domain(entity) { return (entity?.entity_id || "").split(".")[0]; }
function name(entity) { return entity?.attributes?.friendly_name || entity?.entity_id || ""; }
function available(entity) { return entity && entity.state !== "unavailable" && (entity.state !== "unknown" || ["scene","button","input_button"].includes(domain(entity))); }
function areaFor(entity, registry, devices) {
    const entry = registry.find(r => r.entity_id === entity?.entity_id);
    return entry?.area_id || devices.find(d => d.id === entry?.device_id)?.area_id || "unassigned";
}
function icon(entity) {
    const icons = {light:"lightbulb", switch:"power_settings_new", input_boolean:"toggle_on", media_player:"speaker", climate:"thermostat", fan:"mode_fan", cover:"blinds", lock:"lock", automation:"auto_awesome", scene:"palette", script:"play_circle", button:"touch_app", input_button:"touch_app", sensor:"sensors", binary_sensor:"sensors", vacuum:"vacuum", select:"list", input_select:"list", number:"tune", input_number:"tune", alarm_control_panel:"security", humidifier:"humidity_percentage", water_heater:"water_heater"};
    return icons[domain(entity)] || "devices";
}
// Home Assistant uses MDI names; the shell renders Material Symbols.
// Never pass an external icon identifier directly to the icon font.
function roomIcon(icon) {
    const symbols = {
        "bed":"bed", "bed-double":"bed", "bed-king":"bed", "bed-queen":"bed",
        "sofa":"chair", "sofa-single":"chair", "television":"tv",
        "silverware-fork-knife":"restaurant", "silverware":"restaurant", "stove":"cooking",
        "countertop":"countertops", "fridge":"kitchen", "chef-hat":"cooking",
        "shower":"shower", "bathtub":"bathtub", "toilet":"wc",
        "desk":"desk", "desk-lamp":"desk", "desktop-classic":"computer",
        "garage":"garage", "car":"directions_car", "washing-machine":"local_laundry_service",
        "flower":"local_florist", "tree":"park", "grass":"yard", "pool":"pool",
        "baby-face":"child_care", "baby-carriage":"child_care",
        "door":"meeting_room", "door-open":"meeting_room", "home":"home", "stairs":"stairs"
    };
    const name=String(icon || "").replace(/^mdi:/, "").replace(/-outline$/, "");
    return symbols[name] || "meeting_room";
}
function status(entity, labels) {
    if (!entity) return "";
    const a = entity.attributes || {};
    let result = labels?.[entity.state] || entity.state.replace(/_/g, " ");
    if (a.unit_of_measurement) result += " " + a.unit_of_measurement;
    if (domain(entity) === "light" && entity.state === "on" && a.brightness !== undefined) result += " • " + Math.round(a.brightness / 255 * 100) + "%";
    if (domain(entity) === "climate" && a.current_temperature !== undefined) result += " • " + a.current_temperature + "°";
    return result;
}
function primaryAction(entity) {
    const d = domain(entity);
    if (["light", "switch", "input_boolean", "fan", "automation", "humidifier"].includes(d)) return {domain:d, service:entity.state === "on" ? "turn_off" : "turn_on"};
    if (["scene", "script"].includes(d)) return {domain:d, service:"turn_on"};
    if (["button", "input_button"].includes(d)) return {domain:d, service:"press"};
    if (d === "media_player") {
        const playing=entity.state === "playing";
        return hasFeature(entity,playing ? 1 : 16384) ? {domain:d,service:playing ? "media_pause" : "media_play"} : null;
    }
    return null;
}
function hasFeature(entity, flag) { return ((entity?.attributes?.supported_features || 0) & flag) !== 0; }
function rgbFromHue(hue) {
    const x = 255 * (1 - Math.abs((hue / 60) % 2 - 1));
    const c = [[255,x,0],[x,255,0],[0,255,x],[0,x,255],[x,0,255],[255,0,x]][Math.min(5,Math.floor(hue/60))];
    return c.map(Math.round);
}

function mediaPosition(entity, now) {
    const a = entity?.attributes || {};
    let position = Number(a.media_position) || 0;
    const updated = Date.parse(a.media_position_updated_at || "");
    if (entity?.state === "playing" && isFinite(updated)) position += Math.max(0,now - updated) / 1000;
    const duration = Number(a.media_duration);
    return Math.max(0,isFinite(duration) && duration > 0 ? Math.min(position,duration) : position);
}

function mediaTimelinePosition(timeline, now) {
    if (!timeline) return 0;
    const elapsed = timeline.state === "playing" ? Math.max(0, now - timeline.time) / 1000 : 0;
    const position = timeline.position + elapsed;
    return Math.max(0, timeline.duration > 0 ? Math.min(position, timeline.duration) : position);
}

function reconcileMediaTimeline(previous, entity, now) {
    const a = entity?.attributes || {};
    const duration = Number(a.media_duration) || 0;
    const key = [entity?.entity_id, a.media_content_id || a.media_title, a.media_artist, duration].join("|");
    const serverPosition = Number(a.media_position) || 0;
    const stamp = a.media_position_updated_at || "";
    let position = mediaPosition(entity, now);
    if (previous && previous.key === key) {
        const current = mediaTimelinePosition(previous, now);
        const updated = stamp !== previous.stamp || serverPosition !== previous.serverPosition;
        // HA can change playback state before publishing a new position timestamp.
        // Keep our clock frozen through that transition instead of replaying the old anchor.
        const transition = entity.state !== previous.state;
        const fresh = isFinite(Date.parse(stamp)) && Date.parse(stamp) >= previous.time;
        if (!updated || (transition && (!fresh || serverPosition === previous.serverPosition)) || Math.abs(position - current) <= 2)
            position = current;
    }
    if (!["playing", "paused", "buffering"].includes(entity?.state)) position = 0;
    return {key: key, state: entity?.state, position: position, time: now,
        duration: duration, serverPosition: serverPosition, stamp: stamp};
}

function hsvRgb(hue, saturation, value) {
    const h=((hue%360)+360)%360;
    const c=value*saturation;
    const x=c*(1-Math.abs((h/60)%2-1));
    const m=value-c;
    return [[c,x,0],[x,c,0],[0,c,x],[0,x,c],[x,0,c],[c,0,x]][Math.floor(h/60)].map(v => Math.round((v+m)*255));
}
function temperatureRgb(kelvin) {
    const t=Math.max(1000,Math.min(40000,kelvin))/100;
    return [t<=66 ? 255 : 329.698727446*Math.pow(t-60,-.1332047592),t<=66 ? 99.4708025861*Math.log(t)-161.1195681661 : 288.1221695283*Math.pow(t-60,-.0755148492),t>=66 ? 255 : t<=19 ? 0 : 138.5177312231*Math.log(t-10)-305.0447927307].map(v => Math.round(Math.max(0,Math.min(255,v))));
}
function lightColorRgb(color, attributes) {
    if (color.color_temp_kelvin) return temperatureRgb(color.color_temp_kelvin);
    if (color.hs_color) return hsvRgb(color.hs_color[0],color.hs_color[1]/100,1);
    if (color.rgb_color) return color.rgb_color.slice(0,3);
    const channels=color.rgbw_color || color.rgbww_color;
    if (!channels) return [255,255,255];
    let white=[channels[3],channels[3],channels[3]];
    if (color.rgbww_color) {
        const a=attributes || {};
        const ratio=channels[3]+channels[4] ? channels[4]/(channels[3]+channels[4]) : .5;
        const mired=1/(a.max_color_temp_kelvin || 6500)+ratio*(1/(a.min_color_temp_kelvin || 2700)-1/(a.max_color_temp_kelvin || 6500));
        white=temperatureRgb(1/mired).map(v => v*Math.max(channels[3],channels[4])/255);
    }
    const rgb=channels.slice(0,3).map((v,i) => v+white[i]);
    const peak=Math.max(...rgb);
    return rgb.map(v => peak ? Math.round(v*Math.max(...channels)/peak) : 0);
}
function validFavorite(color) {
    if (!color || typeof color!=="object") return false;
    if (Number.isFinite(color.color_temp_kelvin) && color.color_temp_kelvin>0) return true;
    for (const [key,size,max] of [["rgb_color",3,255],["rgbw_color",4,255],["rgbww_color",5,255],["hs_color",2,360]])
        if (Array.isArray(color[key]) && color[key].length===size && color[key].every(v => Number.isFinite(v) && v>=0 && v<=max) && (key!=="hs_color" || color[key][1]<=100)) return true;
    return false;
}
function favoriteColors(entity, registry) {
    if (!entity) return [];
    const stored=registry.find(r => r.entity_id===entity.entity_id)?.options?.light?.favorite_colors;
    if (Array.isArray(stored)) return stored.filter(validFavorite);
    const a=entity.attributes || {};
    const modes=a.supported_color_modes || [];
    const hasRgb=modes.some(m => ["hs","xy","rgb","rgbw","rgbww"].includes(m));
    const hasTemperature=modes.includes("color_temp");
    const colors=[];
    if (hasRgb || hasTemperature) {
        const min=hasTemperature ? a.min_color_temp_kelvin || 2000 : 2000;
        const max=hasTemperature ? a.max_color_temp_kelvin || 6500 : 6500;
        for (let i=0;i<4;i++) { const k=Math.round(min+(max-min)*i/3); colors.push(hasTemperature ? {color_temp_kelvin:k} : {rgb_color:temperatureRgb(k)}); }
    }
    if (hasRgb) for (const rgb of [[127,172,255],[215,150,255],[255,158,243],[255,110,84]]) colors.push({rgb_color:rgb});
    return colors;
}

function mergeStates(snapshot,updates) {
    const states={};
    for (const entity of snapshot) if (entity?.entity_id) states[entity.entity_id]=entity;
    for (const id of Object.keys(updates)) {
        if (updates[id]) states[id]=updates[id]; else delete states[id];
    }
    return states;
}
