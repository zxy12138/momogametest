# -*- coding: utf-8 -*-
"""回滚上一次的出生点 + 灯光改动，恢复到修改前状态。

回滚内容：
1. 灯光：删除 f1_r2.tscn 的 Light_A/B/C 节点 + ext_resource（mask/lflk），删除 mask 图片和 LightFlicker.gd。
2. 出生点：删除 inject_spawns.py v2 注入的 19 个 Spawn 节点（ext_resource id 为 7_spawn_N, N>=1）
   + 对应 ext_resource 行。保留 f1_r1/f2_r1/f3_r0 原有的 Spawn（id 为 4_shhap / 7_spawn）。
3. 删除 LightFlicker.gd / mask.png / inject_lights_f1_r2.py / inject_spawns.py 工具脚本。
"""
import io
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCENES_DIR = os.path.join(ROOT, "src/rooms/scenes")


def rollback_lights_in_f1r2() -> None:
    """从 f1_r2.tscn 删除 Light_A/B/C 节点块 + 灯管 ext_resource。"""
    fname = os.path.join(SCENES_DIR, "f1_r2.tscn")
    if not os.path.exists(fname):
        return
    with io.open(fname, "r", encoding="utf-8") as f:
        content = f.read()
    if "LightFlicker.gd" not in content and "name=\"Light_" not in content:
        print("f1_r2 没有灯光节点，跳过")
        return
    # 删 ext_resource：LightFlicker.gd + mask 图片
    lines = content.split("\n")
    new_lines = []
    for ln in lines:
        if 'path="res://src/fx/LightFlicker.gd"' in ln and ln.startswith("[ext_resource"):
            continue
        if 'path="res://assets/tiles/S_001_2_light_Mask.png"' in ln and ln.startswith("[ext_resource"):
            continue
        new_lines.append(ln)
    content = "\n".join(new_lines)
    # 删 Light_A / Light_B / Light_C 节点块（含子 Sprite）
    # 每个块：[node name="..."] + 属性行 + 可能空行
    for light_name in ["Light_A", "Light_B", "Light_C"]:
        # 删 Light_<X> 节点及整个块（含其子 Sprite）
        pat = re.compile(
            r'\n?\[node name="' + light_name + r'" type="Node2D" parent="\."\].*?(?=\n\[node |\n\[|$)',
            re.S
        )
        content = pat.sub("", content)
        # 删 Light_<X>/Sprite 子节点
        pat2 = re.compile(
            r'\n?\[node name="Sprite" type="Sprite2D" parent="' + light_name + r'"\].*?(?=\n\[node |\n\[|$)',
            re.S
        )
        content = pat2.sub("", content)
    with io.open(fname, "w", encoding="utf-8") as f:
        f.write(content)
    print("已从 f1_r2.tscn 删除 3 个灯管节点 + ext_resource")


def rollback_injected_spawns() -> None:
    """从 22 个房间场景删除 inject_spawns.py v2 注入的 Spawn 节点（id=7_spawn_N, N>=1）+ ext_resource。"""
    # 找出所有 7_spawn_N id（N>=1）被哪些 .tscn 使用，逐个清理
    # v2 注入的 Spawn 节点特征：[node name="Spawn"] + position=Vector2(0, 40) + script=ExtResource("7_spawn_N")
    # 保留：f1_r1（id=4_shhap）, f2_r1 / f3_r0（id=7_spawn, 即 "7_spawn" 不带 _N 后缀）
    v2_ids = []  # 所有 7_spawn_N id
    for fn in sorted(os.listdir(SCENES_DIR)):
        if not fn.endswith(".tscn"):
            continue
        with io.open(os.path.join(SCENES_DIR, fn), "r", encoding="utf-8") as f:
            content = f.read()
        if 'name="Spawn"' in content and 'id="7_spawn_1"' in content:
            # 找所有 7_spawn_N id
            for m in re.finditer(r'\[ext_resource[^\]]*id="(7_spawn_\d+)"', content):
                v2_ids.append((fn, m.group(1)))
    # 清理每个文件的 v2 注入节点
    files_changed = set()
    for fn in sorted(os.listdir(SCENES_DIR)):
        if not fn.endswith(".tscn"):
            continue
        full = os.path.join(SCENES_DIR, fn)
        with io.open(full, "r", encoding="utf-8") as f:
            content = f.read()
        if 'id="7_spawn_1"' not in content:
            continue
        # 收集此文件的 v2 ids
        ids = set(m.group(1) for m in re.finditer(r'id="(7_spawn_\d+)"', content))
        if not ids:
            continue
        original = content
        # 删 ext_resource 行
        for v2_id in ids:
            content = re.sub(
                r'\n?\[ext_resource[^\]]*id="' + re.escape(v2_id) + r'"[^\]]*\]\n?',
                "\n", content
            )
        # 删 Spawn 节点块（script = ExtResource("7_spawn_N") 的那个 Spawn）
        for v2_id in ids:
            content = re.sub(
                r'\n?\[node name="Spawn" type="Node2D" parent="\."\]\nposition = Vector2\([^)]+\)\nscript = ExtResource\("' + re.escape(v2_id) + r'"\)\n?',
                "", content
            )
        if content != original:
            with io.open(full, "w", encoding="utf-8") as f:
                f.write(content)
            files_changed.add(fn)
            print("已从 %s 删除注入的 Spawn（id: %s）" % (fn, ", ".join(sorted(ids))))
    print("回滚 Spawn 完成，共 %d 个文件" % len(files_changed))


def rollback_files() -> None:
    """删除新增文件：LightFlicker.gd、mask 图片、inject 脚本。"""
    targets = [
        os.path.join(ROOT, "src/fx/LightFlicker.gd"),
        os.path.join(ROOT, "assets/tiles/S_001_2_light_Mask.png"),
        os.path.join(ROOT, "assets/tiles/S_001_2_light_Mask.png.import"),
        os.path.join(ROOT, "tools/inject_lights_f1_r2.py"),
    ]
    # inject_spawns.py 保留（用户可能会再用），不删
    for t in targets:
        if os.path.exists(t):
            os.remove(t)
            print("删除文件: %s" % os.path.relpath(t, ROOT))


def main() -> None:
    print("--- 1) 回滚灯光 ---")
    rollback_lights_in_f1r2()
    rollback_files()
    print("\n--- 2) 回滚出生点注入 ---")
    rollback_injected_spawns()
    print("\n--- 完成 ---")


if __name__ == "__main__":
    main()