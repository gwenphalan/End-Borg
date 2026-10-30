#!/usr/bin/env bash
set -euo pipefail

screenshot_path=$1
action=$(notify-send -a Screenshot -i "$screenshot_path" -t 15000 \
    -A 'default=Edit Screenshot' \
    'Screenshot saved and copied' 'Click to edit in Gradia')

if [[ $action == default ]]; then
    exec gradia "$screenshot_path"
fi
