#!/usr/bin/env bash
set -euo pipefail

if pidof hyprlock >/dev/null 2>&1; then
    exit 0
fi

# Preserve the end-4 theme rather than regenerating it on each lock.
exec hyprlock --config "$HOME/.config/hypr/hyprlock.conf" "$@"
