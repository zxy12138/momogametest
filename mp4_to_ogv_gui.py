#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations  # 兼容 Python 3.8：注解延迟求值，避免 list[str] 在 3.8 运行时报 'type' object is not subscriptable
"""
mp4 -> ogv (Theora) 转换器
面向 Godot 4 的 Theora 视频导入：Godot 只认 .ogv（.ogg 会被当音频导入，视频不显示），
且分辨率需为 16 的倍数（如 1072 而非 1080），否则导入后画面异常。

纯 tkinter 实现，无第三方依赖。ffmpeg/ffprobe 默认指向用户 venv: D:/Pythonproject/.venv/Scripts。
"""

import os
import re
import subprocess
import threading
import queue
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

# ---- ffmpeg 路径（按需修改） ----
FFMPEG = r"D:\Pythonproject\.venv\Scripts\ffmpeg.exe"
FFPROBE = r"D:\Pythonproject\.venv\Scripts\ffprobe.exe"

CREATE_NO_WINDOW = 0x08000000  # Windows: 不弹黑框


class ConverterApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("MP4 → OGV 转换器 (Godot Theora)")
        self.geometry("640x560")
        self.resizable(True, True)

        self._queue: "queue.Queue[tuple[str, str]]" = queue.Queue()  # (kind, text)
        self._proc: "subprocess.Popen[bytes] | None" = None
        self._running = False

        self._build_widgets()
        self._poll_queue()

    # ---------------- UI ----------------
    def _build_widgets(self) -> None:
        pad = {"padx": 8, "pady": 4}
        ffmpeg_note = (f"ffmpeg: {FFMPEG}\n"
                       f"ffprobe: {FFPROBE}")
        ttk.Label(self, text=ffmpeg_note, foreground="#666").pack(anchor="w", **pad)

        # 输入文件
        f_in = ttk.Frame(self)
        f_in.pack(fill="x", **pad)
        ttk.Label(f_in, text="输入 MP4:").pack(side="left")
        self.in_var = tk.StringVar()
        ttk.Entry(f_in, textvariable=self.in_var).pack(side="left", fill="x", expand=True)
        ttk.Button(f_in, text="浏览", command=self._browse_input).pack(side="left")

        # 输出文件
        f_out = ttk.Frame(self)
        f_out.pack(fill="x", **pad)
        ttk.Label(f_out, text="输出 OGV:").pack(side="left")
        self.out_var = tk.StringVar()
        ttk.Entry(f_out, textvariable=self.out_var).pack(side="left", fill="x", expand=True)
        ttk.Button(f_out, text="浏览", command=self._browse_output).pack(side="left")

        # 选项行
        f_opt = ttk.Frame(self)
        f_opt.pack(fill="x", **pad)

        ttk.Label(f_opt, text="视频质量(0-10):").pack(side="left")
        self.vq_var = tk.StringVar(value="7")  # theora qscale，越大越好
        ttk.Spinbox(f_opt, from_=0, to=10, textvariable=self.vq_var, width=6).pack(side="left")

        self.audio_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(f_opt, text="保留音频", variable=self.audio_var).pack(side="left", padx=6)

        ttk.Label(f_opt, text="音频质量(0-10):").pack(side="left")
        self.aq_var = tk.StringVar(value="4")
        ttk.Spinbox(f_opt, from_=0, to=10, textvariable=self.aq_var, width=6).pack(side="left")

        # 16 对齐
        f_align = ttk.Frame(self)
        f_align.pack(fill="x", **pad)
        self.align_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(
            f_align, text="高度/宽度 16 对齐 (Godot Theora 要求，避免导入异常)",
            variable=self.align_var
        ).pack(side="left")

        # 按钮
        f_btn = ttk.Frame(self)
        f_btn.pack(fill="x", **pad)
        self.convert_btn = ttk.Button(f_btn, text="开始转换", command=self._start)
        self.convert_btn.pack(side="left")
        self.open_btn = ttk.Button(f_btn, text="打开输出目录", command=self._open_out_dir)
        self.open_btn.pack(side="left")
        ttk.Button(f_btn, text="清空日志", command=self._clear_log).pack(side="left")

        # 进度条
        self.progress = ttk.Progressbar(self, orient="horizontal", mode="determinate", maximum=1000)
        self.progress.pack(fill="x", **pad)

        # 日志
        ttk.Label(self, text="日志:").pack(anchor="w", **pad)
        self.log = tk.Text(self, height=14, wrap="word")
        self.log.pack(fill="both", expand=True, **pad)
        self._log("就绪。选择 MP4 后点击「开始转换」。", "info")

    # ---------------- 文件选择 ----------------
    def _browse_input(self) -> None:
        path = filedialog.askopenfilename(
            title="选择 MP4 视频",
            filetypes=[("MP4 视频", "*.mp4"), ("所有文件", "*.*")],
        )
        if not path:
            return
        self.in_var.set(path)
        if not self.out_var.get():
            base, _ = os.path.splitext(path)
            self.out_var.set(base + ".ogv")

    def _browse_output(self) -> None:
        path = filedialog.asksaveasfilename(
            title="保存为 OGV",
            defaultextension=".ogv",
            filetypes=[("OGV 视频", "*.ogv")],
        )
        if path:
            self.out_var.set(path)

    def _open_out_dir(self) -> None:
        out = self.out_var.get()
        d = os.path.dirname(out) if out else os.getcwd()
        if os.path.isdir(d):
            os.startfile(d)  # type: ignore[attr-defined]

    # ---------------- 辅助 ----------------
    def _log(self, text: str, kind: str = "info") -> None:
        self._queue.put(("log", f"[{kind}] {text}"))

    def _set_progress(self, frac: float) -> None:
        self._queue.put(("progress", str(int(frac * 1000))))

    def _poll_queue(self) -> None:
        try:
            while True:
                kind, text = self._queue.get_nowait()
                if kind == "log":
                    self.log.insert("end", text + "\n")
                    self.log.see("end")
                elif kind == "progress":
                    self.progress["value"] = int(text)
        except queue.Empty:
            pass
        self.after(100, self._poll_queue)

    def _clear_log(self) -> None:
        self.log.delete("1.0", "end")

    # ---------------- 转换 ----------------
    def _get_duration(self, path: str) -> float:
        try:
            out = subprocess.check_output(
                [FFPROBE, "-v", "error", "-show_entries", "format=duration",
                 "-of", "default=noprint_wrappers=1:nokey=1", path],
                creationflags=CREATE_NO_WINDOW,
            )
            return float(out.decode().strip())
        except Exception as e:  # noqa: BLE001
            self._log(f"获取时长失败（将不显示进度百分比）: {e}", "warn")
            return 0.0

    def _build_cmd(self, inp: str, out: str) -> list[str]:
        vq = self.vq_var.get().strip() or "7"
        cmd: list[str] = [FFMPEG, "-y", "-i", inp, "-c:v", "libtheora", "-q:v", vq]

        if self.align_var.get():
            # 缩放到最近的 16 的倍数（保证 Godot 能正常导入）
            cmd += ["-vf", "scale=trunc(iw/16)*16:trunc(ih/16)*16"]

        if self.audio_var.get():
            aq = self.aq_var.get().strip() or "4"
            cmd += ["-c:a", "libvorbis", "-q:a", aq]
        else:
            cmd += ["-an"]

        cmd += ["-progress", "pipe:1", out]
        return cmd

    def _start(self) -> None:
        if self._running:
            messagebox.showwarning("提示", "正在转换中，请等待完成。")
            return
        inp = self.in_var.get().strip()
        out = self.out_var.get().strip()
        if not inp or not os.path.isfile(inp):
            messagebox.showerror("错误", "请先选择有效的输入 MP4 文件。")
            return
        if not out:
            messagebox.showerror("错误", "请设置输出 OGV 路径。")
            return
        if not (os.path.isfile(FFMPEG) and os.path.isfile(FFPROBE)):
            messagebox.showerror("错误", f"找不到 ffmpeg/ffprobe：\n{FFMPEG}\n{FFPROBE}")
            return

        self._running = True
        self.convert_btn["state"] = "disabled"
        self.progress["value"] = 0
        self._log(f"开始转换: {os.path.basename(inp)}", "info")

        duration = self._get_duration(inp)
        threading.Thread(target=self._run, args=(inp, out, duration), daemon=True).start()

    def _run(self, inp: str, out: str, duration: float) -> None:
        try:
            cmd = self._build_cmd(inp, out)
            self._log("命令: " + " ".join(cmd), "debug")
            self._proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                creationflags=CREATE_NO_WINDOW,
            )
            assert self._proc.stdout is not None
            last_t = 0.0
            for raw in self._proc.stdout:
                line = raw.decode("utf-8", errors="ignore").strip()
                # -progress 输出形如 out_time_ms=1234567
                m = re.search(r"out_time_ms=(\d+)", line)
                if m:
                    ms = int(m.group(1)) / 1_000_000
                    if duration > 0:
                        self._set_progress(min(ms / duration, 1.0))
                    last_t = ms
                elif line:
                    self._queue.put(("log", line))
            rc = self._proc.wait()
            if rc == 0:
                self._log(f"完成！输出大小: {self._human(os.path.getsize(out))}", "ok")
                self._set_progress(1.0)
            else:
                self._log(f"ffmpeg 退出码 {rc}，转换失败。", "error")
        except Exception as e:  # noqa: BLE001
            self._log(f"异常: {e}", "error")
        finally:
            self._running = False
            self.convert_btn["state"] = "normal"
            self._proc = None

    @staticmethod
    def _human(size: int) -> str:
        for unit in ("B", "KB", "MB", "GB"):
            if size < 1024 or unit == "GB":
                return f"{size:.1f} {unit}"
            size /= 1024
        return f"{size:.1f} GB"


if __name__ == "__main__":
    ConverterApp().mainloop()
