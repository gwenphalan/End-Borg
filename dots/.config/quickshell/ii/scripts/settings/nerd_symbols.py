#!/usr/bin/env python3
"""List searchable Nerd Font icons actually present in the selected font.

Glyph names come from the installed font, not a remote catalog. Empty outlines,
.notdef and unassigned codepoints never become picker entries. Output is one
JSON object and uses an XDG cache keyed by the exact font file/version.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

FAMILIES = {
    "md": "Material Design", "fa": "Font Awesome", "dev": "Devicons",
    "cod": "Codicons", "oct": "Octicons", "weather": "Weather",
    "fae": "Font Awesome Extension", "seti": "Seti UI", "linux": "Linux",
    "ple": "Powerline Extra", "pl": "Powerline", "pom": "Pomodoro",
    "custom": "Custom", "extra": "Extra", "iec": "IEC Power Symbols",
    "indentation": "Indentation",
}
# Keep common keyboard glyphs alongside the complete icon families, but only if
# the selected font really contains an outline for each character.
KEYBOARD = {
    0x229E: ("Super", "super meta windows modifier key"),
    0x2318: ("Command", "super meta mac apple command cmd modifier"),
    0x25C6: ("Meta diamond", "super meta modifier diamond"),
    0x25C7: ("Meta outline", "super meta modifier diamond"),
    0x2325: ("Alt / Option", "alt option mac modifier"),
    0x2303: ("Control", "control ctrl mac modifier"),
    0x21E7: ("Shift", "shift modifier"),
}
CACHE_VERSION = 1


def enumerate_symbols(font_path, font_index=0):
    from fontTools.ttLib import TTFont
    from fontTools.pens.boundsPen import BoundsPen

    font = TTFont(font_path, fontNumber=font_index, lazy=True)
    cmap = font.getBestCmap() or {}
    glyph_set = font.getGlyphSet()
    outlines = font.get("glyf")
    symbols = []
    counts = {}
    for codepoint, glyph_name in sorted(cmap.items()):
        prefix = glyph_name.split("-", 1)[0]
        keyboard = KEYBOARD.get(codepoint)
        if prefix not in FAMILIES and not keyboard:
            continue
        if glyph_name in (".notdef", ".null", "nonmarkingreturn"):
            continue
        if outlines is not None:
            if outlines[glyph_name].numberOfContours == 0:
                continue
        else:
            pen = BoundsPen(glyph_set)
            glyph_set[glyph_name].draw(pen)
            if pen.bounds is None:
                continue
        if keyboard:
            family = "keyboard"
            title, aliases = keyboard
        else:
            family = prefix
            title = glyph_name.split("-", 1)[-1].replace("_", " ").replace("-", " ").strip().capitalize()
            aliases = ""
            if any(token in glyph_name for token in ("windows", "command", "apple", "linux", "keyboard", "key_")):
                aliases += " super meta modifier logo"
            if "windows" in glyph_name:
                aliases += " microsoft win"
            if "linux" in glyph_name:
                aliases += " tux penguin"
        glyph = chr(codepoint)
        code = f"U+{codepoint:04X}"
        family_name = "Keyboard" if family == "keyboard" else FAMILIES[family]
        symbols.append({
            "name": title, "glyph": glyph, "family": family,
            "code": code,
            "search": f"{title} {glyph_name} nf-{glyph_name} {family_name} {aliases} {code} {codepoint:x} {glyph}".lower(),
        })
        counts[family] = counts.get(family, 0) + 1
    # Familiar modifier choices lead the unfiltered list; the rest remain stable
    # alphabetically within their families instead of following opaque codepoints.
    preferred = [0xE8E5, 0xF05B3, 0xF17A, 0x229E, 0x2318, 0xF0633,
                 0x25C6, 0x25C7, 0xE711, 0xF17C, 0xF033D, 0xF303, 0xF31B, 0xF306,
                 0x2325, 0x2303, 0x21E7]
    ranks = {chr(codepoint): index for index, codepoint in enumerate(preferred)}
    symbols.sort(key=lambda item: (0, ranks[item["glyph"]]) if item["glyph"] in ranks
                 else (1, item["family"], item["name"]))
    families = [{"id": key, "name": "Keyboard" if key == "keyboard" else FAMILIES[key], "count": count}
                for key, count in counts.items()]
    families.sort(key=lambda item: item["name"])
    resolved_family = font["name"].getDebugName(1) or ""
    font.close()
    return {"symbols": symbols, "families": families, "fontFamily": resolved_family}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--font", required=True)
    args = parser.parse_args()
    result = subprocess.run(["fc-match", "--format", "%{file}\\n%{index}\\n", "--", args.font],
                            check=True, capture_output=True, text=True)
    lines = result.stdout.splitlines()
    if not lines or not Path(lines[0]).is_file():
        raise ValueError("The selected font could not be located.")
    font_path = Path(lines[0])
    font_index = int(lines[1]) if len(lines) > 1 and lines[1].isdigit() else 0
    stat = font_path.stat()
    key = hashlib.sha256(f"{CACHE_VERSION}|{font_path}|{font_index}|{stat.st_mtime_ns}|{stat.st_size}".encode()).hexdigest()
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell" / "nerd-symbols" / f"{key}.json"
    try:
        data = json.loads(cache.read_text())
    except (OSError, ValueError):
        data = enumerate_symbols(font_path, font_index)
        try:
            cache.parent.mkdir(parents=True, exist_ok=True)
            temporary = cache.with_suffix(f".{os.getpid()}.tmp")
            temporary.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
            temporary.replace(cache)
        except OSError:
            pass  # A read-only cache does not prevent browsing installed icons.
    print(json.dumps(data, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"symbols": [], "families": [], "error": str(error)}))
        sys.exit(1)
