# -*- coding: utf-8 -*-
"""模拟 RoomManager.safe_spawn_position 在 f3_r0 上的行为（静态验证，不需要 Godot）。

解析 f3_r0.tscn 的 BlockedHandle（position + points），用与 GDScript 相同的
射线法/矩形 AABB 检测，输出：(0,40) Spawn 点是否安全、螺旋搜索/全房间扫描最终出生点。
"""
import io
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
W, H = 880.0, 500.0


def parse_blocked(fname: str):
    """返回 [(center_x, center_y, points_list), ...]"""
    content = io.open(fname, encoding="utf-8").read()
    blocks = []
    # 每个 BlockedHandle 节点块：node 行 + position + points（子节点 PolygonPointHandle 忽略）
    node_re = re.compile(
        r'\[node name="([^"]+)" type="Node2D" parent="\." [^\]]*\]\n'
        r'(?:position = Vector2\(([-\d.]+), ([-\d.]+)\)\n)?'
        r'(?:script = ExtResource\("[^"]+"\)\n)?'
        r'(?:points = PackedVector2Array\((.*?)\)\n)?',
        re.S,
    )
    for m in node_re.finditer(content):
        name = m.group(1)
        cx = float(m.group(2)) if m.group(2) else 0.0
        cy = float(m.group(3)) if m.group(3) else 0.0
        pts_raw = m.group(4)
        pts = []
        if pts_raw:
            nums = [float(x) for x in re.findall(r"[-\d.]+", pts_raw)]
            pts = [(nums[i], nums[i + 1]) for i in range(0, len(nums), 2)]
        if name in ("Room", "Floor"):
            continue
        if pts:
            blocks.append((cx, cy, pts))
    return blocks


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


def is_safe(x, y, blocks):
    """碰撞体级检测：中心 + 8 方向采样点全部不在禁区内（与 GDScript _is_spawn_safe 一致）。"""
    PLAYER_R = 16.0
    if x < -W * 0.5 + PLAYER_R or x > W * 0.5 - PLAYER_R or y < -H * 0.5 + PLAYER_R or y > H * 0.5 - PLAYER_R:
        return False
    offs = [
        (0.0, 0.0), (PLAYER_R, 0.0), (-PLAYER_R, 0.0), (0.0, PLAYER_R), (0.0, -PLAYER_R),
        (PLAYER_R * 0.7, PLAYER_R * 0.7), (-PLAYER_R * 0.7, PLAYER_R * 0.7),
        (PLAYER_R * 0.7, -PLAYER_R * 0.7), (-PLAYER_R * 0.7, -PLAYER_R * 0.7),
    ]
    for ox, oy in offs:
        sx, sy = x + ox, y + oy
        for cx, cy, pts in blocks:
            lx, ly = sx - cx, sy - cy
            if point_in_polygon(lx, ly, pts):
                return False
    return True


def safe_spawn_position(blocks):
    """与 GDScript safe_spawn_position 相同策略。"""
    candidate = (0.0, 40.0)  # Spawn 手柄位置
    if candidate[0] != 0.0 or candidate[1] != 0.0:
        if is_safe(*candidate, blocks):
            return f"Spawn 手柄位置 {candidate}"
    fallback = (0.0, H * 0.5 - 60.0)
    if is_safe(*fallback, blocks):
        return f"底部预置安全区 {fallback}"
    if candidate == (0.0, 0.0):
        candidate = fallback
    import math
    for radius in range(16, int(max(W, H)), 16):
        for k in range(8):
            ang = math.radians(45.0 * k)
            p = (candidate[0] + math.cos(ang) * radius, candidate[1] + math.sin(ang) * radius)
            if is_safe(*p, blocks):
                return f"螺旋搜索命中 ({p[0]:.0f}, {p[1]:.0f}) 半径={radius}"
    gy_max, gx_max = int(H * 0.5 - 16.0), int(W * 0.5 - 16.0)
    for gy in range(-gy_max, gy_max + 1, 16):
        for gx in range(-gx_max, gx_max + 1, 16):
            if is_safe(gx, gy, blocks):
                return f"全房间扫描命中 ({gx}, {gy})"
    return f"未找到（异常）→ 兜底 {fallback}"


def main():
    fname = os.path.join(ROOT, "src/rooms/scenes/f3_r0.tscn")
    blocks = parse_blocked(fname)
    print(f"解析到 {len(blocks)} 个 BlockedHandle")
    print(f"Spawn (0,40) 碰撞体级安全: {is_safe(0.0, 40.0, blocks)}")
    print(f"房间中心 (0,0) 碰撞体级安全: {is_safe(0.0, 0.0, blocks)}")
    print(f"底部 (0,{H*0.5-60}) 碰撞体级安全: {is_safe(0.0, H*0.5-60.0, blocks)}")
    print(f"→ 最终出生点: {safe_spawn_position(blocks)}")


if __name__ == "__main__":
    main()
