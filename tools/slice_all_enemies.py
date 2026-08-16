# 《梦境逐影》批量怪物精灵处理工具
# 输入：assets/sprites/enemies/{layer}/F{x}_N_{NNN}.png 多行/单张图（1024×1024 多行动画表 or 单帧图）
# 输出：每怪 5 个动画键对应的精灵条/立绘（walk_down / walk_right / walk_up / attack / dead）
#   - 规整多行动画表（前几行≥80px 高、每行≥6 帧）→ 按行切横条（128×128 帧格）
#   - 否则 → 缩图为 128×128 单帧立绘（所有动画键共享同一文件）
# 所有怪都按统一架构接入 Enemy.gd（patrol 多方向动画选择），但立绘占位怪无真实动画差异
# —— 视觉上各动画显示同一张图（仅动画状态切换有效），后续 SpriteTool 重切可升级。
import os
import shutil
import sys
from PIL import Image

BASE = r"H:/GodotProject/momogametest/assets/sprites/enemies"
ARTSC = r"H:/GodotProject/momogametest/Artssucai/guaiwu"
FRAME = 128
ANIM_KEYS = ["walk_down", "walk_right", "walk_up", "attack", "dead"]


def row_bands(im):
    a = im.split()[3]
    w, h = im.size
    rows = []
    y = 0
    while y < h:
        while y < h and a.crop((0, y, w, y + 1)).getextrema()[1] == 0:
            y += 1
        if y >= h: break
        y0 = y
        while y < h and a.crop((0, y, w, y + 1)).getextrema()[1] > 0:
            y += 1
        rows.append((y0, y - 1))
    return rows


def col_bands(im, y0, y1):
    a = im.split()[3]
    w, _ = im.size
    cols = []
    x = 0
    while x < w:
        while x < w and a.crop((x, y0, x + 1, y1 + 1)).getextrema()[1] == 0:
            x += 1
        if x >= w: break
        x0 = x
        while x < w and a.crop((x, y0, x + 1, y1 + 1)).getextrema()[1] > 0:
            x += 1
        cols.append((x0, x - 1))
    return cols


def make_portrait(im: Image.Image, frame: int = FRAME) -> Image.Image:
    """缩图到底对齐单帧立绘"""
    canvas = Image.new("RGBA", (frame, frame), (0, 0, 0, 0))
    src = im.copy()
    src.thumbnail((frame - 8, frame - 8), Image.LANCZOS)
    x = (frame - src.size[0]) // 2
    y = frame - src.size[1]  # 底部对齐
    canvas.alpha_composite(src, (x, y))
    return canvas


def make_strip_from_row(im: Image.Image, y0: int, y1: int, frame: int = FRAME) -> Image.Image:
    """从精灵表某一行 8 帧切成横向精灵条（128×128 帧格，水平居中+底部对齐）"""
    cols = col_bands(im, y0, y1)
    strip = Image.new("RGBA", (frame * len(cols), frame), (0, 0, 0, 0))
    for i, (cx0, cx1) in enumerate(cols):
        cell = im.crop((cx0, y0, cx1 + 1, y1 + 1))
        bbox = cell.getbbox()
        if bbox is None: continue
        fw, fh = bbox[2] - bbox[0], bbox[3] - bbox[1]
        content = cell.crop(bbox)
        scale = min(120.0 / fw, 120.0 / fh, 1.0)
        nw, nh = max(1, round(fw * scale)), max(1, round(fh * scale))
        content = content.resize((nw, nh), Image.LANCZOS)
        px = (frame - nw) // 2
        py = frame - nh
        strip.paste(content, (i * frame + px, py), content)
    return strip


def is_regular_table(im: Image.Image, min_rows=4, min_cols=6):
    rows = row_bands(im)
    valid = [r for r in rows if (r[1] - r[0] + 1) >= 80]
    if len(valid) < min_rows:
        return False, []
    for r in valid:
        if len(col_bands(im, r[0], r[1])) < min_cols:
            return False, []
    return True, valid


def process_one(layer: str, fkey: str, force_portrait: bool = False):
    """处理一个怪：返回 (id, paths_dict) 或 None（跳过）"""
    src = os.path.join(BASE, layer, f"{fkey}.png")
    if not os.path.exists(src):
        # 从 Artssucai 复制
        src2 = os.path.join(ARTSC, f"{fkey}.png")
        if os.path.exists(src2):
            shutil.copy2(src2, src)
            print(f"  [copy] {fkey} from Artssucai")
        else:
            print(f"  [SKIP] {fkey} 源图缺失")
            return None
    im = Image.open(src).convert("RGBA")
    is_reg, rows = is_regular_table(im)
    use_strip = is_reg and not force_portrait

    paths = {}
    if use_strip:
        # 用前 5 行：down/right/up/attack/dead（与 F1_N_001 行序一致的推测）
        anim_rows = rows[:5]
        if len(anim_rows) < 5:
            use_strip = False
        else:
            for anim, (y0, y1) in zip(ANIM_KEYS, anim_rows):
                strip = make_strip_from_row(im, y0, y1)
                out = os.path.join(BASE, layer, f"{fkey}_{anim}.png")
                strip.save(out)
                paths[anim] = f"{layer}/{fkey}_{anim}.png"
            print(f"  [strip] {fkey}: {len(anim_rows)}行 × {len(col_bands(im, anim_rows[0][0], anim_rows[0][1]))}帧")

    if not use_strip:
        # 立绘占位：所有动画共享单帧立绘
        portrait = make_portrait(im)
        out = os.path.join(BASE, layer, f"{fkey}_portrait.png")
        portrait.save(out)
        for anim in ANIM_KEYS:
            paths[anim] = f"{layer}/{fkey}_portrait.png"
        print(f"  [portrait] {fkey}: {im.size}→{portrait.size}")

    return fkey, paths


# 主流程
ROSTER = {
    "layer1": ["F1_N_001", "F1_N_002", "F1_N_003", "F1_N_004", "F1_N_005"],
    "layer2": ["F2_N_001", "F2_N_002", "F2_N_003", "F2_N_004", "F2_N_005"],
    "layer3": ["F3_N_001", "F3_N_002", "F3_N_003", "F3_N_004", "F3_N_005", "F3_N_006"],
}
# 已知行序（来自 txt）；未列出的按默认"前 5 行 → down/right/up/attack/dead"推断
KNOWN_ROW_ORDER = {
    "F1_N_001": ["walk_down", "walk_right", "walk_up", "attack", "dead"],          # 已实现
    "F1_N_002": ["walk_down", "walk_right", "walk_up", "dead", "attack", "idle"],   # 6行
    "F1_N_003": ["walk_down", "walk_right", "walk_up", "dead", "attack"],          # 5行
    "F1_N_004": ["walk_down", "walk_right", "walk_up", "attack", "dead"],          # 行4=attack远程,行6=fx
}
# F1_N_001 跳过（已切），其他按 KNOWN_ROW_ORDER 行序映射
# F2/F3 全部未知 → 用默认推断（前 5 行 → walk_down/right/up/attack/dead）

results = {}
for layer, ids in ROSTER.items():
    print(f"=== {layer} ===")
    for fkey in ids:
        if fkey == "F1_N_001":
            # 已切片（之前的工作），直接构造路径
            paths = {a: f"{layer}/F1_N_001_{a}.png" for a in ANIM_KEYS}
            results[fkey] = paths
            print(f"  [skip] F1_N_001 已切片")
            continue
        r = process_one(layer, fkey)
        if r:
            results[fkey[0]] = r[1]

print("\n=== 数据摘要 ===")
for fid in sorted(results.keys()):
    p = results[fid]
    same = len(set(p.values())) == 1
    tag = "立绘占位" if same else "完整动画"
    print(f"  {fid}: {tag}  keys={list(p.keys())}")

# 输出 GDScript DATA 片段（供手动粘贴到 Enemies.gd）
print("\n=== GDScript DATA 片段 ===")
for fid in sorted(results.keys()):
    p = results[fid]
    layer = "E1" if fid.startswith("F1") else ("E2" if fid.startswith("F2") else "E3")
    parts = []
    for anim in ANIM_KEYS:
        parts.append(f"{anim}={layer}+\"{p[anim]}\"")
    print(f'"{fid.lower().replace("_","_")}": {{ name="...", layer={layer[1]}, behavior="patrol", hp=..., xp=..., speed=..., contact_dmg=..., fw=128, fh=128, fwk=1, fa=1, fd=1, atk_range=80, atk_cd=1.2, {", ".join(parts)} }},')