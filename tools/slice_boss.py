# 《梦境逐影》Boss 多形态切片工具（2026-08-16）
# 输入：assets/sprites/bosses/{layer}/F{x}_B_{NNN}.png（1024×1024 或 1024×1224 多行动画表）
# 输出：同目录下 {fid}_{anim}.png 横向精灵条（每帧缩放到 FRAME 高度，宽自适应居中）
#       + {fid}_proj.png 弹道贴图（多帧横向条，供 Projectile 随机选帧/轮播）
#       + {fid}_transform.png 变身动画（Anime 大图切帧缩放到 FRAME，供 SpriteFrames）
# 规则：
#   - 行带检测：每行 alpha>60 计数阈值
#   - 帧切分：用户提供每行帧数（最可靠），按帧间距均匀切 + 内容带自适应
#   - F1_B_001 行5+行6 = 冲撞攻击 8 帧（两行各 4 帧拼成一个动作）
#   - 单向反向：walk_right/attack/dead/melee 镜像生成 *_left
import os
import sys
import statistics
from PIL import Image

SRC = r"H:/GodotProject/momogametest/assets/sprites/bosses"
FRAME = 192          # 输出帧格（boss 用大帧格；内容缩放后统一 192 高，宽自适应居中）
ALPHA_THRESH = 60    # 行带检测阈值

# 每 boss 行序（行号(1起) -> 动画键）与每行帧数
# 帧数来自用户 2026-08-16 提供的说明
ROWS = {
    "F1_B_001": {1: ("walk_up", 6), 2: ("walk_down", 6), 3: ("walk_right", 5),
                 4: ("attack", 2), 5: ("charge_p1", 4), 6: ("charge_p2", 4)},
    "F1_B_002": {1: ("walk_down", 8), 2: ("walk_up", 8), 3: ("walk_right", 8),
                 4: ("dead", 8), 5: ("attack", 8), 6: ("melee", 8),
                 7: ("idle", 8), 8: ("proj", 2)},
    "F2_B_001": {1: ("walk_down", 8), 2: ("walk_up", 8), 3: ("walk_right", 8),
                 4: ("melee", 8), 5: ("attack", 8), 6: ("proj", 1), 7: ("idle", 8)},
    "F2_B_002": {1: ("idle", 8), 2: ("walk_up", 8), 3: ("walk_down", 8),
                 4: ("walk_right", 8), 5: ("dead", 8), 6: ("melee", 8),
                 7: ("attack", 7), 8: ("proj", 1)},
    "F3_B_001": {1: ("walk_down", 12), 2: ("walk_up", 12), 3: ("walk_right", 12),
                 4: ("idle", 10), 5: ("melee", 10)},
    "F3_B_002": {1: ("idle", 10), 2: ("walk_down", 10), 3: ("walk_up", 10),
                 4: ("walk_right", 10), 5: ("melee", 10), 6: ("attack", 6),
                 7: ("dead", 10), 8: ("proj", 3)},
}
LAYER_OF = {fid: ("layer1" if fid.startswith("F1") else "layer2" if fid.startswith("F2") else "layer3") for fid in ROWS}

# 变身动画配置：{fid: (json路径, 输出帧数)}（Anime 大图）
TRANSFORM = {
    "F1_B_001": "F1_B_001Anime.json",
    "F2_B_001": "F2_B_001Anime.json",
    "F3_B_001": "F3_B_001Anime.json",
}

# 冲撞动作：F1_B_001 行5+行6 拼成 8 帧 charge
MERGE_CHARGE = {"F1_B_001": ("charge_p1", "charge_p2", "charge", 8)}

# 行带覆盖（自动检测合并/漏检时手动指定 y 范围）：{fid: {行号: (y0, y1)}}
# F2_B_002：行5(死亡)与行6(踢人)间隙仅 ~1px，自动检测合并成 599~872 —— 提供完整 8 行映射
ROW_OVERRIDES = {
    "F2_B_002": {1: (20, 156), 2: (166, 300), 3: (310, 447), 4: (456, 595),
                 5: (599, 727), 6: (728, 873), 7: (878, 1021), 8: (1052, 1178)},
}

# 弹道行用户指定帧数（内容带数量可能含 1px 碎片导致检测不符）：{fid: 帧数}
# F3_B_002 行8 光弹 3 帧（用户明确：随机选 1 帧发射）；F1_B_002 行8 铁块 2 帧
PROJ_FRAMES = {
    "F3_B_002": 3,
    "F1_B_002": 2,
}


def row_bands(im, thresh=ALPHA_THRESH):
    a = im.split()[3]
    w, h = im.size
    counts = []
    for y in range(h):
        n = 0
        for v in a.crop((0, y, w, y + 1)).getdata():
            if v > thresh:
                n += 1
        counts.append(n)
    rows = []
    y = 0
    while y < h:
        while y < h and counts[y] < 5:
            y += 1
        if y >= h:
            break
        y0 = y
        while y < h and counts[y] >= 5:
            y += 1
        y1 = y - 1
        if (y1 - y0 + 1) >= 15:
            rows.append((y0, y1))
    return rows


def col_profile(im, y0, y1, thresh=8):
    a = im.split()[3]
    w = im.size[0]
    return [sum(1 for v in a.crop((x, y0, x + 1, y1 + 1)).getdata() if v > thresh) for x in range(w)]


def content_bands(im, y0, y1, thresh=8, gap=3):
    prof = col_profile(im, y0, y1, thresh)
    w = len(prof)
    bands = []
    x = 0
    while x < w:
        while x < w and prof[x] < gap:
            x += 1
        if x >= w:
            break
        x0 = x
        while x < w and prof[x] >= gap:
            x += 1
        bands.append((x0, x - 1))
    return bands


def norm_cell(im, x0, x1, y0, y1):
    """裁一帧内容并缩放居中到 FRAME 帧格（保持宽高比，底对齐）。"""
    cell = im.crop((x0, y0, x1 + 1, y1 + 1))
    bbox = cell.getbbox()
    if bbox is None:
        return None
    content = cell.crop(bbox)
    cw = bbox[2] - bbox[0]
    ch = bbox[3] - bbox[1]
    scale = min((FRAME - 4) / float(ch), (FRAME - 4) / float(cw), 1.0)
    nw = max(1, round(cw * scale))
    nh = max(1, round(ch * scale))
    content = content.resize((nw, nh), Image.LANCZOS)
    out = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    px = (FRAME - nw) // 2
    py = FRAME - nh
    out.paste(content, (px, py), content)
    return out


def make_strip(im, y0, y1, frames, x_off=0, x_limit=1024):
    """按「透明间隙内容带」切帧（复用 slice_enemy_rows v3 策略）：
    1) 内容带（透明间隙分隔的独立内容块）数量 == 目标帧数 → 直接用内容带，每帧=一个内容块；
    2) 帧数不符（内容粘连/身体分离）→ 帧间距中位数分析：均匀切 + 跳空帧。
    x_off/x_limit：跨行合并时限制 x 范围。"""
    xa = x_off
    xb = min(x_limit, im.size[0]) - 1
    bands = content_bands(im, y0, y1)
    # 过滤 x 范围外的带
    bands = [b for b in bands if b[0] >= xa and b[1] <= xb]
    if not bands:
        return None
    # 情况1：内容带数量 == 目标帧数 → 直接用透明间隙切的内容带
    if len(bands) == frames:
        cells = []
        for (x0, x1) in bands:
            cell = norm_cell(im, x0, x1, y0, y1)
            if cell is not None:
                cells.append(cell)
        if len(cells) == frames:
            strip = Image.new("RGBA", (FRAME * len(cells), FRAME), (0, 0, 0, 0))
            for i, cell in enumerate(cells):
                strip.paste(cell, (i * FRAME, 0), cell)
            return strip, len(cells)
    # 情况2：帧数不符 → 帧间距中位数分析（均匀切，兼容粘连帧）
    # 帧中心间距：相邻内容带中心的差值中位数
    centers = [(b[0] + b[1]) / 2.0 for b in bands]
    pitch = 0.0
    if len(centers) >= 2:
        deltas = [centers[i + 1] - centers[i] for i in range(len(centers) - 1)]
        pitch = statistics.median(deltas)
    if pitch <= 0:
        pitch = (centers[-1] - centers[0]) / float(frames - 1) if len(centers) >= 2 else 1.0
    c0 = centers[0]
    cells = []
    for i in range(frames):
        cx = c0 + i * pitch
        # 帧宽 = 该中心最近内容带宽度（或中位宽度）
        x0 = int(round(cx - pitch * 0.5))
        x1 = int(round(cx + pitch * 0.5))
        cell = norm_cell(im, max(xa, x0), min(xb, x1), y0, y1)
        if cell is not None:
            cells.append(cell)
    if not cells:
        return None
    strip = Image.new("RGBA", (FRAME * len(cells), FRAME), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        strip.paste(cell, (i * FRAME, 0), cell)
    return strip, len(cells)


def make_proj_row(im, y0, y1, frames=None):
    """弹道行：优先按用户指定帧数切（PROJ_FRAMES 表）；否则内容带 1 帧 / 多帧均匀切。"""
    bands = content_bands(im, y0, y1)
    if not bands:
        return None, 0
    if frames is not None:
        # 用户指定帧数：直接切该帧数（内容带数量可能含碎片，按中位数策略切）
        return make_strip(im, y0, y1, frames)
    if len(bands) == 1:
        best = bands[0]
        cell = norm_cell(im, best[0], best[1], y0, y1)
        if cell is None:
            return None, 0
        strip = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        strip.paste(cell, (0, 0), cell)
        return strip, 1
    # 多帧弹道：均匀切
    return make_strip(im, y0, y1, len(bands))


def build_transform(layer, fid, json_name):
    """Anime 大图：按 json 帧坐标切帧，每帧缩放到 FRAME 高，横排成精灵条。"""
    import json as _json
    jp = os.path.join(SRC, layer, json_name)
    if not os.path.exists(jp):
        print(f"  [ERR] 变身 json 缺失 {json_name}")
        return
    with open(jp, "r", encoding="utf-8") as f:
        j = _json.load(f)
    png = os.path.join(SRC, layer, json_name.replace(".json", ".png"))
    if not os.path.exists(png):
        print(f"  [ERR] 变身 png 缺失 {png}")
        return
    im = Image.open(png).convert("RGBA")
    frames = j.get("frames", [])
    if not frames:
        print(f"  [ERR] {json_name} 无帧定义")
        return
    cells = []
    for fr in frames:
        x0, y0 = int(fr["x"]), int(fr["y"])
        w, h = int(fr["w"]), int(fr["h"])
        cell = norm_cell(im, x0, x0 + w - 1, y0, y0 + h - 1)
        if cell is not None:
            cells.append(cell)
    if not cells:
        print(f"  [ERR] {json_name} 切帧全空")
        return
    strip = Image.new("RGBA", (FRAME * len(cells), FRAME), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        strip.paste(cell, (i * FRAME, 0), cell)
    out = os.path.join(SRC, layer, f"{fid}_transform.png")
    strip.save(out)
    print(f"  [transform] {fid}_transform.png ({len(cells)}帧)")


def _mirror(layer, fid, base, left):
    src = os.path.join(SRC, layer, f"{fid}_{base}.png")
    if not os.path.exists(src):
        return
    img = Image.open(src).transpose(Image.FLIP_LEFT_RIGHT)
    out = os.path.join(SRC, layer, f"{fid}_{left}.png")
    img.save(out)
    print(f"  [mirror] {left} <- {base}")


def main() -> int:
    for fid, anim_map in ROWS.items():
        layer = LAYER_OF[fid]
        src = os.path.join(SRC, layer, f"{fid}.png")
        if not os.path.exists(src):
            print(f"[ERR] {layer}/{fid} 源图缺失")
            continue
        im = Image.open(src).convert("RGBA")
        rows = row_bands(im)
        print(f"==== {fid}（{layer}）: {len(rows)} 行")
        # 检查未被 ROW_OVERRIDES 覆盖的最大行号是否超出检测行数
        max_needed = max(anim_map.keys())
        if max_needed > len(rows) and fid not in ROW_OVERRIDES:
            print(f"  [ERR] 行数不足：表最大行 {max_needed} > 检测 {len(rows)}")
            continue
        saved = {}   # anim -> frames
        for row_no, (anim, frames) in anim_map.items():
            if fid in ROW_OVERRIDES and row_no in ROW_OVERRIDES[fid]:
                y0, y1 = ROW_OVERRIDES[fid][row_no]
            else:
                y0, y1 = rows[row_no - 1]
            if anim == "proj":
                pj_frames: Variant = PROJ_FRAMES.get(fid)
                strip, n = make_proj_row(im, y0, y1, pj_frames)
                if strip is not None:
                    out = os.path.join(SRC, layer, f"{fid}_proj.png")
                    strip.save(out)
                    print(f"  [proj] 行{row_no} -> {fid}_proj.png ({n}帧)")
                continue
            if anim in ("charge_p1", "charge_p2"):
                # 冲撞两行：暂存，稍后合并
                saved[anim] = (y0, y1, frames)
                print(f"  [keep] 行{row_no} {anim} 暂存（{frames}帧）")
                continue
            strip, n = make_strip(im, y0, y1, frames)
            if strip is None:
                print(f"  [ERR] 行{row_no} {anim} 切帧失败")
                continue
            out = os.path.join(SRC, layer, f"{fid}_{anim}.png")
            strip.save(out)
            saved[anim] = n
            print(f"  [ok] 行{row_no} {anim} -> {fid}_{anim}.png ({n}帧)")
        # 合并冲撞（F1_B_001 行5+行6）
        if fid in MERGE_CHARGE:
            _, _, out_anim, total = MERGE_CHARGE[fid]
            if "charge_p1" in saved and "charge_p2" in saved:
                y0a, y1a, fa = saved.pop("charge_p1")
                y0b, y1b, fb = saved.pop("charge_p2")
                sa, na = make_strip(im, y0a, y1a, fa)
                sb, nb = make_strip(im, y0b, y1b, fb)
                if sa is not None and sb is not None:
                    # 两行各 4 帧，拼成 8 帧
                    merged = Image.new("RGBA", (FRAME * (na + nb), FRAME), (0, 0, 0, 0))
                    merged.paste(sa, (0, 0), sa)
                    merged.paste(sb, (FRAME * na, 0), sb)
                    out = os.path.join(SRC, layer, f"{fid}_{out_anim}.png")
                    merged.save(out)
                    saved[out_anim] = na + nb
                    print(f"  [merge] 行5+行6 -> {fid}_{out_anim}.png ({na}+{nb}={na + nb}帧)")
        # 单向反向
        if "walk_right" in saved and "walk_left" not in saved:
            _mirror(layer, fid, "walk_right", "walk_left")
        for base, left in [("attack", "attack_left"), ("dead", "dead_left"), ("melee", "melee_left")]:
            if base in saved:
                _mirror(layer, fid, base, left)
        # 变身动画
        if fid in TRANSFORM:
            build_transform(layer, fid, TRANSFORM[fid])
        print()
    print("===== Boss 帧数摘要 =====")
    for fid in ROWS:
        layer = LAYER_OF[fid]
        found = {}
        for f in os.listdir(os.path.join(SRC, layer)):
            if f.startswith(fid + "_") and f.endswith(".png") and "_left" not in f and "_proj" not in f and "_transform" not in f:
                img = Image.open(os.path.join(SRC, layer, f))
                found[f.replace(fid + "_", "").replace(".png", "")] = img.size[0] // FRAME
        print(f"{fid}: " + " ".join(f"{k}={v}" for k, v in sorted(found.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
