# -*- coding: utf-8 -*-
"""给所有缺失出生点手柄的 start 房预置 SpawnPointHandle。

背景：从地图任意跳转 / 跨层 / 首进时走 safe_spawn_position；
有 Spawn 手柄的房出生在 Spawn（用户可控），无 Spawn 的房走门/兜底。
这里给所有 22 个房间都注入默认 SpawnPointHandle（位置 (0,40)，运行期 safe_spawn_position
会自动校验/避让禁区；用户可在编辑器中拖到想要的位置），保证每个房间都有「出生点」控件。
"""
import io
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SPAWN_SCRIPT = "res://src/rooms/handles/SpawnPointHandle.gd"
SPAWN_UID = "uid://xare6cnk2cgh"
SCENES_DIR = os.path.join(ROOT, "src/rooms/scenes")


def find_unique_ext_id(content: str) -> str:
    """在 content 中找未占用的 ext_resource id，返回 \"7_spawn\" 形式。"""
    used = set()
    for m in __import__("re").finditer(r'\[ext_resource[^\]]*id="([^"]+)"', content):
        used.add(m.group(1))
    n = 1
    while True:
        cand = "7_spawn_%d" % n
        if cand not in used:
            return cand
        n += 1


def ensure_spawn(fname: str) -> None:
    with io.open(fname, "r", encoding="utf-8") as f:
        content = f.read()
    # 已有 Spawn 节点（name="Spawn" 或 SpawnPointHandle.gd 引用）跳过
    if "SpawnPointHandle.gd" in content or 'name="Spawn"' in content:
        return
    # 找最后一个 ext_resource 行，插入新 ext_resource
    idx = content.rfind("[ext_resource ")
    if idx < 0:
        print("  -> 无 ext_resource 块，跳过")
        return
    nl = content.find("\n", idx)
    new_id = find_unique_ext_id(content)
    ext_line = '\n[ext_resource type="Script" uid="%s" path="%s" id="%s"]' % (SPAWN_UID, SPAWN_SCRIPT, new_id)
    content = content[:nl] + ext_line + content[nl:]
    # 追加 Spawn 节点到末尾
    content += (
        '\n[node name="Spawn" type="Node2D" parent="."]\n'
        "position = Vector2(0, 40)\n"
        'script = ExtResource("%s")\n' % new_id
    )
    with io.open(fname, "w", encoding="utf-8") as f:
        f.write(content)


def main() -> None:
    files = sorted(f for f in os.listdir(SCENES_DIR) if f.endswith(".tscn"))
    injected = 0
    skipped = 0
    for fn in files:
        full = os.path.join(SCENES_DIR, fn)
        before = open(full, encoding="utf-8").read()
        if "SpawnPointHandle.gd" in before or 'name="Spawn"' in before:
            print("%-12s 已有 Spawn，跳过" % fn)
            skipped += 1
            continue
        ensure_spawn(full)
        print("%-12s 已注入 SpawnPointHandle（(0,40)，运行期自动避让禁区）" % fn)
        injected += 1
    print("--- 注入 %d / 跳过 %d / 总 %d ---" % (injected, skipped, len(files)))


if __name__ == "__main__":
    main()