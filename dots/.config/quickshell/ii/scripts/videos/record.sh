#!/usr/bin/env bash

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"

CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)

RECORDING_DIR=""

if [[ -n "$CUSTOM_PATH" && "$CUSTOM_PATH" != "null" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos"
fi

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}

getaudiooutput() {
    local default_sink
    default_sink="$(pactl get-default-sink 2>/dev/null)"
    if [[ -n "$default_sink" ]]; then
        echo "${default_sink}.monitor"
    else
        pactl list sources 2>/dev/null | grep 'Name' | grep 'monitor' | head -n 1 | cut -d ' ' -f2
    fi
}

getactivemonitor() {
    local mon
    mon=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name' 2>/dev/null)
    if [[ -z "$mon" || "$mon" == "null" ]]; then
        mon=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name' 2>/dev/null)
    fi
    echo "${mon:-HDMI-A-1}"
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0
ACTION=""

for ((i=0;i<${#ARGS[@]};i++)); do
    case "${ARGS[i]}" in
        --region)
            if (( i+1 < ${#ARGS[@]} )); then
                MANUAL_REGION="${ARGS[i+1]}"
                ((i++))
            else
                notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
                exit 1
            fi
            ;;
        --sound)
            SOUND_FLAG=1
            ;;
        --fullscreen)
            FULLSCREEN_FLAG=1
            ;;
        --stop)
            ACTION="stop"
            ;;
        --pause)
            ACTION="pause"
            ;;
        --resume)
            ACTION="resume"
            ;;
        --toggle-pause)
            ACTION="toggle-pause"
            ;;
        --status)
            ACTION="status"
            ;;
    esac
done

is_wf_running() {
    pgrep -x wf-recorder >/dev/null 2>&1
}

# Check if currently paused (SIGSTOP puts process into 'T' state)
is_wf_paused() {
    local state
    state=$(ps -o state= -C wf-recorder 2>/dev/null | head -n 1)
    [[ "$state" == *T* ]]
}

if [[ "$ACTION" == "status" ]]; then
    if is_wf_running; then
        if is_wf_paused; then
            echo "paused"
        else
            echo "recording"
        fi
    else
        echo "stopped"
    fi
    exit 0
fi

if [[ "$ACTION" == "pause" ]]; then
    if is_wf_running; then
        pkill -STOP -x wf-recorder 2>/dev/null
        notify-send "Recording Paused" "Screen recording paused" -a 'Recorder' -i media-playback-pause & disown
        qs -c ii ipc call recording notifyPaused 2>/dev/null || true
    fi
    exit 0
fi

if [[ "$ACTION" == "resume" ]]; then
    if is_wf_running; then
        pkill -CONT -x wf-recorder 2>/dev/null
        notify-send "Recording Resumed" "Screen recording resumed" -a 'Recorder' -i media-playback-start & disown
        qs -c ii ipc call recording notifyResumed 2>/dev/null || true
    fi
    exit 0
fi

if [[ "$ACTION" == "toggle-pause" ]]; then
    if is_wf_running; then
        if is_wf_paused; then
            pkill -CONT -x wf-recorder 2>/dev/null
            notify-send "Recording Resumed" "Screen recording resumed" -a 'Recorder' -i media-playback-start & disown
            qs -c ii ipc call recording notifyResumed 2>/dev/null || true
        else
            pkill -STOP -x wf-recorder 2>/dev/null
            notify-send "Recording Paused" "Screen recording paused" -a 'Recorder' -i media-playback-pause & disown
            qs -c ii ipc call recording notifyPaused 2>/dev/null || true
        fi
    fi
    exit 0
fi

if [[ "$ACTION" == "stop" ]] || is_wf_running; then
    # Stop recording gracefully: ensure it is resumed first if paused, then send SIGINT
    pkill -CONT -x wf-recorder 2>/dev/null
    pkill -INT -x wf-recorder 2>/dev/null
    notify-send "Recording Stopped" "Saving and finalizing..." -a 'Recorder' -i media-playback-stop & disown
    qs -c ii ipc call recording notifyStopped 2>/dev/null || true
    exit 0
fi

# Starting new recording
TIMESTAMP=$(getdate)
FILENAME="recording_${TIMESTAMP}.mp4"
RAW_FILE="${RECORDING_DIR}/.raw_${FILENAME}"
FINAL_FILE="${RECORDING_DIR}/${FILENAME}"

WF_ARGS=()

if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
    WF_ARGS+=(-o "$(getactivemonitor)")
else
    if [[ -n "$MANUAL_REGION" ]]; then
        region="$MANUAL_REGION"
    else
        if ! region="$(slurp 2>&1)"; then
            notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
            qs -c ii ipc call recording notifyCancelled 2>/dev/null || true
            exit 1
        fi
    fi

    # Normalize geometry to even width and height for H.264 macroblock compatibility
    if [[ "$region" =~ ^([0-9]+),([0-9]+)[[:space:]]+([0-9]+)x([0-9]+)$ ]]; then
        rx="${BASH_REMATCH[1]}"
        ry="${BASH_REMATCH[2]}"
        rw="${BASH_REMATCH[3]}"
        rh="${BASH_REMATCH[4]}"
        (( rw % 2 != 0 )) && (( rw-- ))
        (( rh % 2 != 0 )) && (( rh-- ))
        region="${rx},${ry} ${rw}x${rh}"
    fi

    WF_ARGS+=(--geometry "$region")
fi

if [[ $SOUND_FLAG -eq 1 ]]; then
    AUDIO_DEV=$(getaudiooutput)
    if [[ -n "$AUDIO_DEV" ]]; then
        WF_ARGS+=(--audio="$AUDIO_DEV" -C aac -P b=160k)
    fi
fi

# Universal playback parameters (H.264 Constrained Baseline / Level 4.1, 60 fps, yuv420p)
WF_ARGS+=(
    -r 60
    -c libx264
    -p preset=veryfast
    -p crf=22
    -p level=4.1
    --pixel-format yuv420p
    -f "$RAW_FILE"
)

notify-send "Starting recording" "$FILENAME" -a 'Recorder' -i media-record & disown
qs -c ii ipc call recording notifyStarted 2>/dev/null || true

# Run wf-recorder
wf-recorder "${WF_ARGS[@]}"
WF_EXIT=$?

# Remux to move moov atom to beginning (+faststart) for instant Discord, Proton Drive, and mobile streaming
if [[ -f "$RAW_FILE" ]]; then
    if ffmpeg -y -i "$RAW_FILE" -c copy -movflags +faststart "$FINAL_FILE" >/dev/null 2>&1; then
        rm -f "$RAW_FILE"
    else
        mv -f "$RAW_FILE" "$FINAL_FILE"
    fi
    notify-send "Recording Saved" "$FILENAME" -a 'Recorder' -i video-x-generic & disown
fi

qs -c ii ipc call recording notifyStopped 2>/dev/null || true
