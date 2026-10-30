#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
marker="$state_dir/lock-snapshot-next"
[[ -f "$marker" ]] || exit 0

umask 077
output_dir="$HOME/Pictures/lock-snapshot-$(date '+%Y-%m-%d_%H-%M-%S')"
mkdir -m 700 -p -- "$output_dir"
printf '%s\n' "$output_dir"
