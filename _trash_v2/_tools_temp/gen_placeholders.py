#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
《梦境逐影》占位美术生成器 (pure-python, no PIL needed)
生成「方块人形」风格 PNG 占位素材，路径严格对应 assets/ 结构。
后期美术一键替换：用同名同尺寸 PNG 覆盖即可，Godot 会自动重新导入。

动画统一为「横向精灵表」(horizontal sprite strip)：
  图片宽 = 单帧宽 × 帧数，高 = 单帧高。
  代码在运行时按单帧尺寸切片加载（见 src/autoload/GameManager.gd 的 load_spritesheet）。
"""
import os, zlib, struct, math, json

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def write_png(path, w, h, pixels):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw.extend(pixels[y * w * 4:(y + 1) * w * 4])
    comp = zlib.compress(bytes(raw), 9)

    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", comp))
        f.write(chunk(b"IEND", b""))


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = bytearray(w * h * 4)

    def set(self, x, y, r, g, b, a=255):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h and a > 8:
            i = (y * self.w + x) * 4
            self.px[i] = r; self.px[i + 1] = g; self.px[i + 2] = b; self.px[i + 3] = a

    def rect(self, x0, y0, x1, y1, col, border=None):
        x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        if x1 < x0: x0, x1 = x1, x0
        if y1 < y0: y0, y1 = y1, y0
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, *col)
        if border:
            for x in range(x0, x1 + 1):
                self.set(x, y0, *border); self.set(x, y1, *border)
            for y in range(y0, y1 + 1):
                self.set(x0, y, *border); self.set(x1, y, *border)

    def circle(self, cx, cy, r, col):
        cx, cy = int(round(cx)), int(round(cy))
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.set(x, y, *col)

    def save(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_png(path, self.w, self.h, self.px)


def darker(c, amt=55):
    return (max(0, c[0] - amt), max(0, c[1] - amt), max(0, c[2] - amt))


def draw_humanoid(c, ox, oy, w, h, col, accent, pose, frame, frames):
    """在 canvas 的 (ox,oy) 处画一个方块人形（单帧）。"""
    if pose == "dead":
        ground = oy + h - 1
        dy = ground - int(h * 0.16)
        c.rect(ox + w * 0.18, dy, ox + w * 0.82, dy + int(h * 0.14), col, darker(col))
        c.rect(ox + w * 0.02, dy - int(h * 0.10), ox + w * 0.20, dy + int(h * 0.10), col, darker(col))
        for k in range(3):
            sx = ox + w * (0.3 + k * 0.18); sy = dy - int(h * 0.22)
            c.rect(sx - 1, sy, sx + 1, sy + 2, accent)
            c.rect(sx, sy - 1, sx + 1, sy + 1, accent)
        return

    cx = ox + w / 2.0
    bob = int(round(math.sin(frame / max(1, frames) * math.pi * 2)))
    top = oy + 1 + (bob if pose in ("idle", "true", "walk", "run") else 0)
    if pose == "run":
        cx += w * 0.06  # 前倾
    if pose == "hurt":
        cx -= w * 0.08
    head_w = max(5, int(w * 0.42))
    head_h = max(5, int(head_w * 0.85))
    body_w = max(6, int(w * 0.5))
    body_h = max(8, int(h * 0.38))
    leg_w = max(2, int(body_w * 0.38))
    leg_h = max(4, int(h * 0.20))
    arm_w = max(2, int(body_w * 0.30))
    arm_h = int(body_h * 0.85)
    ground = oy + h - 1

    hx0, hx1 = cx - head_w / 2, cx + head_w / 2
    hy0, hy1 = top, top + head_h
    c.rect(hx0, hy0, hx1, hy1, col, darker(col))
    eyecol = (235, 235, 245) if pose == "hurt" else accent
    ew = max(1, int(head_w * 0.14))
    for sx in (-1, 1):
        ex = cx + sx * head_w * 0.22 - ew / 2
        c.rect(ex, hy0 + head_h * 0.40, ex + ew, hy0 + head_h * 0.40 + ew, eyecol)

    bx0, bx1 = cx - body_w / 2, cx + body_w / 2
    by0, by1 = hy1 + 1, hy0 + head_h + 1 + body_h
    c.rect(bx0, by0, bx1, by1, col, darker(col))

    ly0 = by1 + 1
    ly1 = min(ground, ly0 + leg_h)
    if pose == "jump":
        ly1 = ly0 + int(leg_h * 0.45)
        c.rect(cx - body_w * 0.30, ly0, cx - body_w * 0.30 + leg_w, ly1, darker(col))
        c.rect(cx + body_w * 0.30 - leg_w, ly0, cx + body_w * 0.30, ly1, darker(col))
    elif pose in ("walk", "run"):
        swing = int(math.sin(frame / max(1, frames) * math.pi) * (2 if pose == "run" else 1))
        c.rect(cx - body_w * 0.32, ly0 + swing, cx - body_w * 0.32 + leg_w, min(ground, ly0 + swing + leg_h), darker(col))
        c.rect(cx + body_w * 0.32 - leg_w, ly0 - swing, cx + body_w * 0.32, min(ground, ly0 - swing + leg_h), darker(col))
    else:
        c.rect(cx - body_w * 0.32, ly0, cx - body_w * 0.32 + leg_w, ly1, darker(col))
        c.rect(cx + body_w * 0.32 - leg_w, ly0, cx + body_w * 0.32, ly1, darker(col))

    ay0 = by0 + body_h * 0.10
    ay1 = ay0 + arm_h
    if pose == "attack":
        c.rect(bx1 - 1, ay0, bx1 + arm_w + 1, ay0 + int(arm_h * 0.55), col, darker(col))
        c.rect(bx1 + arm_w, ay0 - 2, bx1 + arm_w + 2, ay0 + int(arm_h * 0.45), accent)
    else:
        c.rect(bx0 - arm_w, ay0, bx0, ay1, col, darker(col))
        c.rect(bx1, ay0, bx1 + arm_w, ay1, col, darker(col))

    if pose in ("ult", "true"):
        midy = (by0 + by1) / 2
        for a in range(0, 360, 18):
            ang = math.radians(a)
            ax = cx + math.cos(ang) * (body_w * 0.95)
            ay = midy + math.sin(ang) * (body_h * 0.95)
            c.set(int(ax), int(ay), *accent)
        if pose == "true":
            for k in range(4):
                ang = math.radians(k * 90 + frame * 30)
                ax = cx + math.cos(ang) * (body_w * 1.3)
                ay = midy + math.sin(ang) * (body_h * 1.1)
                c.set(int(ax), int(ay), *accent)


def sprite_sheet(path, w, h, frames, col, accent, pose):
    c = Canvas(w * frames, h)
    for f in range(frames):
        draw_humanoid(c, f * w, 0, w, h, col, accent, pose, f, frames)
    c.save(path)


def icon(path, w, h, col, accent, kind="block"):
    c = Canvas(w, h)
    if kind == "block":
        c.rect(1, 1, w - 2, h - 2, col, darker(col))
        c.rect(w * 0.3, h * 0.2, w * 0.7, h * 0.5, accent)
    elif kind == "staff":
        c.rect(w * 0.45, 1, w * 0.65, h - 2, col, darker(col))
        c.circle(w * 0.55, h * 0.2, w * 0.22, accent)
    elif kind == "sword":
        c.rect(w * 0.4, 1, w * 0.6, h - 3, accent)
        c.rect(1, h * 0.5, w - 2, h * 0.62, col, darker(col))
    elif kind == "scythe":
        c.rect(w * 0.4, 1, w * 0.55, h - 2, col, darker(col))
        c.rect(w * 0.4, h * 0.1, w - 2, h * 0.25, accent)
    elif kind == "moon":
        c.circle(w * 0.5, h * 0.5, w * 0.4, accent)
    elif kind == "bubble":
        c.circle(w * 0.5, h * 0.5, w * 0.42, col, )
        c.circle(w * 0.4, h * 0.4, w * 0.12, accent)
    elif kind == "spear":
        c.rect(w * 0.45, 1, w * 0.6, h - 2, accent)
    elif kind == "hammer":
        c.rect(w * 0.45, h * 0.4, w * 0.6, h - 2, col, darker(col))
        c.rect(1, h * 0.3, w * 0.7, h * 0.55, darker(col))
    elif kind == "dual":
        c.rect(w * 0.15, 1, w * 0.35, h - 2, accent)
        c.rect(w * 0.6, 1, w * 0.8, h - 2, accent)
    elif kind == "bow":
        c.rect(w * 0.45, 1, w * 0.6, h - 2, col, darker(col))
        c.rect(w * 0.5, 2, w * 0.55, h - 3, accent)
    c.save(path)


def projectile(path, w, h, col, kind="ball"):
    c = Canvas(w, h)
    if kind == "ball":
        c.circle(w / 2, h / 2, min(w, h) * 0.42, col)
    elif kind == "moon":
        c.circle(w / 2, h / 2, min(w, h) * 0.42, col)
        c.circle(w * 0.35, h * 0.35, min(w, h) * 0.12, (255, 255, 255))
    elif kind == "arrow":
        c.rect(0, h * 0.3, w - 1, h * 0.7, col)
        c.rect(w - 2, h * 0.1, w - 1, h * 0.5, (255, 255, 255))
    elif kind == "arrow_c":
        c.rect(0, h * 0.2, w - 1, h * 0.8, col)
        c.rect(w - 3, 0, w - 1, h, (255, 255, 255))
    c.save(path)


def fx_burst(path, w, h, frames, col):
    c = Canvas(w * frames, h)
    for f in range(frames):
        cx = (f + 0.5) * w
        cy = h / 2
        t = (f + 1) / frames
        r = w * 0.12 + t * w * 0.40
        for a in range(0, 360, 30):
            ang = math.radians(a)
            x = cx + math.cos(ang) * r
            y = cy + math.sin(ang) * r
            c.circle(x, y, max(1, int(w * 0.06 * (1 - t) + 1)), col)
        c.circle(cx, cy, max(1, int(r * 0.5)), col)
    c.save(path)


def fx_orb(path, w, h, frames, col):
    c = Canvas(w * frames, h)
    for f in range(frames):
        cx = (f + 0.5) * w
        r = w * 0.32 + math.sin(f / max(1, frames) * 6.28) * w * 0.08
        c.circle(cx, h / 2, r, col)
        c.circle(cx - r * 0.3, h / 2 - r * 0.3, r * 0.3, (255, 255, 255))
    c.save(path)


def fx_ring(path, w, h, frames, col):
    c = Canvas(w * frames, h)
    for f in range(frames):
        cx = (f + 0.5) * w
        t = (f + 1) / frames
        c.circle(cx, h / 2, max(1, int(t * w * 0.46)), col)
    c.save(path)


def fx_star(path, w, h, frames, col):
    c = Canvas(w * frames, h)
    for f in range(frames):
        cx = (f + 0.5) * w
        cy = h / 2
        r = w * 0.1 + (f + 1) / frames * w * 0.42
        for a in range(0, 360, 45):
            ang = math.radians(a)
            c.circle(cx + math.cos(ang) * r, cy + math.sin(ang) * r, max(1, int(w * 0.07)), col)
        c.circle(cx, cy, max(1, int(w * 0.10)), col)
    c.save(path)


def fx_mist(path, w, h, frames, col):
    c = Canvas(w * frames, h)
    for f in range(frames):
        cx = (f + 0.5) * w
        off = int(math.sin(f / max(1, frames) * 6.28) * w * 0.1)
        for k in range(5):
            c.circle(cx + off + (k - 2) * w * 0.12, h / 2 + (k % 2) * 4, w * 0.10, col)
    c.save(path)


def tile(path, w, h, base, border, variant=0):
    c = Canvas(w, h)
    shade = tuple(max(0, min(255, base[i] + (variant - 3) * 6)) for i in range(3))
    c.rect(0, 0, w - 1, h - 1, shade, border)
    c.rect(w * 0.2, h * 0.2, w * 0.5, h * 0.5, tuple(min(255, shade[i] + 25) for i in range(3)))
    c.save(path)


def cg(path, w, h, bg_top, bg_bot, figure_col, accent, seed=0):
    c = Canvas(w, h)
    for y in range(h):
        t = y / h
        r = int(bg_top[0] * (1 - t) + bg_bot[0] * t)
        g = int(bg_top[1] * (1 - t) + bg_bot[1] * t)
        b = int(bg_top[2] * (1 - t) + bg_bot[2] * t)
        for x in range(w):
            c.set(x, y, r, g, b)
    # 远景方块装饰
    for k in range(8):
        bx = (k * 53 + seed * 17) % w
        by = (k * 37 + seed * 11) % (h - 20) + 10
        c.rect(bx, by, bx + 14, by + 10, (bg_top[0] + 20, bg_top[1] + 20, bg_top[2] + 30))
    # 居中小人
    draw_humanoid(c, w / 2 - 16, h / 2 - 16, 32, 40, figure_col, accent, "idle", seed % 4, 4)
    # 星星
    for k in range(6):
        sx = (k * 71 + seed * 23) % w
        sy = (k * 29 + seed * 7) % (h // 2)
        c.rect(sx - 1, sy, sx + 1, sy + 2, accent)
        c.rect(sx, sy - 1, sx + 1, sy + 1, accent)
    c.save(path)


def ui_title(path, w, h):
    c = Canvas(w, h)
    c.rect(0, h * 0.3, w - 1, h * 0.7, (60, 45, 95))
    draw_humanoid(c, 8, 6, 30, 38, (155, 123, 212), (255, 243, 176), "idle", 0, 4)
    c.rect(w * 0.18, h * 0.1, w * 0.9, h * 0.45, (255, 243, 176))
    c.rect(w * 0.18, h * 0.5, w * 0.9, h * 0.85, (155, 123, 212))
    c.save(path)


def ui_button(path, w, h):
    c = Canvas(w, h)
    c.rect(0, 0, w - 1, h - 1, (80, 60, 130), (200, 180, 255))
    c.save(path)


def ui_head(path, w, h):
    c = Canvas(w, h)
    draw_humanoid(c, 0, 0, w, h, (155, 123, 212), (255, 243, 176), "idle", 0, 4)
    c.save(path)


def ui_crit(path, w, h):
    c = Canvas(w, h)
    c.circle(w / 2, h / 2, w * 0.4, (255, 150, 40))
    c.circle(w / 2, h / 2, w * 0.22, (255, 230, 120))
    c.save(path)


PURPLE = (155, 123, 212)
STAR = (255, 243, 176)
WHITE = (235, 235, 245)

GENERATED = []


def gen(path_rel, fn):
    full = os.path.join(ROOT, path_rel)
    fn(full)
    GENERATED.append(path_rel)


# ---------- 主角 弥绘 ----------
P = "assets/sprites/player"
gen(f"{P}/A-001_idle.png", lambda p: sprite_sheet(p, 32, 32, 4, PURPLE, STAR, "idle"))
gen(f"{P}/A-002_walk.png", lambda p: sprite_sheet(p, 32, 32, 6, PURPLE, STAR, "walk"))
gen(f"{P}/A-003_run.png", lambda p: sprite_sheet(p, 32, 32, 6, PURPLE, STAR, "run"))
gen(f"{P}/A-004_jump.png", lambda p: sprite_sheet(p, 32, 32, 3, PURPLE, STAR, "jump"))
gen(f"{P}/A-005_hurt.png", lambda p: sprite_sheet(p, 32, 32, 2, PURPLE, WHITE, "hurt"))
gen(f"{P}/A-006_dead.png", lambda p: sprite_sheet(p, 32, 32, 6, PURPLE, STAR, "dead"))
gen(f"{P}/A-007_attack.png", lambda p: sprite_sheet(p, 32, 32, 4, PURPLE, STAR, "attack"))
gen(f"{P}/A-008_ult.png", lambda p: sprite_sheet(p, 32, 32, 8, PURPLE, STAR, "ult"))
gen(f"{P}/A-009_true.png", lambda p: sprite_sheet(p, 32, 32, 4, (190, 160, 240), (255, 250, 200), "true"))

# ---------- 第一层敌人：午夜办公室 ----------
E1 = "assets/sprites/enemies/layer1"
gen(f"{E1}/e_overtime_ghost_idle.png", lambda p: sprite_sheet(p, 28, 32, 4, (150, 160, 200), (220, 230, 255), "idle"))
gen(f"{E1}/e_overtime_ghost_attack.png", lambda p: sprite_sheet(p, 28, 32, 3, (150, 160, 200), (220, 230, 255), "attack"))
gen(f"{E1}/e_kpi_idle.png", lambda p: sprite_sheet(p, 24, 24, 3, (220, 80, 80), (255, 220, 120), "idle"))
gen(f"{E1}/e_kpi_attack.png", lambda p: sprite_sheet(p, 24, 24, 3, (220, 80, 80), (255, 220, 120), "attack"))
gen(f"{E1}/e_printer_idle.png", lambda p: sprite_sheet(p, 40, 32, 4, (170, 170, 180), (90, 90, 100), "idle"))
gen(f"{E1}/e_printer_attack.png", lambda p: sprite_sheet(p, 40, 32, 3, (170, 170, 180), (90, 90, 100), "attack"))
gen(f"{E1}/e_meeting_idle.png", lambda p: sprite_sheet(p, 32, 40, 3, (120, 140, 210), (200, 220, 255), "idle"))
gen(f"{E1}/e_meeting_attack.png", lambda p: sprite_sheet(p, 32, 40, 3, (120, 140, 210), (200, 220, 255), "attack"))
gen(f"{E1}/e_phone_idle.png", lambda p: sprite_sheet(p, 24, 32, 4, (90, 200, 160), (220, 255, 240), "idle"))
gen(f"{E1}/e_phone_attack.png", lambda p: sprite_sheet(p, 24, 32, 3, (90, 200, 160), (220, 255, 240), "attack"))

# ---------- 第二层敌人：无尽通勤路 ----------
E2 = "assets/sprites/enemies/layer2"
gen(f"{E2}/e_commuter_idle.png", lambda p: sprite_sheet(p, 28, 32, 4, (140, 140, 150), (220, 220, 230), "idle"))
gen(f"{E2}/e_commuter_attack.png", lambda p: sprite_sheet(p, 28, 32, 3, (140, 140, 150), (220, 220, 230), "attack"))
gen(f"{E2}/e_escalator_idle.png", lambda p: sprite_sheet(p, 48, 24, 3, (180, 170, 120), (120, 110, 70), "idle"))
gen(f"{E2}/e_escalator_attack.png", lambda p: sprite_sheet(p, 48, 24, 3, (180, 170, 120), (120, 110, 70), "attack"))
gen(f"{E2}/e_rider_idle.png", lambda p: sprite_sheet(p, 32, 28, 4, (220, 150, 80), (255, 220, 150), "idle"))
gen(f"{E2}/e_rider_attack.png", lambda p: sprite_sheet(p, 32, 28, 3, (220, 150, 80), (255, 220, 150), "attack"))
gen(f"{E2}/e_revolving_idle.png", lambda p: sprite_sheet(p, 40, 40, 4, (120, 200, 200), (220, 255, 255), "idle"))
gen(f"{E2}/e_revolving_attack.png", lambda p: sprite_sheet(p, 40, 40, 3, (120, 200, 200), (220, 255, 255), "attack"))
gen(f"{E2}/e_package_idle.png", lambda p: sprite_sheet(p, 32, 32, 4, (200, 170, 110), (120, 90, 50), "idle"))
gen(f"{E2}/e_package_attack.png", lambda p: sprite_sheet(p, 32, 32, 3, (200, 170, 110), (120, 90, 50), "attack"))

# ---------- 第三层敌人：深夜崩溃核心 ----------
E3 = "assets/sprites/enemies/layer3"
gen(f"{E3}/e_message_idle.png", lambda p: sprite_sheet(p, 16, 16, 2, (230, 90, 200), (255, 200, 240), "idle"))
gen(f"{E3}/e_message_attack.png", lambda p: sprite_sheet(p, 16, 16, 2, (230, 90, 200), (255, 200, 240), "attack"))
gen(f"{E3}/e_overdue_idle.png", lambda p: sprite_sheet(p, 48, 56, 3, (210, 80, 80), (255, 200, 120), "idle"))
gen(f"{E3}/e_overdue_attack.png", lambda p: sprite_sheet(p, 48, 56, 3, (210, 80, 80), (255, 200, 120), "attack"))
gen(f"{E3}/e_rejected_idle.png", lambda p: sprite_sheet(p, 24, 24, 3, (180, 180, 190), (230, 230, 240), "idle"))
gen(f"{E3}/e_rejected_attack.png", lambda p: sprite_sheet(p, 24, 24, 3, (180, 180, 190), (230, 230, 240), "attack"))
gen(f"{E3}/e_heartbeat_idle.png", lambda p: sprite_sheet(p, 32, 32, 4, (220, 90, 120), (255, 200, 210), "idle"))
gen(f"{E3}/e_heartbeat_attack.png", lambda p: sprite_sheet(p, 32, 32, 3, (220, 90, 120), (255, 200, 210), "attack"))
gen(f"{E3}/e_996_idle.png", lambda p: sprite_sheet(p, 40, 48, 6, (230, 70, 70), (255, 200, 120), "idle"))
gen(f"{E3}/e_996_attack.png", lambda p: sprite_sheet(p, 40, 48, 4, (230, 70, 70), (255, 200, 120), "attack"))

# ---------- Bosses ----------
B = "assets/sprites/bosses"
gen(f"{B}/b_director_idle.png", lambda p: sprite_sheet(p, 80, 64, 4, (120, 60, 140), (255, 200, 120), "idle"))
gen(f"{B}/b_director_attack.png", lambda p: sprite_sheet(p, 80, 64, 4, (120, 60, 140), (255, 200, 120), "attack"))
gen(f"{B}/b_train_idle.png", lambda p: sprite_sheet(p, 128, 48, 4, (90, 120, 160), (200, 230, 255), "idle"))
gen(f"{B}/b_train_attack.png", lambda p: sprite_sheet(p, 128, 48, 5, (90, 120, 160), (200, 230, 255), "attack"))
gen(f"{B}/b_fear_idle.png", lambda p: sprite_sheet(p, 48, 64, 4, (45, 45, 65), (180, 80, 200), "idle"))
gen(f"{B}/b_fear_phase2.png", lambda p: sprite_sheet(p, 64, 80, 5, (120, 40, 140), (255, 120, 200), "idle"))
gen(f"{B}/b_fear_phase3.png", lambda p: sprite_sheet(p, 80, 96, 5, (200, 40, 120), (255, 200, 120), "idle"))
gen(f"{B}/b_fear_phase4.png", lambda p: sprite_sheet(p, 64, 80, 6, (20, 20, 30), (255, 80, 80), "attack"))
gen(f"{B}/b_fear_eye.png", lambda p: sprite_sheet(p, 80, 80, 3, (255, 240, 120), (255, 255, 255), "idle"))

# ---------- 武器图标 ----------
WI = "assets/weapons/icons"
gen(f"{WI}/w_staff.png", lambda p: icon(p, 16, 16, PURPLE, STAR, "staff"))
gen(f"{WI}/w_sword.png", lambda p: icon(p, 16, 16, (180, 200, 255), (240, 250, 255), "sword"))
gen(f"{WI}/w_scythe.png", lambda p: icon(p, 16, 16, (60, 40, 90), (160, 120, 220), "scythe"))
gen(f"{WI}/w_moon.png", lambda p: icon(p, 16, 16, (200, 200, 220), (255, 240, 150), "moon"))
gen(f"{WI}/w_bubble.png", lambda p: icon(p, 16, 16, (120, 180, 255), (220, 240, 255), "bubble"))
gen(f"{WI}/w_spear.png", lambda p: icon(p, 16, 16, (200, 200, 220), (255, 255, 255), "spear"))
gen(f"{WI}/w_hammer.png", lambda p: icon(p, 16, 16, (60, 40, 90), (160, 160, 170), "hammer"))
gen(f"{WI}/w_dual.png", lambda p: icon(p, 16, 16, (200, 200, 220), (255, 240, 150), "dual"))
gen(f"{WI}/w_bow.png", lambda p: icon(p, 16, 16, (120, 90, 200), (255, 240, 150), "bow"))
gen(f"{WI}/w_staff_adv.png", lambda p: icon(p, 16, 16, (200, 170, 90), (255, 240, 150), "staff"))
gen(f"{WI}/w_sword_adv.png", lambda p: icon(p, 16, 16, (120, 255, 220), (240, 255, 255), "sword"))
gen(f"{WI}/w_scythe_adv.png", lambda p: icon(p, 16, 16, (80, 200, 255), (200, 240, 255), "scythe"))

# ---------- 弹射物 ----------
WP = "assets/weapons/projectiles"
gen(f"{WP}/p_staff.png", lambda p: projectile(p, 8, 8, (180, 140, 255), "ball"))
gen(f"{WP}/p_tribolt.png", lambda p: projectile(p, 8, 8, (255, 220, 120), "moon"))
gen(f"{WP}/p_moon.png", lambda p: projectile(p, 12, 12, (255, 240, 150), "moon"))
gen(f"{WP}/p_bubble.png", lambda p: projectile(p, 16, 16, (150, 200, 255), "ball"))
gen(f"{WP}/p_arrow.png", lambda p: projectile(p, 10, 4, (200, 180, 255), "arrow"))
gen(f"{WP}/p_arrow_charge.png", lambda p: projectile(p, 12, 6, (255, 220, 150), "arrow_c"))

# ---------- 特效 FX ----------
FX = "assets/fx"
gen(f"{FX}/fx_crit.png", lambda p: fx_burst(p, 48, 48, 5, (255, 150, 40)))
gen(f"{FX}/fx_expball.png", lambda p: fx_burst(p, 32, 32, 6, (180, 140, 255)))
gen(f"{FX}/fx_xp.png", lambda p: fx_orb(p, 8, 8, 3, (190, 150, 255)))
gen(f"{FX}/fx_crystal.png", lambda p: fx_orb(p, 8, 8, 3, (120, 220, 255)))
gen(f"{FX}/fx_killfade.png", lambda p: fx_mist(p, 32, 32, 5, (150, 120, 220)))
gen(f"{FX}/fx_levelup.png", lambda p: fx_star(p, 64, 64, 8, (255, 240, 150)))
gen(f"{FX}/fx_roomsmoke.png", lambda p: fx_mist(p, 32, 32, 4, (150, 110, 220)))
gen(f"{FX}/fx_ice.png", lambda p: fx_ring(p, 32, 32, 3, (150, 220, 255)))
gen(f"{FX}/fx_shockwave.png", lambda p: fx_ring(p, 64, 16, 5, (200, 200, 220)))

# ---------- 瓦片 Tiles ----------
T = "assets/tiles"
for i in range(8):
    gen(f"{T}/t_floor_{i}.png", lambda p, v=i: tile(p, 16, 16, (70, 64, 96), (40, 36, 60), v))
    gen(f"{T}/t_wall_{i}.png", lambda p, v=i: tile(p, 16, 16, (50, 48, 78), (28, 26, 48), v))
gen(f"{T}/t_door_closed.png", lambda p: sprite_sheet(p, 32, 48, 1, (90, 90, 110), (200, 200, 220), "idle"))
gen(f"{T}/t_door_open.png", lambda p: sprite_sheet(p, 32, 48, 4, (120, 200, 180), (220, 255, 240), "idle"))
gen(f"{T}/t_portal.png", lambda p: sprite_sheet(p, 48, 16, 4, (150, 120, 255), (220, 200, 255), "idle"))
gen(f"{T}/t_chest_closed.png", lambda p: sprite_sheet(p, 16, 16, 1, (180, 150, 90), (255, 240, 150), "idle"))
gen(f"{T}/t_chest_open.png", lambda p: sprite_sheet(p, 16, 16, 5, (180, 150, 90), (255, 240, 150), "idle"))

# ---------- UI ----------
U = "assets/ui"
gen(f"{U}/ui_title.png", lambda p: ui_title(p, 180, 48))
gen(f"{U}/ui_button.png", lambda p: ui_button(p, 80, 18))
gen(f"{U}/ui_head.png", lambda p: ui_head(p, 32, 32))
gen(f"{U}/ui_crit_icon.png", lambda p: ui_crit(p, 16, 16))

# ---------- CG ----------
gen(f"{U}/cg_death_a.png", lambda p: cg(p, 320, 180, (40, 30, 70), (10, 8, 20), PURPLE, STAR, 1))
gen(f"{U}/cg_death_b.png", lambda p: cg(p, 320, 180, (30, 40, 60), (8, 10, 20), (140, 140, 150), (255, 230, 150), 2))
gen(f"{U}/cg_death_c.png", lambda p: cg(p, 320, 180, (60, 20, 40), (15, 5, 15), (40, 40, 60), (255, 120, 120), 3))
gen(f"{U}/cg_birthday.png", lambda p: cg(p, 320, 180, (30, 20, 60), (10, 30, 50), PURPLE, (255, 240, 150), 4))

# ---------- 写清单 ----------
manifest = {"generated": GENERATED, "note": "占位素材为程序生成方块人形；用同名同尺寸 PNG 覆盖即可替换。"}
with open(os.path.join(ROOT, "assets", "GENERATED_PLACEHOLDERS.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)

print("生成占位素材 %d 个" % len(GENERATED))
