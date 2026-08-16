# 《梦境逐影》闹钟怪精灵表切片工具
# 输入：assets/sprites/enemies/layer1/F1_N_001.png（5行×8列 多行动画表）
# 输出：5 条横向精灵条（walk_down/walk_right/walk_up/attack/dead），每条 8 帧，帧格 128×128
# 行为模式（对应精灵表行序，与设计文档一致）：
#   行1 -> 向下移动 walk_down
#   行2 -> 向右移动 walk_right（左右翻转覆盖 left）
#   行3 -> 向上移动 walk_up
#   行4 -> 攻击 attack
#   行5 -> 死亡 dead
import os
import sys
from PIL import Image

SRC = r"H:/GodotProject/momogametest/assets/sprites/enemies/layer1/F1_N_001.png"
OUT_DIR = r"H:/GodotProject/momogametest/assets/sprites/enemies/layer1"
FRAME = 128  # 帧格 128×128（对齐原网格 1024/8）
ROWS = 5     # 5 行动画
COLS = 8     # 每行 8 帧
ROW_ANIMS = ["walk_down", "walk_right", "walk_up", "attack", "dead"]


def row_bands(im: Image.Image):
    """按 alpha 找内容行带 [(y0, y1), ...]"""
    a = im.split()[3]
    w, h = im.size
    bands = []
    y = 0
    while y < h:
        while y < h and a.crop((0, y, w, y + 1)).getextrema()[1] == 0:
            y += 1
        if y >= h:
            break
        y0 = y
        while y < h and a.crop((0, y, w, y + 1)).getextrema()[1] > 0:
            y += 1
        bands.append((y0, y - 1))
    return bands


def col_bands(im: Image.Image, y0: int, y1: int):
    """按 alpha 找行内的内容列带 [(x0, x1), ...]"""
    a = im.split()[3]
    w, _ = im.size
    bands = []
    x = 0
    while x < w:
        while x < w and a.crop((x, y0, x + 1, y1 + 1)).getextrema()[1] == 0:
            x += 1
        if x >= w:
            break
        x0 = x
        while x < w and a.crop((x, y0, x + 1, y1 + 1)).getextrema()[1] > 0:
            x += 1
        bands.append((x0, x - 1))
    return bands


def main() -> int:
    src = Image.open(SRC).convert("RGBA")
    rows = row_bands(src)
    if len(rows) != ROWS:
        print(f"[ERR] 行带数={len(rows)} 预期 {ROWS}，F1_N_001 结构不符")
        return 1

    os.makedirs(OUT_DIR, exist_ok=True)
    for r_idx, (ry0, ry1) in enumerate(rows):
        anim = ROW_ANIMS[r_idx]
        cols = col_bands(src, ry0, ry1)
        if len(cols) != COLS:
            print(f"[WARN] {anim} 行{ry0}-{ry1} 列带={len(cols)} 预期 {COLS}，跳过")
            continue
        strip = Image.new("RGBA", (FRAME * COLS, FRAME), (0, 0, 0, 0))
        for c_idx, (cx0, cx1) in enumerate(cols):
            # 每帧内容 bbox（带内进一步收紧）
            cell = src.crop((cx0, ry0, cx1 + 1, ry1 + 1))
            bbox = cell.getbbox()
            if bbox is None:
                continue
            fw = bbox[2] - bbox[0]
            fh = bbox[3] - bbox[1]
            content = cell.crop(bbox)
            # 缩放装进 128×128（保持比例，最长边 120，留 padding）
            scale = min(120.0 / fw, 120.0 / fh, 1.0)
            nw = max(1, round(fw * scale))
            nh = max(1, round(fh * scale))
            content = content.resize((nw, nh), Image.LANCZOS)
            # 水平居中，底部对齐（脚底贴 y=127）
            px = (FRAME - nw) // 2
            py = FRAME - nh
            strip.paste(content, (c_idx * FRAME + px, py), content)
        out = os.path.join(OUT_DIR, f"F1_N_001_{anim}.png")
        strip.save(out)
        print(f"[ok] {anim}: {strip.size} 8帧 -> {os.path.basename(out)}")

    # 校验：输出 5 条
    for anim in ROW_ANIMS:
        p = os.path.join(OUT_DIR, f"F1_N_001_{anim}.png")
        if not os.path.exists(p):
            print(f"[ERR] 缺失 {p}")
            return 1
        im = Image.open(p)
        assert im.size == (FRAME * COLS, FRAME), f"{anim} 尺寸错误 {im.size}"
        print(f"[check] {anim}.png {im.size} OK")
    print("全部完成：5 条精灵条已生成")
    return 0


if __name__ == "__main__":
    sys.exit(main())
