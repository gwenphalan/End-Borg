#!/usr/bin/env python3
"""Build the Hyprlock theme from the settings saved by Quickshell."""

import argparse
import datetime as dt
import html
import json
import locale
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


HOME = Path.home()
SETTINGS = HOME / ".config/illogical-impulse/config.json"
PALETTE = HOME / ".local/state/quickshell/user/generated/colors.json"
OUTPUT = HOME / ".config/hypr/hyprlock.conf"
WALLPAPER_DIR = HOME / ".config/hypr/hyprlock"
SCRIPT = Path(__file__).resolve()


def read_json(path):
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def get(data, dotted, default=None):
    for key in dotted.split("."):
        if not isinstance(data, dict):
            return default
        data = data.get(key)
    return default if data is None else data


def safe_font(value, fallback):
    if isinstance(value, str) and re.fullmatch(r"[\w .-]{1,80}", value, re.UNICODE):
        return value
    return fallback


def color(palette, name, fallback):
    value = palette.get(name, fallback)
    if not isinstance(value, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        value = fallback
    return f"rgba({value[1:]}FF)"


def number(value, minimum, maximum, fallback):
    try:
        value = float(value)
        if not (minimum <= value <= maximum):
            return fallback
        return value
    except (TypeError, ValueError):
        return fallback


def add_block(lines, kind, **options):
    lines.append(f"{kind} {{")
    lines.append("    monitor =")
    for key, value in options.items():
        if value is not None:
            lines.append(f"    {key} = {value}")
    lines.append("}")
    lines.append("")


def label(lines, text, x, y, size, font, ink, *, align="center", valign="center", onclick=None, shadow=False):
    add_block(
        lines,
        "label",
        text=text,
        color=ink,
        font_size=size,
        font_family=font,
        shadow_passes=2 if shadow else None,
        shadow_size=3 if shadow else None,
        shadow_color="rgba(00000066)" if shadow else None,
        position=f"{int(x)}, {int(y)}",
        halign=align,
        valign=valign,
        onclick=onclick,
    )


def wallpaper_path(settings, directory):
    path = get(settings, "background.wallpaperPath", "")
    if isinstance(path, str) and Path(path).suffix.lower() in {".mp4", ".webm", ".mkv", ".avi", ".mov"}:
        path = get(settings, "background.thumbnailPath", "")
    if not isinstance(path, str) or not path:
        return ""
    if get(settings, "workSafety.enable.wallpaper", False):
        keywords = get(settings, "workSafety.triggerCondition.fileKeywords", [])
        sensitive = isinstance(keywords, list) and any(isinstance(word, str) and word.lower() in path.lower() for word in keywords if word)
        if sensitive:
            network_keywords = get(settings, "workSafety.triggerCondition.networkNameKeywords", [])
            try:
                result = subprocess.run(["nmcli", "-t", "-f", "IN-USE,SSID", "dev", "wifi"], capture_output=True, text=True, timeout=2, check=True)
                current_network = next((line[2:] for line in result.stdout.splitlines() if line.startswith("*:")), "")
            except (OSError, subprocess.SubprocessError):
                current_network = ""
            # Hide a sensitive wallpaper if the active network is public, or
            # if its name cannot be checked reliably at lock time.
            if not current_network or (isinstance(network_keywords, list) and any(isinstance(word, str) and word.lower() in current_network.lower() for word in network_keywords if word)):
                return ""
    original = Path(path).expanduser()
    if original.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp"} or not original.is_file():
        return ""
    directory.mkdir(parents=True, exist_ok=True)
    link = directory / ("current-wallpaper" + original.suffix.lower())
    temporary = directory / (link.name + ".new")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(original.resolve())
    os.replace(temporary, link)
    return str(link)


def clock_offset(settings):
    if get(settings, "lock.centerClock", True):
        return 0, 0
    # Quickshell stores the clock's top-left coordinates. Hyprlock positions
    # each label from screen center, so use the current monitor as a reference.
    width, height = 1920, 1080
    try:
        result = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True, timeout=1, check=True)
        monitors = json.loads(result.stdout)
        if monitors:
            width = int(monitors[0].get("width", width))
            height = int(monitors[0].get("height", height))
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    x = number(get(settings, "background.widgets.clock.x"), 0, 100000, 0)
    y = number(get(settings, "background.widgets.clock.y"), 0, 100000, 0)
    return int(x + 150 - width / 2), int(height / 2 - y - 90)


def build(settings, palette, wallpaper):
    ink = color(palette, "on_background", "#f9dcd8")
    subtext = color(palette, "on_surface_variant", "#e7bdb8")
    toolbar = color(palette, "surface_container", "#2b1c1a")
    field = color(palette, "surface_container_high", "#372624")
    primary = color(palette, "primary", "#ffabf3")
    on_primary = color(palette, "on_primary", "#551352")
    error = color(palette, "error", "#ffb4ab")
    base = color(palette, "background", "#1e100e")
    main_font = safe_font(get(settings, "appearance.fonts.main"), "Google Sans Flex")
    expressive_font = safe_font(get(settings, "appearance.fonts.expressive"), "Space Grotesk")
    reading_font = safe_font(get(settings, "appearance.fonts.reading"), main_font)
    clock_font = safe_font(get(settings, "background.widgets.clock.digital.font.family"), main_font)
    symbols = "Material Symbols Rounded"
    lines = ["# Generated by hyprlock/sync.py from Quickshell Settings. Edit those settings instead.", ""]

    blur_enabled = bool(get(settings, "lock.blur.enable", True))
    blur_radius = number(get(settings, "lock.blur.radius"), 0, 1000000, 100)
    passes = max(1, min(5, round(blur_radius / 35))) if blur_enabled and blur_radius > 0 else 0
    size = max(2, min(14, round(blur_radius / 11))) if passes else 0
    add_block(lines, "background", path=wallpaper or None, color=base,
              blur_passes=passes, blur_size=size, noise=0.0,
              contrast=0.9, brightness=0.78, vibrancy=0.16)

    if get(settings, "background.widgets.clock.enable", True):
        dx, dy = clock_offset(settings)
        vertical = bool(get(settings, "background.widgets.clock.digital.vertical", False))
        clock_size = int(number(get(settings, "background.widgets.clock.digital.font.size"), 20, 240, 90))
        text_command = f"python3 {SCRIPT} text"
        time_format = get(settings, "time.format", "h:mm AP")
        if vertical:
            label(lines, "cmd[update:5000] " + text_command + " hour", dx, dy + 116, clock_size, clock_font, ink, shadow=True)
            label(lines, "cmd[update:5000] " + text_command + " minute", dx, dy + 28, clock_size, clock_font, ink, shadow=True)
            below = dy - 52
        else:
            time_text = "$TIME" if time_format == "hh:mm" else "$TIME12" if time_format == "h:mm AP" else "cmd[update:5000] " + text_command + " time"
            label(lines, time_text, dx, dy + 70, clock_size, clock_font, ink, shadow=True)
            below = dy + 8
        if get(settings, "background.widgets.clock.digital.showDate", True):
            label(lines, "cmd[update:30000] " + text_command + " date", dx, below, 20, expressive_font, ink, shadow=True)
            below -= 32
        if get(settings, "background.widgets.clock.quote.enable", False) and get(settings, "background.widgets.clock.quote.text", ""):
            label(lines, "cmd[update:0] " + text_command + " quote", dx, below, 16, reading_font, ink, shadow=True)
            below -= 34
        if get(settings, "lock.showLockedText", True):
            label(lines, "lock", dx - 38, below, 22, symbols, ink)
            label(lines, "Locked", dx + 12, below, 20, expressive_font, ink)

    # Quickshell's three 56px toolbar islands.
    for width, x in ((200, -240), (260, 0), (144, 212)):
        add_block(lines, "shape", size=f"{width}, 56", color=toolbar, rounding=-1,
                  position=f"{x}, 20", halign="center", valign="bottom")
    shape_chars = bool(get(settings, "lock.materialShapeChars", True))
    add_block(lines, "input-field", size="200, 40", outline_thickness=0,
              inner_color=field, font_color=subtext, font_family=main_font,
              rounding=-1, dots_size=0.25 if shape_chars else 0.17,
              dots_spacing=0.12, dots_center="false", dots_text_format="◆" if shape_chars else None,
              fade_on_empty="false", placeholder_text="Enter password",
              check_color=primary, fail_color=error, fail_text="Incorrect password",
              position="-22, 28", halign="center", valign="bottom")
    add_block(lines, "shape", size="40, 40", color=primary, rounding=-1,
              position="104, 28", halign="center", valign="bottom")
    label(lines, "arrow_right_alt", 104, 36, 24, symbols, on_primary, valign="bottom",
          onclick="ydotool key 28:1 28:0")

    label(lines, "account_circle", -318, 37, 22, symbols, subtext, valign="bottom")
    label(lines, "$USER", -272, 39, 14, main_font, subtext, valign="bottom")
    label(lines, "keyboard_alt", -211, 37, 22, symbols, subtext, valign="bottom")
    label(lines, f"cmd[update:5000] python3 {SCRIPT} text layout", -166, 39, 14, main_font, subtext, valign="bottom")

    label(lines, "dark_mode", 164, 37, 22, symbols, subtext, valign="bottom",
          onclick="systemctl suspend")
    if not get(settings, "lock.security.requirePasswordToPower", False):
        label(lines, "power_settings_new", 212, 37, 22, symbols, subtext,
              valign="bottom", onclick="systemctl poweroff")
        label(lines, "restart_alt", 260, 37, 22, symbols, subtext,
              valign="bottom", onclick="systemctl reboot")

    label(lines, f"cmd[update:250] {WALLPAPER_DIR}/check-capslock.sh", 0, 95,
          14, main_font, error, valign="bottom")
    return "\n".join(lines)


QT_DATE_TOKENS = re.compile(r"yyyy|MMMM|dddd|MMM|ddd|yy|MM|dd|M|d")
QT_DATE_MAP = {"yyyy": "%Y", "yy": "%y", "MMMM": "%B", "MMM": "%b",
               "MM": "%m", "M": "%-m", "dddd": "%A", "ddd": "%a",
               "dd": "%d", "d": "%-d"}


def print_text(kind, settings):
    now = dt.datetime.now()
    chosen_locale = get(settings, "calendar.locale", "")
    if isinstance(chosen_locale, str) and chosen_locale:
        try:
            locale.setlocale(locale.LC_TIME, chosen_locale)
        except locale.Error:
            pass
    time_format = get(settings, "time.format", "h:mm AP")
    if kind == "time":
        text = now.strftime("%H:%M" if time_format == "hh:mm" else "%-I:%M %p")
        if time_format == "h:mm ap":
            text = text[:-2] + text[-2:].lower()
    elif kind == "hour":
        text = now.strftime("%H" if time_format == "hh:mm" else "%-I")
    elif kind == "minute":
        text = now.strftime("%M") + (now.strftime(" %p") if time_format != "hh:mm" else "")
        if time_format == "h:mm ap":
            text = text[:-2] + text[-2:].lower()
    elif kind == "date":
        pattern = get(settings, "time.dateFormat", "ddd, MMM dd")
        if not isinstance(pattern, str) or len(pattern) > 100:
            pattern = "ddd, MMM dd"
        text = now.strftime(QT_DATE_TOKENS.sub(lambda match: QT_DATE_MAP[match.group()], pattern.replace("%", "%%")))
    elif kind == "quote":
        text = str(get(settings, "background.widgets.clock.quote.text", ""))
    elif kind == "layout":
        text = "US"
        try:
            result = subprocess.run(["hyprctl", "-j", "devices"], capture_output=True, text=True, timeout=1, check=True)
            keyboards = json.loads(result.stdout).get("keyboards", [])
            keyboard = next((item for item in keyboards if item.get("main")), keyboards[0] if keyboards else {})
            name = keyboard.get("active_keymap", "")
            if isinstance(name, str) and name:
                matched = re.search(r"\(([^)]+)\)", name)
                text = (matched.group(1) if matched else {"English": "US", "German": "DE", "French": "FR", "Spanish": "ES"}.get(name, name[:2])).upper()
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
    else:
        raise ValueError("unknown text field")
    print(html.escape(text, quote=False).replace("\n", " "))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["generate", "text"])
    parser.add_argument("kind", nargs="?")
    parser.add_argument("--settings", type=Path, default=SETTINGS)
    parser.add_argument("--palette", type=Path, default=PALETTE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--wallpaper-dir", type=Path, default=WALLPAPER_DIR)
    args = parser.parse_args()
    settings = read_json(args.settings)
    if args.action == "text":
        print_text(args.kind, settings)
        return
    palette = read_json(args.palette)
    wallpaper = wallpaper_path(settings, args.wallpaper_dir)
    config = build(settings, palette, wallpaper)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=args.output.parent,
                                     prefix=".hyprlock-", delete=False) as file:
        file.write(config)
        temporary = Path(file.name)
    temporary.chmod(0o644)
    os.replace(temporary, args.output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"hyprlock sync: {error}", file=sys.stderr)
        sys.exit(1)
