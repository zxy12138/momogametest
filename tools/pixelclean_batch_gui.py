# -*- coding: utf-8 -*-
"""
PixelClean 批量处理界面 (PySide6)
=================================
对 pixanalyze.exe（AI 像素画转小尺寸游戏像素图工具）做图形化批量封装：
  - 批量添加 PNG/MP4 等文件（可拖拽），多选管理
  - 全部核心参数可视化（算法/颜色数/阈值/尺寸/调色板/去背景/SDF/视频参数）
  - 输出可选「源文件旁」或「统一目录」（-o 重定向，全套产物跟随）
  - QThread 后台执行不卡界面，进度条 + 逐文件日志

运行：
  E:/python project/开发Python插件管理分发系统/.venv/Scripts/python.exe pixelclean_batch_gui.py

核心执行逻辑独立成 build_command / run_batch，便于无头测试与复用。
"""

import os
import subprocess
import sys

from PySide6.QtCore import Qt, QThread, Signal
from PySide6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout, QGroupBox, QFormLayout,
    QLineEdit, QPushButton, QListWidget, QAbstractItemView, QComboBox,
    QSpinBox, QDoubleSpinBox, QCheckBox, QRadioButton, QFileDialog,
    QProgressBar, QPlainTextEdit, QMessageBox, QLabel, QFrame,
)

# ---------------------------------------------------------------- 常量

def _default_exe() -> str:
    """自动定位 pixanalyze.exe：优先脚本旁 tools/pixelclean/publish/，兼容旧位置。"""
    here = os.path.dirname(os.path.abspath(__file__))
    cands = [
        os.path.join(here, "pixelclean", "publish", "pixanalyze.exe"),
        r"E:\python project\pixelclean\publish\pixanalyze.exe",  # 旧位置兼容
    ]
    for c in cands:
        if os.path.isfile(c):
            return c
    return cands[0]


DEFAULT_EXE = _default_exe()

# 可处理的扩展名（图片 + 视频，其余交给 pixanalyze 自动识别）
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".bmp", ".webp", ".gif", ".tga"}
VIDEO_EXTS = {".mp4", ".mov", ".webm", ".avi", ".mkv", ".m4v"}
ALLOWED_EXTS = IMAGE_EXTS | VIDEO_EXTS

# ---------------------------------------------------------------- 核心逻辑（无 GUI 依赖，可独立测试）

def build_command(exe: str, file_path: str, opts: dict, out_dir: str = "") -> list:
    """根据选项拼出 pixanalyze 命令行。

    opts 字段：
      algorithm: 'cluster' | 'greedy'
      max_colors: int
      threshold: float (ΔE)
      size: str  "" 表示自动，否则 "WxH"
      palette: str  "" 表示不传，否则 JSON 的 palette 十六进制串
      sdf: bool
      no_remove_bg: bool
      fps: int  (0 = 原始帧率，仅视频)
      dup_threshold: float (仅视频)
      keep_frames: bool (仅视频)
    out_dir: "" = 输出到源文件旁；否则统一输出目录（-o 重定向，全套产物跟随）
    """
    cmd = [exe, file_path]
    algo = opts.get("algorithm", "cluster")
    if algo in ("cluster", "greedy"):
        cmd += ["--algorithm", algo]
    cmd += ["--max-colors", str(int(opts.get("max_colors", 64)))]
    cmd += ["--threshold", f"{float(opts.get('threshold', 15.0)):.1f}"]
    size = str(opts.get("size", "")).strip()
    if size:
        cmd += ["--size", size]
    palette = str(opts.get("palette", "")).strip()
    if palette:
        cmd += ["--palette", palette]
    if opts.get("sdf", False):
        cmd += ["--sdf"]
    if opts.get("no_remove_bg", False):
        cmd += ["--no-remove-bg"]
    fps = int(opts.get("fps", 0))
    if fps > 0:
        cmd += ["--fps", str(fps)]
        cmd += ["--dup-threshold", f"{float(opts.get('dup_threshold', 0.99)):.2f}"]
        if opts.get("keep_frames", False):
            cmd += ["--keep-frames"]
    if out_dir:
        base = os.path.splitext(os.path.basename(file_path))[0]
        cmd += ["-o", os.path.join(out_dir, base + "_small.png")]
    return cmd


def _decode_output(b: bytes) -> str:
    """优先 utf-8，失败回退 gbk（pixanalyze 中文输出在不同终端编码不同）。"""
    for enc in ("utf-8", "gbk"):
        try:
            return b.decode(enc)
        except UnicodeDecodeError:
            continue
    return b.decode("utf-8", errors="replace")


def run_batch(files: list, opts: dict, out_dir: str = "",
              log_cb=None, progress_cb=None) -> tuple:
    """批量执行。返回 (ok_count, fail_list)。

    log_cb(text: str)      —— 逐条日志回调
    progress_cb(done: int, total: int) —— 进度回调
    同步执行，GUI 里放在 QThread 中调用。
    """
    ok = 0
    fails = []
    total = len(files)
    for i, f in enumerate(files, 1):
        cmd = build_command(str(opts.get("exe", DEFAULT_EXE)), f, opts, out_dir)
        if log_cb:
            log_cb(f"\n[{i}/{total}] {os.path.basename(f)}")
        try:
            proc = subprocess.run(
                cmd, capture_output=True, text=False, timeout=3600,
            )
            out = _decode_output(proc.stdout) + _decode_output(proc.stderr)
            if log_cb:
                # 只展示关键行：已保存/错误/失败
                for line in out.splitlines():
                    s = line.strip()
                    if s and ("已保存" in s or "保存" in s or "错误" in s or "失败" in s
                              or "Error" in s or "error" in s or "Exception" in s):
                        log_cb("   " + s)
                if proc.returncode != 0 and not out.strip():
                    log_cb("   退出码非 0，无输出")
            if proc.returncode == 0:
                ok += 1
            else:
                fails.append((f, out[-300:] if out else f"exit={proc.returncode}"))
        except Exception as e:  # noqa: BLE001
            fails.append((f, str(e)))
            if log_cb:
                log_cb(f"   异常: {e}")
        if progress_cb:
            progress_cb(i, total)
    return ok, fails


def _resolve_exe(opts: dict) -> str:
    """从 opts 取 exe 路径（供 run_batch 使用）。"""
    return str(opts.get("exe", DEFAULT_EXE))


# ---------------------------------------------------------------- 后台线程

class BatchWorker(QThread):
    """后台批量处理线程，避免阻塞界面。"""

    log = Signal(str)
    progress = Signal(int, int)          # (done, total)
    finished_all = Signal(bool, str)     # (全部成功?, 摘要)

    def __init__(self, files: list, opts: dict, out_dir: str, parent=None):
        super().__init__(parent)
        self._files = files
        self._opts = opts
        self._out_dir = out_dir

    def run(self) -> None:
        try:
            ok, fails = run_batch(
                self._files, self._opts, self._out_dir,
                log_cb=lambda t: self.log.emit(t),
                progress_cb=lambda d, t: self.progress.emit(d, t),
            )
            total = len(self._files)
            if fails:
                msg = f"完成：成功 {ok}/{total}，失败 {len(fails)} 个"
                for f, why in fails:
                    msg += f"\n  ✗ {os.path.basename(f)}: {why[:120]}"
            else:
                msg = f"全部完成：{ok}/{total} 个文件处理成功"
            self.finished_all.emit(not fails, msg)
        except Exception as e:  # noqa: BLE001
            self.finished_all.emit(False, f"批量处理异常: {e}")


# ---------------------------------------------------------------- 主窗口

class PixelCleanWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("PixelClean 批量处理工具 · AI 像素画 → 游戏像素图")
        self.resize(920, 700)

        self._worker: BatchWorker | None = None

        self._build_ui()
        self._load_state()

    # ---------------- UI 构建 ----------------
    def _build_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setSpacing(8)

        # ① 工具路径
        exe_box = QGroupBox("PixelClean 工具")
        exe_row = QHBoxLayout(exe_box)
        self.exe_edit = QLineEdit(DEFAULT_EXE)
        self.exe_edit.setPlaceholderText("pixanalyze.exe 路径（默认已定位到 pixelclean/publish/）")
        exe_row.addWidget(self.exe_edit, 1)
        btn = QPushButton("浏览…")
        btn.clicked.connect(self._pick_exe)
        exe_row.addWidget(btn)
        root.addWidget(exe_box)

        # ② 文件列表
        file_box = QGroupBox("待处理文件（PNG 图片 / MP4 视频 · 可直接拖拽文件进来）")
        fv = QVBoxLayout(file_box)
        self.file_list = QListWidget()
        self.file_list.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.file_list.setAcceptDrops(True)
        self.file_list.dragEnterEvent = self._on_drag_enter
        self.file_list.dropEvent = self._on_drop
        fv.addWidget(self.file_list, 1)

        btn_row = QHBoxLayout()
        b_add = QPushButton("➕ 添加文件")
        b_dir = QPushButton("📁 添加文件夹")
        b_del = QPushButton("➖ 移除选中")
        b_clear = QPushButton("🗑 清空")
        b_add.clicked.connect(self._add_files)
        b_dir.clicked.connect(self._add_dir)
        b_del.clicked.connect(self._remove_selected)
        b_clear.clicked.connect(lambda: self.file_list.clear())
        for b in (b_add, b_dir, b_del, b_clear):
            btn_row.addWidget(b)
        btn_row.addStretch(1)
        self.count_label = QLabel("0 个文件")
        btn_row.addWidget(self.count_label)
        fv.addLayout(btn_row)
        root.addWidget(file_box, 1)

        # ③ 参数
        opt_box = QGroupBox("处理参数")
        form = QFormLayout(opt_box)

        self.algo_cb = QComboBox()
        self.algo_cb.addItems(["cluster", "greedy"])
        self.algo_cb.setToolTip("调色板算法：cluster=聚类（默认），greedy=贪心")
        form.addRow("调色板算法", self.algo_cb)

        self.colors_sp = QSpinBox()
        self.colors_sp.setRange(4, 256)
        self.colors_sp.setValue(64)
        form.addRow("最大颜色数", self.colors_sp)

        self.threshold_ds = QDoubleSpinBox()
        self.threshold_ds.setRange(1.0, 50.0)
        self.threshold_ds.setSingleStep(0.5)
        self.threshold_ds.setValue(15.0)
        form.addRow("合并阈值 ΔE", self.threshold_ds)

        self.size_edit = QLineEdit()
        self.size_edit.setPlaceholderText("留空自动检测，如 64x64")
        form.addRow("小图尺寸", self.size_edit)

        self.palette_edit = QLineEdit()
        self.palette_edit.setPlaceholderText("可选：调色板十六进制串（来自上次输出的 JSON palette 字段）")
        form.addRow("参考调色板", self.palette_edit)

        self.sdf_chk = QCheckBox("同时输出 SDF 距离场图")
        form.addRow("辅助图", self.sdf_chk)

        self.nobg_chk = QCheckBox("不删除背景（默认自动去背景）")
        form.addRow("去背景", self.nobg_chk)

        self.fps_sp = QSpinBox()
        self.fps_sp.setRange(0, 120)
        self.fps_sp.setValue(0)
        self.fps_sp.setSpecialValueText("原始帧率")
        self.fps_sp.setToolTip("仅视频有效；>0 时按此帧率拆帧")
        form.addRow("视频帧率", self.fps_sp)

        self.dup_ds = QDoubleSpinBox()
        self.dup_ds.setRange(0.5, 1.0)
        self.dup_ds.setSingleStep(0.01)
        self.dup_ds.setValue(0.99)
        self.dup_ds.setEnabled(False)
        self.fps_sp.valueChanged.connect(
            lambda v: self.dup_ds.setEnabled(v > 0))
        form.addRow("帧去重阈值", self.dup_ds)

        self.keep_chk = QCheckBox("保留 ffmpeg 拆帧原始帧文件")
        self.keep_chk.setEnabled(False)
        self.fps_sp.valueChanged.connect(
            lambda v: self.keep_chk.setEnabled(v > 0))
        form.addRow("视频杂项", self.keep_chk)

        root.addWidget(opt_box)

        # ④ 输出
        out_box = QGroupBox("输出位置")
        ov = QVBoxLayout(out_box)
        self.radio_src = QRadioButton("输出到源文件旁（默认）")
        self.radio_src.setChecked(True)
        self.radio_dir = QRadioButton("输出到统一目录：")
        ov.addWidget(self.radio_src)
        dir_row = QHBoxLayout()
        dir_row.addWidget(self.radio_dir)
        self.out_dir_edit = QLineEdit()
        self.out_dir_edit.setPlaceholderText("选择输出目录（所有产物 small/alpha/edge/json 都会输出到这里）")
        dir_row.addWidget(self.out_dir_edit, 1)
        b_out = QPushButton("浏览…")
        b_out.clicked.connect(self._pick_out_dir)
        dir_row.addWidget(b_out)
        ov.addLayout(dir_row)
        root.addWidget(out_box)

        # ⑤ 执行区
        exec_row = QHBoxLayout()
        self.run_btn = QPushButton("▶ 开始批量处理")
        self.run_btn.setMinimumHeight(40)
        self.run_btn.clicked.connect(self._start)
        exec_row.addWidget(self.run_btn, 1)
        self.progress = QProgressBar()
        self.progress.setRange(0, 1)
        self.progress.setValue(0)
        self.progress.setFormat("%v / %m")
        exec_row.addWidget(self.progress, 2)
        root.addLayout(exec_row)

        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setMaximumBlockCount(2000)
        self.log_view.setPlaceholderText("处理日志会显示在这里…")
        root.addWidget(self.log_view, 2)

    # ---------------- 文件管理 ----------------
    def _add_files(self) -> None:
        files, _ = QFileDialog.getOpenFileNames(
            self, "选择图片 / 视频", "",
            "图片与视频 (*.png *.jpg *.jpeg *.bmp *.webp *.gif *.tga *.mp4 *.mov *.webm *.avi *.mkv *.m4v);;所有文件 (*.*)")
        self._append_files(files)

    def _add_dir(self) -> None:
        d = QFileDialog.getExistingDirectory(self, "选择文件夹（递归收集图片/视频）")
        if not d:
            return
        found = []
        for root_dir, _, names in os.walk(d):
            for n in names:
                ext = os.path.splitext(n)[1].lower()
                if ext in ALLOWED_EXTS:
                    found.append(os.path.join(root_dir, n))
        found.sort()
        self._append_files(found)

    def _remove_selected(self) -> None:
        for item in self.file_list.selectedItems():
            self.file_list.takeItem(self.file_list.row(item))

    def _append_files(self, paths: list) -> None:
        existing = {self.file_list.item(i).text() for i in range(self.file_list.count())}
        added = 0
        for p in paths:
            ext = os.path.splitext(p)[1].lower()
            if ext not in ALLOWED_EXTS:
                continue
            if p not in existing:
                self.file_list.addItem(p)
                existing.add(p)
                added += 1
        self._update_count()

    def _update_count(self) -> None:
        self.count_label.setText(f"{self.file_list.count()} 个文件")

    def _on_drag_enter(self, e) -> None:
        if e.mimeData().hasUrls():
            e.acceptProposedAction()

    def _on_drop(self, e) -> None:
        urls = e.mimeData().urls()
        paths = [u.toLocalFile() for u in urls if u.isLocalFile()]
        self._append_files(paths)

    # ---------------- 路径选择 ----------------
    def _pick_exe(self) -> None:
        f, _ = QFileDialog.getOpenFileName(self, "选择 pixanalyze.exe", "", "pixanalyze (*.exe)")
        if f:
            self.exe_edit.setText(f)

    def _pick_out_dir(self) -> None:
        d = QFileDialog.getExistingDirectory(self, "选择输出目录")
        if d:
            self.out_dir_edit.setText(d)
            self.radio_dir.setChecked(True)

    # ---------------- 参数收集 ----------------
    def _collect_opts(self) -> dict:
        return {
            "exe": self.exe_edit.text().strip() or DEFAULT_EXE,
            "algorithm": self.algo_cb.currentText(),
            "max_colors": self.colors_sp.value(),
            "threshold": self.threshold_ds.value(),
            "size": self.size_edit.text().strip(),
            "palette": self.palette_edit.text().strip(),
            "sdf": self.sdf_chk.isChecked(),
            "no_remove_bg": self.nobg_chk.isChecked(),
            "fps": self.fps_sp.value(),
            "dup_threshold": self.dup_ds.value(),
            "keep_frames": self.keep_chk.isChecked(),
        }

    # ---------------- 执行 ----------------
    def _start(self) -> None:
        if self._worker is not None and self._worker.isRunning():
            QMessageBox.information(self, "提示", "正在处理中，请稍候…")
            return

        files = [self.file_list.item(i).text() for i in range(self.file_list.count())]
        if not files:
            QMessageBox.warning(self, "提示", "请先添加要处理的文件。")
            return
        exe = self.exe_edit.text().strip()
        if not exe or not os.path.isfile(exe):
            QMessageBox.warning(self, "提示", "找不到 pixanalyze.exe，请先选择正确路径。")
            return

        opts = self._collect_opts()
        out_dir = self.out_dir_edit.text().strip() if self.radio_dir.isChecked() else ""

        self.run_btn.setEnabled(False)
        self.run_btn.setText("⏳ 处理中…")
        self.progress.setRange(0, len(files))
        self.progress.setValue(0)
        self.log_view.clear()

        self._worker = BatchWorker(files, opts, out_dir, self)
        self._worker.log.connect(self._on_log)
        self._worker.progress.connect(self._on_progress)
        self._worker.finished_all.connect(self._on_finished)
        self._worker.start()

    def _on_log(self, text: str) -> None:
        self.log_view.appendPlainText(text)

    def _on_progress(self, done: int, total: int) -> None:
        self.progress.setMaximum(total)
        self.progress.setValue(done)

    def _on_finished(self, all_ok: bool, summary: str) -> None:
        self.run_btn.setEnabled(True)
        self.run_btn.setText("▶ 开始批量处理")
        self._on_log("\n" + "=" * 40)
        self._on_log(summary)
        self._save_state()
        if all_ok:
            QMessageBox.information(self, "完成", summary)
        else:
            QMessageBox.warning(self, "完成（有失败）", summary)

    # ---------------- 状态持久化（QSettings 轻量记忆） ----------------
    def _load_state(self) -> None:
        from PySide6.QtCore import QSettings
        s = QSettings("PixelCleanBatch", "BatchGUI")
        exe = s.value("exe", "")
        # 记忆的 exe 已不存在（如迁移后）则回退自动探测的默认路径
        if isinstance(exe, str) and exe and os.path.isfile(exe):
            self.exe_edit.setText(exe)
        else:
            self.exe_edit.setText(DEFAULT_EXE)
        out_dir = s.value("out_dir", "")
        if isinstance(out_dir, str) and out_dir:
            self.out_dir_edit.setText(out_dir)

    def _save_state(self) -> None:
        from PySide6.QtCore import QSettings
        s = QSettings("PixelCleanBatch", "BatchGUI")
        s.setValue("exe", self.exe_edit.text().strip())
        s.setValue("out_dir", self.out_dir_edit.text().strip())


# ---------------------------------------------------------------- 入口

def main() -> int:
    app = QApplication(sys.argv)
    w = PixelCleanWindow()
    w.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
