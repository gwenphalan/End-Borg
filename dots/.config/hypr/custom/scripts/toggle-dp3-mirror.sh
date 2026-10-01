#!/usr/bin/env bash
# Toggle which monitor DP-3 mirrors, between MIRROR_A and MIRROR_B.

set -euo pipefail

TARGET="DP-3"
TARGET_MODE="1920x1080@60"
TARGET_POS="3840x0"
TARGET_SCALE="1"
MIRROR_A="HDMI-A-1"
MIRROR_B="DP-2"

monitors=$(hyprctl monitors all -j)

# mirrorOf is reported as a monitor *id*, so resolve it back to a name.
current_id=$(jq -r --arg t "$TARGET" '.[] | select(.name == $t) | .mirrorOf' <<<"$monitors")
if [[ "$current_id" == "none" || -z "$current_id" ]]; then
    current=""
else
    current=$(jq -r --arg id "$current_id" '.[] | select(.id == ($id | tonumber)) | .name' <<<"$monitors")
fi

if [[ "$current" == "$MIRROR_A" ]]; then
    next="$MIRROR_B"
else
    next="$MIRROR_A"
fi

if ! jq -e --arg n "$next" 'any(.[]; .name == $n)' <<<"$monitors" >/dev/null; then
    notify-send "Mirror toggle failed" "Output $next not connected" -a Hyprland
    exit 1
fi

# `hyprctl keyword` is rejected under the Lua config parser, so go through eval.
hyprctl eval "hl.monitor({output=\"$TARGET\", mode=\"$TARGET_MODE\", position=\"$TARGET_POS\", scale=$TARGET_SCALE, mirror=\"$next\"})"

# Follow the mirror with the pointer: same relative spot on the new source
# monitor, unless the pointer is already sitting on it. Empty output = no move.
newpos=$(jq -rn \
    --argjson mons "$monitors" \
    --argjson cur "$(hyprctl cursorpos -j)" \
    --arg a "$MIRROR_A" --arg b "$MIRROR_B" --arg next "$next" '
    # Logical extents: pixels over scale, with the axes swapped on 90/270 rotations.
    def rect: {
        name,
        x: .x, y: .y,
        w: ((if (.transform % 2) == 1 then .height else .width end) / .scale),
        h: ((if (.transform % 2) == 1 then .width  else .height end) / .scale)
    };
    def clamp($lo; $hi): if . < $lo then $lo elif . > $hi then $hi else . end;

    [$mons[] | select(.name == $a or .name == $b) | rect] as $rects
    | (first($rects[] | select(.name == $next))) as $to
    | (first($rects[] | select(
          $cur.x >= .x and $cur.x < .x + .w and
          $cur.y >= .y and $cur.y < .y + .h)) // null) as $from
    | if $from != null and $from.name == $next then empty
      else
        (if $from == null
         then {fx: 0.5, fy: 0.5}
         else {fx: (($cur.x - $from.x) / $from.w), fy: (($cur.y - $from.y) / $from.h)}
         end) as $f
        | "\(($to.x + $f.fx * $to.w) | floor | clamp($to.x; $to.x + $to.w - 1)) " +
          "\(($to.y + $f.fy * $to.h) | floor | clamp($to.y; $to.y + $to.h - 1))"
      end')

if [[ -n "$newpos" ]]; then
    read -r cx cy <<<"$newpos"
    hyprctl dispatch "hl.dsp.cursor.move({x=$cx, y=$cy})" >/dev/null
fi

# The notification daemon (quickshell) puts popups on Hyprland.focusedMonitor,
# so the popup lands on the new source only if focus is there too. With
# input:follow_mouse=1 the cursor move above already did it; this covers the
# case where it didn't. Refocusing warps the pointer to the focused window, so
# put it back where we left it.
if [[ "$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')" != "$next" ]]; then
    read -r kx ky < <(hyprctl cursorpos -j | jq -r '"\(.x) \(.y)"')
    hyprctl dispatch "hl.dsp.focus({monitor=\"$next\"})" >/dev/null
    hyprctl dispatch "hl.dsp.cursor.move({x=$kx, y=$ky})" >/dev/null
fi

# quickshell picks up focusedmon over IPC asynchronously; give it a beat so the
# popup isn't placed against the old focus.
sleep 0.15
notify-send "$TARGET mirroring $next" -a Hyprland -t 1500
