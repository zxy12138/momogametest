# -*- coding: utf-8 -*-
# 统计所有房间场景的 BlockedHandle：每个 Blocked 节点的 PolygonPointHandle 子节点数
import io
import re
import os

os.chdir('H:/GodotProject/momogametest')

for fname in sorted(os.listdir('src/rooms/scenes')):
    if not fname.endswith('.tscn'):
        continue
    path = os.path.join('src/rooms/scenes', fname)
    with io.open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    if 'BlockedHandle.gd' not in content:
        continue
    # 所有 [node 块
    blocks = re.split(r'\n(?=\[node)', content)
    blocked = []
    for b in blocks:
        m = re.match(r'\[node name="([^"]+)" type="Node2D" parent="\.?"', b)
        if not m:
            continue
        name = m.group(1)
        # 找这个节点的 script 是否指向 BlockedHandle：往下找 script = ExtResource("X")，再查 X 对应 ext_resource
        # 简化：Blocked 节点的子节点是 @Node2D@xxx parent="Blocked..."（PolygonPointHandle）
        if not name.startswith('Blocked'):
            continue
        kids = len(re.findall(r'parent="%s"' % re.escape(name), b))
        pts = re.search(r'points\s*=\s*PackedVector2Array\(([^)]*)\)', b)
        np = len([x for x in pts.group(1).split(',') if x.strip()]) // 2 if pts else 0
        blocked.append((name, kids, np))
    if not blocked:
        print(fname, '有 BlockedHandle 引用但无 Blocked 节点！')
        continue
    # 汇总：缺点的（<3）
    bad = [n for n, k, p in blocked if k < 3 and p < 3]
    print('%s: %d 个 Blocked；缺点(<3): %s' % (fname, len(blocked), bad if bad else '无'))
