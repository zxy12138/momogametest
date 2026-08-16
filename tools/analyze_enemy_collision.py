# -*- coding: utf-8 -*-
"""
analyze_enemy_collision.py —— 分析每个怪物的身体碰撞框尺寸（贴合动画帧）
=====================================================================
扫描 assets/sprites/enemies/{layer1,layer2,layer3} 里所有 *_walk_down.png，
取第一帧 bbox，算出视觉尺寸（sprite scale 0.45）与中心偏移，输出到
Enemies.gd 可用的 cb_w/cb_h/cb_ox/cb_oy 配置（世界单位）。

怪物是瘦长形，用 RectangleShape2D 方形碰撞贴合身体，替换原 CircleShape2D(半径41)。
"""
import os
import json

BASE = r"H:/GodotProject/momogametest/assets/sprites/enemies"
SCALE = 0.45  # Enemy.gd 里 _sprite.scale 的 0.45（与玩家同比例缩小）

from PIL import Image


def first_frame_bbox(path, frame_w):
    im = Image.open(path).convert("RGBA")
    cell = im.crop((0, 0, frame_w, im.size[1]))
    bb = cell.getbbox()
    return bb


def main():
    results = {}
    for layer in ["layer1", "layer2", "layer3"]:
        d = os.path.join(BASE, layer)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith("_walk_down.png"):
                continue
            fid = fn.replace("_walk_down.png", "")
            p = os.path.join(d, fn)
            im = Image.open(p)
            fw = im.size[0] // 8  # 多方向怪 walk 都是 8 帧（或不足，但第一帧宽 = 总宽/帧数）
            # 帧数不一定是 8，用实际内容带确定第一帧宽
            # 简化：读第一帧用固定 8 帧网格（多数怪是 8 帧）
            bb = first_frame_bbox(p, fw)
            if bb is None:
                results[fid] = {"w": 0, "h": 0, "ox": 0, "oy": 0, "skip": True}
                continue
            w_px = bb[2] - bb[0]
            h_px = bb[3] - bb[1]
            cx_px = (bb[0] + bb[2]) / 2.0
            cy_px = (bb[1] + bb[3]) / 2.0
            # 帧中心
            fcx = fw / 2.0
            fcy = im.size[1] / 2.0
            # 世界单位
            w = round(w_px * SCALE)
            h = round(h_px * SCALE)
            ox = round((cx_px - fcx) * SCALE)
            oy = round((cy_px - fcy) * SCALE)
            results[fid] = {"w": w, "h": h, "ox": ox, "oy": oy}
            print(f"{layer}/{fid}: 帧格{fw}x{im.size[1]} bbox={bb} -> 视觉 {w}x{h} 偏移({ox},{oy})")

    # 输出 GDScript 常量表
    print("\n=== GDScript 碰撞配置（cb 表）===")
    for fid, v in sorted(results.items()):
        if v.get("skip"):
            print(f'  "{fid}": Vector4(0,0,0,0),  # skip')
        else:
            print(f'  "{fid}": Vector4({v["w"]},{v["h"]},{v["ox"]},{v["oy"]}),  # {v["w"]}x{v["h"]} off({v["ox"]},{v["oy"]})')

    with open(os.path.join(os.path.dirname(__file__), "_enemy_collision.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("\n已写入 _enemy_collision.json")


if __name__ == "__main__":
    main()
