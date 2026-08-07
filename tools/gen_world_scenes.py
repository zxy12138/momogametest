# -*- coding: utf-8 -*-
"""生成场景化关卡文件：
1) src/rooms/scenes/f{层}_{房}.tscn —— 24 个房间场景（RoomManager + 导出 layer/room_id）
2) src/rooms/worlds/Layer{1,2,3}.tscn —— 3 个世界场景（房间锚点按 LevelData.pos 摆布 + Ghost 占位框 + 邻居连线）
3) src/rooms/worlds/Layer.gd —— 运行时隐藏占位框/连线的脚本

数据源：src/data/LevelData.gd（GDScript 字面量，正则解析 rooms 的 pos/neighbors/type）。
UID 规则：不手写 UID——ext_resource 只写 path（Godot 4.7 自动匹配 .uid）；场景头不写 uid（引擎自动生成）。
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LEVELDATA = os.path.join(ROOT, "src", "data", "LevelData.gd")
ROOM_MGR_SCRIPT = "res://src/rooms/RoomManager.gd"
LAYER_SCRIPT = "res://src/rooms/worlds/Layer.gd"


def read_uid(script_res_path):
    """从脚本同名的 .uid 文件读真实 UID（不手写）；不存在则返回 ''（省略 uid）。"""
    rel = script_res_path.replace("res://", "").replace("/", os.sep)
    uid_file = os.path.join(ROOT, rel + ".uid")
    if os.path.exists(uid_file):
        with open(uid_file, encoding="utf-8") as fp:
            return fp.read().strip()
    return ""
ROOM_SCENES_DIR = os.path.join(ROOT, "src", "rooms", "scenes")
WORLDS_DIR = os.path.join(ROOT, "src", "rooms", "worlds")

# 世界坐标摆布：pos 归一化 [0,1] -> 世界像素。房间 880x500。
# 归一化差 0.15 至少要对应 900px（880 宽 + 空隙），0.25 对应 560px（500 高 + 空隙），
# 否则相邻房间框会重叠。故 scale = 900/0.15 = 6000, 560/0.25 = 2240。
SPACING = (6000.0, 2240.0)


def parse_layers():
    """从 LevelData.gd 解析 LAYERS = {1: {rooms: {"r1": {...}, ...}}, ...} 的结构。"""
    src = open(LEVELDATA, encoding="utf-8").read()
    # 提取每个 "rX": {type=..., pos=[..], neighbors=[..], ...} 条目（含跨行，简化：假设单行或多行都按括号匹配）
    layers = {}
    # 先按层块切分：找到 LAYERS = { 后的每个 数字: { 块
    layers_body = src.split("const LAYERS = {", 1)[1].split("const TILES", 1)[0]
    # 层块：^\t(\d+): \{ ... \n\t\}  （用括号计数取平衡块）
    layer_pat = re.compile(r"^\s*(\d+):\s*\{(.*?)^\s*\}", re.S | re.M)
    for lm in layer_pat.finditer(layers_body):
        fid = int(lm.group(1))
        body = lm.group(2)
        rooms = {}
        # 房间条目："rX": { ... }，
        room_pat = re.compile(r'"(\w+)":\s*\{(.*?)\},?\n', re.S)
        for rm in room_pat.finditer(body + "\n"):
            rid = rm.group(1)
            rbody = rm.group(2)
            fields = {}
            # type / boss / pos / neighbors / boss_intro_img / boss_intro_time
            m = re.search(r'type\s*=\s*"([^"]+)"', rbody)
            fields["type"] = m.group(1) if m else "combat"
            m = re.search(r'pos\s*=\s*\[([^\]]+)\]', rbody)
            if m:
                nums = [float(x.strip()) for x in m.group(1).split(",")]
                fields["pos"] = nums
            else:
                fields["pos"] = [0.5, 0.5]
            m = re.search(r'neighbors\s*=\s*\[([^\]]*)\]', rbody)
            fields["neighbors"] = [x.strip().strip('"') for x in m.group(1).split(",")] if m and m.group(1).strip() else []
            m = re.search(r'boss\s*=\s*"([^"]+)"', rbody)
            fields["boss"] = m.group(1) if m else ""
            m = re.search(r'boss_intro_img\s*=\s*"([^"]+)"', rbody)
            fields["boss_intro_img"] = m.group(1) if m else ""
            m = re.search(r'boss_intro_time\s*=\s*([\d.]+)', rbody)
            fields["boss_intro_time"] = float(m.group(1)) if m else 0.0
            rooms[rid] = fields
        layers[fid] = rooms
    return layers


def room_scene(fid, rid):
    """单个房间场景内容。ext_resource 从 .uid 文件读真实 UID（不手写）。
    必须包含 Floor 子节点：RoomManager._build_floor 会 get_node("Floor")（现已加防御，但规范起见保留）。"""
    uid = read_uid(ROOM_MGR_SCRIPT)
    uid_part = (' uid="%s"' % uid) if uid else ""
    return (
        "[gd_scene load_steps=2 format=3]\n"
        "\n"
        '[ext_resource type="Script"%s path="%s" id="1"]\n'
        "\n"
        '[node name="Room" type="Node2D"]\n'
        "script = ExtResource(\"1\")\n"
        "layer = %d\n"
        'room_id = "%s"\n'
        "\n"
        '[node name="Floor" type="TextureRect" parent="."]\n' % (uid_part, ROOM_MGR_SCRIPT, fid, rid)
    )


def ghost_block(rid, title):
    """锚点下的占位块：边框 + 房间名（去掉 Bg 半透明蓝填充，避免编辑器里像盖了一层滤镜）。
    运行时由 Layer.gd 隐藏。注意：.tscn 的 parent 必须是【相对场景根的路径】（不带根节点名），
    写成 "Layer1/r1/Ghost" 这类绝对路径会导致实例化报 "Parent path ... has vanished"。
    """
    return (
        '[node name="Ghost" type="Node2D" parent="%s"]\n'
        'groups=["layer_ghost"]\n'
        "\n"
        '[node name="Title" type="Label" parent="%s/Ghost"]\n'
        'text = "%s"\n'
        'position = Vector2(-56, -10)\n'
        'add_theme_font_size_override("font_size", 20)\n'
        'add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))\n'
        "\n"
        '[node name="Frame" type="Line2D" parent="%s/Ghost"]\n'
        'points = PackedVector2Array(-440, -250, 440, -250, 440, 250, -440, 250, -440, -250)\n'
        'width = 3\n'
        'default_color = Color(0.65, 0.82, 1.0, 0.55)\n'
        "\n" % (rid, rid, title, rid)
    )


def world_scene(fid, rooms, links):
    """世界场景：根 + Layer.gd + 锚点 + Ghost 占位 + 邻居连线。"""
    uid = read_uid(LAYER_SCRIPT)
    uid_part = (' uid="%s"' % uid) if uid else ""
    lines = []
    lines.append("[gd_scene load_steps=2 format=3]")
    lines.append("")
    lines.append('[ext_resource type="Script"%s path="%s" id="1"]' % (uid_part, LAYER_SCRIPT))
    lines.append("")
    lines.append('[node name="Layer%d" type="Node2D"]' % fid)
    lines.append('script = ExtResource("1")')
    lines.append("")
    type_names = {"start": "起点", "combat": "战斗", "elite": "精英", "inn": "驿站", "boss": "BOSS"}
    for rid, f in sorted(rooms.items()):
        px, py = f["pos"][0], f["pos"][1]
        wx, wy = px * SPACING[0], py * SPACING[1]
        lines.append('[node name="%s" type="Node2D" parent="."]' % rid)
        lines.append("position = Vector2(%.1f, %.1f)" % (wx, wy))
        lines.append("")
        title = "%s · %s" % (rid, type_names.get(f["type"], f["type"]))
        lines.append(ghost_block(rid, title).rstrip("\n"))
    # 邻居连线已按用户要求取消（2026-08-07）：世界场景只保留房间锚点+占位框，不再画连线。
    return "\n".join(lines)


def main():
    layers = parse_layers()
    print("解析到层:", {f: sorted(r.keys()) for f, r in layers.items()})

    os.makedirs(ROOM_SCENES_DIR, exist_ok=True)
    os.makedirs(WORLDS_DIR, exist_ok=True)

    # 1) 房间场景
    for fid, rooms in layers.items():
        for rid in rooms.keys():
            path = os.path.join(ROOM_SCENES_DIR, "f%d_%s.tscn" % (fid, rid))
            with open(path, "w", encoding="utf-8", newline="\n") as fp:
                fp.write(room_scene(fid, rid))

    # 2) 世界场景
    for fid, rooms in layers.items():
        links = []
        for rid, f in rooms.items():
            for nb in f["neighbors"]:
                links.append((rid, nb))
        path = os.path.join(WORLDS_DIR, "Layer%d.tscn" % fid)
        with open(path, "w", encoding="utf-8", newline="\n") as fp:
            fp.write(world_scene(fid, rooms, links))

    # 3) Layer.gd
    layer_gd = os.path.join(WORLDS_DIR, "Layer.gd")
    with open(layer_gd, "w", encoding="utf-8", newline="\n") as fp:
        fp.write(
            "# 世界场景（整层关卡总览）根脚本。\n"
            "# 编辑器里：锚点占位框(Ghost)与邻居连线可见，直观看到整层房间拓扑。\n"
            "# 运行时：隐藏占位框与连线（真实房间内容由 Game 在锚点下实例化），避免遮挡。\n"
            "@tool\n"
            "extends Node2D\n"
            "\n"
            "func _ready() -> void:\n"
            "\tif Engine.is_editor_hint():\n"
            "\t\treturn\n"
            "\tfor n in get_tree().get_nodes_in_group(\"layer_ghost\"):\n"
            "\t\tn.visible = false\n"
        )

    print("房间场景:", len(os.listdir(ROOM_SCENES_DIR)), "个")
    print("世界场景:", sorted(f for f in os.listdir(WORLDS_DIR) if f.startswith("Layer") and f.endswith(".tscn")))


if __name__ == "__main__":
    main()
