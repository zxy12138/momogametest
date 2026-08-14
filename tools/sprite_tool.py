# -*- coding: utf-8 -*-
"""
SpriteTool v2 —— 精灵图工作台（PySide6）

界面：3 列 QSplitter — 切帧 / 帧库+动作 / 预览（看起来像 3 个独立窗口）
核心：SpriteToolCore（chroma_key / detect_frames / build_sheet，无 GUI 依赖可单测）

启动：  <venv>/pythonw.exe sprite_tool.py
       或双击  启动精灵图工具.bat
"""

import sys, os, traceback
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

from PySide6.QtCore import Qt, QTimer, QRectF, QPoint, QMimeData, QSize
from PySide6.QtGui import (
    QImage, QPixmap, QColor, QPainter, QPen, QBrush, QFont,
    QDrag, QPalette,
)
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QLabel, QPushButton, QSlider,
    QSpinBox, QCheckBox, QListWidget, QListWidgetItem, QFrame,
    QVBoxLayout, QHBoxLayout, QGridLayout, QGroupBox, QScrollArea,
    QGraphicsView, QGraphicsScene, QGraphicsPixmapItem, QFileDialog,
    QSplitter, QMessageBox, QAbstractItemView, QLineEdit, QComboBox,
    QListView, QSizePolicy,
)


# ============================================================
# 核心算法（无 GUI 依赖）
# ============================================================

class SpriteToolCore:
    """精灵图处理核心：抠图 / 切帧 / 排列 / 合成。"""

    @staticmethod
    def chroma_key(img: Image.Image, key_rgb, tolerance: int, feather: int) -> Image.Image:
        a = np.asarray(img.convert("RGBA"), dtype=np.float32)
        rgb = a[..., :3]
        key = np.array(key_rgb, dtype=np.float32)
        dist = np.sqrt(((rgb - key) ** 2).sum(axis=-1))
        tol = float(max(1, tolerance))
        alpha = np.clip((dist - tol) / tol, 0.0, 1.0) * 255.0
        if feather > 0:
            alpha_img = Image.fromarray(alpha.astype(np.uint8), "L")
            alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(radius=float(feather)))
            alpha = np.asarray(alpha_img, dtype=np.float32)
        out = np.asarray(img.convert("RGBA")).copy()
        out[..., 3] = alpha.astype(np.uint8)
        return Image.fromarray(out, "RGBA")

    @staticmethod
    def detect_frames(img: Image.Image, mode: str = "auto", rows: int = 1,
                      cols: int = 1, min_gap: int = 2) -> list:
        """检测精灵表中的帧矩形。

        关键改进（v2）：alpha 阈值更严（>64 而非 >24）+ 合并相邻小间隙（min_gap）→
        行框精确对齐，不再因边缘散点延长横线。
        """
        a = np.asarray(img.convert("RGBA"))
        # 更严格的 alpha 阈值：排除边缘半透明/噪点像素
        alpha = a[..., 3] > 64
        h, w = alpha.shape
        if mode == "grid":
            fr_w = w // cols
            fr_h = h // rows
            rects = []
            for r in range(rows):
                for c in range(cols):
                    cell_x0 = c * fr_w
                    cell_y0 = r * fr_h
                    cell_x1 = cell_x0 + fr_w
                    cell_y1 = cell_y0 + fr_h
                    # 紧凑边界：x0/y0 紧贴格子内首内容像素；x1/y1 紧贴末内容像素但不超过格子边界
                    # （保证 frame 不超出格子，横线对齐）
                    cell = alpha[cell_y0:cell_y1, cell_x0:cell_x1]
                    ys2 = np.where(cell.any(axis=1))[0]
                    xs2 = np.where(cell.any(axis=0))[0]
                    if ys2.size == 0 or xs2.size == 0:
                        # 空格子：跳过
                        continue
                    x0 = cell_x0 + int(xs2[0])
                    y0 = cell_y0 + int(ys2[0])
                    x1 = min(cell_x1, cell_x0 + int(xs2[-1]) + 1)
                    y1 = min(cell_y1, cell_y0 + int(ys2[-1]) + 1)
                    rects.append((x0, y0, x1, y1))
            return rects

        # auto：二维检测（v3 紧凑边界）
        # 行 = 投影 y 轴有内容的连续段；行 y0/y1 紧贴首/末内容 y（避免空白延伸）
        # 列同理；行/列间距 < min_gap 视为同一行/列（合并微小断裂）
        def _compact_axis(has_bool, length, min_gap):
            ys = np.where(has_bool)[0]
            if ys.size == 0:
                return []
            segs = []
            start = int(ys[0])
            prev = start
            for y in ys[1:]:
                y = int(y)
                if y - prev > min_gap:
                    segs.append((start, prev + 1))
                    start = y
                prev = y
            segs.append((start, prev + 1))
            return segs

        row_segs = _compact_axis(alpha.any(axis=1), h, min_gap)
        rects = []
        for (ry0, ry1) in row_segs:
            band = alpha[ry0:ry1, :]
            segs = _compact_axis(band.any(axis=0), w, min_gap)
            for (sx, ex) in segs:
                band2 = alpha[ry0:ry1, sx:ex]
                ys2 = np.where(band2.any(axis=1))[0]
                if ys2.size == 0:
                    continue
                # 帧 y0 = 段内首内容 y，y1 = 末内容 y+1（紧贴）
                y0 = ry0 + int(ys2[0])
                y1 = ry0 + int(ys2[-1]) + 1
                rects.append((sx, y0, ex, y1))
        return rects

    @staticmethod
    def crop_frames(img: Image.Image, rects: list, pad: int = 0) -> list:
        return [img.crop((x0 - pad, y0 - pad, x1 + pad, y1 + pad)) for (x0, y0, x1, y1) in rects]

    @staticmethod
    def build_sheet(frames: list, per_row: int, pad: int = 0) -> Image.Image:
        if not frames:
            return None
        fw = max(f.width for f in frames)
        fh = max(f.height for f in frames)
        rows = (len(frames) + per_row - 1) // per_row
        sheet_w = per_row * (fw + pad) - pad
        sheet_h = rows * (fh + pad) - pad
        sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            r, c = divmod(i, per_row)
            sheet.paste(f, (c * (fw + pad), r * (fh + pad)), f)
        return sheet


# ============================================================
# GUI：深色主题
# ============================================================

DARK_QSS = """
QMainWindow, QWidget { background: #1e1f24; color: #e8e8ec; font-size: 13px; }
QGroupBox {
    border: 1px solid #3a3d45; border-radius: 8px;
    margin-top: 10px; padding: 10px 8px 8px 8px; background: #26282f;
}
QGroupBox::title { subcontrol-origin: margin; left: 12px; padding: 0 4px; color: #9fd0ff; }
QLabel { color: #d5d5da; }
QPushButton {
    background: #3a3f4b; color: #f0f0f4; border: 1px solid #4a4f5c;
    border-radius: 6px; padding: 6px 12px;
}
QPushButton:hover { background: #464c5a; }
QPushButton:pressed { background: #2e333d; }
QPushButton:disabled { color: #6a6e78; background: #2c2e35; }
QPushButton#accent { background: #2f6bd8; border-color: #3f7be8; }
QPushButton#accent:hover { background: #3a7ae8; }
QSlider::groove:horizontal { height: 4px; background: #3a3d45; border-radius: 2px; }
QSlider::handle:horizontal { width: 14px; margin: -5px 0; border-radius: 7px; background: #5b8fe8; }
QSpinBox, QDoubleSpinBox, QLineEdit, QComboBox {
    background: #17181c; border: 1px solid #3a3d45; border-radius: 5px;
    padding: 4px 6px; color: #f0f0f4; selection-background-color: #2f6bd8;
}
QListWidget, QListView {
    background: #17181c; border: 1px solid #3a3d45; border-radius: 6px;
    outline: none; padding: 4px;
}
QListWidget::item, QListView::item { padding: 4px; border-radius: 4px; }
QListWidget::item:selected, QListView::item:selected { background: #2f6bd8; color: white; }
QScrollArea { border: none; background: transparent; }
QScrollBar:vertical { background: transparent; width: 10px; }
QScrollBar::handle:vertical { background: #444851; border-radius: 5px; min-height: 30px; }
QScrollBar::add-line, QScrollBar::sub-line { height: 0; }
QCheckBox { spacing: 6px; }
QSplitter::handle { background: #3a3d45; }
QSplitter::handle:horizontal { width: 4px; }
QSplitter::handle:vertical { height: 4px; }
QFrame[frameShape="4"], QFrame[frameShape="5"], QFrame[frameShape="6"], QFrame[frameShape="7"] {
    color: #3a3d45;
}
QToolBar { background: #26282f; border-bottom: 1px solid #3a3d45; spacing: 4px; padding: 4px; }
QStatusBar { background: #1a1b20; border-top: 1px solid #3a3d45; color: #9fd0ff; }
"""


# ============================================================
# 帧缩略图（自定义 QListWidgetItem）
# ============================================================

class FrameItem(QListWidgetItem):
    """帧缩略图项，存全局帧索引 + PIL Image。"""
    def __init__(self, frame_index: int, pil_img: Image.Image, label: str = ""):
        super().__init__(label or f"#{frame_index}")
        self.frame_index = frame_index
        self.pil_img = pil_img
        # 缩略图（48×48）
        if pil_img is not None:
            thumb = pil_img.copy()
            thumb.thumbnail((64, 64), Image.LANCZOS)
            qimg = _pil_to_qimage(thumb)
            self.setIcon(QPixmap.fromImage(qimg))
        self.setSizeHint(QSize(80, 72))
        self.setTextAlignment(Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignBottom)


def _pil_to_qimage(img: Image.Image) -> QImage:
    img = img.convert("RGBA")
    data = img.tobytes("raw", "RGBA")
    qimg = QImage(data, img.width, img.height, QImage.Format.Format_RGBA8888)
    return qimg.copy()


# ============================================================
# 切帧窗口（左侧）
# ============================================================

class CropView(QGraphicsView):
    """带网格的预览视图，支持取色。"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self._scene = QGraphicsScene(self)
        self.setScene(self._scene)
        self.setRenderHints(QPainter.RenderHint.SmoothPixmapTransform)
        self.setDragMode(QGraphicsView.DragMode.ScrollHandDrag)
        self.setTransformationAnchor(QGraphicsView.ViewportAnchor.AnchorUnderMouse)
        self.setBackgroundBrush(QBrush(QColor("#121317")))
        self._item = None
        self.setMinimumSize(420, 320)

    def show_image(self, img: Image.Image):
        self._scene.clear()
        if img is None:
            self._item = None
            return
        qimg = _pil_to_qimage(img)
        pm = QPixmap.fromImage(qimg)
        self._item = self._scene.addPixmap(pm)
        self._scene.setSceneRect(QRectF(pm.rect()))
        self.fitInView(self._item, Qt.AspectRatioMode.KeepAspectRatio)

    def draw_grid(self, rects, img_w=0, img_h=0, color="#3ddc84"):
        if self._item is None:
            return
        # 清除之前可能遗留的 rect（在 pixmap 上重画前清场景）
        self._scene.clear()
        if hasattr(self, "_orig_pm") and self._orig_pm is not None:
            self._item = self._scene.addPixmap(self._orig_pm)
        else:
            return
        if rects:
            pen = QPen(QColor(color), 2)
            for (x0, y0, x1, y1) in rects:
                self._scene.addRect(x0, y0, x1 - x0, y1 - y0, pen)

    def show_with_grid(self, img: Image.Image, rects, color="#3ddc84"):
        """一次性显示图 + 网格（防止 addPixmap 重复）。"""
        self._scene.clear()
        if img is None:
            self._item = None
            return
        qimg = _pil_to_qimage(img)
        pm = QPixmap.fromImage(qimg)
        self._orig_pm = pm
        self._item = self._scene.addPixmap(pm)
        if rects:
            pen = QPen(QColor(color), 2)
            for (x0, y0, x1, y1) in rects:
                self._scene.addRect(x0, y0, x1 - x0, y1 - y0, pen)
        self._scene.setSceneRect(QRectF(pm.rect()))
        self.fitInView(self._item, Qt.AspectRatioMode.KeepAspectRatio)

    def zoom_in(self):
        self.scale(1.25, 1.25)

    def zoom_out(self):
        self.scale(0.8, 0.8)

    def zoom_fit(self):
        if self._item is not None:
            self.fitInView(self._item, Qt.AspectRatioMode.KeepAspectRatio)


class CropPanel(QWidget):
    """切帧面板：参数 + 自动检测 + 切帧。"""
    request_pick = None  # 信号回调：request_pick()

    def __init__(self, main_win):
        super().__init__()
        self.main = main_win
        v = QVBoxLayout(self)
        v.setContentsMargins(6, 6, 6, 6)
        v.setSpacing(6)

        # 预览
        gb = QGroupBox("① 切帧预览")
        gv = QVBoxLayout(gb)
        self.view = CropView()
        gv.addWidget(self.view)
        bar = QHBoxLayout()
        self.btn_zoom_in = QPushButton("＋")
        self.btn_zoom_out = QPushButton("－")
        self.btn_zoom_fit = QPushButton("适应")
        bar.addWidget(self.btn_zoom_in)
        bar.addWidget(self.btn_zoom_out)
        bar.addWidget(self.btn_zoom_fit)
        bar.addStretch(1)
        self.lbl_size = QLabel("未打开")
        bar.addWidget(self.lbl_size)
        gv.addLayout(bar)
        v.addWidget(gb, 1)

        # 抠图参数
        g1 = QGroupBox("颜色抠图")
        g1v = QVBoxLayout(g1)
        r1 = QHBoxLayout()
        self.btn_pick = QPushButton("🎯 吸管取色（点预览图）")
        self.btn_pick.setCheckable(True)
        r1.addWidget(self.btn_pick)
        g1v.addLayout(r1)
        r2 = QHBoxLayout()
        self.color_preview = QLabel()
        self.color_preview.setFixedSize(36, 24)
        self.color_preview.setStyleSheet("background:#000; border:1px solid #555; border-radius:4px;")
        self.lbl_key = QLabel("RGB(0,0,0)")
        r2.addWidget(QLabel("颜色"))
        r2.addWidget(self.color_preview)
        r2.addWidget(self.lbl_key)
        r2.addStretch(1)
        g1v.addLayout(r2)
        # 容差
        r3 = QHBoxLayout()
        r3.addWidget(QLabel("容差"))
        self.sl_tol = QSlider(Qt.Orientation.Horizontal)
        self.sl_tol.setRange(0, 255); self.sl_tol.setValue(30)
        self.lbl_tol = QLabel("30")
        self.lbl_tol.setFixedWidth(40)
        r3.addWidget(self.sl_tol, 1); r3.addWidget(self.lbl_tol)
        g1v.addLayout(r3)
        # 羽化
        r4 = QHBoxLayout()
        r4.addWidget(QLabel("羽化"))
        self.sl_feather = QSlider(Qt.Orientation.Horizontal)
        self.sl_feather.setRange(0, 10); self.sl_feather.setValue(1)
        self.lbl_feather = QLabel("1 px")
        self.lbl_feather.setFixedWidth(50)
        r4.addWidget(self.sl_feather, 1); r4.addWidget(self.lbl_feather)
        g1v.addLayout(r4)
        # RGB 手输
        r5 = QHBoxLayout()
        r5.addWidget(QLabel("R/G/B"))
        self.sp_r = QSpinBox(); self.sp_r.setRange(0, 255)
        self.sp_g = QSpinBox(); self.sp_g.setRange(0, 255)
        self.sp_b = QSpinBox(); self.sp_b.setRange(0, 255)
        r5.addWidget(self.sp_r); r5.addWidget(self.sp_g); r5.addWidget(self.sp_b)
        self.chk_key = QCheckBox("启用抠图"); self.chk_key.setChecked(True)
        r5.addWidget(self.chk_key)
        g1v.addLayout(r5)
        v.addWidget(g1)

        # 切帧参数
        g2 = QGroupBox("切帧参数")
        g2v = QVBoxLayout(g2)
        r6 = QHBoxLayout()
        r6.addWidget(QLabel("模式"))
        self.cmb_mode = QComboBox()
        self.cmb_mode.addItems(["auto（投影）", "grid（网格）"])
        r6.addWidget(self.cmb_mode)
        self.btn_detect = QPushButton("🔍 检测")
        self.btn_detect.setObjectName("accent")
        r6.addWidget(self.btn_detect)
        g2v.addLayout(r6)
        r7 = QHBoxLayout()
        self.sp_rows = QSpinBox(); self.sp_rows.setRange(1, 32); self.sp_rows.setValue(3)
        self.sp_cols = QSpinBox(); self.sp_cols.setRange(1, 32); self.sp_cols.setValue(4)
        r7.addWidget(QLabel("行")); r7.addWidget(self.sp_rows)
        r7.addWidget(QLabel("列")); r7.addWidget(self.sp_cols)
        self.sp_gap = QSpinBox(); self.sp_gap.setRange(1, 30); self.sp_gap.setValue(2)
        r7.addWidget(QLabel("间隙"))
        r7.addWidget(self.sp_gap)
        g2v.addLayout(r7)
        r8 = QHBoxLayout()
        self.sp_pad = QSpinBox(); self.sp_pad.setRange(0, 30); self.sp_pad.setValue(0)
        r8.addWidget(QLabel("裁边留白")); r8.addWidget(self.sp_pad)
        self.btn_apply = QPushButton("✂️ 切出帧")
        self.btn_apply.setObjectName("accent")
        r8.addWidget(self.btn_apply)
        g2v.addLayout(r8)
        self.lbl_frames = QLabel("帧数：0")
        self.lbl_frames.setStyleSheet("color:#9fd0ff;")
        g2v.addWidget(self.lbl_frames)
        v.addWidget(g2)

        # 信号
        self.btn_zoom_in.clicked.connect(self.view.zoom_in)
        self.btn_zoom_out.clicked.connect(self.view.zoom_out)
        self.btn_zoom_fit.clicked.connect(self.view.zoom_fit)
        self.btn_pick.toggled.connect(self._on_pick_toggled)
        self.btn_detect.clicked.connect(self.main._do_detect)
        self.btn_apply.clicked.connect(self.main._do_apply_frames)
        # 滑杆数值实时跟随（修 bug：原版未绑 valueChanged）
        self.sl_tol.valueChanged.connect(lambda v: self.lbl_tol.setText(str(v)))
        self.sl_feather.valueChanged.connect(lambda v: self.lbl_feather.setText(f"{v} px"))
        self.sl_tol.valueChanged.connect(self.main._on_key_param)
        self.sl_feather.valueChanged.connect(self.main._on_key_param)
        self.chk_key.toggled.connect(self.main._on_key_param)
        self.sp_r.valueChanged.connect(self._on_rgb_changed)
        self.sp_g.valueChanged.connect(self._on_rgb_changed)
        self.sp_b.valueChanged.connect(self._on_rgb_changed)
        self.cmb_mode.currentIndexChanged.connect(self._on_mode_changed)

    def _on_pick_toggled(self, on):
        self.main.pick_armed = on
        if on:
            self.btn_pick.setText("点击预览图取色…（再次点击按钮取消）")
        else:
            self.btn_pick.setText("🎯 吸管取色（点预览图）")

    def _on_rgb_changed(self):
        if self.main._src_img is None:
            return
        self.main._on_pick_color((self.sp_r.value(), self.sp_g.value(), self.sp_b.value()))

    def _on_mode_changed(self):
        self.sp_rows.setEnabled(self.cmb_mode.currentIndex() == 1)
        self.sp_cols.setEnabled(self.cmb_mode.currentIndex() == 1)

    def show_color(self, rgb):
        self.color_preview.setStyleSheet(
            "background: rgb(%d,%d,%d); border:1px solid #555; border-radius:4px;" % rgb)
        self.lbl_key.setText("RGB%s" % str(rgb))
        self.sp_r.setValue(rgb[0]); self.sp_g.setValue(rgb[1]); self.sp_b.setValue(rgb[2])


# ============================================================
# 帧库 + 动作管理面板（中间）
# ============================================================

class LibraryPanel(QWidget):
    """帧库 + 动作管理：左侧动作列表，右侧当前动作帧缩略图（可拖拽排序）。"""

    def __init__(self, main_win):
        super().__init__()
        self.main = main_win
        h = QHBoxLayout(self)
        h.setContentsMargins(6, 6, 6, 6)
        h.setSpacing(6)

        # 左：动作列表
        left = QWidget()
        lv = QVBoxLayout(left)
        lv.setContentsMargins(0, 0, 0, 0)
        lv.setSpacing(4)
        lv.addWidget(QLabel("动作列表"))
        self.list_actions = QListWidget()
        self.list_actions.setDragDropMode(QAbstractItemView.DragDropMode.InternalMove)
        self.list_actions.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.list_actions.setMinimumWidth(180)
        lv.addWidget(self.list_actions, 1)
        ab = QHBoxLayout()
        self.btn_new = QPushButton("＋ 新建")
        self.btn_del = QPushButton("🗑")
        self.btn_del.setStyleSheet("color:#ff7a7a;")
        ab.addWidget(self.btn_new); ab.addWidget(self.btn_del)
        lv.addLayout(ab)
        self.ed_name = QLineEdit(); self.ed_name.setPlaceholderText("选中动作后改名（回车）")
        lv.addWidget(self.ed_name)
        h.addWidget(left, 1)

        # 右：帧池（所有未分配帧 + 选中动作的帧）
        right = QWidget()
        rv = QVBoxLayout(right)
        rv.setContentsMargins(0, 0, 0, 0)
        rv.setSpacing(4)
        # 帧池：所有裁出的帧（顶部）
        rv.addWidget(QLabel("帧池（拖拽到下方动作区）"))
        self.pool = QListWidget()
        self.pool.setViewMode(QListView.ViewMode.IconMode)
        self.pool.setIconSize(QSize(56, 56))
        self.pool.setResizeMode(QListView.ResizeMode.Adjust)
        self.pool.setMovement(QListView.Movement.Snap)
        self.pool.setGridSize(QSize(72, 84))
        self.pool.setAcceptDrops(True)
        self.pool.setDragDropMode(QAbstractItemView.DragDropMode.DropOnly)
        self.pool.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.pool.setMinimumHeight(180)
        rv.addWidget(self.pool, 1)

        # 选中动作的帧区
        rv.addWidget(QLabel("选中动作的帧（可拖动重排）"))
        self.acting = QListWidget()
        self.acting.setViewMode(QListView.ViewMode.IconMode)
        self.acting.setIconSize(QSize(56, 56))
        self.acting.setResizeMode(QListView.ResizeMode.Adjust)
        self.acting.setMovement(QListView.Movement.Snap)
        self.acting.setGridSize(QSize(72, 84))
        self.acting.setDragDropMode(QAbstractItemView.DragDropMode.InternalMove)
        self.acting.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.acting.setMinimumHeight(180)
        rv.addWidget(self.acting, 1)

        # 帧操作按钮
        fb = QHBoxLayout()
        self.btn_frame_add = QPushButton("＋ 加入帧")
        self.btn_frame_del = QPushButton("－ 删除帧")
        self.btn_frame_up = QPushButton("↑ 上移")
        self.btn_frame_down = QPushButton("↓ 下移")
        fb.addWidget(self.btn_frame_add)
        fb.addWidget(self.btn_frame_del)
        fb.addWidget(self.btn_frame_up)
        fb.addWidget(self.btn_frame_down)
        fb.addStretch(1)
        rv.addLayout(fb)
        h.addWidget(right, 2)

        # 信号
        self.btn_new.clicked.connect(self.main._new_action)
        self.btn_del.clicked.connect(self.main._del_action)
        self.ed_name.returnPressed.connect(self.main._rename_action)
        self.list_actions.currentItemChanged.connect(self._on_action_changed)
        self.pool.itemClicked.connect(lambda it: self.main._frame_select(it.frame_index))
        self.acting.internalMove = None  # 内部移动由 Qt 处理
        self.btn_frame_add.clicked.connect(self._add_pool_to_acting)
        self.btn_frame_del.clicked.connect(self._del_acting_frame)
        self.btn_frame_up.clicked.connect(lambda: self._move_acting(-1))
        self.btn_frame_down.clicked.connect(lambda: self._move_acting(1))

    def _on_action_changed(self, curr, prev):
        if curr is None:
            return
        self.main._select_action_by_row(self.list_actions.row(curr))
        self.refresh_acting()

    def refresh_actions(self):
        self.list_actions.clear()
        for a in self.main._actions:
            n_frames = len(a.get("frames", []))
            item = QListWidgetItem(f"{a['name']}  ({n_frames} 帧)")
            self.list_actions.addItem(item)

    def refresh_pool(self):
        self.pool.clear()
        for i, f in enumerate(self.main._frames):
            self.pool.addItem(FrameItem(i, f, f"#{i}"))

    def refresh_acting(self):
        self.acting.clear()
        row = self.list_actions.currentRow()
        if row < 0 or row >= len(self.main._actions):
            return
        act = self.main._actions[row]
        for i, f_idx in enumerate(act.get("frames", [])):
            if 0 <= f_idx < len(self.main._frames):
                self.acting.addItem(FrameItem(f_idx, self.main._frames[f_idx], f"#{i}→#{f_idx}"))

    def _add_pool_to_acting(self):
        row = self.list_actions.currentRow()
        if row < 0 or row >= len(self.main._actions):
            return
        items = self.pool.selectedItems()
        if not items:
            return
        act = self.main._actions[row]
        for it in items:
            act.setdefault("frames", []).append(it.frame_index)
        self.refresh_acting()
        self.refresh_actions()  # 更新帧数显示

    def _del_acting_frame(self):
        row = self.list_actions.currentRow()
        if row < 0 or row >= len(self.main._actions):
            return
        items = self.acting.selectedItems()
        if not items:
            return
        act = self.main._actions[row]
        # 按选中顺序删除（从后往前删避免索引错乱）
        idxs = sorted([self.acting.row(it) for it in items], reverse=True)
        for i in idxs:
            if 0 <= i < len(act["frames"]):
                act["frames"].pop(i)
        self.refresh_acting()
        self.refresh_actions()

    def _move_acting(self, d):
        row = self.list_actions.currentRow()
        if row < 0 or row >= len(self.main._actions):
            return
        items = self.acting.selectedItems()
        if not items:
            return
        act = self.main._actions[row]
        frames = act["frames"]
        idxs = sorted([self.acting.row(it) for it in items])
        for i in idxs:
            ni = i + d
            if 0 <= ni < len(frames):
                frames[i], frames[ni] = frames[ni], frames[i]
        self.refresh_acting()
        self.refresh_actions()


# ============================================================
# 预览面板（右侧）
# ============================================================

class PreviewPanel(QWidget):
    """播放预览面板：选中动作大图预览 + 播放控制。"""

    def __init__(self, main_win):
        super().__init__()
        self.main = main_win
        v = QVBoxLayout(self)
        v.setContentsMargins(6, 6, 6, 6)
        v.setSpacing(6)

        gb = QGroupBox("③ 预览（选中动作或全表）")
        gv = QVBoxLayout(gb)
        self.view = CropView()
        gv.addWidget(self.view, 1)
        bar = QHBoxLayout()
        self.cmb_action = QComboBox()
        self.cmb_action.addItem("全表（按动作顺序）")
        bar.addWidget(QLabel("播放"))
        bar.addWidget(self.cmb_action, 1)
        bar.addStretch(1)
        self.btn_play = QPushButton("▶ 播放")
        self.btn_stop = QPushButton("⏹")
        bar.addWidget(self.btn_play)
        bar.addWidget(self.btn_stop)
        gv.addLayout(bar)
        bar2 = QHBoxLayout()
        bar2.addWidget(QLabel("帧率"))
        self.sl_fps = QSlider(Qt.Orientation.Horizontal)
        self.sl_fps.setRange(1, 60); self.sl_fps.setValue(10)
        self.lbl_fps = QLabel("10")
        self.lbl_fps.setFixedWidth(30)
        bar2.addWidget(self.sl_fps, 1); bar2.addWidget(self.lbl_fps)
        bar2.addSpacing(10)
        bar2.addWidget(QLabel("帧"))
        self.lbl_frame = QLabel("0/0")
        self.lbl_frame.setFixedWidth(60)
        bar2.addWidget(self.lbl_frame)
        bar2.addStretch(1)
        self.btn_zoom_in = QPushButton("＋")
        self.btn_zoom_out = QPushButton("－")
        self.btn_zoom_fit = QPushButton("适应")
        bar2.addWidget(self.btn_zoom_out)
        bar2.addWidget(self.btn_zoom_in)
        bar2.addWidget(self.btn_zoom_fit)
        gv.addLayout(bar2)
        v.addWidget(gb, 1)

        self.btn_play.clicked.connect(self.main._play)
        self.btn_stop.clicked.connect(self.main._stop_play)
        self.sl_fps.valueChanged.connect(lambda v: (self.lbl_fps.setText(str(v)), self.main._on_fps(v)))
        self.btn_zoom_in.clicked.connect(self.view.zoom_in)
        self.btn_zoom_out.clicked.connect(self.view.zoom_out)
        self.btn_zoom_fit.clicked.connect(self.view.zoom_fit)
        self.cmb_action.currentIndexChanged.connect(self.main._on_action_pick_changed)


# ============================================================
# 主窗口
# ============================================================

class SpriteToolWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("SpriteTool v2 · 精灵图工作台")
        self.resize(1600, 960)
        self.setStyleSheet(DARK_QSS)

        self._src_img: Image.Image = None
        self._keyed_img: Image.Image = None
        self._rects: list = []
        self._frames: list = []
        self._actions: list = []
        self._key_rgb = (0, 0, 0)
        self.pick_armed = False

        self._play_timer = QTimer(self)
        self._play_timer.timeout.connect(self._tick_play)
        self._play_idx = 0
        self._play_list: list = []

        self._build_ui()
        self._connect()

    def _build_ui(self):
        # 工具栏
        tb = QWidget()
        tbl = QHBoxLayout(tb)
        tbl.setContentsMargins(8, 6, 8, 6)
        self.btn_open = QPushButton("📂 打开精灵图…")
        self.btn_open.setObjectName("accent")
        tbl.addWidget(self.btn_open)
        self.btn_export = QPushButton("💾 导出精灵表 PNG")
        tbl.addWidget(self.btn_export)
        self.btn_export_action = QPushButton("💾 导出选中动作")
        tbl.addWidget(self.btn_export_action)
        tbl.addStretch(1)
        self.lbl_file = QLabel("未打开")
        self.lbl_file.setStyleSheet("color:#8a8e99;")
        tbl.addWidget(self.lbl_file)
        # 上方放工具栏作为 dock（顶部）
        top = QWidget()
        tv = QVBoxLayout(top); tv.setContentsMargins(0, 0, 0, 0); tv.setSpacing(0)
        tv.addWidget(tb)
        tv.addWidget(self._make_sep())

        # 3 列 splitter：切帧 / 帧库 / 预览
        self.crop_panel = CropPanel(self)
        self.lib_panel = LibraryPanel(self)
        self.preview_panel = PreviewPanel(self)

        # 关键：3 个面板看起来像"3 个独立窗口"——给每个标题头 + 边框
        for w, title in [
            (self.crop_panel, "① 切帧"),
            (self.lib_panel, "② 帧库 + 动作"),
            (self.preview_panel, "③ 播放预览"),
        ]:
            w.setObjectName(f"panel_{title[:3]}")
            wrap = QFrame()
            wrap.setFrameShape(QFrame.Shape.StyledPanel)
            wrap.setStyleSheet("QFrame { border: 1px solid #3a3d45; border-radius: 8px; background: #1a1b20; }")
            wlayout = QVBoxLayout(wrap)
            wlayout.setContentsMargins(0, 0, 0, 0)
            # 标题栏
            tb2 = QLabel(title)
            tb2.setStyleSheet("padding: 6px 10px; color: #9fd0ff; font-weight: bold; font-size: 14px; background: #26282f; border-bottom: 1px solid #3a3d45; border-top-left-radius: 8px; border-top-right-radius: 8px;")
            wlayout.addWidget(tb2)
            wlayout.addWidget(w)
            wrap.setTitle = lambda *a: None
            # 把 wrap 存到面板，方便后面布局
            if title.startswith("①"):
                self._crop_wrap = wrap
            elif title.startswith("②"):
                self._lib_wrap = wrap
            else:
                self._prev_wrap = wrap

        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.addWidget(self._crop_wrap)
        splitter.addWidget(self._lib_wrap)
        splitter.addWidget(self._prev_wrap)
        splitter.setSizes([520, 580, 460])
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 1)
        splitter.setStretchFactor(2, 1)

        central = QWidget()
        cv = QVBoxLayout(central); cv.setContentsMargins(0, 0, 0, 0); cv.setSpacing(0)
        cv.addWidget(top)
        cv.addWidget(splitter, 1)
        self.setCentralWidget(central)
        self.statusBar().showMessage("就绪。打开图片 → 吸管取背景色 → 自动检测 → 切出帧。")

    def _make_sep(self):
        f = QFrame(); f.setFrameShape(QFrame.Shape.HLine); f.setStyleSheet("background:#3a3d45;")
        return f

    def _connect(self):
        self.btn_open.clicked.connect(self._open)
        self.btn_export.clicked.connect(self._export_sheet)
        self.btn_export_action.clicked.connect(self._export_action)
        # 切帧面板的 CropView 吸管（点击）
        self.crop_panel.view.mousePressEvent = self._wrap_view_click(self.crop_panel.view.mousePressEvent)
        self.crop_panel.view.viewport().setMouseTracking(True)

    def _wrap_view_click(self, orig):
        """包装 CropView.mousePressEvent，吸管取色。"""
        def new_event(ev):
            if self.pick_armed and ev.button() == Qt.MouseButton.LeftButton:
                view = self.crop_panel.view
                if view._item is not None:
                    sp = view.mapToScene(ev.position().toPoint())
                    pm = view._item.pixmap()
                    x, y = int(sp.x()), int(sp.y())
                    if 0 <= x < pm.width() and 0 <= y < pm.height():
                        qc = pm.toImage().pixelColor(x, y)
                        self._on_pick_color((qc.red(), qc.green(), qc.blue()))
                        # 取色完成退出吸管
                        self.crop_panel.btn_pick.setChecked(False)
                        return
            orig(ev)
        return new_event

    # ---------------- 文件 ----------------
    def _open(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "打开精灵图", "", "图片 (*.png *.jpg *.jpeg *.bmp *.webp *.gif *.tga)")
        if not path:
            return
        try:
            img = Image.open(path).convert("RGBA")
        except Exception as e:
            QMessageBox.warning(self, "打开失败", str(e))
            return
        self._src_img = img
        self.lbl_file.setText(os.path.basename(path))
        self.crop_panel.lbl_size.setText(f"{img.width}×{img.height}")
        self._rects = []
        self._frames = []
        self._actions = []
        self.lib_panel.refresh_actions()
        self.lib_panel.refresh_pool()
        self.lib_panel.refresh_acting()
        self.crop_panel.lbl_frames.setText("帧数：0")
        self._refresh_preview()
        self.statusBar().showMessage("已打开：%s（%d×%d）。🎯 吸管点背景色 → 自动检测 → 切出帧" % (
            os.path.basename(path), img.width, img.height))

    # ---------------- 抠图 / 预览 ----------------
    def _on_pick_color(self, rgb):
        self._key_rgb = rgb
        self.crop_panel.show_color(rgb)
        self._refresh_preview()

    def _current_key(self):
        return (self.crop_panel.sp_r.value(),
                self.crop_panel.sp_g.value(),
                self.crop_panel.sp_b.value())

    def _keyed(self):
        if not self.crop_panel.chk_key.isChecked() or self._src_img is None:
            return self._src_img
        return SpriteToolCore.chroma_key(
            self._src_img, self._current_key(),
            self.crop_panel.sl_tol.value(), self.crop_panel.sl_feather.value())

    def _on_key_param(self):
        self._refresh_preview()

    def _refresh_preview(self):
        if self._src_img is None:
            return
        self._keyed_img = self._keyed()
        self.crop_panel.view.show_with_grid(self._keyed_img, self._rects)

    # ---------------- 切帧 ----------------
    def _do_detect(self):
        if self._keyed_img is None:
            self.statusBar().showMessage("请先打开图片并抠图。", 3000)
            return
        mode = "grid" if self.crop_panel.cmb_mode.currentIndex() == 1 else "auto"
        rows = self.crop_panel.sp_rows.value()
        cols = self.crop_panel.sp_cols.value()
        gap = self.crop_panel.sp_gap.value()
        self._rects = SpriteToolCore.detect_frames(
            self._keyed_img, mode=mode, rows=rows, cols=cols, min_gap=gap)
        self.crop_panel.lbl_frames.setText("帧数：%d（已检测，未裁切）" % len(self._rects))
        self._refresh_preview()
        # 自动按行分组为动作
        if self._rects and not self._actions:
            self._actions = self._row_groups(self._rects)
            self.lib_panel.refresh_actions()
            self.preview_panel.cmb_action.clear()
            self.preview_panel.cmb_action.addItem("全表（按动作顺序）")
            for a in self._actions:
                self.preview_panel.cmb_action.addItem(a["name"])
            self.lib_panel.list_actions.setCurrentRow(0)
        self.statusBar().showMessage("检测到 %d 帧（alpha 阈值 >64 + 间隙合并 min_gap=%d）" % (len(self._rects), gap))

    def _row_groups(self, rects) -> list:
        if not rects:
            return []
        groups = []
        cur_y = rects[0][1]
        cur = []
        for r in rects:
            if r[1] != cur_y and cur:
                groups.append(cur)
                cur = []
                cur_y = r[1]
            cur.append(r)
        if cur:
            groups.append(cur)
        out = []
        for i, g in enumerate(groups):
            out.append({"name": "动作%d" % (i + 1), "frames": list(range(len(self._frames) + sum(len(x["frames"]) for x in out), len(self._frames) + len(g)))})
        # 实际帧索引在 _do_apply_frames 后设置
        return out

    def _do_apply_frames(self):
        if self._keyed_img is None or not self._rects:
            self.statusBar().showMessage("先检测帧（自动/网格）再切出。", 3000)
            return
        pad = self.crop_panel.sp_pad.value()
        self._frames = SpriteToolCore.crop_frames(self._keyed_img, self._rects, pad=pad)
        # 自动按行分配每动作的 frames 列表（按矩形顺序索引）
        self._actions = []
        idx = 0
        cur_y = self._rects[0][1] if self._rects else 0
        group_idx = 0
        cur_list = []
        for r in self._rects:
            if r[1] != cur_y and cur_list:
                self._actions.append({
                    "name": "动作%d" % (group_idx + 1),
                    "frames": cur_list,
                    "rect_y": cur_y,
                })
                group_idx += 1
                cur_list = []
                cur_y = r[1]
            cur_list.append(idx)
            idx += 1
        if cur_list:
            self._actions.append({
                "name": "动作%d" % (group_idx + 1),
                "frames": cur_list,
                "rect_y": cur_y,
            })
        self.lib_panel.refresh_actions()
        self.lib_panel.refresh_pool()
        self.lib_panel.refresh_acting()
        # 更新预览下拉
        self.preview_panel.cmb_action.clear()
        self.preview_panel.cmb_action.addItem("全表（按动作顺序）")
        for a in self._actions:
            self.preview_panel.cmb_action.addItem(a["name"])
        self.lib_panel.list_actions.setCurrentRow(0)
        self.crop_panel.lbl_frames.setText("帧数：%d（已切出）" % len(self._frames))
        self.statusBar().showMessage("已切出 %d 帧，自动分组为 %d 个动作。" % (len(self._frames), len(self._actions)))

    # ---------------- 动作管理 ----------------
    def _new_action(self):
        if not self._frames:
            self.statusBar().showMessage("请先切出帧。", 3000)
            return
        self._actions.append({
            "name": "动作%d" % (len(self._actions) + 1),
            "frames": [],
            "rect_y": 0,
        })
        self.lib_panel.refresh_actions()
        self.lib_panel.list_actions.setCurrentRow(len(self._actions) - 1)
        # 更新预览下拉
        self.preview_panel.cmb_action.addItem(self._actions[-1]["name"])

    def _del_action(self):
        row = self.lib_panel.list_actions.currentRow()
        if row < 0:
            return
        del self._actions[row]
        self.lib_panel.refresh_actions()
        if row < self.lib_panel.list_actions.count():
            self.lib_panel.list_actions.setCurrentRow(row)
        # 预览下拉同步
        self.preview_panel.cmb_action.clear()
        self.preview_panel.cmb_action.addItem("全表（按动作顺序）")
        for a in self._actions:
            self.preview_panel.cmb_action.addItem(a["name"])

    def _rename_action(self):
        row = self.lib_panel.list_actions.currentRow()
        nm = self.lib_panel.ed_name.text().strip()
        if row < 0 or not nm:
            return
        self._actions[row]["name"] = nm
        self.lib_panel.ed_name.clear()
        self.lib_panel.refresh_actions()
        self.lib_panel.list_actions.setCurrentRow(row)
        # 预览下拉同步
        idx = row + 1
        if idx < self.preview_panel.cmb_action.count():
            self.preview_panel.cmb_action.setItemText(idx, nm)

    def _select_action_by_row(self, row):
        if 0 <= row < len(self._actions):
            self.preview_panel.cmb_action.setCurrentIndex(row + 1)

    def _on_action_pick_changed(self, idx):
        pass  # 由播放时按当前选择构建序列

    # ---------------- 播放 ----------------
    def _play_list_build(self) -> list:
        seq = []
        for a in self._actions:
            seq.extend(a.get("frames", []))
        return seq

    def _play(self):
        if not self._frames:
            self.statusBar().showMessage("请先切出帧。", 3000)
            return
        idx = self.preview_panel.cmb_action.currentIndex()
        if idx <= 0:
            seq = self._play_list_build()
        else:
            if idx - 1 < len(self._actions):
                seq = list(self._actions[idx - 1].get("frames", []))
        if not seq:
            self.statusBar().showMessage("当前动作没有帧。", 3000)
            return
        self._play_list = seq
        self._play_idx = 0
        self._play_timer.start(1000 // max(1, self.preview_panel.sl_fps.value()))

    def _stop_play(self):
        self._play_timer.stop()

    def _tick_play(self):
        if not self._play_list or not self._frames:
            self._stop_play()
            return
        fi = self._play_list[self._play_idx]
        if 0 <= fi < len(self._frames):
            self.preview_panel.view.show_image(self._frames[fi])
            self.preview_panel.lbl_frame.setText("%d/%d" % (self._play_idx + 1, len(self._play_list)))
        self._play_idx = (self._play_idx + 1) % len(self._play_list)

    def _on_fps(self, v):
        if self._play_timer.isActive():
            self._play_timer.setInterval(1000 // max(1, v))

    def _frame_select(self, idx):
        # 单击帧池/动作区帧 → 预览
        if 0 <= idx < len(self._frames):
            self.preview_panel.view.show_image(self._frames[idx])
            self.preview_panel.lbl_frame.setText("单帧 #%d" % idx)

    # ---------------- 导出 ----------------
    def _ordered_frames(self):
        seq = self._play_list_build()
        return [self._frames[i] for i in seq if 0 <= i < len(self._frames)]

    def _export_sheet(self):
        frames = self._ordered_frames()
        if not frames:
            QMessageBox.warning(self, "提示", "没有可导出的帧。")
            return
        path, _ = QFileDialog.getSaveFileName(self, "保存精灵表", "sprite_sheet.png", "PNG (*.png)")
        if not path:
            return
        # 默认按 8 列
        sheet = SpriteToolCore.build_sheet(frames, per_row=8)
        sheet.save(path)
        QMessageBox.information(self, "导出成功", "已保存：%s\n%d 帧，每行 8。" % (path, len(frames)))

    def _export_action(self):
        idx = self.preview_panel.cmb_action.currentIndex()
        if idx <= 0 or idx - 1 >= len(self._actions):
            QMessageBox.warning(self, "提示", "请先选中一个动作。")
            return
        act = self._actions[idx - 1]
        frames = [self._frames[i] for i in act.get("frames", []) if 0 <= i < len(self._frames)]
        if not frames:
            QMessageBox.warning(self, "提示", "该动作没有帧。")
            return
        path, _ = QFileDialog.getSaveFileName(self, "保存动作", "%s.png" % act["name"], "PNG (*.png)")
        if not path:
            return
        sheet = SpriteToolCore.build_sheet(frames, per_row=8)
        sheet.save(path)
        QMessageBox.information(self, "导出成功", "动作「%s」%d 帧已保存。" % (act["name"], len(frames)))


def main():
    app = QApplication(sys.argv)
    win = SpriteToolWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()