#!/bin/sh
config="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/icon-review.qml"
if hyprctl clients -j | jq -e 'any(.[]; .title == "Icon Studio")' >/dev/null 2>&1; then
    hyprctl dispatch focuswindow 'title:^(Icon Studio)$' >/dev/null
    exit 0
fi
qs kill -p "$config" >/dev/null 2>&1 || :
attempt=0
while qs list --all | grep -Fq "Config path: $config"; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 30 ] || exit 1
    sleep 0.1
done
exec qs -n -p "$config"
