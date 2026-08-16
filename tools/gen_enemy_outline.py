# -*- coding: utf-8 -*-
"""
gen_enemy_outline.py —— 批量生成怪物的描边兄弟图（_outline.png）
=====================================================================
复用 Player 的描边机制（pack_momo.py 的 make_outline 算法）：
对每帧做 3×3 MaxFilter 扩张 1px，减去原 alpha = 轮廓外 1px 白色描边环。
怪物 sprite 用 outline_color(黑) modulate 后即黑色描边。

扫描 assets/sprites/enemies/{layer1,layer2,layer3} 里所有动画条
（*_walk_*.png / *_attack*.png / *_dead*.png / *_idle.png / *_melee*.png），
逐帧生成描边环，拼接成同名 _outline.png（白色环，供 Outline 节点 modulate）。
"""
import os
from PIL import Image, ImageFilter

BASE = r"H:/GodotProject/momogametest/assets/sprites/enemies"

# 帧宽统一 128（Enemies.gd 里 fw=128；帧数按动画不同，但帧宽一致）
FRAME_W = 128


def make_outline_frame(frame_rgba):
    """单帧：灰度化 -> 3x3 MaxFilter 扩张 1px -> 减去原灰度 = 描边环（白色 + 透明）。"""
    g = frame_rgba.convert("L")
    dil = g.filter(ImageFilter.MaxFilter(3))
    out = Image.new("RGBA", frame_rgba.size, (255, 255, 255, 0))
    opx = out.load()
    gpx = g.load()
    dpx = dil.load()
    w, h = g.size
    for y in range(h):
        for x in range(w):
            if dpx[x, y] > 8 and gpx[x, y] <= 8:
                opx[x, y] = (255, 255, 255, 255)
    return out


def process_strip(path, frame_w):
    im = Image.open(path).convert("RGBA")
    n = im.size[0] // frame_w
    h = im.size[1]
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    for i in range(n):
        frame = im.crop((i * frame_w, 0, (i + 1) * frame_w, h))
        ring = make_outline_frame(frame)
        out.paste(ring, (i * frame_w, 0), ring)
    return out


def main():
    count = 0
    for layer in ["layer1", "layer2", "layer3"]:
        d = os.path.join(BASE, layer)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".png"):
                continue
            if "_outline" in fn or "_proj" in fn or "_portrait" in fn:
                continue
            # 只处理动画条（含 _walk_/_attack/_dead/_idle/_melee），跳过原始整表
            base = fn[:-4]  # 去 .png
            if not any(k in fn for k in ["_walk_", "_attack", "_dead", "_idle", "_melee"]):
                continue
            p = os.path.join(d, fn)
            im = Image.open(p)
            w = im.size[0]
            frame_w = FRAME_W
            if w % frame_w != 0:
                print(f"跳过（宽度不整除帧宽）: {layer}/{fn} w={w} fw={frame_w}")
                continue
            ring = process_strip(p, frame_w)
            outp = os.path.join(d, base + "_outline.png")
            ring.save(outp)
            count += 1
            print(f"[ok] {layer}/{fn} ({w}x{im.size[1]}, {w//frame_w}帧) -> {base}_outline.png")
    print(f"\n共生成 {count} 个描边兄弟图")


if __name__ == "__main__":
    main()
