#!/usr/bin/env bash
set -euo pipefail

settings_file="$HOME/.config/illogical-impulse/config.json"
if pidof hyprlock >/dev/null 2>&1; then
    exit 0
fi

# Persist the latest subscribed bedtime state before either lock backend.
# The cache remains usable when the keyring cannot be read during a lock.
timeout 1s quickshell -c ii ipc call homeAssistant cacheBedtime >/dev/null 2>&1 || true

try_quickshell_lock() {
    timeout 3s quickshell -c ii ipc call lock activate || return 1

    # IPC success only means Quickshell received the request. Wait until its
    # session lock actually covers the displays before treating it as locked.
    for ((attempt = 0; attempt < 30; attempt++)); do
        if [[ "$(timeout 2s quickshell -c ii ipc call lock isSecure 2>/dev/null)" == "true" ]]; then
            return 0
        fi
        sleep 0.1
    done

    # A rejected lock request can leave the lock-themed background visible
    # without a password surface. Clear it before retrying or falling back.
    timeout 3s quickshell -c ii ipc call lock unlock >/dev/null 2>&1 || true
    return 1
}

if jq -e '.lock.useHyprlock == false' "$settings_file" >/dev/null 2>&1; then
    if try_quickshell_lock || try_quickshell_lock; then
        exit 0
    fi
fi

# A missing Quickshell instance must never leave an idle session unlocked.
exec "$HOME/.config/hypr/hyprlock/launch.sh"
