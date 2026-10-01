#!/usr/bin/env bash
# Toggle Bed Mode: Swap stereo channels of the audio output (Left <-> Right)
# for when facing the bed TV opposite the desk monitors.

set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
ORIG_SINK_FILE="$STATE_DIR/bed_mode_orig_sink"
SINK_NAME="reverse-stereo"

is_active() {
    local cur_sink
    cur_sink=$(pactl get-default-sink 2>/dev/null || echo "")
    if [[ "$cur_sink" == "$SINK_NAME" ]]; then
        return 0
    fi
    if pactl list sinks short 2>/dev/null | awk '{print $2}' | grep -qx "$SINK_NAME"; then
        return 0
    fi
    return 1
}

unload_existing_modules() {
    local mods
    mods=$(pactl list modules short 2>/dev/null | awk '/module-remap-sink.*reverse-stereo/ {print $1}')
    if [[ -n "$mods" ]]; then
        for mod in $mods; do
            pactl unload-module "$mod" 2>/dev/null || true
        done
    fi
}

enable_bed_mode() {
    local orig_sink
    orig_sink=$(pactl get-default-sink 2>/dev/null || echo "")

    if [[ "$orig_sink" == "$SINK_NAME" ]]; then
        exit 0
    fi

    if [[ -n "$orig_sink" ]]; then
        echo "$orig_sink" > "$ORIG_SINK_FILE"
    fi

    unload_existing_modules

    # Load reverse-stereo module mapping FL->FR and FR->FL
    local master_target="${orig_sink:-@DEFAULT_SINK@}"
    pactl load-module module-remap-sink \
        sink_name="$SINK_NAME" \
        sink_properties=device.description="Bed\ Mode\ (Reversed\ Stereo)" \
        master="$master_target" \
        channels=2 \
        master_channel_map=front-right,front-left \
        channel_map=front-left,front-right \
        remix=no >/dev/null

    pactl set-default-sink "$SINK_NAME"

    notify-send "Bed Mode Enabled" "Audio channels reversed (L ⟷ R)" -a "Bed Mode" -i audio-speakers -t 2000 2>/dev/null || true
}

disable_bed_mode() {
    local restore_sink=""

    if [[ -f "$ORIG_SINK_FILE" ]]; then
        local saved_sink
        saved_sink=$(cat "$ORIG_SINK_FILE" 2>/dev/null || echo "")
        if [[ -n "$saved_sink" ]] && pactl list sinks short 2>/dev/null | awk '{print $2}' | grep -qx "$saved_sink"; then
            restore_sink="$saved_sink"
        fi
    fi

    if [[ -z "$restore_sink" ]]; then
        restore_sink=$(pactl list sinks short 2>/dev/null | awk '{print $2}' | grep -v "^$SINK_NAME$" | head -n 1)
    fi

    if [[ -n "$restore_sink" ]]; then
        pactl set-default-sink "$restore_sink" 2>/dev/null || true
    fi

    unload_existing_modules

    rm -f "$ORIG_SINK_FILE"

    notify-send "Bed Mode Disabled" "Audio channels restored to normal" -a "Bed Mode" -i audio-speakers -t 2000 2>/dev/null || true
}

action="${1:-toggle}"

case "$action" in
    on|enable)
        enable_bed_mode
        ;;
    off|disable)
        disable_bed_mode
        ;;
    status)
        if is_active; then
            echo "enabled"
            exit 0
        else
            echo "disabled"
            exit 1
        fi
        ;;
    toggle)
        if is_active; then
            disable_bed_mode
        else
            enable_bed_mode
        fi
        ;;
    *)
        echo "Usage: $0 {on|off|toggle|status}" >&2
        exit 1
        ;;
esac
