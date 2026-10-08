#!/usr/bin/env python3
"""
Generates dark fantasy arcane tarot & dice assets for Dice Fate using OmniFlash API.
"""

import os
import sys
import time
import json
import urllib.request
from PIL import Image
import rembg

API_URL = "http://100.124.202.25:8080"
BASE_DIR = "/home/runner/make-games/assets"
SPRITES_DIR = os.path.join(BASE_DIR, "sprites")
TEXTURES_DIR = os.path.join(BASE_DIR, "textures")
os.makedirs(SPRITES_DIR, exist_ok=True)
os.makedirs(TEXTURES_DIR, exist_ok=True)

ASSETS_TO_GENERATE = [
    # 1. Monsters & Bosses
    {
        "out_dir": SPRITES_DIR,
        "filename": "monster_stone_sentinel.png",
        "size": (192, 192),
        "prompt": "dark fantasy monster portrait of a heavy ancient craggy stone golem sentinel with glowing runic cracks, front view, clean isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "monster_hexweaver.png",
        "size": (192, 192),
        "prompt": "dark fantasy monster portrait of an eldritch hooded spider priestess with glowing violet eyes and web tendrils, front view, clean isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "monster_blood_cultist.png",
        "size": (192, 192),
        "prompt": "dark fantasy monster portrait of a sinister vampire blood cultist in crimson velvet mantle with fangs, front view, clean isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "monster_devourer.png",
        "size": (256, 256),
        "prompt": "dark fantasy cosmic horror boss portrait of a massive multi-jawed eldritch devourer entity with shadowy tentacles, front view, clean isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "monster_goblin_thief.png",
        "size": (192, 192),
        "prompt": "dark fantasy character portrait of a sneaky grinning shadow goblin gambler holding golden dice, front view, clean isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "monster_bone_knight.png",
        "size": (192, 192),
        "prompt": "dark fantasy monster portrait of a cursed skeletal dark paladin in black iron armor with glowing visor, front view, clean isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },

    # 2. Hero Classes
    {
        "out_dir": SPRITES_DIR,
        "filename": "hero_sellsword.png",
        "size": (192, 192),
        "prompt": "dark fantasy hero portrait of a battle-worn sellsword warrior in heavy fur cloak with steel greatsword, front view, clean isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "hero_occultist.png",
        "size": (192, 192),
        "prompt": "dark fantasy hero portrait of an arcane warlock occultist tarot reader with glowing eye talisman, front view, clean isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "hero_bastion.png",
        "size": (192, 192),
        "prompt": "dark fantasy hero portrait of an impenetrable juggernaut knight with heavy fortress plate armor and warhammer, front view, clean isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },

    # 3. Dice Face Symbols & Relic Icons
    {
        "out_dir": SPRITES_DIR,
        "filename": "icon_blade.png",
        "size": (96, 96),
        "prompt": "embossed dark fantasy game icon of glowing sharp crossed steel swords with ruby jewel, isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "icon_ward.png",
        "size": (96, 96),
        "prompt": "embossed dark fantasy game icon of a heavy ornate sapphire tower shield with silver trim, isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "icon_sunder.png",
        "size": (96, 96),
        "prompt": "embossed dark fantasy game icon of a cracked shattered iron armor plate with orange sparks, isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "icon_hex.png",
        "size": (96, 96),
        "prompt": "embossed dark fantasy game icon of an eldritch glowing purple amethyst skull with mystical smoke, isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "icon_focus.png",
        "size": (96, 96),
        "prompt": "embossed dark fantasy game icon of a glowing mystical all-seeing eye with golden flame aura, isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "icon_bless.png",
        "size": (96, 96),
        "prompt": "embossed dark fantasy game icon of a holy radiant sunburst halo with emerald light, isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "icon_reroll.png",
        "size": (96, 96),
        "prompt": "embossed dark fantasy game icon of mystical tumbling obsidian d6 dice with glowing gold pips, isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },
    {
        "out_dir": SPRITES_DIR,
        "filename": "icon_relic_pouch.png",
        "size": (96, 96),
        "prompt": "embossed dark fantasy game icon of a velvet relic coin pouch tied with golden rope, isolated on plain background",
        "aspect": "square",
        "is_bg": False
    },

    # 4. Environments & Banners
    {
        "out_dir": TEXTURES_DIR,
        "filename": "bg_altar_table.png",
        "size": (1280, 720),
        "prompt": "atmospheric dark fantasy background of an occult candlelit mahogany altar table with dark velvet cloth and gold filigree trim, 16:9 wallpaper",
        "aspect": "landscape",
        "is_bg": True
    },
    {
        "out_dir": TEXTURES_DIR,
        "filename": "title_cover_banner.png",
        "size": (1280, 720),
        "prompt": "epic dark fantasy game title screen cover banner of mystical glowing dice floating over an occult tarot table with mysterious masked dealer, 16:9 wallpaper",
        "aspect": "landscape",
        "is_bg": True
    }
]

def generate_image(prompt: str, aspect: str = "square") -> str:
    url = f"{API_URL}/generate/image"
    data = json.dumps({"prompt": prompt, "aspect": aspect, "count": 1}).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            res_data = json.loads(response.read().decode("utf-8"))
            if res_data.get("success") and res_data.get("outputs"):
                out = res_data["outputs"][0]
                fn = out.get("filename")
                dl_url = f"{API_URL}/download/{fn}"
                return dl_url
    except Exception as e:
        print(f"Error generating image: {e}")
    return ""

def download_and_process(url: str, out_path: str, target_size: tuple, is_bg: bool = False):
    temp_path = out_path + ".temp.jpg"
    urllib.request.urlretrieve(url, temp_path)
    
    img = Image.open(temp_path)
    if is_bg:
        img = img.convert("RGBA")
        img = img.resize(target_size, Image.Resampling.LANCZOS)
        img.save(out_path, "PNG")
    else:
        rgba = rembg.remove(img)
        bbox = rgba.getbbox()
        if bbox:
            cropped = rgba.crop(bbox)
            max_side = max(cropped.width, cropped.height)
            square_img = Image.new("RGBA", (max_side, max_side), (0, 0, 0, 0))
            offset_x = (max_side - cropped.width) // 2
            offset_y = (max_side - cropped.height) // 2
            square_img.paste(cropped, (offset_x, offset_y), cropped)
            final_img = square_img.resize(target_size, Image.Resampling.LANCZOS)
            final_img.save(out_path, "PNG")
        else:
            rgba = rgba.resize(target_size, Image.Resampling.LANCZOS)
            rgba.save(out_path, "PNG")

    if os.path.exists(temp_path):
        os.remove(temp_path)
    print(f" Saved: {out_path} ({target_size[0]}x{target_size[1]})")

def main():
    print(f"Generating {len(ASSETS_TO_GENERATE)} assets for Dice Fate...")
    for idx, item in enumerate(ASSETS_TO_GENERATE):
        filename = item["filename"]
        out_path = os.path.join(item["out_dir"], filename)
        print(f"[{idx+1}/{len(ASSETS_TO_GENERATE)}] Generating {filename}...")
        
        dl_url = generate_image(item["prompt"], item["aspect"])
        if dl_url:
            download_and_process(dl_url, out_path, item["size"], item["is_bg"])
        else:
            print(f"Failed to generate {filename}")
        time.sleep(1.0)
    print("\nAll Dice Fate assets generated successfully!")

if __name__ == "__main__":
    main()
