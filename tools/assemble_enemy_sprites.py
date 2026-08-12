#!/usr/bin/env python3
"""Assemble generated enemy frames into Godot-ready horizontal sprite strips.

Godot 的 GameManager.make_frames 要求每个动画是「一条横向 PNG」：第 i 帧位于
Rect2(i*fw, 0, fw, fh)。本工具接收每个动画的一组输入帧图，统一归一化到
fw x fh（contain 不变形 + 底部对齐，保证脚底在每帧一致），可选把纯色背景
抠成透明，再从左到右拼成一条 PNG。

同时打印一份 Enemies.gd 数据片段（各动画帧数 + 建议 fps），方便直接粘进数据表。

用法：
  python assemble_enemy_sprites.py \
      --out assets/sprites/enemies/layerX \
      --fw 260 --fh 500 \
      --key 00FF00 \
      --anim idle:frames/idle_00.png,frames/idle_01.png,... \
      --anim walk:frames/walk_00.png,... \
      --anim attack:frames/attack_00.png,... \
      --anim dead:frames/dead_00.png,...
"""
from __future__ import annotations

import argparse
import os

from PIL import Image

# 各动画默认 fps（与现有敌人 idle=10/attack=12 接近，walk/dead 略调整）
DEF_FPS: dict[str, int] = {"idle": 8, "walk": 12, "attack": 14, "dead": 12}


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def load_rgba(path: str) -> Image.Image:
    return Image.open(path).convert("RGBA")


def key_background(im: Image.Image, key_rgb: tuple[int, int, int], tol: int = 60) -> Image.Image:
    """把颜色接近 key_rgb 的像素抠成透明（绿幕/纯色底通用）。"""
    px = im.load()
    w, h = im.size
    kr, kg, kb = key_rgb
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0 and (abs(r - kr) + abs(g - kg) + abs(b - kb)) < tol * 3:
                px[x, y] = (r, g, b, 0)
    return im


def normalize(im: Image.Image, fw: int, fh: int) -> Image.Image:
    """contain 归一化（不变形），透明填充，水平居中 + 底部对齐（脚底一致）。"""
    canvas = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    iw, ih = im.size
    if iw == 0 or ih == 0:
        return canvas
    scale = min(fw / iw, fh / ih)
    nw, nh = max(1, round(iw * scale)), max(1, round(ih * scale))
    resized = im.resize((nw, nh), Image.LANCZOS)
    x = (fw - nw) // 2
    y = fh - nh  # 底部对齐
    canvas.alpha_composite(resized, (x, y))
    return canvas


def stitch(frames: list[Image.Image], fw: int, fh: int) -> Image.Image:
    n = len(frames)
    strip = Image.new("RGBA", (fw * n, fh), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        strip.alpha_composite(fr, (i * fw, 0))
    return strip


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="输出目录")
    ap.add_argument("--fw", type=int, default=260)
    ap.add_argument("--fh", type=int, default=500)
    ap.add_argument("--key", default=None, help="要抠掉的纯色背景 hex，如 00FF00（留空则假定输入已带透明）")
    ap.add_argument(
        "--anim",
        action="append",
        required=True,
        help="name:frame1.png,frame2.png,... （从左到右的顺序）",
    )
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    key_rgb = hex_to_rgb(args.key) if args.key else None

    print(f"目标帧尺寸: {args.fw}x{args.fh}  key={args.key}\n")
    counts: dict[str, int] = {}
    for a in args.anim:
        name, paths = a.split(":", 1)
        frame_paths = [p for p in paths.split(",") if p]
        frames: list[Image.Image] = []
        for p in frame_paths:
            im = load_rgba(p)
            if key_rgb is not None:
                im = key_background(im, key_rgb)
            im = normalize(im, args.fw, args.fh)
            frames.append(im)
        strip = stitch(frames, args.fw, args.fh)
        out_path = os.path.join(args.out, f"{name}.png")
        strip.save(out_path)
        counts[name] = len(frames)
        fps = DEF_FPS.get(name, 12)
        print(
            f"[ok] {name:7s}: {len(frames)} 帧 -> {out_path}  "
            f"({args.fw * len(frames)}x{args.fh})  fps={fps}"
        )

    print("\n--- Enemies.gd 数据片段（把 OUT 换成对应层目录常量，如 E1）---")
    lines = []
    for name in ("idle", "walk", "attack", "dead"):
        if name in counts:
            lines.append(f'    {name}=OUT+"{name}.png",')
    lines.append(f"    fw={args.fw}, fh={args.fh},")
    if "idle" in counts:
        lines.append(f"    fi={counts['idle']},")
    if "walk" in counts:
        lines.append(f"    fwk={counts['walk']},")
    if "attack" in counts:
        lines.append(f"    fa={counts['attack']},")
    if "dead" in counts:
        lines.append(f"    fd={counts['dead']},")
    for ln in lines:
        print(ln)


if __name__ == "__main__":
    main()
