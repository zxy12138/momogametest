# -*- coding: utf-8 -*-
import io
import re
import os

os.chdir('H:/GodotProject/momogametest')

# 解析 LevelData.gd 提取 LAYERS 中每房 neighbors
src = open('src/data/LevelData.gd', encoding='utf-8').read()
pat = re.compile(r'"(r\d+)":\s*\{type="(\w+)",[^}]*neighbors=\[([^\]]*)\]')
layout = {1: {}, 2: {}, 3: {}}
cur_layer = 0
for line in src.splitlines():
    m_lay = re.match(r'\s*(\d+):\s*\{', line)
    if m_lay:
        cur_layer = int(m_lay.group(1))
        continue
    if cur_layer == 0:
        continue
    m_room = pat.search(line)
    if m_room:
        rid, rtype, neigh_str = m_room.group(1), m_room.group(2), m_room.group(3)
        neighs = re.findall(r'"(r\d+)"', neigh_str)
        layout[cur_layer][rid] = {'type': rtype, 'neighbors': neighs}

# 边对应位置（与 RoomManager._build_doors 默认 edges 一致）
# 0=top, 1=bottom, 2=left, 3=right
EDGES = [
    (0.0, -224.0),   # top
    (0.0,  224.0),   # bottom
    (-414.0, 0.0),   # left
    (414.0, 0.0),    # right
]
SCENE_PATH = 'res://src/rooms/handles/DoorHandle.gd'
SCENE_UID = 'uid://dlvob655ashqj'

count = 0
for layer, rooms in layout.items():
    for rid, info in rooms.items():
        if rid == 'r7':
            continue  # boss 房不预置门（走 NextDoorHandle）
        fname = 'src/rooms/scenes/f%d_%s.tscn' % (layer, rid)
        with io.open(fname, 'r', encoding='utf-8') as f:
            content = f.read()
        if 'path="res://src/rooms/handles/DoorHandle.gd"' in content or '[node name="Door_' in content:
            print(fname, '已有 DoorHandle，跳过')
            continue
        # load_steps +1
        old_ls = re.search(r'load_steps=(\d+)', content).group(1)
        new_ls = int(old_ls) + 1
        content = content.replace('load_steps=%s' % old_ls, 'load_steps=%d' % new_ls)
        # 追加 ext_resource（id 用 max+1）
        ids = [int(m) for m in re.findall(r' id="(\d+)"', content)]
        new_id = max(ids) + 1
        first_ext = re.search(r'\[ext_resource[^\]]+\]', content).group(0)
        new_ext = '[ext_resource type="Script" uid="%s" path="%s" id="%d"]' % (SCENE_UID, SCENE_PATH, new_id)
        content = content.replace(first_ext, first_ext + '\n' + new_ext)
        # 追加 DoorHandle 节点
        for i, nid in enumerate(info['neighbors']):
            if i >= len(EDGES):
                break
            px, py = EDGES[i]
            content += '\n[node name="Door_%s" type="Node2D" parent="."]\nscript = ExtResource("%d")\nposition = Vector2(%.1f, %.1f)\ntarget = "%s"\nlayer = %d\n' % (nid, new_id, px, py, nid, layer)
        with io.open(fname, 'w', encoding='utf-8') as f:
            f.write(content)
        count += 1
        print(fname, '已注入 %d 个门' % len(info['neighbors']))

print('---')
print('共修改 %d 个房间场景' % count)
