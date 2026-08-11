# -*- coding: utf-8 -*-
"""
将 assets/sprites/player/momo/ 的网格精灵表打包成 momo_packed/ 紧凑图集。

每张 _small.png = 512x384 = 4 列 x 3 行网格，每格 128x128，共 10 帧有效：
  行0: 帧0-3   行1: 帧4-7   行2: 帧8-9（第10/11格空）
帧序 = 行优先（r = i/4, c = i%4）。

方向映射（**源素材命名即真实朝向，直接直出**）：
  walk_back(源)      -> walk_back      上
  walk_font(源)      -> walk_front     下（源文件名 font 是拼写错误）
  walk_right(源)     -> walk_right     右
  walk_right(源)     -> walk_left 镜像  左
  walk_leftup(源)    -> walk_leftup    左上（直出！）
  walk_leftup(源)    -> walk_rightup 镜像 右上
  walk_rightdown(源) -> walk_rightdown 右下（直出！）
  walk_rightdown(源) -> walk_leftdown 镜像 左下

每个动作打包三张图（同名不同后缀），**裁剪 bbox 以 main 图为准**，保证三张同尺寸：
  *.png         彩色主图
  *_alpha.png   alpha 兄弟（前景白色 / 背景透明）
  *_outline.png 描边环（由 alpha 扩张 1px 减去原 alpha 生成，**不含 128x128 格子边框线**）
                —— 替代源 _edge 图：PixelClean 的 edge 检测把画布格子边框线也当边缘保留，
                   直接打包会画出"方框"。描边环 = 角色轮廓外 1px 白线，干净可用。
"""
import os, sys
from PIL import Image, ImageFilter

SRC_DIR = r"E:\Godot\Godot_Project\momogametest\assets\sprites\player\momo"
OUT_DIR = r"E:\Godot\Godot_Project\momogametest\assets\sprites\player\momo_packed"

# (源文件 base name, 输出 base name, 是否水平镜像)
ACTIONS = [
    # 8 向走路（源素材命名即真实朝向）
    ("walk_back",       "walk_back",      False),    # 上（背对镜头）
    ("walk_font",       "walk_front",     False),    # 下（面对镜头，源文件名 font 是拼写错误）
    ("walk_right",      "walk_right",     False),    # 右
    ("walk_right",      "walk_left",      True),     # 左 = 右 镜像
    ("walk_leftup",     "walk_leftup",    False),    # 左上（直出！）
    ("walk_leftup",     "walk_rightup",   True),     # 右上 = 左上 镜像
    ("walk_rightdown",  "walk_rightdown", False),    # 右下（直出！）
    ("walk_rightdown",  "walk_leftdown",  True),     # 左下 = 右下 镜像
    # 待机 / 死亡 / 攻击（无方向概念）
    ("dead",            "dead",           False),
    ("idea",            "idea",           False),
    ("attack",          "attack",         False),
]

COLS, ROWS = 4, 3
CELL = 128
TOTAL = 10   # 有效帧数（末行仅 2 帧）
SUFFIXES = ("", "_alpha", "_outline")


def cell_bbox(im, frame_idx):
    """第 frame_idx 帧（行优先 4 列网格）内容 alpha bbox，格子内坐标。"""
    r = frame_idx // COLS
    c = frame_idx % COLS
    gx0, gy0 = c * CELL, r * CELL
    px = im.load()
    mnx, mny, mxx, mxy = CELL, CELL, 0, 0
    for x in range(gx0, gx0 + CELL):
        for y in range(gy0, gy0 + CELL):
            if px[x, y][3] > 8:
                lx, ly = x - gx0, y - gy0
                if lx < mnx: mnx = lx
                if lx > mxx: mxx = lx
                if ly < mny: mny = ly
                if ly > mxy: mxy = ly
    return None if mxx < mnx else (mnx, mny, mxx + 1, mxy + 1)


def make_outline(mask_rgba):
    """从 alpha 剪影生成 1px 描边环（扩张 - 原 alpha），无网格线。

    mask_rgba: PixelClean 的 _alpha.png（RGBA，**前景用白色 RGB 表示**、背景黑色，
    即前景信息在灰度不在 alpha 通道）。灰度化后扩张 1px，减去原灰度 = 描边环。
    返回 RGBA：白色描边环 + 透明其余。
    """
    g = mask_rgba.convert("L")  # 灰度：白(255)=前景，黑(0)=背景
    dil = g.filter(ImageFilter.MaxFilter(3))  # 3x3 max -> 向外扩张 1px
    out = Image.new("RGBA", mask_rgba.size, (255, 255, 255, 0))
    opx = out.load()
    gpx = g.load()
    dpx = dil.load()
    w, h = g.size
    for y in range(h):
        for x in range(w):
            if dpx[x, y] > 8 and gpx[x, y] <= 8:
                opx[x, y] = (255, 255, 255, 255)
    return out


def pack_im(im, boxes, mirror, transform=None):
    """按 boxes（来自 main 图的 10 帧 bbox）裁剪 im 同样 10 帧，拼接成紧凑横排。

    transform: 可选逐帧变换函数（如生成描边环）。
    """
    max_fw = max(b[2] - b[0] for b in boxes)
    max_fh = max(b[3] - b[1] for b in boxes)
    sheet = Image.new("RGBA", (max_fw * TOTAL, max_fh), (0, 0, 0, 0))
    for i in range(TOTAL):
        b = boxes[i]
        if b is None:
            continue
        fx0, fy0, fx1, fy1 = b
        r = i // COLS
        c = i % COLS
        gx0, gy0 = c * CELL, r * CELL
        fcontent = im.crop((gx0 + fx0, gy0 + fy0, gx0 + fx1, gy0 + fy1))
        if transform is not None:
            fcontent = transform(fcontent)
        if mirror:
            fcontent = fcontent.transpose(Image.FLIP_LEFT_RIGHT)
        paste_x = i * max_fw + (max_fw - fcontent.width) // 2
        paste_y = (max_fh - fcontent.height) // 2
        sheet.paste(fcontent, (paste_x, paste_y))
    return sheet, max_fw, max_fh


def main():
    if "--check" in sys.argv:
        ok = True
        for _, name, _ in ACTIONS:
            for sfx in SUFFIXES:
                p = os.path.join(OUT_DIR, f"{name}{sfx}.png")
                if not os.path.isfile(p):
                    print("MISSING:", p); ok = False
                else:
                    im = Image.open(p); print("OK:", name + sfx, im.size)
        return 0 if ok else 1

    results = []
    for src, dst, mirror in ACTIONS:
        im_main = Image.open(os.path.join(SRC_DIR, f"momo_{src}_small.png")).convert("RGBA")
        main_boxes = [b for b in (cell_bbox(im_main, i) for i in range(TOTAL)) if b]
        if not main_boxes:
            print(f"SKIP {src}: main 图无内容")
            continue
        for sfx in SUFFIXES:
            if sfx == "":
                im = im_main
            elif sfx == "_alpha":
                im = Image.open(os.path.join(SRC_DIR, f"momo_{src}_small_alpha.png")).convert("RGBA")
            else:  # _outline
                im_alpha = Image.open(os.path.join(SRC_DIR, f"momo_{src}_small_alpha.png")).convert("RGBA")
                im = im_alpha  # 占位，实际由 pack_im 的 transform 逐帧生成
                # 直接生成描边环并打包
                def _transform(frame, _im_alpha=im_alpha):
                    return make_outline(frame)
                sheet, fw, fh = pack_im(im, main_boxes, mirror, transform=_transform)
                os.makedirs(OUT_DIR, exist_ok=True)
                out_path = os.path.join(OUT_DIR, f"{dst}{sfx}.png")
                sheet.save(out_path)
                results.append({"name": dst + sfx, "fw": fw, "fh": fh, "fr": TOTAL, "path": out_path})
                continue
            sheet, fw, fh = pack_im(im, main_boxes, mirror)
            os.makedirs(OUT_DIR, exist_ok=True)
            out_path = os.path.join(OUT_DIR, f"{dst}{sfx}.png")
            sheet.save(out_path)
            results.append({"name": dst + sfx, "fw": fw, "fh": fh, "fr": TOTAL, "path": out_path})
    print(f"PACKED {len(results)} (action x suffix) -> {OUT_DIR} (每动作 {TOTAL} 帧)")
    for r in results:
        print(f"  {r['name']:24s} {r['fw']}x{r['fh']} x{r['fr']} -> {os.path.basename(r['path'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())