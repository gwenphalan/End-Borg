#!/usr/bin/env bash
# Sync the committed shell palette, preserving VS Code's JSONC settings.
set -euo pipefail
exec "${HOME}/.local/bin/node" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/quickshell-vscode-theme-sync/sync.cjs" "$@"
