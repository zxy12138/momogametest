"""生成《梦境逐影》三把初始武器的清晰图标（覆盖式）。
绘制 staff / sword / scythe 三张带透明背景的图标，覆盖：
  assets/weapons/icons/W-001_dream_staff_icon.png
  assets/weapons/icons/W-002_starlight_sword_icon.png
  assets/weapons/icons/W-003_nightmare_scythe_icon.png
采用 4x 超采样 + LANCZOS 缩小，得到干净抗锯齿边缘。
运行：python tools/gen_weapon_icons.py
"""
from __future__ import annotations
import math
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "assets", "weapons", "icons"))
S = 96          # 最终尺寸
SUP = 4         # 超采样倍数
B = S * SUP     # 绘制画布尺寸
CX = B // 2


def new_img() -> Image.Image:
    return Image.new("RGBA", (B, B), (0, 0, 0, 0))


def radial_glow(d: ImageDraw.ImageDraw, c: tuple[int, int], r: int, color: tuple[int, int, int],
                max_alpha: int = 160) -> None:
    for i in range(r, 0, -1):
        a = int(max_alpha * (1.0 - i / r) ** 1.6)
        d.ellipse([c[0] - i, c[1] - i, c[0] + i, c[1] + i],
                  fill=(color[0], color[1], color[2], a))


def star(d: ImageDraw.ImageDraw, x: int, y: int, r: int, color: tuple[int, int, int, int]) -> None:
    w = max(1, SUP // 2)
    d.line([(x - r, y), (x + r, y)], fill=color, width=w)
    d.line([(x, y - r), (x, y + r)], fill=color, width=w)


def make_staff() -> Image.Image:
    img = new_img()
    d = ImageDraw.Draw(img)
    # 法杖木杆
    rx0, rx1 = CX - 7 * SUP, CX + 7 * SUP
    d.rectangle([rx0, 40 * SUP, rx1, 92 * SUP], fill=(110, 72, 40, 255))
    d.rectangle([rx0, 40 * SUP, CX, 92 * SUP], fill=(142, 98, 56, 255))  # 左侧高光
    # 顶部梦境宝珠（青色辉光）
    oc = (CX, 26 * SUP)
    radial_glow(d, oc, 30 * SUP, (90, 220, 255))
    d.ellipse([oc[0] - 16 * SUP, oc[1] - 16 * SUP, oc[0] + 16 * SUP, oc[1] + 16 * SUP],
              fill=(150, 240, 255, 255))
    d.ellipse([oc[0] - 9 * SUP, oc[1] - 9 * SUP, oc[0] + 9 * SUP, oc[1] + 9 * SUP],
              fill=(236, 255, 255, 255))
    # 星点
    star(d, CX + 24 * SUP, 16 * SUP, 6 * SUP, (255, 255, 255, 230))
    star(d, CX - 22 * SUP, 34 * SUP, 5 * SUP, (200, 245, 255, 220))
    return img


def make_sword() -> Image.Image:
    img = new_img()
    d = ImageDraw.Draw(img)
    # 斜向上的钢刃
    blade = [(30 * SUP, 86 * SUP), (44 * SUP, 80 * SUP), (72 * SUP, 22 * SUP),
             (78 * SUP, 18 * SUP), (84 * SUP, 30 * SUP), (58 * SUP, 84 * SUP),
             (46 * SUP, 90 * SUP)]
    d.polygon(blade, fill=(205, 214, 228, 255))
    d.line([(50 * SUP, 84 * SUP), (74 * SUP, 26 * SUP)], fill=(245, 250, 255, 255), width=3 * SUP)
    # 金色横护手
    d.polygon([(28 * SUP, 74 * SUP), (56 * SUP, 62 * SUP), (60 * SUP, 70 * SUP),
               (32 * SUP, 82 * SUP)], fill=(240, 200, 90, 255))
    # 缠绕握柄
    d.rectangle([(33 * SUP, 78 * SUP), (43 * SUP, 94 * SUP)], fill=(90, 60, 34, 255))
    # 柄头
    d.ellipse([(30 * SUP, 90 * SUP), (44 * SUP, 98 * SUP)], fill=(240, 200, 90, 255))
    # 寒光
    star(d, 70 * SUP, 28 * SUP, 5 * SUP, (255, 255, 255, 230))
    return img


def make_scythe() -> Image.Image:
    img = new_img()
    d = ImageDraw.Draw(img)
    # 噩梦辉光（淡紫光晕，靠低不透明度、缩小半径，避免糊成一团）
    radial_glow(d, (30 * SUP, 46 * SUP), 18 * SUP, (170, 90, 230), max_alpha=90)
    # 长柄（占整个下半部分，更「长柄大镰刀」）
    d.polygon([(42 * SUP, 38 * SUP), (52 * SUP, 38 * SUP), (56 * SUP, 94 * SUP),
               (46 * SUP, 94 * SUP)], fill=(70, 52, 38, 255))
    d.polygon([(42 * SUP, 38 * SUP), (47 * SUP, 38 * SUP), (51 * SUP, 94 * SUP),
               (46 * SUP, 94 * SUP)], fill=(96, 74, 54, 255))
    # 弯刀刃（左扫月牙，更明显）
    blade = [(46 * SUP, 36 * SUP), (28 * SUP, 36 * SUP), (8 * SUP, 58 * SUP),
             (10 * SUP, 68 * SUP), (24 * SUP, 66 * SUP), (40 * SUP, 50 * SUP),
             (48 * SUP, 42 * SUP)]
    d.polygon(blade, fill=(205, 212, 228, 255))
    d.line([(42 * SUP, 40 * SUP), (14 * SUP, 58 * SUP), (12 * SUP, 66 * SUP)],
           fill=(245, 250, 255, 255), width=3 * SUP)
    # 刀尖寒芒 + 紫色刀背一点
    d.line([(46 * SUP, 36 * SUP), (12 * SUP, 66 * SUP)], fill=(195, 160, 230, 220), width=2 * SUP)
    star(d, 12 * SUP, 56 * SUP, 4 * SUP, (220, 210, 255, 230))
    star(d, 28 * SUP, 30 * SUP, 3 * SUP, (200, 180, 240, 200))
    return img


def save(img: Image.Image, name: str) -> None:
    out = img.resize((S, S), Image.LANCZOS)
    path = os.path.join(OUT_DIR, name)
    out.save(path)
    print("wrote", path)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    save(make_staff(), "W-001_dream_staff_icon.png")
    save(make_sword(), "W-002_starlight_sword_icon.png")
    save(make_scythe(), "W-003_nightmare_scythe_icon.png")
    print("done")


if __name__ == "__main__":
    main()
