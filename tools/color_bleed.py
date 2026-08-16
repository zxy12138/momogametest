# -*- coding: utf-8 -*-
"""
color_bleed.py —— 透明素材「去黑边 / 去杂色边」工具（v2 重写）
=====================================================================
问题：AI 生成/羽化的透明素材，半透明边缘的 RGB 是黑色（或杂色）。
      Godot 按 straight alpha 渲染：颜色 = RGB*alpha + 背景*(1-alpha)，
      半透明像素 RGB 若为黑 → 边缘发黑（黑边）。

v2 修复（相较 v1 的「邻居平均」）：
      v1 用「邻居颜色取平均」扩散，多轮后把门框深色 + 门洞亮色混在一起 → 灰彩虹/彩色边。
      v2 改为「复制最近的不透明像素颜色」——每个半透明像素直接采用离它最近的那个
      不透明像素的 RGB（BFS 逐轮外扩、只拷贝不平均），保证羽化区沿物体自己的
      边缘颜色平滑渐隐，不混色、不产生彩色边。

用法：
  python color_bleed.py <输入.png> [输出.png]
  默认输出覆盖输入（首次先备份 .bak）。
"""
import os
import sys
import shutil

import numpy as np
from PIL import Image


def color_bleed(src: str, dst: str, max_rounds: int = 2000) -> None:
    im = Image.open(src).convert("RGBA")
    a = np.array(im).astype(np.float32)
    alpha = a[:, :, 3]
    rgb = a[:, :, :3]

    # 颜色来源：不透明像素（alpha>=255）
    filled = alpha >= 255
    frgb = rgb.copy()

    # BFS 外扩：每轮向 上/下/左/右 各拷一次「已填充邻居」的颜色（只拷贝，不平均）。
    # 目标：有内容(alpha>0) 且 尚未填充 且 有已填充邻居。
    for _ in range(max_rounds):
        changed = False
        # 上（从上一行拷）
        m = np.zeros_like(filled); m[1:, :] = filled[:-1, :]
        r = np.zeros_like(frgb); r[1:, :] = frgb[:-1, :]
        t = (alpha > 0) & (~filled) & m
        if t.any():
            frgb[t] = r[t]; filled[t] = True; changed = True
        # 下
        m = np.zeros_like(filled); m[:-1, :] = filled[1:, :]
        r = np.zeros_like(frgb); r[:-1, :] = frgb[1:, :]
        t = (alpha > 0) & (~filled) & m
        if t.any():
            frgb[t] = r[t]; filled[t] = True; changed = True
        # 左
        m = np.zeros_like(filled); m[:, 1:] = filled[:, :-1]
        r = np.zeros_like(frgb); r[:, 1:] = frgb[:, :-1]
        t = (alpha > 0) & (~filled) & m
        if t.any():
            frgb[t] = r[t]; filled[t] = True; changed = True
        # 右
        m = np.zeros_like(filled); m[:, :-1] = filled[:, 1:]
        r = np.zeros_like(frgb); r[:, :-1] = frgb[:, 1:]
        t = (alpha > 0) & (~filled) & m
        if t.any():
            frgb[t] = r[t]; filled[t] = True; changed = True
        if not changed:
            break

    result = a.copy()
    result[:, :, :3] = frgb
    result[alpha == 0, :3] = 0  # 完全透明像素 RGB 归零（无所谓，保持干净）
    Image.fromarray(result.astype(np.uint8), "RGBA").save(dst)


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: python color_bleed.py <输入.png> [输出.png]")
        return 2
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src

    if not os.path.isfile(src):
        print("文件不存在:", src)
        return 2

    # 覆盖输入时首次备份
    if os.path.abspath(src) == os.path.abspath(dst):
        bak = src + ".bak"
        if not os.path.isfile(bak):
            shutil.copy2(src, bak)
            print("已备份原图 ->", bak)

    print(f"去黑边(v2 拷贝最近不透明色)中: {src}")
    color_bleed(src, dst)
    print("完成 ->", dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
