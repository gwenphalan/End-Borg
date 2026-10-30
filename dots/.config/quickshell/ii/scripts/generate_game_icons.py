#!/usr/bin/env python3
"""
Studio Game Icon Generator & Alternative Icon Resolver for Quickshell.
Creates studio-grade 256x256 square iOS-style tiles with:
1. Official hero background art filling the tile
2. Official crisp transparent logo overlaid cleanly with drop shadow
3. Exports to ~/.cache/quickshell/game_icons/ and ~/.local/share/icons/hicolor/256x256/apps/
4. Generates ~/.cache/quickshell/game_icons/fill_icons.json for zero-latency FILL vs FIT detection.
"""

import os
import glob
import re
import json
import urllib.request
import urllib.parse
from PIL import Image, ImageFilter

CACHE_DIR = os.path.expanduser("~/.cache/quickshell/game_icons")
HICOLOR_DIR = os.path.expanduser("~/.local/share/icons/hicolor/256x256/apps")
STEAM_CACHE = os.path.expanduser("~/.local/share/Steam/appcache/librarycache")
os.makedirs(CACHE_DIR, exist_ok=True)
os.makedirs(HICOLOR_DIR, exist_ok=True)

fill_map = {}

def search_steam_appid(name):
    clean_name = re.sub(r"[™®\(\)]", "", name).strip()
    try:
        url = "https://steamcommunity.com/actions/SearchApps/" + urllib.parse.quote(clean_name)
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=4) as res:
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
        with urllib.request.urlopen(req, timeout=4) as resp:
            with open(out_path, "wb") as f:
                f.write(resp.read())
            return out_path
    except Exception:
        return None

def generate_studio_tile(appid, name):
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
        # Center crop square from hero/cover
        crop_size = min(hw, hh)
        crop_x = int((hw - crop_size) * 0.5)
        crop_y = int((hh - crop_size) * 0.3) if hh > hw else int((hh - crop_size) * 0.5)
        bg = hero.crop((crop_x, crop_y, crop_x + crop_size, crop_y + crop_size)).resize((256, 256), Image.Resampling.LANCZOS)

        if logo_file and os.path.exists(logo_file):
            # Subtle background blur and dim to make title pop
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
        return out_file
    except Exception as e:
        print(f"Error generating tile for {name} ({appid}): {e}")
        return None

def main():
    desktop_files = glob.glob(os.path.expanduser("~/.local/share/applications/*.desktop")) + glob.glob("/usr/share/applications/*.desktop")
    processed = 0

    for df in desktop_files:
        try:
            content = open(df, errors="ignore").read()
            is_game = "Categories=" in content and ("Game" in content or "Games" in content) or "steam" in df.lower()
            if not is_game:
                continue

            lines = dict([l.split("=", 1) for l in content.splitlines() if "=" in l and not l.startswith("[")])
            name = lines.get("Name", "")
            exec_cmd = lines.get("Exec", "")
            icon_name = lines.get("Icon", "")

            appid = None
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
                tile_path = generate_studio_tile(appid, name)
                if tile_path:
                    base_name = os.path.splitext(os.path.basename(df))[0].lower().replace(" ", "")
                    alias_file = os.path.join(CACHE_DIR, f"{base_name}.png")
                    try:
                        if os.path.exists(alias_file) or os.path.islink(alias_file):
                            os.remove(alias_file)
                        os.symlink(tile_path, alias_file)
                    except: pass

                    if icon_name and icon_name.startswith("steam_icon_"):
                        hicolor_path = os.path.join(HICOLOR_DIR, f"{icon_name}.png")
                        try:
                            if os.path.exists(hicolor_path) or os.path.islink(hicolor_path):
                                os.remove(hicolor_path)
                            os.symlink(tile_path, hicolor_path)
                        except: pass

                    fill_map[appid] = True
                    fill_map[base_name] = True
                    fill_map[f"steam_icon_{appid}"] = True
                    fill_map[f"steam_app_{appid}"] = True
                    if icon_name: fill_map[icon_name] = True
                    processed += 1
                    print(f"[STUDIO TILE OK] {name} ({appid})")
        except Exception:
            pass

    # Save fill_map JSON
    meta_path = os.path.join(CACHE_DIR, "fill_icons.json")
    with open(meta_path, "w") as f:
        json.dump(fill_map, f, indent=2)

    print(f"Total processed studio tiles: {processed}. Metadata written to {meta_path}")

if __name__ == "__main__":
    main()
