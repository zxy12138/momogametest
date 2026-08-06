"""Generate weapon icons (sliced from Allweapons.png) and placeholder FX sprites.

Run: python tools/gen_weapon_assets.py
Outputs:
  assets/weapons/icons/weapon_<type>.png   (8 sliced, auto-cropped icons)
  assets/weapons/fx/weapon_fx_<type>.png   (9 placeholder attack FX)
These FX are placeholders; the user will replace them with real art later.
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "assets", "weapons", "icons", "Allweapons.png")
ICON_DIR = os.path.join(ROOT, "assets", "weapons", "icons")
FX_DIR = os.path.join(ROOT, "assets", "weapons", "fx")
PAD = 12

# 4 cols x 2 rows. Each weapon -> (col, row)
ORDER = [
    ("staff", 0, 0),
    ("sword", 1, 0),
    ("scythe", 2, 0),
    ("bow", 3, 0),
    ("hammer", 0, 1),
    ("whip", 1, 1),
    ("spear", 2, 1),
    ("axe", 3, 1),
]


def slice_icons() -> None:
    os.makedirs(ICON_DIR, exist_ok=True)
    img = Image.open(SHEET).convert("RGBA")
    w, h = img.size
    cw, ch = w // 4, h // 2
    px = img.load()
    for name, col, row in ORDER:
        x0, y0 = col * cw, row * ch
        # find alpha bbox inside the cell
        minx, miny, maxx, maxy = cw, ch, -1, -1
        for yy in range(ch):
            for xx in range(cw):
                if px[x0 + xx, y0 + yy][3] > 12:
                    minx = min(minx, xx)
                    maxx = max(maxx, xx)
                    miny = min(miny, yy)
                    maxy = max(maxy, yy)
        if maxx < 0:
            minx, miny, maxx, maxy = 0, 0, cw - 1, ch - 1
        minx = max(0, minx - PAD)
        miny = max(0, miny - PAD)
        maxx = min(cw - 1, maxx + PAD)
        maxy = min(ch - 1, maxy + PAD)
        crop = img.crop((x0 + minx, y0 + miny, x0 + maxx + 1, y0 + maxy + 1))
        out = os.path.join(ICON_DIR, f"weapon_{name}.png")
        crop.save(out)
        print(f"  icon  {name:7s} -> {crop.size[0]}x{crop.size[1]}  {os.path.relpath(out, ROOT)}")


def _glow(draw: ImageDraw.ImageDraw, cx: int, cy: int, r: int, color: tuple) -> None:
    for i in range(r, 0, -1):
        a = int(color[3] * (1.0 - i / (r + 1)) ** 0.6)
        draw.ellipse([cx - i, cy - i, cx + i, cy + i], fill=(color[0], color[1], color[2], a))


def make_bolt(path: str) -> None:
    s = 48
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    _glow(d, 24, 24, 18, (120, 220, 255, 255))
    d.ellipse([16, 16, 32, 32], fill=(235, 255, 255, 255))
    im.save(path)


def make_arrow(path: str) -> None:
    w, h = 52, 18
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.line([6, 9, 40, 9], fill=(255, 224, 130, 255), width=3)
    d.polygon([(40, 2), (50, 9), (40, 16)], fill=(255, 240, 170, 255))
    im.save(path)


def make_axe(path: str) -> None:
    s = 48
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([8, 8, 40, 40], outline=(180, 190, 210, 255), width=4)
    d.pieslice([4, 4, 44, 44], 200, 340, fill=(210, 220, 240, 230))
    d.ellipse([20, 20, 28, 28], fill=(120, 130, 150, 255))
    im.save(path)


def make_sword(path: str) -> None:
    s = 96
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = 48, 48
    # crescent slash arc (faces +x)
    for i in range(10, 0, -1):
        a = int(220 * (i / 10.0))
        d.arc([cx - 44, cy - 44, cx + 44, cy + 44], -42, 42, fill=(200, 245, 255, a), width=3)
    d.arc([cx - 44, cy - 44, cx + 44, cy + 44], -42, 42, fill=(255, 255, 255, 235), width=2)
    im.save(path)


def make_scythe(path: str) -> None:
    s = 170
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = 85, 85
    for i in range(6, 0, -1):
        a = int(180 * (i / 6.0))
        d.ellipse([cx - 78, cy - 78, cx + 78, cy + 78], outline=(180, 120, 255, a), width=3)
    d.ellipse([cx - 78, cy - 78, cx + 78, cy + 78], outline=(230, 210, 255, 235), width=2)
    im.save(path)


def make_hammer(path: str) -> None:
    s = 96
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = 48, 48
    for r in (14, 26, 38):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 200, 120, 200), width=2)
    d.line([cx, cy, cx, cy - 40], fill=(255, 230, 160, 230), width=3)
    d.line([cx, cy, cx + 36, cy + 14], fill=(255, 230, 160, 230), width=3)
    d.line([cx, cy, cx - 36, cy + 14], fill=(255, 230, 160, 230), width=3)
    im.save(path)


def make_whip(path: str) -> None:
    s = 130
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = 10, 65
    bbox = [cx, cy - 60, cx + 120, cy + 60]
    for i in range(5, 0, -1):
        a = int(170 * (i / 5.0))
        d.pieslice(bbox, -52, 52, outline=(255, 140, 200, a), width=3)
    d.pieslice(bbox, -52, 52, outline=(255, 200, 230, 235), width=2)
    im.save(path)


def make_spear(path: str) -> None:
    w, h = 110, 26
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.line([6, 13, 92, 13], fill=(200, 230, 255, 255), width=4)
    d.polygon([(92, 4), (108, 13), (92, 22)], fill=(235, 245, 255, 255))
    im.save(path)


def make_hit(path: str) -> None:
    s = 40
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = 20, 20
    for r in (6, 12):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 200, 210), width=2)
    d.line([cx - 14, cy, cx + 14, cy], fill=(255, 240, 160, 220), width=2)
    d.line([cx, cy - 14, cx, cy + 14], fill=(255, 240, 160, 220), width=2)
    im.save(path)


def gen_fx() -> None:
    os.makedirs(FX_DIR, exist_ok=True)
    makers = {
        "staff": make_bolt,
        "bow": make_arrow,
        "axe": make_axe,
        "sword": make_sword,
        "scythe": make_scythe,
        "hammer": make_hammer,
        "whip": make_whip,
        "spear": make_spear,
    }
    for name, fn in makers.items():
        out = os.path.join(FX_DIR, f"weapon_fx_{name}.png")
        fn(out)
        print(f"  fx    {name:7s} -> {os.path.relpath(out, ROOT)}")
    hit = os.path.join(FX_DIR, "weapon_fx_hit.png")
    make_hit(hit)
    print(f"  fx    hit     -> {os.path.relpath(hit, ROOT)}")


if __name__ == "__main__":
    print("Slicing weapon icons from Allweapons.png ...")
    slice_icons()
    print("Generating placeholder FX sprites ...")
    gen_fx()
    print("Done.")
