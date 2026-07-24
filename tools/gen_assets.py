# -*- coding: utf-8 -*-
# 按 v3.0 最终美术清单生成程序占位 PNG（数据源 tools/v3_assets.py）。
# 命名：{编号}_{英文名称}.png；场景按「数量单位」展开（8块→_1..8 多文件 / N帧→横向精灵表 / 1张→单文件）。
# 不依赖 Pillow：用 zlib 手写 RGBA PNG 编码器。
import os, json, zlib, struct, random, math
from v3_assets import RAW, CODE_EN, BOSS_CODES

ROOT = r"E:\Godot\Godot_Project\momogametest"
ASSETS = os.path.join(ROOT, "assets")

# ---------- PNG 编码器（RGBA, color type 6, 8-bit） ----------
def _crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xffffffff

def write_png(path: str, w: int, h: int, rgba: bytes) -> None:
    assert len(rgba) == w * h * 4, "rgba size mismatch %d vs %d" % (len(rgba), w*h*4)
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0 (None)
        raw += rgba[y*w*4:(y+1)*w*4]
    comp = zlib.compress(bytes(raw), 9)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    out = bytearray()
    out += b'\x89PNG\r\n\x1a\n'
    out += struct.pack('>I', 13) + b'IHDR' + ihdr + struct.pack('>I', _crc32(b'IHDR' + ihdr))
    out += struct.pack('>I', len(comp)) + b'IDAT' + comp + struct.pack('>I', _crc32(b'IDAT' + comp))
    out += struct.pack('>I', 0) + b'IEND' + struct.pack('>I', _crc32(b'IEND'))
    with open(path, 'wb') as f:
        f.write(bytes(out))

# ---------- 绘图基元 ----------
def new_buf(w, h, bg=(0,0,0,0)):
    return bytearray(bytes(bg)) * (w*h)

def set_px(buf, w, x, y, c):
    if x < 0 or y < 0 or x >= w or y >= len(buf)//(w*4):
        return
    i = (y*w + x)*4
    buf[i] = c[0]; buf[i+1] = c[1]; buf[i+2] = c[2]; buf[i+3] = c[3]

def fill_rect(buf, w, h, x0, y0, x1, y1, c):
    for y in range(int(y0), int(y1)):
        for x in range(int(x0), int(x1)):
            set_px(buf, w, x, y, c)

def stroke_rect(buf, w, h, x0, y0, x1, y1, c, t=2):
    fill_rect(buf, w, h, x0, y0, x1, y0+t, c)
    fill_rect(buf, w, h, x0, y1-t, x1, y1, c)
    fill_rect(buf, w, h, x0, y0, x0+t, y1, c)
    fill_rect(buf, w, h, x1-t, y0, x1, y1, c)

def fill_circle(buf, w, h, cx, cy, r, c):
    for y in range(int(cy-r), int(cy+r)+1):
        for x in range(int(cx-r), int(cx+r)+1):
            if (x-cx)**2 + (y-cy)**2 <= r*r:
                set_px(buf, w, x, y, c)

def vgrad(buf, w, h, top, bot):
    for y in range(h):
        t = y/(max(h-1,1))
        c = (int(top[0]+(bot[0]-top[0])*t), int(top[1]+(bot[1]-top[1])*t),
             int(top[2]+(bot[2]-top[2])*t), 255)
        fill_rect(buf, w, h, 0, y, w, y+1, c)

def shade(c, f):
    return (max(0,min(255,int(c[0]*f))), max(0,min(255,int(c[1]*f))), max(0,min(255,int(c[2]*f))), c[3])

# ---------- 分类配色 / 形状 ----------
CAT = {
    'player':  ((0,200,220,255), 'char'),
    'enemy':   ((215,80,80,255),  'char'),
    'boss':    ((210,60,180,255),'char'),
    'wicon':   ((80,130,240,255), 'icon'),
    'wproj':   ((120,200,255,255),'proj'),
    'fx':      ((240,150,40,255), 'fx'),
    'tile':    ((120,120,140,255),'tile'),
    'ui':      ((150,100,210,255),'card'),
    'cg':      ((40,160,150,255), 'bg'),
}

def draw_asset(buf, w, h, frame, nframes, color, shape, seed):
    rnd = random.Random(seed)
    if shape == 'char':
        bw, bh = w*0.55, h*0.55
        bx, by = (w-bw)/2, h*0.30
        fill_rect(buf, w, h, bx, by, bx+bw, by+bh, color)
        stroke_rect(buf, w, h, bx, by, bx+bw, by+bh, shade(color,0.6), 2)
        hr = min(w,h)*0.22
        fill_circle(buf, w, h, w/2, h*0.26, hr, shade(color,1.15))
    elif shape == 'icon':
        cx, cy = w/2, h/2
        for y in range(h):
            half = (h/2 - abs(y-cy)) * (w/h) * 0.9
            fill_rect(buf, w, h, cx-half, y, cx+half, y+1, color)
        stroke_rect(buf, w, h, 1, 1, w-1, h-1, shade(color,0.6), 1)
    elif shape == 'proj':
        fill_circle(buf, w, h, w/2, h/2, min(w,h)*0.4, color)
    elif shape == 'fx':
        fill_circle(buf, w, h, w/2, h/2, min(w,h)*0.35, color)
        for k in range(6):
            a = k/6.0*2*math.pi + frame*0.3
            x0 = int(w/2 + math.cos(a)*min(w,h)*0.35)
            y0 = int(h/2 + math.sin(a)*min(w,h)*0.35)
            x1 = int(w/2 + math.cos(a)*min(w,h)*0.46) + 1
            y1 = int(h/2 + math.sin(a)*min(w,h)*0.46) + 1
            fill_rect(buf, w, h, x0, y0, x1, y1, shade(color,0.8))
    elif shape == 'tile':
        fill_rect(buf, w, h, 0, 0, w, h, shade(color, 0.8 + 0.2*(seed%3)/2.0))
        stroke_rect(buf, w, h, 0, 0, w, h, shade(color,0.45), 2)
        if (seed % 2) == 0:
            fill_rect(buf, w, h, w*0.3, h*0.3, w*0.7, h*0.7, shade(color,1.1))
    elif shape == 'card':
        fill_rect(buf, w, h, 2, 2, w-2, h-2, shade(color,0.85))
        stroke_rect(buf, w, h, 2, 2, w-2, h-2, shade(color,0.5), 2)
    elif shape == 'bg':
        vgrad(buf, w, h, (20,20,40), shade(color,0.5))
    else:
        fill_rect(buf, w, h, 1, 1, w-1, h-1, color)

# ---------- 文件夹映射 ----------
def folder_of(cat, code):
    if cat == 'player': return 'sprites/player'
    if cat == 'boss':   return 'sprites/bosses'
    if cat == 'enemy':
        num = int(code.split('-')[1])
        if num <= 8:   return 'sprites/enemies/layer1'
        if num <= 19:  return 'sprites/enemies/layer2'
        return 'sprites/enemies/layer3'
    if cat == 'wicon': return 'weapons/icons'
    if cat == 'wproj': return 'weapons/projectiles'
    if cat == 'fx':    return 'fx'
    if cat == 'tile':  return 'tiles'
    if cat == 'ui':    return 'ui'
    if cat == 'cg':    return 'ui'
    return 'misc'

# ---------- 生成 ----------
generated = []
for (code, en, w, h, frames, cat, kind) in RAW:
    color, shape = CAT.get(cat, ((200,200,200,255),'char'))
    folder = folder_of(cat, code)
    outdir = os.path.join(ASSETS, *folder.split('/'))
    os.makedirs(outdir, exist_ok=True)
    if kind == 'single':
        buf = new_buf(w, h)
        draw_asset(buf, w, h, 0, 1, color, shape, hash(code) & 0xffff)
        fn = "%s_%s.png" % (code, en)
        write_png(os.path.join(outdir, fn), w, h, bytes(buf))
        generated.append(os.path.join('assets', folder, fn).replace('\\','/'))
    elif kind == 'sheet':
        buf = new_buf(w*frames, h)
        for f in range(frames):
            sub = new_buf(w, h)
            draw_asset(sub, w, h, f, frames, color, shape, (hash(code) & 0xffff) + f*7)
            for y in range(h):
                for x in range(w):
                    si = (y*w+x)*4
                    di = (y*(w*frames) + (f*w + x))*4
                    buf[di:di+4] = sub[si:si+4]
        fn = "%s_%s.png" % (code, en)
        write_png(os.path.join(outdir, fn), w*frames, h, bytes(buf))
        generated.append(os.path.join('assets', folder, fn).replace('\\','/'))
    elif kind == 'multi':
        for i in range(1, frames+1):
            buf = new_buf(w, h)
            draw_asset(buf, w, h, 0, 1, color, shape, (hash(code)&0xffff) + i*13)
            fn = "%s_%s_%d.png" % (code, en, i)
            write_png(os.path.join(outdir, fn), w, h, bytes(buf))
            generated.append(os.path.join('assets', folder, fn).replace('\\','/'))

# ---------- 写回新清单（仅删除“旧清单有、本次未生成”的文件，避免误删本次产物；os.remove 包 try/except 兜 safe-delete 守护 EPERM） ----------
old_json = os.path.join(ASSETS, "GENERATED_PLACEHOLDERS.json")
gen_set = set(generated)
if os.path.exists(old_json):
    try:
        with open(old_json, 'r', encoding='utf-8') as f:
            old = json.load(f)
        for p in old.get('generated', []):
            if p in gen_set:
                continue  # 本次会重新生成同名文件，跳过（不删自己的产物）
            fp = os.path.join(ROOT, p.replace('/', os.sep))
            for ext in ('', '.import'):
                tgt = fp + ext
                if os.path.exists(tgt):
                    try:
                        os.remove(tgt)
                        print("  removed stale:", p + ext)
                    except OSError as e:
                        print("  (skip delete %s: %s)" % (p + ext, e))
    except Exception as e:
        print("  (cleanup skipped: %s)" % e)

with open(old_json, 'w', encoding='utf-8') as f:
    json.dump({"generated": sorted(generated),
               "note": "v3.0 占位素材：{编号}_{英文名称}.png（英文取清单英文列转 snake_case）；角色/怪 130x250、Boss 260x500；场景按数量单位展开（8块→_1..8，N帧→横向精灵表，1张/1种/1帧→单文件）。同名 PNG 覆盖即可替换。"},
              f, ensure_ascii=False, indent=2)

print("\nTOTAL generated:", len(generated))
