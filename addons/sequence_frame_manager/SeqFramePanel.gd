@tool
extends Control
class_name SeqFramePanel

## 序列帧素材管理面板（编辑器底部 Dock，左配置 / 右素材库双栏）。
##
## 工作流：
##   1. ① 选一张图片（序列帧大图 / 单图）。
##   2. ② 帧切分：默认「自动识别」——若同目录有 .json 图集（本项目 index.json / TexturePacker）则用帧矩形；
##      否则用像素算法检测透明间隔推断单元格（无透明间隔则提示手动）。任何模式都可手动覆盖。
##   3. ④ 左栏实时预览（逐帧 / 播放），帧率默认自动（图集时序或 12fps）。
##   4. ③ 生成 SpriteFrames(.tres) + AnimatedSprite2D(.tscn)。
##   5. ⑤ 右栏「素材库」自动列出输出目录已生成的素材，循环预览，可直接拖入任意场景。

const DEFAULT_OUTPUT := "res://Artssucai/gen/"

var _texture: Texture2D = null
var _texture_path: String = ""
var _atlas: Dictionary = {}        # 解析后的图集 JSON（无则为空）
var _json_name: String = ""
var _detected: Dictionary = {"ok": false}  # 像素自动识别结果

# ---- UI 引用（_build_ui 中赋值）----
var _path_edit: LineEdit
var _pick_btn: Button
var _json_label: Label
var _grid_box: VBoxContainer
var _auto_detect: CheckBox
var _frame_w: SpinBox
var _frame_h: SpinBox
var _use_override: CheckBox
var _frames_override: SpinBox
var _auto_fps: CheckBox
var _fps: SpinBox
var _loop: CheckBox
var _name_edit: LineEdit
var _output_edit: LineEdit
var _gen_btn: Button
var _preview_rect: TextureRect
var _preview_caption: Label
var _preview_timer: Timer
var _preview_frames: Array[Texture2D] = []
var _preview_idx: int = 0
var _updating: bool = false
var _prev_btn: Button
var _next_btn: Button
var _play_btn: Button
var _frame_label: Label
var _frame_slider: HSlider
var _status: Label

# ---- 右侧素材库 ----
var _lib_scroll: ScrollContainer
var _lib_list: VBoxContainer
var _lib_timer: Timer
var _lib_items: Array[MaterialItem] = []
var _refresh_btn: Button


func _ready() -> void:
	_build_ui()
	_scan_output()


# ----------------------------------------------------------------------------
# UI 构建（左右双栏）
# ----------------------------------------------------------------------------
func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	# ---------- 左栏：配置 + 预览 ----------
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(380.0, 460.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	root.add_child(_header("① 选择素材图片"))
	var row1 := HBoxContainer.new()
	root.add_child(row1)
	_path_edit = LineEdit.new()
	_path_edit.placeholder_text = "点击右侧按钮选择图片（序列帧大图或单图）"
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.editable = false
	row1.add_child(_path_edit)
	_pick_btn = Button.new()
	_pick_btn.text = "选择图片"
	_pick_btn.pressed.connect(_pick_file)
	row1.add_child(_pick_btn)
	_json_label = Label.new()
	_json_label.text = "尚未选择图片"
	root.add_child(_json_label)

	root.add_child(_header("② 帧切分设置"))
	_grid_box = VBoxContainer.new()
	root.add_child(_grid_box)
	_auto_detect = CheckBox.new()
	_auto_detect.text = "自动识别（像素透明间隔 / 图集 JSON）"
	_auto_detect.button_pressed = true
	_auto_detect.toggled.connect(_on_auto_detect_toggled)
	_grid_box.add_child(_auto_detect)

	var rw := HBoxContainer.new()
	_grid_box.add_child(rw)
	rw.add_child(_label("帧宽(px):"))
	_frame_w = SpinBox.new()
	_frame_w.min_value = 1.0
	_frame_w.max_value = 8192.0
	_frame_w.step = 1.0
	_frame_w.value = 1280.0
	rw.add_child(_frame_w)
	rw.add_child(_label("  帧高(px):"))
	_frame_h = SpinBox.new()
	_frame_h.min_value = 1.0
	_frame_h.max_value = 8192.0
	_frame_h.step = 1.0
	_frame_h.value = 720.0
	rw.add_child(_frame_h)

	var ro := HBoxContainer.new()
	_grid_box.add_child(ro)
	_use_override = CheckBox.new()
	_use_override.text = "手动指定总帧数（覆盖网格推算）"
	ro.add_child(_use_override)
	_frames_override = SpinBox.new()
	_frames_override.min_value = 0.0
	_frames_override.max_value = 100000.0
	_frames_override.step = 1.0
	_frames_override.value = 0.0
	ro.add_child(_frames_override)

	var ro2 := HBoxContainer.new()
	_grid_box.add_child(ro2)
	_auto_fps = CheckBox.new()
	_auto_fps.text = "帧率自动（图集时序 / 默认12）"
	_auto_fps.button_pressed = true
	_auto_fps.toggled.connect(_on_fps_auto_toggled)
	ro2.add_child(_auto_fps)
	ro2.add_child(_label("  手动fps:"))
	_fps = SpinBox.new()
	_fps.min_value = 0.1
	_fps.max_value = 240.0
	_fps.step = 0.5
	_fps.value = 12.0
	_fps.editable = false
	ro2.add_child(_fps)
	_loop = CheckBox.new()
	_loop.text = "循环"
	_loop.button_pressed = true
	ro2.add_child(_loop)

	root.add_child(_header("③ 输出"))
	var rn := HBoxContainer.new()
	root.add_child(rn)
	rn.add_child(_label("素材名:"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "留空则取图片文件名"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rn.add_child(_name_edit)
	var ro3 := HBoxContainer.new()
	root.add_child(ro3)
	ro3.add_child(_label("输出目录:"))
	_output_edit = LineEdit.new()
	_output_edit.text = DEFAULT_OUTPUT
	_output_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ro3.add_child(_output_edit)

	_gen_btn = Button.new()
	_gen_btn.text = "生成素材（.tres + .tscn）"
	_gen_btn.pressed.connect(_generate)
	root.add_child(_gen_btn)

	_status = Label.new()
	_status.text = "就绪"
	root.add_child(_status)

	root.add_child(_header("④ 预览（逐帧 / 播放）"))
	var pv_panel := Panel.new()
	pv_panel.custom_minimum_size = Vector2(0.0, 200.0)
	pv_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(pv_panel)
	_preview_rect = TextureRect.new()
	_preview_rect.position = Vector2(8.0, 8.0)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.custom_minimum_size = Vector2(280.0, 144.0)
	_preview_rect.size = Vector2(280.0, 144.0)
	pv_panel.add_child(_preview_rect)
	_preview_caption = Label.new()
	_preview_caption.text = "（未选择图片 —— 点上方「选择图片」后这里显示预览）"
	_preview_caption.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	root.add_child(_preview_caption)

	var ctrl := HBoxContainer.new()
	root.add_child(ctrl)
	_prev_btn = Button.new()
	_prev_btn.text = "上一帧"
	_prev_btn.pressed.connect(_on_prev_pressed)
	ctrl.add_child(_prev_btn)
	_play_btn = Button.new()
	_play_btn.text = "播放"
	_play_btn.pressed.connect(_on_play_pressed)
	ctrl.add_child(_play_btn)
	_next_btn = Button.new()
	_next_btn.text = "下一帧"
	_next_btn.pressed.connect(_on_next_pressed)
	ctrl.add_child(_next_btn)
	_frame_label = Label.new()
	_frame_label.text = "第 0 / 0 帧"
	_frame_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	ctrl.add_child(_frame_label)

	_frame_slider = HSlider.new()
	_frame_slider.min_value = 0.0
	_frame_slider.max_value = 0.0
	_frame_slider.step = 1.0
	_frame_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_slider.value_changed.connect(_on_slider_changed)
	root.add_child(_frame_slider)

	_preview_timer = Timer.new()
	_preview_timer.wait_time = 1.0 / 12.0
	_preview_timer.timeout.connect(_on_preview_timeout)
	add_child(_preview_timer)

	# ---------- 右栏：素材库 ----------
	var lib_box := VBoxContainer.new()
	lib_box.custom_minimum_size = Vector2(240.0, 0.0)
	lib_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lib_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(lib_box)
	lib_box.add_child(_header("⑤ 素材库（循环预览 · 可拖入场景）"))
	var lib_top := HBoxContainer.new()
	lib_box.add_child(lib_top)
	lib_top.add_child(_label("输出目录同上 ③"))
	_refresh_btn = Button.new()
	_refresh_btn.text = "重新扫描"
	_refresh_btn.pressed.connect(_scan_output)
	lib_top.add_child(_refresh_btn)
	_lib_scroll = ScrollContainer.new()
	_lib_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lib_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lib_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lib_box.add_child(_lib_scroll)
	_lib_list = VBoxContainer.new()
	_lib_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lib_scroll.add_child(_lib_list)
	_lib_timer = Timer.new()
	_lib_timer.wait_time = 1.0 / 12.0
	_lib_timer.timeout.connect(_on_lib_timeout)
	add_child(_lib_timer)
	_lib_timer.start()

	# 设置项变更实时重算（仅已选图时）
	_frame_w.value_changed.connect(_on_settings_changed)
	_frame_h.value_changed.connect(_on_settings_changed)
	_use_override.toggled.connect(_on_settings_changed)
	_frames_override.value_changed.connect(_on_settings_changed)
	_fps.value_changed.connect(_on_settings_changed)
	_loop.toggled.connect(_on_settings_changed)


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	var f := l.get_theme_font("font")
	if f != null:
		l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	return l


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


# ----------------------------------------------------------------------------
# 文件选择
# ----------------------------------------------------------------------------
func _pick_file() -> void:
	var fd := EditorFileDialog.new()
	fd.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	fd.access = EditorFileDialog.ACCESS_RESOURCES
	fd.add_filter("*.png,*.jpg,*.jpeg,*.webp,*.bmp,*.tga ; 图片素材")
	fd.current_path = _texture_path if _texture_path != "" else "res://"
	fd.file_selected.connect(_on_image_selected.bind(fd))
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(900, 600))


func _on_image_selected(path: String, fd: EditorFileDialog) -> void:
	fd.queue_free()
	_texture_path = path
	var res := load(path)
	if res is Texture2D:
		_texture = res as Texture2D
	else:
		_texture = null
		_set_status("无法加载为纹理：%s" % path, true)
		return

	_atlas = _find_atlas(path.get_base_dir())
	_auto_detect.button_pressed = true
	_auto_detect.disabled = false
	_grid_box.visible = true
	_detected = {"ok": false}

	if not _atlas.is_empty():
		_json_label.text = "已探测到图集 JSON：%s（使用其中的帧矩形）" % _json_name
		var fs: Variant = _atlas.get("frame_size", {})
		if fs is Dictionary and fs.has("w") and fs.has("h"):
			_frame_w.value = float(fs["w"])
			_frame_h.value = float(fs["h"])
		_auto_detect.disabled = true
	elif _texture.has_alpha():
		_detected = _detect_grid()
		if _detected.get("ok", false):
			var cell: Vector2 = _detected["cell"]
			var cols: int = int(_detected["cols"])
			var rows: int = int(_detected["rows"])
			_frame_w.value = cell.x
			_frame_h.value = cell.y
			_json_label.text = "自动识别：%d×%d 网格，单元格 %d×%d（也可手动覆盖）" \
				% [cols, rows, int(cell.x), int(cell.y)]
		else:
			_json_label.text = "有透明通道但无法稳定识别间隔，请手动输入帧宽/帧高"
	else:
		_json_label.text = "图片无透明通道，无法自动识别网格，请手动输入帧宽/帧高"

	_path_edit.text = path
	if _name_edit.text.is_empty():
		_name_edit.text = path.get_file().get_basename()
	_rebuild_preview()
	_update_frame_info()


# ----------------------------------------------------------------------------
# 图集探测与帧矩形收集
# ----------------------------------------------------------------------------
func _find_atlas(dir_path: String) -> Dictionary:
	var da := DirAccess.open(dir_path)
	if da == null:
		return {}
	for f in da.get_files():
		if f.get_extension().to_lower() == "json":
			var txt := FileAccess.get_file_as_string(dir_path.path_join(f))
			if txt.is_empty():
				continue
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary and (parsed as Dictionary).has("frames"):
				_json_name = f
				return parsed as Dictionary
	return {}


## 像素算法：检测不透明「帧带」，推断单元格(stride，含透明间隔)与行列数。
## 无透明通道 / 无法稳定识别时返回 ok=false。
func _detect_grid() -> Dictionary:
	if _texture == null or not _texture.has_alpha():
		return {"ok": false}
	var img := _texture.get_image()
	if img == null:
		return {"ok": false}
	var w := img.get_width()
	var h := img.get_height()
	var xb: Array[Dictionary] = _find_opaque_bands(img, true)
	var yb: Array[Dictionary] = _find_opaque_bands(img, false)
	if xb.is_empty() or yb.is_empty():
		return {"ok": false}
	var xw := int(xb[0]["w"])
	var yw := int(yb[0]["w"])
	var xc: PackedInt32Array = []
	var yc: PackedInt32Array = []
	for b in xb:
		xc.append(int(b["c"]))
	for b in yb:
		yc.append(int(b["c"]))
	var sx := _modal_gap(xc)
	var sy := _modal_gap(yc)
	if sx <= 0 or sy <= 0:
		return {"ok": false}
	# 列/行数用 (总长-帧宽)/stride + 1，避免末位间隔导致漏掉最后一帧。
	var cols := int((w - xw) / sx) + 1
	var rows := int((h - yw) / sy) + 1
	if cols < 1 or rows < 1 or cols * xw > w + 1 or rows * yw > h + 1:
		return {"ok": false}
	return {"ok": true, "cell": Vector2(sx, sy), "cols": cols, "rows": rows}


## 返回同维内「不透明帧带」列表（每带含中心 c 与宽度 w）。垂直=true 看列，false 看行。
func _find_opaque_bands(img: Image, vertical: bool) -> Array[Dictionary]:
	var size := img.get_width() if vertical else img.get_height()
	var other := img.get_height() if vertical else img.get_width()
	var bands: Array[Dictionary] = []
	var in_band := false
	var start := 0
	for i in size:
		var opaque := false
		for j in other:
			var x := i if vertical else j
			var y := j if vertical else i
			if img.get_pixel(x, y).a > 0.01:
				opaque = true
				break
		if opaque and not in_band:
			in_band = true
			start = i
		elif not opaque and in_band:
			in_band = false
			bands.append({"c": (start + i - 1) / 2.0, "w": float(i - start)})
	if in_band:
		bands.append({"c": (start + size - 1) / 2.0, "w": float(size - start)})
	return bands


## 由相邻帧带中心间距取众数，作为每帧 stride（含间隔）。
func _modal_gap(centers: PackedInt32Array) -> int:
	if centers.size() < 2:
		return 0
	var gaps: PackedInt32Array = []
	for i in range(1, centers.size()):
		var g := centers[i] - centers[i - 1]
		if g > 0:
			gaps.append(g)
	var counts: Dictionary = {}
	for g in gaps:
		counts[g] = counts.get(g, 0) + 1
	var best := 0
	var best_cnt := 0
	for k in counts.keys():
		if counts[k] > best_cnt:
			best_cnt = counts[k]
			best = k
	return best


## 返回所有帧在整图中的矩形（绝对坐标）。图集优先，否则网格切分。
func _collect_regions() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if not _atlas.is_empty():
		var frames: Variant = _atlas.get("frames", {})
		if frames is Array:
			for f in (frames as Array):
				if f is Dictionary and (f as Dictionary).has("x") \
						and (f as Dictionary).has("y") \
						and (f as Dictionary).has("w") \
						and (f as Dictionary).has("h"):
					var d: Dictionary = f
					rects.append(Rect2(d["x"], d["y"], d["w"], d["h"]))
		elif frames is Dictionary:
			for key in (frames as Dictionary).keys():
				var fr: Variant = (frames as Dictionary)[key]
				var f: Variant = fr.get("frame", fr) if fr is Dictionary else fr
				if f is Dictionary and (f as Dictionary).has("x"):
					var d: Dictionary = f
					rects.append(Rect2(d["x"], d["y"], d["w"], d["h"]))
	else:
		if _texture == null:
			return rects
		var tw: int = _texture.get_width()
		var th: int = _texture.get_height()
		if _auto_detect.button_pressed and _detected.get("ok", false):
			# 像素自动识别：以 stride(含间隔) 为单元格，按识别出的行列数切分，避免末位漏帧。
			var cell: Vector2 = _detected["cell"]
			var cols: int = int(_detected["cols"])
			var rows: int = int(_detected["rows"])
			var n: int = cols * rows
			if _use_override.button_pressed and int(_frames_override.value) > 0:
				n = int(_frames_override.value)
			for i in n:
				var x: int = (i % cols) * int(cell.x)
				var y: int = int(i / cols) * int(cell.y)
				rects.append(Rect2(x, y, int(cell.x), int(cell.y)))
		else:
			var fw: int = int(_frame_w.value)
			var fh: int = int(_frame_h.value)
			if fw <= 0 or fh <= 0:
				return rects
			var cols: int = int(tw / fw)
			var rows: int = int(th / fh)
			var n: int = cols * rows
			if _use_override.button_pressed and int(_frames_override.value) > 0:
				n = int(_frames_override.value)
			for i in n:
				var x: int = (i % cols) * fw
				var y: int = int(i / cols) * fh
				rects.append(Rect2(x, y, fw, fh))
	return rects


## 帧率：自动模式优先用图集时序，否则回退 UI 默认值；手动模式始终用 UI 值。
func _compute_fps(_rects_count: int) -> float:
	if _auto_fps.button_pressed and not _atlas.is_empty():
		var frames: Variant = _atlas.get("frames", {})
		if frames is Array and (frames as Array).size() >= 2:
			var arr: Array = frames
			var sum := 0.0
			var cnt := 0
			for i in (arr.size() - 1):
				var a: Variant = arr[i]
				var b: Variant = arr[i + 1]
				if a is Dictionary and b is Dictionary:
					var da: Dictionary = a
					var db: Dictionary = b
					if da.has("t") and db.has("t"):
						var dt: float = float(db["t"]) - float(da["t"])
						if dt > 0.0:
							sum += dt
							cnt += 1
			if cnt > 0 and sum > 0.0:
				return float(cnt) / sum
	return float(_fps.value)


# ----------------------------------------------------------------------------
# 构建 SpriteFrames
# ----------------------------------------------------------------------------
func _build_sprite_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	sf.add_animation("default")
	var rects := _collect_regions()
	var fps := _compute_fps(rects.size())
	sf.set_animation_speed("default", fps)
	sf.set_animation_loop("default", _loop.button_pressed)
	if _texture == null:
		return sf
	for r in rects:
		var at := AtlasTexture.new()
		at.atlas = _texture
		at.region = r
		sf.add_frame("default", at)
	return sf


# ----------------------------------------------------------------------------
# 预览与信息
# ----------------------------------------------------------------------------
func _rebuild_preview() -> void:
	if _preview_timer != null:
		_preview_timer.stop()
	_preview_frames.clear()
	_preview_idx = 0
	if _texture == null:
		_preview_rect.texture = null
		_preview_caption.text = "（未选择图片 —— 点上方「选择图片」后这里显示预览）"
		_update_frame_counter(0)
		_play_btn.text = "播放"
		return
	var rects := _collect_regions()
	for r in rects:
		var at := AtlasTexture.new()
		at.atlas = _texture
		at.region = r
		_preview_frames.append(at)
	if _preview_frames.is_empty():
		_preview_rect.texture = null
		_preview_caption.text = "切分后没有有效帧，请检查帧宽/帧高或图集。"
		_update_frame_counter(0)
		_play_btn.text = "播放"
		return
	_updating = true
	_frame_slider.max_value = float(_preview_frames.size() - 1)
	_updating = false
	var fps := _compute_fps(_preview_frames.size())
	_preview_timer.wait_time = 1.0 / maxf(fps, 0.01)
	_set_frame(0)
	_preview_caption.text = "共 %d 帧 ｜ fps：%.2f ｜ %s（可用下方按钮逐帧 / 播放）" \
			% [_preview_frames.size(), fps, "循环" if _loop.button_pressed else "单次"]
	if _preview_frames.size() > 1:
		_play_btn.text = "暂停"
		_preview_timer.start()
	else:
		_play_btn.text = "播放"


func _set_frame(idx: int) -> void:
	if _preview_frames.is_empty():
		return
	var n := _preview_frames.size()
	idx = idx if idx >= 0 else n - 1
	idx = idx if idx < n else 0
	_preview_idx = idx
	_updating = true
	if _frame_slider != null:
		_frame_slider.value = float(idx)
	_updating = false
	_preview_rect.texture = _preview_frames[idx]
	_update_frame_counter(idx)


func _update_frame_counter(idx: int) -> void:
	var n := _preview_frames.size()
	if _frame_label != null:
		_frame_label.text = "第 %d / %d 帧" % [idx + 1, n]


func _on_prev_pressed() -> void:
	if _preview_frames.is_empty():
		return
	_preview_timer.stop()
	_play_btn.text = "播放"
	var n := _preview_frames.size()
	_set_frame((_preview_idx - 1 + n) % n)


func _on_next_pressed() -> void:
	if _preview_frames.is_empty():
		return
	_preview_timer.stop()
	_play_btn.text = "播放"
	var n := _preview_frames.size()
	_set_frame((_preview_idx + 1) % n)


func _on_play_pressed() -> void:
	if _preview_frames.size() <= 1:
		return
	if _preview_timer.is_stopped():
		_play_btn.text = "暂停"
		_preview_timer.start()
	else:
		_preview_timer.stop()
		_play_btn.text = "播放"


func _on_slider_changed(_value: float) -> void:
	if _updating:
		return
	_preview_timer.stop()
	_play_btn.text = "播放"
	_set_frame(int(_frame_slider.value))


func _on_preview_timeout() -> void:
	var n := _preview_frames.size()
	if n == 0:
		return
	var next := _preview_idx + 1
	if next >= n:
		next = 0 if _loop.button_pressed else n - 1
	_set_frame(next)
	if next == n - 1 and not _loop.button_pressed:
		_preview_timer.stop()
		_play_btn.text = "播放"


func _on_auto_detect_toggled(on: bool) -> void:
	# 自动识别开启时禁用手动帧尺寸输入；关闭后才允许手改。
	_frame_w.editable = not on
	_frame_h.editable = not on
	# 重新开启时重新识别一次，使预览/切分立即生效。
	if on and _texture != null and not _auto_detect.disabled:
		_detected = _detect_grid()
		if _detected.get("ok", false):
			var cell: Vector2 = _detected["cell"]
			_frame_w.value = cell.x
			_frame_h.value = cell.y
		_rebuild_preview()
		_update_frame_info()


func _on_fps_auto_toggled(on: bool) -> void:
	_fps.editable = not on


func _on_settings_changed(_v: Variant = 0.0) -> void:
	if _texture == null:
		return
	_rebuild_preview()
	_update_frame_info()


func _update_frame_info() -> void:
	var rects := _collect_regions()
	var mode := "图集JSON" if not _atlas.is_empty() else "网格切分"
	_set_status("切分模式：%s ｜ 帧数：%d ｜ fps：%.2f ｜ 循环：%s"
			% [mode, rects.size(), _compute_fps(rects.size()),
			"是" if _loop.button_pressed else "否"], false)


func _set_status(text: String, is_error: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color",
			Color(1.0, 0.4, 0.4) if is_error else Color(0.8, 0.8, 0.8))


# ----------------------------------------------------------------------------
# 生成素材
# ----------------------------------------------------------------------------
func _generate() -> void:
	if _texture == null:
		_set_status("请先选择一张图片再生成。", true)
		return
	var name: String = _name_edit.text.strip_edges()
	if name.is_empty():
		name = _texture_path.get_file().get_basename()
	name = _sanitize(name)

	var out_dir: String = _output_edit.text.strip_edges()
	if not out_dir.ends_with("/"):
		out_dir += "/"
	var da := DirAccess.open("res://")
	if da == null or da.make_dir_recursive(out_dir) != OK:
		_set_status("无法创建/访问输出目录：%s" % out_dir, true)
		return

	var sframes_path := out_dir + name + ".tres"
	var tscn_path := out_dir + name + ".tscn"

	var sf := _build_sprite_frames()
	var err := ResourceSaver.save(sf, sframes_path)
	if err != OK:
		_set_status("保存 SpriteFrames 失败（错误码 %d）：%s" % [err, sframes_path], true)
		return

	var saved_sf := load(sframes_path) as SpriteFrames
	var as_node := AnimatedSprite2D.new()
	as_node.name = name
	as_node.sprite_frames = saved_sf
	as_node.autoplay = "default"
	as_node.centered = false

	var ps := PackedScene.new()
	if ps.pack(as_node) != OK:
		as_node.queue_free()
		_set_status("打包场景失败：%s" % tscn_path, true)
		return
	err = ResourceSaver.save(ps, tscn_path)
	as_node.queue_free()

	if err != OK:
		_set_status("保存场景失败（错误码 %d）：%s" % [err, tscn_path], true)
		return

	if Engine.is_editor_hint():
		var efs: Object = Engine.get_singleton("EditorFileSystem")
		if efs != null and efs.has_method("scan"):
			efs.call("scan")
	_set_status("已生成：%s 与 %s" % [sframes_path, tscn_path], false)
	_scan_output()


func _sanitize(s: String) -> String:
	var out := ""
	for c in s:
		if c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			out += c
		else:
			out += "_"
	return out if out != "" else "asset"


# ----------------------------------------------------------------------------
# 右侧素材库（循环预览 + 拖入场景）
# ----------------------------------------------------------------------------
func _scan_output() -> void:
	for it in _lib_items:
		it.queue_free()
	_lib_items.clear()
	var out_dir: String = _output_edit.text.strip_edges()
	if not out_dir.ends_with("/"):
		out_dir += "/"
	var da := DirAccess.open(out_dir)
	if da == null:
		return
	for f in da.get_files():
		if f.get_extension().to_lower() != "tscn":
			continue
		var full := out_dir + f
		var frames := _load_lib_frames(full)
		if frames.is_empty():
			continue
		var item := MaterialItem.new(full, f.get_basename(), frames)
		_lib_list.add_child(item)
		_lib_items.append(item)


## 从生成的 .tscn 提取 SpriteFrames 各帧纹理，用于素材库循环预览。
func _load_lib_frames(tscn_path: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var ps := load(tscn_path) as PackedScene
	if ps == null:
		return out
	var inst := ps.instantiate() as AnimatedSprite2D
	if inst == null:
		return out
	var sf := inst.sprite_frames
	if sf != null and sf.has_animation("default"):
		var n := sf.get_frame_count("default")
		for i in n:
			out.append(sf.get_frame_texture("default", i))
	inst.queue_free()
	return out


func _on_lib_timeout() -> void:
	for it in _lib_items:
		if it.frames.is_empty():
			continue
		it.idx = (it.idx + 1) % it.frames.size()
		it.tex.texture = it.frames[it.idx]


# ----------------------------------------------------------------------------
# 素材库条目（可循环预览 + 拖入场景）
# ----------------------------------------------------------------------------
class MaterialItem extends Panel:
	var path: String = ""
	var frames: Array[Texture2D] = []
	var idx: int = 0
	var tex: TextureRect
	var name_label: Label

	func _init(p_path: String, p_name: String, p_frames: Array[Texture2D]) -> void:
		path = p_path
		frames = p_frames
		custom_minimum_size = Vector2(220.0, 180.0)
		tex = TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(200.0, 130.0)
		tex.size = Vector2(200.0, 130.0)
		tex.position = Vector2(10.0, 10.0)
		add_child(tex)
		name_label = Label.new()
		name_label.text = p_name
		name_label.position = Vector2(10.0, 145.0)
		add_child(name_label)
		if not frames.is_empty():
			tex.texture = frames[0]

	## 拖入场景：返回文件拖拽数据，编辑器 2D 视口 / 场景树即可接收。
	func _get_drag_data(_pos: Vector2) -> Variant:
		return {"files": [path]}
