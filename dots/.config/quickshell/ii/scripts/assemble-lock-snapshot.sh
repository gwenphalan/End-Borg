#!/usr/bin/env bash
set -euo pipefail

output_dir="${1:?snapshot directory required}"
[[ -d "$output_dir" ]] || exit 1

# Qt's asynchronous grabs need a moment to finish writing both layers.
for attempt in {1..30}; do
    backgrounds=("$output_dir"/*-background.png)
    ready=false
    for background in "${backgrounds[@]}"; do
        [[ -f "$background" ]] || continue
        surface="${background%-background.png}-surface.png"
        if [[ -f "$surface" ]]; then
            ready=true
            break
        fi
    done
    [[ "$ready" == true ]] && break
    sleep 0.2
done

# Other monitors may complete their Qt grabs a little later.
sleep 0.5

assembled=false
for background in "$output_dir"/*-background.png; do
    [[ -f "$background" ]] || continue
    surface="${background%-background.png}-surface.png"
    [[ -f "$surface" ]] || continue
    final="${background%-background.png}.png"
    magick "$background" "$surface" -compose over -composite "$final"
    assembled=true
done

if [[ "$assembled" == true ]]; then
    state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
    rm -f -- "$state_dir/lock-snapshot-next"
else
    printf 'Capture failed: check the Quickshell log for Lock snapshot warnings.\n' > "$output_dir/capture-failed.txt"
fi
