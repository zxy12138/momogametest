#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
video_to_spritesheet.py —— 视频转透明序列帧 / 精灵图集 工具
=====================================================================
功能：
  1. 选择视频（avi / mp4 / mov / webm / mkv / ogv 等 ffmpeg 支持的格式）
  2. 支持带 Alpha 通道的视频（导出 RGBA PNG，预览用棋盘格显示透明）
  3. 预览界面 + 入点/出点双滑块，定义你要保留的片段
  4. 裁剪（在预览上拖拽矩形，或填数值）
  5. 自动读取分辨率与帧率
  6. 导出透明 PNG（默认只拼成一张精灵表；可勾选「同时导出 PNG 序列」保留单独帧）
  7. 写出与游戏序列帧插件兼容的 index.json（含每帧 x/y/w/h/t）

依赖：Python 3.8+、Pillow、tkinter（标准库）、ffmpeg（外部程序，可配置；本脚本用 ffmpeg -i 读信息，无需 ffprobe）。
核心函数均为模块级，可用 `python video_to_spritesheet.py --selftest` 无头自测。
"""

import os
import re
import sys
import json
import math
import glob
import shutil
import subprocess
import tempfile
import threading
from typing import Optional, List, Tuple, Dict, Any

# GUI 仅在需要时才 import，方便无头自测
try:
    from PIL import Image, ImageDraw
except Exception as exc:  # pragma: no cover
    Image = ImageDraw = None
    _PIL_ERROR = exc

# ImageTk 依赖 tkinter，与核心图像功能解耦：无 tkinter 时 GUI 不可用，但无头自测/核心管线仍可用。
try:
    from PIL import ImageTk
except Exception:  # pragma: no cover
    ImageTk = None


# ============================================================================
# ffmpeg 路径探测
# ============================================================================
_FFMPEG_CANDIDATES = [
    r"D:\Pythonproject\.venv\Scripts\ffmpeg.exe",
    r"D:/Pythonproject/.venv/Scripts/ffmpeg.exe",
    r"/d/Pythonproject/.venv/Scripts/ffmpeg.exe",
    r"D:\Pythonproject\pythonProject\.venv\Scripts\ffmpeg.exe",
    r"D:/Pythonproject/pythonProject/.venv/Scripts/ffmpeg.exe",
    r"/d/Pythonproject/pythonProject/.venv/Scripts/ffmpeg.exe",
    r"C:/ffmpeg/bin/ffmpeg.exe",
    r"D:/ffmpeg/bin/ffmpeg.exe",
]


def find_ffmpeg(explicit: str = "") -> str:
    """返回可用的 ffmpeg 路径，找不到则返回空串。"""
    candidates: List[str] = []
    if explicit:
        candidates.append(explicit)
    candidates.extend(_FFMPEG_CANDIDATES)
    # PATH 里也找一下
    p = shutil.which("ffmpeg")
    if p:
        candidates.append(p)
    for c in candidates:
        if c and os.path.isfile(c):
            return c
    return ""


# ============================================================================
# 核心管线（模块级，可无头调用）
# ============================================================================
def probe_video(ffmpeg_path: str, video_path: str) -> Dict[str, Any]:
    """用 ffmpeg -i 读取视频元数据（不依赖 ffprobe）。返回 dict（width/height/fps/duration/pix_fmt/has_alpha）。"""
    cmd = [ffmpeg_path, "-hide_banner", "-i", video_path]
    # encoding="utf-8" + errors="replace"：ffmpeg 输出（含视频元数据里的中文/UTF-8 字符）不会被
    # Windows 默认 GBK 解码崩掉，无法解码的字节用 � 替换（probe 只取 ASCII 字段，不影响结果）。
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       text=True, encoding="utf-8", errors="replace")
    info = (p.stderr or "") + "\n" + (p.stdout or "")
    # 分辨率：取第一个 Video 流里的 WxH
    width, height = 0, 0
    m = re.search(r"Video:.*?(\d{2,5})x(\d{2,5})", info)
    if m:
        width, height = int(m.group(1)), int(m.group(2))
    # 帧率：第一个 "N fps"
    fps = 0.0
    m = re.search(r"(\d+(?:\.\d+)?)\s*fps", info)
    if m:
        fps = float(m.group(1))
    # 像素格式：Video: codec (…), pixfmt(…)，取逗号后、左括号前的 token
    pix = ""
    m = re.search(r"Video:.*?,\s*([a-z0-9_]+)\s*\(", info)
    if m:
        pix = m.group(1).lower()
    has_alpha = ("a" in pix) and (pix not in ("gray", "monob", "gray8"))
    # 时长：Duration: HH:MM:SS.cc
    dur = 0.0
    m = re.search(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)", info)
    if m:
        dur = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
    return {
        "width": width,
        "height": height,
        "fps": fps,
        "duration": dur,
        "pix_fmt": pix,
        "has_alpha": has_alpha,
    }


def extract_proxy(ffmpeg_path: str, video_path: str, tmpdir: str,
                  max_w: int = 420, proxy_fps: int = 12,
                  alpha: bool = False) -> Tuple[float, List[str]]:
    """抽取低分辨率代理帧用于预览。返回 (proxy_fps, 帧文件路径列表，按时间升序)。"""
    os.makedirs(tmpdir, exist_ok=True)
    scale_vf = f"scale='min({max_w},iw)':-1"
    if alpha:
        vf = f"{scale_vf},fps={proxy_fps}"
        pattern = os.path.join(tmpdir, "p_%05d.png")
        cmd = [ffmpeg_path, "-y", "-i", video_path, "-vf", vf,
               "-pix_fmt", "rgba", pattern]
    else:
        vf = f"{scale_vf},fps={proxy_fps}"
        pattern = os.path.join(tmpdir, "p_%05d.jpg")
        cmd = [ffmpeg_path, "-y", "-i", video_path, "-vf", vf,
               "-q:v", "4", pattern]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    ext = "png" if alpha else "jpg"
    files = sorted(glob.glob(os.path.join(tmpdir, f"p_*.{ext}")))
    return float(proxy_fps), files


def export_frames(ffmpeg_path: str, video_path: str, out_dir: str,
                  in_s: float, out_s: float,
                  crop: Optional[Tuple[int, int, int, int]],
                  target_fps: float) -> List[str]:
    """按入出点+裁剪+目标帧率抽取 RGBA PNG 序列。返回排序后的帧路径列表。"""
    os.makedirs(out_dir, exist_ok=True)
    # 清掉旧帧，避免混入
    for f in glob.glob(os.path.join(out_dir, "frame_*.png")):
        try:
            os.remove(f)
        except OSError:
            pass
    dur = max(0.001, out_s - in_s)
    vf_parts: List[str] = []
    if crop and crop[2] > 0 and crop[3] > 0:
        cx, cy, cw, ch = crop
        vf_parts.append(f"crop={cw}:{ch}:{cx}:{cy}")
    if target_fps and target_fps > 0:
        vf_parts.append(f"fps={target_fps:.4f}")
    pattern = os.path.join(out_dir, "frame_%05d.png")
    cmd = [ffmpeg_path, "-y", "-ss", f"{in_s:.4f}", "-i", video_path,
           "-t", f"{dur:.4f}"]
    if vf_parts:
        cmd += ["-vf", ",".join(vf_parts)]
    cmd += ["-pix_fmt", "rgba", pattern]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    return sorted(glob.glob(os.path.join(out_dir, "frame_*.png")))


def compose_sheet(frame_files: List[str], cols: int,
                  fw: int, fh: int) -> "Image.Image":
    """把若干 RGBA 帧拼成一张精灵表（从左到右、从上到下）。"""
    n = len(frame_files)
    cols = max(1, cols)
    rows = math.ceil(n / cols)
    sheet = Image.new("RGBA", (cols * fw, rows * fh), (0, 0, 0, 0))
    for i, fp in enumerate(frame_files):
        im = Image.open(fp).convert("RGBA")
        if im.size != (fw, fh):
            im = im.resize((fw, fh), Image.NEAREST)
        x = (i % cols) * fw
        y = (i // cols) * fh
        sheet.paste(im, (x, y))
    return sheet


def write_atlas_json(json_path: str, fw: int, fh: int,
                     n_frames: int, cols: int,
                     target_fps: float) -> Dict[str, Any]:
    """写出与游戏序列帧插件兼容的 index.json（字段对齐示例）。"""
    cols = max(1, cols)
    rows = math.ceil(n_frames / cols)
    sheet_w = cols * fw
    sheet_h = rows * fh
    frames = []
    for i in range(n_frames):
        col = i % cols
        row = i // cols
        t = (i / target_fps) if target_fps > 0 else 0.0
        frames.append({
            "i": i,
            "x": col * fw,
            "y": row * fh,
            "w": fw,
            "h": fh,
            "t": round(t, 4),
        })
    doc = {
        "version": "1.0",
        "frame_size": {"w": fw, "h": fh},
        "sheet_size": {"w": sheet_w, "h": sheet_h},
        "frames": frames,
    }
    with open(json_path, "w", encoding="utf-8") as fh_obj:
        json.dump(doc, fh_obj, ensure_ascii=False, indent=2)
    return doc


# ============================================================================
# 无头自测
# ============================================================================
def _selftest() -> int:
    if Image is None:
        print("缺少 Pillow，无法自测。")
        return 2
    ff = find_ffmpeg()
    if not ff:
        print("找不到 ffmpeg，无法自测。")
        return 2
    tmp = tempfile.mkdtemp(prefix="v2s_selftest_")
    print(f"[selftest] ffmpeg={ff}\n[selftest] tmp={tmp}")
    # 1) 造一段带 alpha 的测试视频：128x128，2 秒，12fps
    #    用 .mov + qtrle 才能真正保留 alpha（mp4/h264 不存 alpha）
    vid = os.path.join(tmp, "test_src.mov")
    mk = [ff, "-y", "-f", "lavfi",
          "-i", "color=c=red:s=128x128:d=2:r=12",
          "-vf", "format=rgba", "-c:v", "qtrle", vid]
    subprocess.run(mk, check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    # 2) probe
    meta = probe_video(ff, vid)
    assert meta["width"] == 128 and meta["height"] == 128, meta
    assert abs(meta["fps"] - 12.0) < 0.5, meta
    assert meta["has_alpha"] is True, meta
    print(f"[selftest] probe OK: {meta}")
    # 3) export 0.5s~1.5s，目标 12fps，裁剪 32,32,64,64
    exd = os.path.join(tmp, "frames")
    frames = export_frames(ff, vid, exd, 0.5, 1.5, (32, 32, 64, 64), 12.0)
    assert len(frames) == 12, f"expected 12 frames, got {len(frames)}"
    # 校验裁剪尺寸 + alpha 通道
    im0 = Image.open(frames[0]).convert("RGBA")
    assert im0.size == (64, 64), im0.size
    # RGBA 通道必须保留（透明与否由源决定；纯色源为不透明是正常的）
    assert im0.mode == "RGBA", f"未输出 RGBA（实际 {im0.mode}）"
    print(f"[selftest] export OK: {len(frames)} frames, size={im0.size}")
    # 4) compose + json
    sheet = compose_sheet(frames, cols=4, fw=64, fh=64)
    assert sheet.size == (256, 192), sheet.size  # 4列 x 3行
    sheet_path = os.path.join(tmp, "sheet.png")
    sheet.save(sheet_path)
    jp = os.path.join(tmp, "index.json")
    doc = write_atlas_json(jp, 64, 64, len(frames), 4, 12.0)
    assert doc["sheet_size"]["w"] == 256 and len(doc["frames"]) == 12
    assert doc["frames"][0]["t"] == 0.0 and abs(doc["frames"][1]["t"] - 1/12) < 1e-3
    print(f"[selftest] compose+json OK: sheet={sheet.size}, frames={len(doc['frames'])}")
    # 5) proxy
    pdir = os.path.join(tmp, "proxy")
    pf, pfiles = extract_proxy(ff, vid, pdir, alpha=True)
    assert len(pfiles) >= 20, f"proxy frames={len(pfiles)}"
    print(f"[selftest] proxy OK: {len(pfiles)} frames @ {pf}fps")
    print("[selftest] ALL PASS")
    return 0


# ============================================================================
# GUI
# ============================================================================
def _build_gui() -> None:
    import tkinter as tk
    import tkinter.ttk as ttk
    from tkinter import filedialog, messagebox

    if Image is None:
        messagebox.showerror("依赖缺失", f"缺少 Pillow：{_PIL_ERROR}")
        return

    PROXY_FPS = 12
    MAX_W = 440

    class App(tk.Tk):
        def __init__(self) -> None:
            super().__init__()
            self.title("视频转序列帧 / 精灵图集工具")
            self.geometry("980x720")
            self.minsize(900, 680)

            self.ffmpeg = find_ffmpeg()
            self.video_path = ""
            self.meta: Dict[str, Any] = {}
            self.proxy_fps = PROXY_FPS
            self.proxy_files: List[str] = []
            self.proxy_dir = tempfile.mkdtemp(prefix="v2s_proxy_")
            self._photo = None          # 当前预览 PhotoImage 引用
            self._sheet_photo = None
            self.crop: List[int] = [0, 0, 0, 0]   # x,y,w,h (源像素)
            self._drag = None           # 拖拽状态
            self._scale = 1.0
            self._off = (0, 0)
            self._proxy_size = (0, 0)   # 当前预览的代理帧尺寸（extract_proxy 缩放到 max_w=440，可能与原始视频尺寸不同）
            self._playing = False
            self._play_idx = 0

            self._build_ui()
            self._refresh_ffmpeg_label()

        # ---------------- UI ----------------
        def _build_ui(self) -> None:
            pad = {"padx": 6, "pady": 4}
            # --- ffmpeg ---
            ffm_row = ttk.Frame(self)
            ffm_row.pack(fill="x", **pad)
            ttk.Label(ffm_row, text="ffmpeg:").pack(side="left")
            self._ff_label = ttk.Label(ffm_row, text="", foreground="#666")
            self._ff_label.pack(side="left", padx=4)
            ttk.Button(ffm_row, text="浏览…", command=self._browse_ffmpeg).pack(side="left")
            ttk.Button(ffm_row, text="选择视频…", command=self._browse_video).pack(side="left", padx=8)
            ttk.Button(ffm_row, text="打开输出文件夹", command=self._open_out).pack(side="right")

            # 主区：左预览 / 右设置
            main = ttk.Frame(self)
            main.pack(fill="both", expand=True, **pad)

            left = ttk.LabelFrame(main, text="预览（拖拽可设裁剪区，棋盘格=透明）")
            left.pack(side="left", fill="both", expand=True, padx=(0, 6))
            self.canvas = tk.Canvas(left, bg="#2b2b2b", width=MAX_W, height=300)
            self.canvas.pack(fill="both", expand=True, padx=4, pady=4)
            self.canvas.bind("<ButtonPress-1>", self._on_down)
            self.canvas.bind("<B1-Motion>", self._on_move)
            self.canvas.bind("<ButtonRelease-1>", self._on_up)
            self.canvas.bind("<Configure>", self._on_canvas_configure)

            # 入出点滑块
            sl = ttk.Frame(left)
            sl.pack(fill="x", padx=4, pady=2)
            self.in_s = tk.DoubleVar(value=0.0)
            self.out_s = tk.DoubleVar(value=0.0)
            ttk.Label(sl, text="入点").pack(side="left")
            self.in_scale = ttk.Scale(sl, from_=0, to=1, variable=self.in_s,
                                      command=lambda v: self._on_in())
            self.in_scale.pack(side="left", fill="x", expand=True, padx=4)
            self._in_lbl = ttk.Label(sl, text="0.00s")
            self._in_lbl.pack(side="left")
            ttk.Label(sl, text="出点").pack(side="left", padx=(10, 0))
            self.out_scale = ttk.Scale(sl, from_=0, to=1, variable=self.out_s,
                                       command=lambda v: self._on_out())
            self.out_scale.pack(side="left", fill="x", expand=True, padx=4)
            self._out_lbl = ttk.Label(sl, text="0.00s")
            self._out_lbl.pack(side="left")
            pl = ttk.Frame(left)
            pl.pack(fill="x", padx=4, pady=2)
            self.play_btn = ttk.Button(pl, text="▶ 播放片段", command=self._toggle_play)
            self.play_btn.pack(side="left")
            self._seg_lbl = ttk.Label(pl, text="片段时长: 0.00s", foreground="#666")
            self._seg_lbl.pack(side="left", padx=10)

            right = ttk.Frame(main)
            right.pack(side="right", fill="y", padx=(6, 0))

            info = ttk.LabelFrame(right, text="视频信息（自动读取）")
            info.pack(fill="x", pady=4)
            self._res_lbl = ttk.Label(info, text="分辨率: -")
            self._res_lbl.pack(anchor="w", padx=4)
            self._fps_lbl = ttk.Label(info, text="帧率: -")
            self._fps_lbl.pack(anchor="w", padx=4)
            self._dur_lbl = ttk.Label(info, text="时长: -")
            self._dur_lbl.pack(anchor="w", padx=4)
            self.alpha_var = tk.BooleanVar(value=False)
            self.alpha_chk = ttk.Checkbutton(info, text="源含 Alpha（透明）",
                                             variable=self.alpha_var,
                                             command=self._reproxy)
            self.alpha_chk.pack(anchor="w", padx=4, pady=2)

            cropf = ttk.LabelFrame(right, text="裁剪（源像素）")
            cropf.pack(fill="x", pady=4)
            self._crop_entries: Dict[str, ttk.Entry] = {}
            for key in ("x", "y", "w", "h"):
                row = ttk.Frame(cropf)
                row.pack(fill="x", padx=4, pady=2)
                ttk.Label(row, text=key, width=4).pack(side="left")
                e = ttk.Entry(row)
                e.pack(side="left", fill="x", expand=True)
                e.bind("<Return>", lambda e, k=key: self._on_crop_entry(k))
                e.bind("<FocusOut>", lambda e, k=key: self._on_crop_entry(k))
                self._crop_entries[key] = e
            ttk.Button(cropf, text="重置为整画面",
                       command=self._reset_crop).pack(anchor="e", padx=4, pady=2)

            exp = ttk.LabelFrame(right, text="导出设置")
            exp.pack(fill="x", pady=4)
            self.auto_fps = tk.BooleanVar(value=True)
            af = ttk.Checkbutton(exp, text="保持原帧率", variable=self.auto_fps,
                                 command=self._on_auto_fps)
            af.pack(anchor="w", padx=4)
            row = ttk.Frame(exp)
            row.pack(fill="x", padx=4, pady=2)
            ttk.Label(row, text="目标帧率", width=8).pack(side="left")
            self.fps_entry = ttk.Entry(row, width=8)
            self.fps_entry.pack(side="left", padx=4)
            self.fps_entry.insert(0, "12")
            self.fps_entry.configure(state="disabled")

            row = ttk.Frame(exp)
            row.pack(fill="x", padx=4, pady=2)
            ttk.Label(row, text="每行帧数", width=8).pack(side="left")
            self.cols_entry = ttk.Entry(row, width=8)
            self.cols_entry.pack(side="left", padx=4)
            self.cols_entry.insert(0, "8")

            row = ttk.Frame(exp)
            row.pack(fill="x", padx=4, pady=2)
            ttk.Label(row, text="输出目录", width=8).pack(side="left")
            self.out_dir = tk.StringVar(value="")
            ttk.Entry(row, textvariable=self.out_dir).pack(side="left", fill="x", expand=True, padx=4)
            ttk.Button(row, text="…", width=3, command=self._browse_out).pack(side="left")

            row = ttk.Frame(exp)
            row.pack(fill="x", padx=4, pady=2)
            ttk.Label(row, text="文件名", width=8).pack(side="left")
            self.base_name = tk.StringVar(value="")
            ttk.Entry(row, textvariable=self.base_name).pack(side="left", fill="x", expand=True, padx=4)

            # 是否同时保留单独 PNG 序列（默认否：只保留合成图集一张，避免导出文件过多）
            self.keep_seq = tk.BooleanVar(value=False)
            ttk.Checkbutton(exp, text="同时导出 PNG 序列（单独帧，否则只留图集）",
                            variable=self.keep_seq).pack(anchor="w", padx=4, pady=2)

            ttk.Button(right, text="▶ 导出（图集 + 可选序列）",
                       command=self._run_export).pack(fill="x", pady=6)

            # 日志
            logf = ttk.LabelFrame(self, text="日志")
            logf.pack(fill="both", expand=True, padx=6, pady=(0, 6))
            self.log = tk.Text(logf, height=8, wrap="word")
            self.log.pack(fill="both", expand=True, padx=4, pady=4)

        # ---------------- ffmpeg ----------------
        def _refresh_ffmpeg_label(self) -> None:
            if self.ffmpeg and os.path.isfile(self.ffmpeg):
                self._ff_label.configure(text=self.ffmpeg, foreground="#2a7")
            else:
                self._ff_label.configure(text="未找到 ffmpeg（点浏览指定）", foreground="#c33")

        def _browse_ffmpeg(self) -> None:
            p = filedialog.askopenfilename(title="选择 ffmpeg",
                                           filetypes=[("ffmpeg", "ffmpeg.exe"), ("*", "*")])
            if p:
                self.ffmpeg = p
                self._refresh_ffmpeg_label()

        # ---------------- 视频 ----------------
        def _browse_video(self) -> None:
            p = filedialog.askopenfilename(
                title="选择视频",
                filetypes=[("视频", "*.avi *.mp4 *.mov *.webm *.mkv *.ogv *.flv *.m4v *.wmv"),
                           ("所有文件", "*")])
            if not p:
                return
            self.video_path = p
            self._load_video()

        def _load_video(self) -> None:
            if not self.ffmpeg or not os.path.isfile(self.ffmpeg):
                messagebox.showerror("错误", "请先指定 ffmpeg 路径。")
                return
            try:
                self.meta = probe_video(self.ffmpeg, self.video_path)
            except Exception as e:
                messagebox.showerror("读取失败", str(e))
                return
            w, h = self.meta["width"], self.meta["height"]
            dur = self.meta["duration"]
            fps = self.meta["fps"]
            self._res_lbl.configure(text=f"分辨率: {w}×{h}")
            self._fps_lbl.configure(text=f"帧率: {fps:.3f} fps")
            self._dur_lbl.configure(text=f"时长: {dur:.2f}s")
            self.alpha_var.set(self.meta["has_alpha"])
            # 默认裁剪=整画面
            self.crop = [0, 0, w, h]
            self._set_crop_entries()
            # 滑块范围
            self.in_scale.configure(to=dur)
            self.out_scale.configure(to=dur)
            self.in_s.set(0.0)
            self.out_s.set(dur)
            self._in_lbl.configure(text="0.00s")
            self._out_lbl.configure(text=f"{dur:.2f}s")
            self._seg_lbl.configure(text=f"片段时长: {dur:.2f}s")
            # 默认输出
            d = os.path.dirname(self.video_path)
            self.out_dir.set(d)
            self.base_name.set(os.path.splitext(os.path.basename(self.video_path))[0] + "_sheet")
            self.fps_entry.configure(state="normal")
            self.fps_entry.delete(0, "end")
            self.fps_entry.insert(0, f"{fps:.3f}")
            self.fps_entry.configure(state="disabled")
            self._log(f"已载入: {os.path.basename(self.video_path)}  {w}x{h}  {fps:.3f}fps  {dur:.2f}s  alpha={self.meta['has_alpha']}")
            self._reproxy()

        def _reproxy(self) -> None:
            if not self.meta:
                return
            self._log("正在抽取预览代理帧…")
            try:
                self.proxy_fps, self.proxy_files = extract_proxy(
                    self.ffmpeg, self.video_path, self.proxy_dir,
                    max_w=MAX_W, proxy_fps=PROXY_FPS,
                    alpha=self.alpha_var.get())
                self._log(f"预览帧就绪: {len(self.proxy_files)} 张")
            except Exception as e:
                self._log(f"代理帧抽取失败: {e}")
                self.proxy_files = []
            self._show_frame(self.in_s.get())

        # ---------------- 预览渲染 ----------------
        def _on_canvas_configure(self, event) -> None:
            self._show_frame(self.in_s.get())

        def _proxy_idx_for_time(self, t: float) -> int:
            if not self.proxy_files:
                return 0
            idx = int(round(t * self.proxy_fps))
            return max(0, min(len(self.proxy_files) - 1, idx))

        def _checker(self, size: Tuple[int, int]) -> "Image.Image":
            w, h = size
            bg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            sq = 8
            d = ImageDraw.Draw(bg)
            for yy in range(0, h, sq):
                for xx in range(0, w, sq):
                    if ((xx // sq) + (yy // sq)) % 2 == 0:
                        d.rectangle([xx, yy, xx + sq - 1, yy + sq - 1], fill=(200, 200, 200, 255))
                    else:
                        d.rectangle([xx, yy, xx + sq - 1, yy + sq - 1], fill=(120, 120, 120, 255))
            return bg

        def _show_frame(self, t: float) -> None:
            if not self.proxy_files:
                return
            fp = self.proxy_files[self._proxy_idx_for_time(t)]
            im = Image.open(fp).convert("RGBA")
            # 棋盘格合成（仅当源有 alpha 时显示透明）
            if self.alpha_var.get():
                bg = self._checker(im.size)
                im = Image.alpha_composite(bg, im)
            else:
                im = im.convert("RGB")
            # 适配画布
            cw = self.canvas.winfo_width() or MAX_W
            ch = self.canvas.winfo_height() or 300
            sw, sh = im.size
            scale = min(cw / sw, ch / sh, 1.0)
            dw, dh = max(1, int(sw * scale)), max(1, int(sh * scale))
            disp = im.resize((dw, dh), Image.BILINEAR if not self.alpha_var.get() else Image.NEAREST)
            self._scale = scale
            self._off = ((cw - dw) // 2, (ch - dh) // 2)
            self._proxy_size = (sw, sh)  # 记录代理帧尺寸，供裁剪坐标在「原始视频 ↔ 画布」间换算
            self.canvas.delete("all")
            self._photo = ImageTk.PhotoImage(disp)
            self.canvas.create_image(self._off[0], self._off[1], image=self._photo, anchor="nw")
            self._draw_crop()

        def _draw_crop(self) -> None:
            if not self.meta:
                return
            self.canvas.delete("crop")  # 先清掉上一帧的裁剪框，避免拖拽时矩形/角标叠加残留
            # 原始视频坐标 → 代理帧坐标 → 画布坐标（代理帧缩放到 max_w=440，与原始尺寸不同需换算）
            if self._proxy_size[0] > 0 and self._proxy_size[1] > 0:
                kx = self._proxy_size[0] / float(self.meta["width"])
                ky = self._proxy_size[1] / float(self.meta["height"])
            else:
                kx = ky = 1.0
            x, y, w, h = self.crop
            dx = x * kx * self._scale + self._off[0]
            dy = y * ky * self._scale + self._off[1]
            dw = w * kx * self._scale
            dh = h * ky * self._scale
            self.canvas.create_rectangle(dx, dy, dx + dw, dy + dh,
                                         outline="#ffcc00", width=2, tags="crop")
            # 角标
            for cx, cy in [(dx, dy), (dx + dw, dy), (dx, dy + dh), (dx + dw, dy + dh)]:
                self.canvas.create_oval(cx - 3, cy - 3, cx + 3, cy + 3,
                                        fill="#ffcc00", outline="", tags="crop")

        # ---------------- 裁剪交互 ----------------
        def _canvas_to_src(self, cx: int, cy: int) -> Tuple[int, int]:
            # 画布坐标 → 代理帧坐标 → 原始视频坐标
            if self._proxy_size[0] > 0 and self._proxy_size[1] > 0:
                kx = self.meta["width"] / float(self._proxy_size[0])
                ky = self.meta["height"] / float(self._proxy_size[1])
            else:
                kx = ky = 1.0
            sx = (cx - self._off[0]) / self._scale * kx
            sy = (cy - self._off[1]) / self._scale * ky
            return int(round(sx)), int(round(sy))

        def _on_down(self, event) -> None:
            if not self.meta:
                return
            self._drag = self._canvas_to_src(event.x, event.y)

        def _on_move(self, event) -> None:
            if self._drag is None or not self.meta:
                return
            ex, ey = self._canvas_to_src(event.x, event.y)
            x0, y0 = self._drag
            x = min(x0, ex); y = min(y0, ey)
            w = abs(ex - x0); h = abs(ey - y0)
            W, H = self.meta["width"], self.meta["height"]
            x = max(0, min(x, W)); y = max(0, min(y, H))
            w = max(1, min(w, W - x)); h = max(1, min(h, H - y))
            self.crop = [x, y, w, h]
            self._set_crop_entries()
            self._draw_crop()

        def _on_up(self, event) -> None:
            self._drag = None

        def _set_crop_entries(self) -> None:
            for i, key in enumerate(("x", "y", "w", "h")):
                self._crop_entries[key].delete(0, "end")
                self._crop_entries[key].insert(0, str(self.crop[i]))

        def _on_crop_entry(self, key: str) -> None:
            try:
                v = int(self._crop_entries[key].get())
            except ValueError:
                self._set_crop_entries()
                return
            idx = ("x", "y", "w", "h").index(key)
            self.crop[idx] = v
            # 夹到画面内
            if self.meta:
                W, H = self.meta["width"], self.meta["height"]
                if key in ("x", "w"):
                    self.crop[0] = max(0, min(self.crop[0], W))
                    self.crop[2] = max(1, min(self.crop[2], W - self.crop[0]))
                else:
                    self.crop[1] = max(0, min(self.crop[1], H))
                    self.crop[3] = max(1, min(self.crop[3], H - self.crop[1]))
            self._set_crop_entries()
            self._draw_crop()

        def _reset_crop(self) -> None:
            if self.meta:
                self.crop = [0, 0, self.meta["width"], self.meta["height"]]
                self._set_crop_entries()
                self._draw_crop()

        # ---------------- 入出点 ----------------
        def _on_in(self) -> None:
            v = self.in_s.get()
            if v > self.out_s.get():
                self.out_s.set(v)
            self._in_lbl.configure(text=f"{v:.2f}s")
            self._seg_lbl.configure(text=f"片段时长: {self.out_s.get()-self.in_s.get():.2f}s")
            self._show_frame(v)

        def _on_out(self) -> None:
            v = self.out_s.get()
            if v < self.in_s.get():
                self.in_s.set(v)
            self._out_lbl.configure(text=f"{v:.2f}s")
            self._seg_lbl.configure(text=f"片段时长: {self.out_s.get()-self.in_s.get():.2f}s")
            self._show_frame(v)

        def _toggle_play(self) -> None:
            if self._playing:
                self._playing = False
                self.play_btn.configure(text="▶ 播放片段")
                return
            if not self.proxy_files:
                return
            self._playing = True
            self.play_btn.configure(text="⏸ 停止")
            self._play_idx = self._proxy_idx_for_time(self.in_s.get())
            self._play_tick()

        def _play_tick(self) -> None:
            if not self._playing or not self.proxy_files:
                self._playing = False
                self.play_btn.configure(text="▶ 播放片段")
                return
            t0 = self.in_s.get(); t1 = self.out_s.get()
            t = self._play_idx / self.proxy_fps
            if t > t1:
                self._play_idx = self._proxy_idx_for_time(t0)
                t = t0
            self._show_frame(t)
            self._play_idx += 1
            self.after(1000 // max(1, int(self.proxy_fps)), self._play_tick)

        # ---------------- 导出 ----------------
        def _on_auto_fps(self) -> None:
            if self.auto_fps.get():
                self.fps_entry.configure(state="disabled")
            else:
                self.fps_entry.configure(state="normal")

        def _browse_out(self) -> None:
            d = filedialog.askdirectory(title="选择输出目录")
            if d:
                self.out_dir.set(d)

        def _run_export(self) -> None:
            if not self.video_path or not self.meta:
                messagebox.showerror("错误", "请先选择视频。")
                return
            if not self.ffmpeg or not os.path.isfile(self.ffmpeg):
                messagebox.showerror("错误", "未指定 ffmpeg。")
                return
            out_dir = self.out_dir.get().strip()
            base = self.base_name.get().strip() or "sheet"
            if not out_dir:
                messagebox.showerror("错误", "请指定输出目录。")
                return
            try:
                cols = max(1, int(self.cols_entry.get()))
            except ValueError:
                messagebox.showerror("错误", "每行帧数需为整数。")
                return
            if self.auto_fps.get():
                target_fps = 0.0  # 保持原帧率
            else:
                try:
                    target_fps = float(self.fps_entry.get())
                except ValueError:
                    messagebox.showerror("错误", "目标帧率需为数字。")
                    return
                if target_fps <= 0:
                    messagebox.showerror("错误", "目标帧率需大于 0。")
                    return
            in_s = self.in_s.get(); out_s = self.out_s.get()
            if out_s <= in_s:
                messagebox.showerror("错误", "出点必须晚于入点。")
                return
            src_fps = self.meta["fps"]
            crop = tuple(self.crop) if (self.crop[2] < self.meta["width"] or self.crop[3] < self.meta["height"]) else None
            # 用线程避免界面卡死
            threading.Thread(target=self._export_worker,
                             args=(out_dir, base, cols, target_fps, in_s, out_s, crop, src_fps),
                             daemon=True).start()

        def _export_worker(self, out_dir, base, cols, target_fps, in_s, out_s, crop, src_fps) -> None:
            keep = self.keep_seq.get()
            try:
                self.after(0, lambda: self._log(f"导出中… 入={in_s:.2f}s 出={out_s:.2f}s 裁剪={crop} 目标帧率={'原' if target_fps==0 else target_fps} 保留序列={'是' if keep else '否'}"))
                # 中间帧目录：保留时放输出目录子文件夹；否则用临时目录（导出完即删，只留图集）。
                if keep:
                    frames_dir = os.path.join(out_dir, base + "_frames")
                    os.makedirs(frames_dir, exist_ok=True)
                else:
                    frames_dir = tempfile.mkdtemp(prefix="v2s_frames_")
                frames = export_frames(self.ffmpeg, self.video_path, frames_dir, in_s, out_s, crop, target_fps)
                if not frames:
                    self.after(0, lambda: self._log("错误：未生成任何帧，请检查入出点/裁剪。"))
                    if not keep:
                        shutil.rmtree(frames_dir, ignore_errors=True)
                    return
                # 帧尺寸取首帧
                fw, fh = Image.open(frames[0]).convert("RGBA").size
                eff_fps = target_fps if target_fps > 0 else src_fps
                sheet = compose_sheet(frames, cols, fw, fh)
                sheet_path = os.path.join(out_dir, base + ".png")
                sheet.save(sheet_path)
                json_path = os.path.join(out_dir, base + ".json")
                doc = write_atlas_json(json_path, fw, fh, len(frames), cols, eff_fps)
                # 不保留序列时清理中间帧，保证输出目录只留合成图集 1 张
                if not keep:
                    shutil.rmtree(frames_dir, ignore_errors=True)
                self.after(0, lambda: self._log(
                    f"完成：{len(frames)} 帧，单帧 {fw}x{fh}，图集 {doc['sheet_size']['w']}x{doc['sheet_size']['h']}，帧率 {eff_fps:.3f}"))
                if keep:
                    self.after(0, lambda: self._log(f"序列帧目录（已保留）：\n  {frames_dir}"))
                self.after(0, lambda: self._log(f"产物：\n  {sheet_path}\n  {json_path}"))
                # 缩略图
                thumb = sheet.copy()
                thumb.thumbnail((240, 240))
                self.after(0, lambda: self._show_sheet(thumb, sheet_path))
            except Exception as e:
                self.after(0, lambda: self._log(f"导出失败：{e}"))

        def _show_sheet(self, thumb: "Image.Image", path: str) -> None:
            self._sheet_photo = ImageTk.PhotoImage(thumb)
            top = tk.Toplevel(self)
            top.title("生成的精灵表（缩略图）")
            top.geometry(f"{thumb.width+20}x{thumb.height+60}")
            lbl = ttk.Label(top, text=os.path.basename(path))
            lbl.pack()
            c = tk.Canvas(top, width=thumb.width, height=thumb.height, bg="#2b2b2b")
            c.pack()
            c.create_image(0, 0, image=self._sheet_photo, anchor="nw")

        def _open_out(self) -> None:
            d = self.out_dir.get().strip()
            if d and os.path.isdir(d):
                os.startfile(d) if os.name == "nt" else os.system(f'open "{d}"')
            else:
                messagebox.showinfo("提示", "先选择视频并设定输出目录。")

        # ---------------- 工具 ----------------
        def _log(self, msg: str) -> None:
            self.log.insert("end", msg + "\n")
            self.log.see("end")

    App().mainloop()


def main() -> None:
    if "--selftest" in sys.argv:
        sys.exit(_selftest())
    _build_gui()


if __name__ == "__main__":
    main()
