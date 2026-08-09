# -*- coding: utf-8 -*-
import io
import re
import os

os.chdir('H:/GodotProject/momogametest')

BOSS_SCRIPT = 'res://src/rooms/handles/BossHandle.gd'
TARGETS = [
    ('src/rooms/scenes/f1_r7.tscn', 0),  # b_director
    ('src/rooms/scenes/f2_r7.tscn', 1),  # b_train
    ('src/rooms/scenes/f3_r7.tscn', 2),  # b_fear
]

for fname, btype in TARGETS:
    with io.open(fname, 'r', encoding='utf-8') as f:
        content = f.read()
    if 'BossHandle.gd' in content:
        print(fname, '已有 BossHandle，跳过')
        continue
    # load_steps +1（若存在；Godot 重写过的场景头可能没有 load_steps）
    m_ls = re.search(r'load_steps=(\d+)', content)
    if m_ls:
        content = content.replace('load_steps=%s' % m_ls.group(1), 'load_steps=%d' % (int(m_ls.group(1)) + 1))
    # 追加 ext_resource（id = max+1；无 uid——新脚本未被 Godot 扫描，由引擎补）
    ids = [int(m) for m in re.findall(r' id="(\d+)"', content)]
    new_id = (max(ids) + 1) if ids else 2
    first_ext = re.search(r'\[ext_resource[^\]]+\]', content).group(0)
    new_ext = '[ext_resource type="Script" path="%s" id="%d"]' % (BOSS_SCRIPT, new_id)
    content = content.replace(first_ext, first_ext + '\n' + new_ext)
    # 追加 Boss 节点（默认位置房间顶部偏下）
    content += '\n[node name="Boss" type="Node2D" parent="."]\nscript = ExtResource("%d")\nposition = Vector2(0, -60)\nboss_type = %d\n' % (new_id, btype)
    with io.open(fname, 'w', encoding='utf-8') as f:
        f.write(content)
    print(fname, '已注入 BossHandle（boss_type=%d）' % btype)

print('--- done ---')
