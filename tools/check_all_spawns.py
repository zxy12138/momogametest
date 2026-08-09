# -*- coding: utf-8 -*-
"""全量检查：模拟每个房间场景的 safe_spawn_position，确认从地图任意跳转都不会出生在禁区。

遍历 src/rooms/scenes/*.tscn，解析 SpawnPointHandle / DoorHandle / BlockedHandle
（多边形 points 与矩形 rect_size 都支持），用与 GDScript 相同的碰撞体级检测，
输出每个房间的最终出生点结论。任何房间"找不到安全点"都会标红。
"""
import io
import math
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
W, H = 880.0, 500.0
PLAYER_R = 16.0


def parse_room(fname):
    """返回 (spawns, doors, blocked)，其中 blocked = [(cx, cy, shape, is_rect), ...]"""
    content = io.open(fname, encoding="utf-8").read()
    # ext_resource id -> path 映射（node 块里只有 script = ExtResource("id")；path 在 id 之前）
    res_map = {}
    for m in re.finditer(r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', content):
        res_map[m.group(2)] = m.group(1)
    spawns, doors, blocked = [], [], []
    blocks = re.split(r"(?=\[node )", content)
    for blk in blocks:
        if not blk.startswith("[node "):
            continue
        pos_m = re.search(r"position = Vector2\(([-+\d.eE]+), ([-+\d.eE]+)\)", blk)
        pos = (float(pos_m.group(1)), float(pos_m.group(2))) if pos_m else (0.0, 0.0)
        scr_m = re.search(r'script = ExtResource\("([^"]+)"\)', blk)
        scr_path = res_map.get(scr_m.group(1), "") if scr_m else ""
        if "SpawnPointHandle.gd" in scr_path:
            spawns.append(pos)
        elif "DoorHandle.gd" in scr_path:
            t_m = re.search(r'target = "([^"]+)"', blk)
            doors.append((pos, t_m.group(1) if t_m else ""))
        elif "BlockedHandle.gd" in scr_path:
            pts_m = re.search(r"points = PackedVector2Array\((.*?)\)", blk, re.S)
            rect_m = re.search(r"rect_size = Vector2\(([-\d.]+), ([-\d.]+)\)", blk)
            if pts_m and pts_m.group(1).strip():
                # 支持科学计数法（如 3.673819e-15，用户拖拽产生的微小值）
                nums = [float(x) for x in re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", pts_m.group(1))]
                pts = [(nums[i], nums[i + 1]) for i in range(0, len(nums), 2)]
                blocked.append((pos[0], pos[1], pts, False))
            elif rect_m:
                w = float(rect_m.group(1))
                h = float(rect_m.group(2))
                blocked.append((pos[0], pos[1], (w, h), True))
    return spawns, doors, blocked


def point_in_polygon(px, py, pts):
    inside = False
    n = len(pts)
    j = n - 1
    for i in range(n):
        ax, ay = pts[i]
        bx, by = pts[j]
        if (ay > py) != (by > py):
            x_int = ax + (py - ay) * (bx - ax) / (by - ay)
            if px < x_int:
                inside = not inside
        j = i
    return inside


def point_blocked(x, y, blocked):
    for cx, cy, shape, is_rect in blocked:
        lx, ly = x - cx, y - cy
        if is_rect:
            w, h = shape
            if abs(lx) <= w * 0.5 and abs(ly) <= h * 0.5:
                return True
        else:
            if point_in_polygon(lx, ly, shape):
                return True
    return False


def is_safe(x, y, blocked):
    if x < -W * 0.5 + PLAYER_R or x > W * 0.5 - PLAYER_R or y < -H * 0.5 + PLAYER_R or y > H * 0.5 - PLAYER_R:
        return False
    offs = [
        (0.0, 0.0), (PLAYER_R, 0.0), (-PLAYER_R, 0.0), (0.0, PLAYER_R), (0.0, -PLAYER_R),
        (PLAYER_R * 0.7, PLAYER_R * 0.7), (-PLAYER_R * 0.7, PLAYER_R * 0.7),
        (PLAYER_R * 0.7, -PLAYER_R * 0.7), (-PLAYER_R * 0.7, -PLAYER_R * 0.7),
    ]
    for ox, oy in offs:
        if point_blocked(x + ox, y + oy, blocked):
            return False
    return True


def safe_spawn(spawns, doors, blocked):
    """与 GDScript safe_spawn_position 相同的优先级。"""
    if spawns and is_safe(*spawns[0], blocked):
        return "Spawn 手柄 (%d,%d)" % (spawns[0][0], spawns[0][1])
    if doors and is_safe(*doors[0][0], blocked):
        return "门 %s (%d,%d)" % (doors[0][1], doors[0][0][0], doors[0][0][1])
    fallback = (0.0, H * 0.5 - 60.0)
    if is_safe(*fallback, blocked):
        return "底部安全区 (%d,%d)" % fallback
    candidate = spawns[0] if spawns else fallback
    for radius in range(16, int(max(W, H)), 16):
        for k in range(8):
            ang = math.radians(45.0 * k)
            p = (candidate[0] + math.cos(ang) * radius, candidate[1] + math.sin(ang) * radius)
            if is_safe(*p, blocked):
                return "螺旋搜索 (%d,%d)" % (p[0], p[1])
    gy_max, gx_max = int(H * 0.5 - PLAYER_R), int(W * 0.5 - PLAYER_R)
    for gy in range(-gy_max, gy_max + 1, 16):
        for gx in range(-gx_max, gx_max + 1, 16):
            if is_safe(gx, gy, blocked):
                return "全房间扫描 (%d,%d)" % (gx, gy)
    return "X 找不到安全点！"


def main():
    scenes_dir = os.path.join(ROOT, "src/rooms/scenes")
    files = sorted(f for f in os.listdir(scenes_dir) if f.endswith(".tscn"))
    bad = []
    print("%-12s %-5s %-3s %-4s 出生点" % ("房间", "禁区", "门", "Spawn"))
    print("-" * 80)
    for fn in files:
        spawns, doors, blocked = parse_room(os.path.join(scenes_dir, fn))
        result = safe_spawn(spawns, doors, blocked)
        flag = " <-- 有问题" if result.startswith("X") else ""
        print("%-12s %-5d %-3d %-4d %s%s" % (fn, len(blocked), len(doors), len(spawns), result, flag))
        if flag:
            bad.append(fn)
    print("-" * 80)
    if bad:
        print("X 有问题的房间: %s" % bad)
        sys.exit(1)
    print("OK 全部房间都能找到安全出生点")


if __name__ == "__main__":
    main()
