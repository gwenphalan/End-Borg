#!/usr/bin/env bash
set -euo pipefail

# Settings requests a candidate only. Existing callers still apply immediately.
download_only=false
case "${1:-}" in
    --download-only) download_only=true ;;
    "") ;;
    *) printf 'Usage: %s [--download-only]\n' "$0" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
    printf 'Usage: %s [--download-only]\n' "$0" >&2
    exit 2
fi

get_pictures_dir() {
    local pictures_path=""
    if command -v xdg-user-dir >/dev/null 2>&1; then
        pictures_path=$(xdg-user-dir PICTURES 2>/dev/null || true)
    fi
    if [[ -z "$pictures_path" ]]; then
        local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
        if [[ -f "$config_file" ]]; then
            pictures_path=$(source "$config_file" >/dev/null 2>&1; printf '%s' "${XDG_PICTURES_DIR:-}")
        fi
    fi
    printf '%s\n' "${pictures_path:-$HOME/Pictures}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_path="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
if [[ "${QS_SETTINGS_PREVIEW:-}" == 1 ]]; then
    wallpaper_dir="${QS_SETTINGS_PREVIEW_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/settings-preview}/wallpapers"
else
    wallpaper_dir="$(get_pictures_dir)/Wallpapers"
fi
mkdir -p "$wallpaper_dir"
# Use an absolute path for the machine-readable result and never overwrite a
# currently selected image while selecting another candidate.
wallpaper_dir="$(cd "$wallpaper_dir" && pwd)"
user_agent=$(jq -r '.networking.userAgent // empty' "$config_path" 2>/dev/null || true)
curl_args=(--fail --location --silent --show-error --max-time 60)
[[ -z "$user_agent" ]] || curl_args+=(--user-agent "$user_agent")

page=$((1 + RANDOM % 1000))
response=$(curl "${curl_args[@]}" "https://konachan.net/post.json?tags=rating%3Asafe&limit=1&page=$page")
link=$(jq -er '.[0].file_url | select(type == "string" and length > 0)' <<< "$response")

[[ "$link" == //* ]] && link="https:$link"
if [[ ! "$link" =~ ^https?:// ]]; then
    printf 'The wallpaper service did not return an image URL.\n' >&2
    exit 1
fi
extension="${link%%\?*}"
extension="${extension##*.}"
extension="${extension,,}"
case "$extension" in
    jpg|jpeg|png|webp|avif|gif|bmp) ;;
    *) extension=jpg ;;
esac
download_path=$(mktemp --suffix=".$extension" "$wallpaper_dir/random-konachan.XXXXXX")
keep_download=false
trap 'if [[ "$keep_download" != true ]]; then rm -f -- "$download_path"; fi' EXIT
curl "${curl_args[@]}" --output "$download_path" "$link"
if [[ ! -s "$download_path" ]]; then
    printf 'The downloaded wallpaper was empty.\n' >&2
    exit 1
fi
keep_download=true
if [[ "$download_only" == true ]]; then
    printf 'WALLPAPER_PATH=%s\n' "$download_path"
else
    "$SCRIPT_DIR/../switchwall.sh" --image "$download_path"
fi
