# 《梦境逐影》全怪物按行序切片工具（v3 · 内容带自适应 + 攻击/弹道分离）
# 行序表来自 C:/Users/17930_ueiiii0/Desktop/怪物说明.txt
# 规则（v3 重写）：
#   - 行带检测：每行 alpha>60 计数阈值（行间有半透明残留，勿用"完全透明"）
#   - 帧切分：内容带自适应（空白间隙分隔），每帧独立 bbox 裁剪，帧宽=内容实际宽度
#   - 攻击行（含弹道）：攻击帧等宽 + 弹道帧（多帧动画）单独切出
#   - 单向反向：walk_right/attack/dead/melee 镜像生成 *_left
# 输出：{fid}_{anim}.png 横向精灵条 + {fid}_proj.png（弹道多帧）+ 数据摘要
import os
import sys
import statistics
from PIL import Image

SRC_DIR = r"H:/GodotProject/momogametest/assets/sprites/enemies"
FRAME = 128          # 输出帧格（bbox 内容缩放后统一 128 高，宽自适应居中）
ALPHA_THRESH = 60    # 行带检测阈值

# 每怪行序（行号(1起) -> 动画键）
ROWS = {
    "F1_N_001": {1: "walk_down", 2: "walk_right", 3: "walk_up", 4: "attack", 5: "dead"},
    "F1_N_002": {1: "walk_down", 2: "walk_right", 3: "walk_up", 4: "dead", 5: "attack", 6: "idle"},
    "F1_N_003": {1: "walk_down", 2: "walk_right", 3: "walk_up", 4: "dead", 5: "attack"},
    "F1_N_004": {1: "walk_down", 2: "walk_right", 3: "walk_up", 4: "attack", 5: "dead", 6: "proj"},
    "F1_N_005": {1: "walk_down", 2: "walk_up", 3: "walk_right", 4: "attack", 5: "dead", 6: "idle"},
    "F2_N_001": {1: "walk_down", 2: "walk_right", 3: "walk_up", 4: "dead", 5: "attack", 6: "proj", 7: "idle"},
    "F2_N_002": {1: "walk_up", 2: "walk_down", 3: "walk_right", 4: "dead", 5: "melee", 6: "attack", 7: "idle", 8: "proj"},
    "F2_N_003": {1: "walk_down", 2: "walk_right", 3: "walk_left", 4: "attack", 5: "proj", 6: "dead", 7: "dead2"},
    "F2_N_004": {1: "idle", 2: "attack", 3: "melee", 4: "dead", 5: "dead2"},
    "F2_N_005": {1: "walk_down", 2: "walk_up", 3: "walk_right", 4: "attack", 5: "dead"},
    "F3_N_001": {1: "walk_down", 2: "walk_up", 3: "walk_right", 4: "attack", 5: "dead"},
    "F3_N_002": {1: "walk_up", 2: "walk_down", 3: "walk_right", 4: "attack", 5: "skip", 6: "dead"},
    "F3_N_003": {1: "walk_down", 2: "walk_right", 3: "walk_up", 4: "attack", 5: "dead"},
    "F3_N_004": {1: "idle", 2: "walk_down", 3: "walk_up", 4: "walk_right", 5: "walk_left", 6: "attack", 7: "dead"},
    "F3_N_005": {1: "walk_down", 2: "walk_up", 3: "walk_right", 4: "attack", 5: "dead", 6: "idle"},
    "F3_N_006": {1: "walk_down", 2: "walk_right", 3: "walk_up", 4: "attack", 5: "proj", 7: "dead", 8: "idle"},
}
LAYER_OF = {fid: ("layer1" if fid.startswith("F1") else "layer2" if fid.startswith("F2") else "layer3") for fid in ROWS}

# 攻击行内嵌弹道：攻击帧末尾带弹道贴图（用户明确：攻击帧数 + 弹道帧数）
# 值 = (行号, 攻击帧数, 弹道帧数)。弹道帧紧跟在攻击帧之后，切出为 {fid}_proj.png（多帧）。
ATTACK_PROJ = {
    "F3_N_002": (4, 3, 3),   # kpi团：行4 远程攻击，攻击3帧 + 弹道3帧
    "F3_N_003": (4, 3, 1),   # 硬件核心：行4 远程攻击，攻击3帧 + 弹道1帧
}

# 每行精确帧数（用户 2026-08-15 提供）。未列出的行默认 8 帧。
FRAMES = {
    "F1_N_002": {1: 10, 2: 10, 3: 10, 4: 8, 5: 8, 6: 8},
    "F2_N_004": {1: 4, 2: 6, 3: 4, 4: 6, 5: 4},   # 蜈蚣（1202宽）：idle4/远程攻击6/melee4/dead6/dead2-4帧
    "F2_N_005": {1: 6, 2: 6, 3: 3, 4: 6, 5: 5},   # 僵尸：down/up各6帧、right3帧、attack6帧、dead5帧
    "F3_N_002": {1: 8, 2: 8, 3: 8, 6: 8},   # 行4 由 ATTACK_PROJ 处理（攻击3+弹道3）
    "F3_N_003": {1: 8, 2: 8, 3: 8, 5: 6},   # 行4 由 ATTACK_PROJ 处理（攻击3+弹道1）
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
    """列投影找内容带（空白间隙 >= gap 列分隔）。"""
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
    """裁一帧内容并缩放居中到 128×128 帧格（保持宽高比，底对齐）。"""
    cell = im.crop((x0, y0, x1 + 1, y1 + 1))
    bbox = cell.getbbox()
    if bbox is None:
        return None
    content = cell.crop(bbox)
    cw = bbox[2] - bbox[0]
    ch = bbox[3] - bbox[1]
    scale = min(120.0 / cw, 120.0 / ch, 1.0)
    nw = max(1, round(cw * scale))
    nh = max(1, round(ch * scale))
    content = content.resize((nw, nh), Image.LANCZOS)
    out = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    px = (FRAME - nw) // 2
    py = FRAME - nh
    out.paste(content, (px, py), content)
    return out


def make_strip(im, y0, y1, frames=8):
    """切帧。frames 指定时：内容带数量==帧数则用内容带，否则按帧间距均匀切；
    默认 8 帧均匀切（身体分离怪兜底，避免碎片化）。"""
    if frames is None:
        frames = 8
    bands = content_bands(im, y0, y1)
    # 内容带数量 == 目标帧数 → 直接用内容带（帧宽=内容实际宽度）
    if len(bands) == frames:
        strip = Image.new("RGBA", (FRAME * len(bands), FRAME), (0, 0, 0, 0))
        for i, (x0, x1) in enumerate(bands):
            cell = norm_cell(im, x0, x1, y0, y1)
            if cell is not None:
                strip.paste(cell, (i * FRAME, 0), cell)
        return strip, len(bands)
    # 帧数不符（身体分离/粘连）→ 均匀切分
    w = im.size[0]
    fw = w / float(frames)
    strip = Image.new("RGBA", (FRAME * frames, FRAME), (0, 0, 0, 0))
    for i in range(frames):
        x0 = int(round(i * fw))
        x1 = int(round((i + 1) * fw)) - 1
        cell = norm_cell(im, x0, x1, y0, y1)
        if cell is not None:
            strip.paste(cell, (i * FRAME, 0), cell)
    return strip, frames


def make_attack_proj(im, y0, y1, atk_n, proj_n):
    """攻击行：攻击帧等宽切 + 弹道帧（多帧）单独切。返回 (attack_strip, proj_strip)。"""
    bands = content_bands(im, y0, y1)
    # 攻击帧宽 = 前几个攻击帧内容带宽度的中位数（攻击帧之间有空隙，可检测）
    if len(bands) >= atk_n:
        atk_widths = [b[1] - b[0] + 1 for b in bands[:atk_n]]
        fw = statistics.median(atk_widths)
    else:
        fw = (bands[0][1] - bands[0][0] + 1) if bands else 120.0
    # 攻击帧中心间距（用前2个攻击帧中心）
    centers = [(b[0] + b[1]) / 2.0 for b in bands]
    if len(centers) >= 2:
        pitch = centers[1] - centers[0]
    else:
        pitch = fw + 25.0
    # 攻击帧 N 帧：从第一个攻击帧中心开始，等距排列
    atk_cells = []
    c0 = centers[0]
    for i in range(atk_n):
        cx = c0 + i * pitch
        x0 = int(round(cx - fw / 2.0))
        x1 = int(round(cx + fw / 2.0))
        cell = norm_cell(im, max(0, x0), min(im.size[0] - 1, x1), y0, y1)
        if cell is not None:
            atk_cells.append(cell)
    attack_strip = Image.new("RGBA", (FRAME * len(atk_cells), FRAME), (0, 0, 0, 0))
    for i, cell in enumerate(atk_cells):
        attack_strip.paste(cell, (i * FRAME, 0), cell)
    # 弹道帧：攻击帧最后一个右边界之后到行内容末尾，均匀切 proj_n 帧
    atk_right = int(round(c0 + (atk_n - 1) * pitch + fw / 2.0))
    # 行内容右边界（最后一个内容带）
    content_right = bands[-1][1] if bands else im.size[0] - 1
    # 弹道区域可能包含残影，限制在最后一个弹道带（用内容带检测弹道区域）
    proj_bands = content_bands(im, y0, y1)
    proj_right = content_right
    # 弹道区域 = atk_right 到 proj_right
    region_w = proj_right - atk_right + 1
    if region_w <= 0:
        return attack_strip, None
    pw = region_w / float(proj_n)
    proj_cells = []
    for i in range(proj_n):
        x0 = atk_right + int(round(i * pw))
        x1 = atk_right + int(round((i + 1) * pw)) - 1
        cell = norm_cell(im, max(0, x0), min(im.size[0] - 1, x1), y0, y1)
        if cell is not None:
            proj_cells.append(cell)
    proj_strip = Image.new("RGBA", (FRAME * len(proj_cells), FRAME), (0, 0, 0, 0))
    for i, cell in enumerate(proj_cells):
        proj_strip.paste(cell, (i * FRAME, 0), cell)
    return attack_strip, proj_strip


def make_proj_row(im, y0, y1):
    """独立弹道行：取最大的内容带（单帧弹道贴图，供 Projectile 用）。"""
    bands = content_bands(im, y0, y1)
    if not bands:
        return None
    # 取最大的内容带（过滤碎片）
    best = max(bands, key=lambda b: b[1] - b[0] + 1)
    cell = norm_cell(im, best[0], best[1], y0, y1)
    if cell is None:
        return None
    strip = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    strip.paste(cell, (0, 0), cell)
    return strip


def _mirror(fid, layer, base, left, anim_frames):
    src = os.path.join(SRC_DIR, layer, f"{fid}_{base}.png")
    if not os.path.exists(src):
        return
    img = Image.open(src).transpose(Image.FLIP_LEFT_RIGHT)
    out = os.path.join(SRC_DIR, layer, f"{fid}_{left}.png")
    img.save(out)
    anim_frames[left] = anim_frames[base]
    print(f"  [mirror] {left} <- {base} 镜像")


def main() -> int:
    summary = {}
    for fid, anim_map in ROWS.items():
        layer = LAYER_OF[fid]
        src = os.path.join(SRC_DIR, layer, f"{fid}.png")
        if not os.path.exists(src):
            print(f"[ERR] {layer}/{fid} 源图缺失")
            continue
        im = Image.open(src).convert("RGBA")
        rows = row_bands(im)
        print(f"==== {fid}（{layer}）: {len(rows)} 行")
        if len(rows) < max(anim_map.keys()):
            print(f"  [ERR] 行数不足：表最大行 {max(anim_map.keys())} > 检测 {len(rows)}")
            continue
        anim_frames = {}
        for row_no, anim in anim_map.items():
            if anim == "skip":
                print(f"  [skip] 行{row_no} 多余行，忽略")
                continue
            y0, y1 = rows[row_no - 1]
            if anim == "proj":
                pj = make_proj_row(im, y0, y1)
                if pj is not None:
                    out = os.path.join(SRC_DIR, layer, f"{fid}_proj.png")
                    pj.save(out)
                    print(f"  [proj] 行{row_no} -> {fid}_proj.png ({pj.size[0] // FRAME}帧)")
                continue
            if anim == "dead2":
                strip, frames = make_strip(im, y0, y1)
                out = os.path.join(SRC_DIR, layer, f"{fid}_{anim}.png")
                strip.save(out)
                print(f"  [aux]  行{row_no} {anim} -> {fid}_{anim}.png ({frames}帧)")
                continue
            # 攻击行（含弹道）
            if fid in ATTACK_PROJ and ATTACK_PROJ[fid][0] == row_no:
                _, atk_n, proj_n = ATTACK_PROJ[fid]
                astrip, pstrip = make_attack_proj(im, y0, y1, atk_n, proj_n)
                aout = os.path.join(SRC_DIR, layer, f"{fid}_{anim}.png")
                astrip.save(aout)
                anim_frames[anim] = astrip.size[0] // FRAME
                print(f"  [ok]   行{row_no} {anim} -> {fid}_{anim}.png ({anim_frames[anim]}帧)")
                if pstrip is not None:
                    pout = os.path.join(SRC_DIR, layer, f"{fid}_proj.png")
                    pstrip.save(pout)
                    print(f"  [proj] 行{row_no}末尾 {proj_n}帧弹道 -> {fid}_proj.png ({pstrip.size[0] // FRAME}帧)")
                continue
            row_frames = FRAMES.get(fid, {}).get(row_no)
            strip, frames = make_strip(im, y0, y1, row_frames)
            out = os.path.join(SRC_DIR, layer, f"{fid}_{anim}.png")
            strip.save(out)
            anim_frames[anim] = frames
            print(f"  [ok]   行{row_no} {anim} -> {fid}_{anim}.png ({frames}帧)")
        # 单向反向
        if "walk_left" not in anim_map.values() and "walk_right" in anim_frames:
            _mirror(fid, layer, "walk_right", "walk_left", anim_frames)
        for base, left in [("attack", "attack_left"), ("dead", "dead_left"), ("melee", "melee_left")]:
            if base in anim_frames:
                _mirror(fid, layer, base, left, anim_frames)
        summary[fid] = anim_frames
        print()

    print("===== 帧数摘要 =====")
    for fid in ROWS:
        if fid not in summary:
            continue
        af = summary[fid]
        print(f"{fid}: " + " ".join(f"{k}={v}" for k, v in af.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
