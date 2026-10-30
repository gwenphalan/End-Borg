#!/usr/bin/env python3
"""
Comprehensive Icon Engine for Quickshell.
1. Generates studio-grade 256x256 square iOS-style tiles for all games (backdrop + title logo + drop shadow).
2. Analyzes ALL installed desktop applications (300+ apps) to identify which icons best FILL vs FIT:
   - If an icon is opaque across all borders (no background pixels visible when filled) -> FILL (margins: 0, squircle crop).
   - If an icon has transparent padding/borders (cutout logo, SVG, shaped glyph) -> FIT (with padding, centered on Material You squircle).
3. Exports metadata to ~/.cache/quickshell/game_icons/app_icons_meta.json used across Search, Spotlight, and Overview.
"""

import os
import glob
import re
import json
import urllib.request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageFilter

try:
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
    gtk_theme = Gtk.IconTheme.get_default()
except Exception:
    gtk_theme = None

CACHE_DIR = os.path.expanduser("~/.cache/quickshell/game_icons")
HICOLOR_DIR = os.path.expanduser("~/.local/share/icons/hicolor/256x256/apps")
STEAM_CACHE = os.path.expanduser("~/.local/share/Steam/appcache/librarycache")
os.makedirs(CACHE_DIR, exist_ok=True)
os.makedirs(HICOLOR_DIR, exist_ok=True)

def search_steam_appid(name):
    clean_name = re.sub(r"[™®\(\)]", "", name).strip()
    try:
        url = "https://steamcommunity.com/actions/SearchApps/" + urllib.parse.quote(clean_name)
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=3) as res:
            data = json.loads(res.read().decode())
            if data and "appid" in data[0]:
                return str(data[0]["appid"])
    except Exception:
        pass
    return None

def fetch_asset(appid, filename, out_path):
    local_path = os.path.join(STEAM_CACHE, appid, filename)
    if os.path.exists(local_path):
        return local_path

    url = f"https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/{filename}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=3) as resp:
            with open(out_path, "wb") as f:
                f.write(resp.read())
            return out_path
    except Exception:
        return None

def generate_studio_tile(game_info):
    appid, name, df, icon_name = game_info
    out_file = os.path.join(CACHE_DIR, f"{appid}.png")

    tmp_hero = f"/tmp/{appid}_hero.jpg"
    tmp_logo = f"/tmp/{appid}_logo.png"
    tmp_cover = f"/tmp/{appid}_cover.jpg"

    hero_file = fetch_asset(appid, "library_hero.jpg", tmp_hero)
    logo_file = fetch_asset(appid, "logo.png", tmp_logo)

    if not hero_file:
        hero_file = fetch_asset(appid, "library_600x900.jpg", tmp_cover)
    if not hero_file:
        hero_file = fetch_asset(appid, "header.jpg", tmp_cover)

    if not hero_file:
        return None

    try:
        hero = Image.open(hero_file).convert("RGBA")
        hw, hh = hero.size
        crop_size = min(hw, hh)
        crop_x = int((hw - crop_size) * 0.5)
        crop_y = int((hh - crop_size) * 0.3) if hh > hw else int((hh - crop_size) * 0.5)
        bg = hero.crop((crop_x, crop_y, crop_x + crop_size, crop_y + crop_size)).resize((256, 256), Image.Resampling.LANCZOS)

        if logo_file and os.path.exists(logo_file):
            bg_blurred = bg.filter(ImageFilter.GaussianBlur(radius=3.5))
            dimmer = Image.new("RGBA", (256, 256), (0, 0, 0, 75))
            tile = Image.alpha_composite(bg_blurred, dimmer)

            logo = Image.open(logo_file).convert("RGBA")
            lw, lh = logo.size
            scale = min(208.0 / lw, 140.0 / lh)
            target_w = max(1, int(lw * scale))
            target_h = max(1, int(lh * scale))
            logo_resized = logo.resize((target_w, target_h), Image.Resampling.LANCZOS)

            # Drop shadow
            shadow = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
            shadow_mask = logo_resized.split()[3]
            shadow_color = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 185))
            paste_x = int((256 - target_w) / 2)
            paste_y = int((256 - target_h) / 2)
            shadow.paste(shadow_color, (paste_x + 2, paste_y + 4), shadow_mask)
            shadow = shadow.filter(ImageFilter.GaussianBlur(radius=5))

            tile = Image.alpha_composite(tile, shadow)
            tile.paste(logo_resized, (paste_x, paste_y), logo_resized)
        else:
            tile = bg

        tile.save(out_file, "PNG")

        # Link aliases
        base_name = os.path.splitext(os.path.basename(df))[0].lower().replace(" ", "")
        alias_file = os.path.join(CACHE_DIR, f"{base_name}.png")
        try:
            if os.path.exists(alias_file) or os.path.islink(alias_file):
                os.remove(alias_file)
            os.symlink(out_file, alias_file)
        except Exception:
            pass

        if icon_name and icon_name.startswith("steam_icon_"):
            hicolor_path = os.path.join(HICOLOR_DIR, f"{icon_name}.png")
            try:
                if os.path.exists(hicolor_path) or os.path.islink(hicolor_path):
                    os.remove(hicolor_path)
                os.symlink(out_file, hicolor_path)
            except Exception:
                pass

        return appid, out_file
    except Exception as e:
        print(f"Error generating tile for {name} ({appid}): {e}")
        return None

def is_full_fill(img_path):
    """
    Checks if an icon fills its entire canvas with solid pixels:
    If all border pixels are opaque -> FILL (squircle crop with 0 margins).
    If any border pixel is transparent -> FIT (with padding so it doesn't get clipped).
    """
    if not img_path or not os.path.exists(img_path) or img_path.endswith(".svg"):
        return False
    try:
        im = Image.open(img_path)
        if im.mode == "RGB":
            return True
        im = im.convert("RGBA")
        w, h = im.size
        # Sample edge pixels along top, bottom, left, right
        edges = []
        step_x = max(1, w // 12)
        step_y = max(1, h // 12)
        for x in range(0, w, step_x):
            edges.append(im.getpixel((x, 0)))
            edges.append(im.getpixel((x, h - 1)))
        for y in range(0, h, step_y):
            edges.append(im.getpixel((0, y)))
            edges.append(im.getpixel((w - 1, y)))
        # Check if transparent
        return not any(len(p) > 3 and p[3] < 220 for p in edges)
    except Exception:
        return False

def resolve_icon_path(icon_name):
    if not icon_name:
        return None
    if icon_name.startswith("/") and os.path.exists(icon_name):
        return icon_name
    if gtk_theme:
        try:
            info = gtk_theme.lookup_icon(icon_name, 48, 0)
            if info:
                return info.get_filename()
        except Exception:
            pass
    # Fallback search
    for d in [HICOLOR_DIR, "/usr/share/pixmaps"]:
        for ext in [".png", ".svg"]:
            p = os.path.join(d, icon_name + ext)
            if os.path.exists(p):
                return p
    return None

def main():
    desktop_files = sorted(set(glob.glob(os.path.expanduser("~/.local/share/applications/*.desktop")) +
                               glob.glob("/usr/share/applications/*.desktop")))
    print(f"Analyzing {len(desktop_files)} desktop applications...")

    games_to_generate = []
    apps_data = []

    for df in desktop_files:
        try:
            content = open(df, errors="ignore").read()
            lines = dict([l.split("=", 1) for l in content.splitlines() if "=" in l and not l.startswith("[")])
            name = lines.get("Name", "")
            exec_cmd = lines.get("Exec", "")
            icon_name = lines.get("Icon", "")
            wm_class = lines.get("StartupWMClass", "")
            is_game = "Categories=" in content and ("Game" in content or "Games" in content) or "steam" in df.lower()

            base_name = os.path.splitext(os.path.basename(df))[0]

            appid = None
            if is_game:
                m = re.search(r"rungameid/(\d+)", exec_cmd)
                if m:
                    appid = m.group(1)
                if not appid:
                    m = re.search(r"steam_icon_(\d+)", icon_name)
                    if m:
                        appid = m.group(1)
                if not appid and name:
                    appid = search_steam_appid(name)
                if appid:
                    games_to_generate.append((appid, name, df, icon_name))

            apps_data.append({
                "df": df,
                "base": base_name,
                "name": name,
                "icon": icon_name,
                "wm_class": wm_class,
                "is_game": is_game,
                "appid": appid
            })
        except Exception:
            pass

    print(f"Generating studio tiles for {len(games_to_generate)} games in parallel...")
    with ThreadPoolExecutor(max_workers=12) as ex:
        results = list(ex.map(generate_studio_tile, games_to_generate))
    print(f"Generated {sum(1 for r in results if r)} studio game tiles.")

    meta = {}

    for app in apps_data:
        appid = app["appid"]
        icon_name = app["icon"]
        resolved_path = None
        fill = False

        if appid:
            # Game studio tile
            tile_path = os.path.join(CACHE_DIR, f"{appid}.png")
            if os.path.exists(tile_path):
                resolved_path = tile_path
                fill = True

        if not resolved_path:
            resolved_path = resolve_icon_path(icon_name)
            fill = is_full_fill(resolved_path)

        entry = {
            "path": resolved_path,
            "fill": fill,
            "is_game": app["is_game"]
        }

        # Index under various keys for rapid O(1) lookup
        keys = [
            app["base"],
            app["base"].lower(),
            app["base"].lower().replace(" ", ""),
            app["name"],
            app["name"].lower(),
            icon_name,
            app["wm_class"]
        ]
        if appid:
            keys.extend([appid, f"steam_icon_{appid}", f"steam_app_{appid}"])

        for k in keys:
            if k:
                meta[k] = entry

    meta_file = os.path.join(CACHE_DIR, "app_icons_meta.json")
    with open(meta_file, "w") as f:
        json.dump(meta, f, indent=2)

    total_fill = sum(1 for v in meta.values() if v.get("fill"))
    print(f"Metadata exported to {meta_file} ({len(meta)} keys indexed, {total_fill} FILL entries).")

if __name__ == "__main__":
    main()
