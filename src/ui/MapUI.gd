# 《梦境逐影》网状地图 UI（CanvasLayer）
# M 键开关；从 MapData 渲染房间网，连线相邻房间；
# 点击「已进入」房间 -> 当前场景的 transition_to(rid) 进行传送。
# 房间三种视觉状态：
#   当前房间   —— 指针动画（mapzhizheng.png，7 帧切片）指示所在关卡
#   已进入     —— 正常按钮（房间名+类型，可点击传送）
#   未进入     —— 问号动画（wenhao.png，8x3=24 帧切片），不可点击；不画连线、不显示文字
# 地图界面按 F12 临时全开（MapData.full_map_override，只影响显示，不污染进度）。
# 动画实现：Control 体系下 Node2D/AnimatedSprite2D 不渲染，AnimatedTexture 在本构建实机也异常，
# 故用最稳的 TextureRect + Timer 轮播 AtlasTexture 帧（与序列帧插件预览同款方案）。
extends CanvasLayer

const TYPE_LABEL = {
	"start": "起点",
	"combat": "战斗",
	"elite": "精英",
	"inn": "驿站",
	"boss": "BOSS",
}

# 指针动画（当前关卡指示）：966x113 -> 7 帧横排，单帧 138x113
const POINTER_PATH := "res://assets/ui/map/mapzhizheng.png"
const POINTER_FW := 138
const POINTER_FH := 113
const POINTER_COLS := 7
const POINTER_ROWS := 1
const POINTER_FPS := 10.0
# 问号动画（未进入关卡）：10240x2160 -> 8 列 x 3 行 = 24 帧，单帧 1280x720
const QMARK_PATH := "res://assets/ui/map/wemhao/wenhao.png"
const QMARK_FW := 1280
const QMARK_FH := 720
const QMARK_COLS := 8
const QMARK_ROWS := 3
const QMARK_FPS := 10.0

var _panel: Control = null
var _links: Node2D = null
var _room_btns: Array = []
var _layer_btns: Array = []
var _open := false
# 图标动画：TextureRect + Timer 轮播 AtlasTexture 帧
var _icons: Array = []          # [{rect, frames, idx, n}]
var _icon_timer: Timer = null
# 切片帧缓存（key -> Array[AtlasTexture]），避免每次开图重建
var _frame_cache: Dictionary = {}

func _ready() -> void:
	_build_panel()
	_panel.visible = false
	_open = false
	# 全局图标轮播 Timer：10fps 推进所有地图图标帧
	_icon_timer = Timer.new()
	_icon_timer.wait_time = 1.0 / POINTER_FPS
	_icon_timer.autostart = true
	_icon_timer.timeout.connect(_tick_icons)
	add_child(_icon_timer)

func _build_panel() -> void:
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS  # 拦截点击，避免穿透到游戏世界
	_panel.position = Vector2.ZERO
	_panel.size = get_window().get_visible_rect().size
	add_child(_panel)

	# 地图背景图（铺在最底层；上方 dim 仅留薄薄一层滤镜让文字仍清晰可读）
	var bg_tex: Texture2D = load("res://assets/ui/map/Maps_001.png") as Texture2D
	if bg_tex != null:
		var bg := TextureRect.new()
		bg.name = "MapBg"
		bg.texture = bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED  # 等比铺满，超出裁掉
		bg.size = _panel.size
		bg.position = Vector2.ZERO
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE            # 不拦截点击
		_panel.add_child(bg)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.30)                    # 降低透明度让羊皮纸透出
	dim.mouse_filter = Control.MOUSE_FILTER_PASS
	dim.size = _panel.size
	_panel.add_child(dim)

	var title := Label.new()
	title.name = "Title"
	title.text = "梦境地图  ·  按 M 或 ESC 关闭  ·  F12 全开"
	title.position = Vector2(20, 16)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 1.0))
	_panel.add_child(title)

	# 开发者模式选层按钮（默认隐藏，dev 模式时在地图内显示）
	_layer_btns = []
	var vw2 := get_window().get_visible_rect().size.x
	for l in [1, 2, 3]:
		var lb := Button.new()
		lb.text = "L" + str(l)
		lb.position = Vector2(vw2 - 230 + (l - 1) * 70, 16)
		lb.size = Vector2(60, 26)
		lb.visible = false
		lb.pressed.connect(_on_layer_pressed.bind(l))
		_panel.add_child(lb)
		_layer_btns.append(lb)

	_links = Node2D.new()
	_panel.add_child(_links)


func _set_gm_locked(v: bool) -> void:
	if GameManager != null and "input_locked" in GameManager:
		GameManager.input_locked = v


func _is_gm_locked() -> bool:
	if GameManager == null or not ("input_locked" in GameManager):
		return false
	return GameManager.input_locked


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		if _open:
			_close()
		elif not _is_gm_locked():
			_open_map()
		return
	# 地图界面按 F12 临时全开 / 恢复迷雾（只影响显示与可传送，不改进度数据）
	# 需在设置里开启「F12 全开地图」（GameManager.debug_full_map，默认关闭）。
	if _open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		if not GameManager.debug_full_map:
			return
		MapData.full_map_override = not MapData.full_map_override
		_draw_map()

func _open_map() -> void:
	if MapData.rooms.is_empty():
		return
	_open = true
	_set_gm_locked(true)
	_draw_map()
	_panel.visible = true

func _close() -> void:
	_open = false
	_set_gm_locked(false)
	_panel.visible = false

# 供外部（Game 的 ESC 返回）查询/关闭地图
func is_open() -> bool:
	return _open

func close_map() -> void:
	if _open:
		_close()

func _draw_map() -> void:
	for b in _room_btns:
		if is_instance_valid(b):
			b.queue_free()
	_room_btns.clear()
	# 图标由 _icons 单独登记，一并清理（它们也在 _panel 下）
	for it in _icons:
		if is_instance_valid(it.get("rect", null)):
			(it["rect"] as Node).queue_free()
	_icons.clear()
	if is_instance_valid(_links):
		_links.queue_free()
	_links = Node2D.new()
	_panel.add_child(_links)

	# 合并地图：三层合一视图（保证已构建）
	if MapData.merged.is_empty():
		MapData.build_merged()
	var m: Dictionary = MapData.merged

	# 按羊皮纸背景的可视区域留边（略收紧让地图区更大不空）：避开两侧卷起和顶/底装饰。
	# Maps_001.png 实测 1408×768，两侧卷起各占约 12%，中部米色平展约 76% 宽 / 78% 高。
	var vw := get_window().get_visible_rect().size.x
	var vh := get_window().get_visible_rect().size.y
	var pad_x: float = vw * 0.06
	var pad_y_top: float = vh * 0.085
	var pad_y_bot: float = vh * 0.075
	var map_w: float = vw - 2.0 * pad_x
	var map_h: float = vh - pad_y_top - pad_y_bot

	# gx/gy ∈ [0,1] -> 平展区画布坐标；仅自动模式加波浪微扰（手动模式由 LevelData.pos 精确定位，不加抖动）
	var pos_of: Dictionary = {}
	for key in m.keys():
		var node: Dictionary = m[key]
		var gx: float = node.get("gx", 0.0)
		var gy: float = node.get("gy", 0.0)
		var jy: float = 0.0 if MapData.USE_MANUAL_POS else _wave_jitter(key)
		pos_of[key] = Vector2(pad_x + gx * map_w, pad_y_top + gy * map_h + jy)

	# 连线：只画「两端都可见」的（含 REVEALED 邻居线）；key 字典序去重 → 单向单条，避免双向重复
	for key in m.keys():
		var node: Dictionary = m[key]
		var from: Vector2 = pos_of.get(key, Vector2.ZERO)
		var from_fi: int = node.get("floor", 1)
		var from_rid: String = String(node.get("rid", ""))
		for lk in node.get("links", []):
			if not pos_of.has(lk):
				continue
			if String(key) > String(lk):
				continue   # 只画 key < lk 的一条，双向邻居不重复画
			if not MapData.is_visible(from_fi, from_rid):
				continue
			var other: Dictionary = m[lk]
			if not MapData.is_visible(other.get("floor", 1), String(other.get("rid", ""))):
				continue
			var ln := Line2D.new()
			ln.points = _bezier_pts(from, pos_of[lk], 0.32, 24)
			ln.width = 4.5
			ln.default_color = Color(0.30, 0.30, 0.34, 0.95)
			ln.antialiased = true
			_links.add_child(ln)

	# 节点（三种视觉状态：当前=指针动画 / 已进入=正常按钮 / 下一个未进入=问号动画；LOCKED 完全不画）
	for key in m.keys():
		var node: Dictionary = m[key]
		var fi: int = node.get("floor", 1)
		var rid: String = String(node.get("rid", ""))
		if not MapData.is_visible(fi, rid):
			continue
		var sp: Vector2 = pos_of.get(key, Vector2.ZERO)
		var st: String = MapData.show_state_for(fi, rid)
		var typ: String = node.get("type", "")
		var type_txt: String = TYPE_LABEL.get(typ, "?")

		if st == "CURRENT":
			# 当前所在关卡：指针动画（放大、叠在房间上方） + 房间名小标签
			_room_btns.append(_add_icon(POINTER_PATH, POINTER_FW, POINTER_FH, POINTER_COLS, POINTER_ROWS,
				sp - Vector2(0.0, 52.0), Vector2(96.0, 72.0)))
			_room_btns.append(_room_label("%s · %s" % [rid, type_txt], sp + Vector2(0.0, 18.0), Color(1.0, 0.9, 0.4)))
		elif st in ["VISITED", "BOSS_CLEARED"]:
			# 已进入（可传送）：正常按钮（两行：房号+类型）
			var tele: bool = MapData.merged_teleportable(key)
			var b := Button.new()
			b.position = sp - Vector2(36, 24)
			b.size = Vector2(72, 48)
			b.text = rid + "\n" + type_txt
			b.add_theme_font_size_override("font_size", 13)
			b.modulate = _color_for(st)
			b.disabled = not tele
			b.pressed.connect(_on_room_pressed.bind(key))
			_panel.add_child(b)
			_room_btns.append(b)
		else:
			# 下一个未进入（REVEALED）：只显示问号动画（放大、不显示文字/无线）
			_room_btns.append(_add_icon(QMARK_PATH, QMARK_FW, QMARK_FH, QMARK_COLS, QMARK_ROWS,
				sp, Vector2(100.0, 70.0)))

	for lb in _layer_btns:
		lb.visible = GameManager.dev_mode


## 确定性波浪微扰（按 key 哈希 -14..+14）：同排房间上下错落，每次打开地图结果一致。
func _wave_jitter(key: String) -> float:
	return float(abs(key.hash()) % 29 - 14)


## 三次贝塞尔 S 型曲线采样点列：控制点取两端沿法线反向偏移（起点向一侧出、终点向另一侧入），
## 形成 S 形弯，避免 C 形弧线贴边；弯度 = 距离 x curve。
func _bezier_pts(a: Vector2, b: Vector2, curve: float, segs: int) -> PackedVector2Array:
	var d := b - a
	if d.length() < 4.0:
		return PackedVector2Array([a, b])
	var normal := Vector2(-d.y, d.x).normalized()
	var c1 := a + normal * (d.length() * curve)
	var c2 := b - normal * (d.length() * curve)
	var pts := PackedVector2Array()
	for i in segs + 1:
		var t := float(i) / float(segs)
		var inv := 1.0 - t
		pts.append(inv * inv * inv * a + 3.0 * inv * inv * t * c1 + 3.0 * inv * t * t * c2 + t * t * t * b)
	return pts


## 在面板上放一个循环播放动画的图标：切片精灵表 → TextureRect，注册进 _icons 由全局 Timer 轮播帧。
## 帧缓存复用同一精灵表的切片，避免每次开图重复建 AtlasTexture。
func _add_icon(path: String, fw: int, fh: int, cols: int, rows: int, center: Vector2, size: Vector2) -> TextureRect:
	var frames: Array = _frame_cache.get(path, [])
	if frames.is_empty():
		var sheet: Texture2D = load(path) as Texture2D
		if sheet == null:
			push_error("MapUI: 动画贴图加载失败 %s" % path)
			return null
		for i in cols * rows:
			var atl := AtlasTexture.new()
			atl.atlas = sheet
			atl.region = Rect2((i % cols) * fw, (i / cols) * fh, fw, fh)
			frames.append(atl)
		_frame_cache[path] = frames
	var tr := TextureRect.new()
	tr.texture = frames[0] as Texture2D
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size = size
	tr.position = center - size / 2.0
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(tr)
	_icons.append({"rect": tr, "frames": frames, "idx": 0, "n": frames.size()})
	return tr


## Timer 驱动：推进所有图标的当前帧（已释放节点防御性跳过）。
func _tick_icons() -> void:
	for it in _icons:
		var rect: Object = it.get("rect", null)
		if rect == null or not is_instance_valid(rect):
			continue
		var n: int = int(it.get("n", 1))
		if n <= 0:
			continue
		var idx: int = (int(it.get("idx", 0)) + 1) % n
		it["idx"] = idx
		var frames: Array = it.get("frames", [])
		if idx < frames.size():
			(rect as TextureRect).texture = frames[idx] as Texture2D


func _room_label(txt: String, pos: Vector2, color: Color) -> Label:
	var lb := Label.new()
	lb.text = txt
	lb.position = pos
	lb.add_theme_font_size_override("font_size", 12)
	lb.add_theme_color_override("font_color", color)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(lb)
	return lb


func _on_room_pressed(rid: String) -> void:
	var sc := get_tree().current_scene
	if sc != null and sc.has_method("transition_to"):
		sc.call("transition_to", rid)
		_close()

func _on_layer_pressed(l: int) -> void:
	var sc := get_tree().current_scene
	if sc != null and sc.has_method("dev_goto_layer"):
		sc.call("dev_goto_layer", l)

# 供外部（开发者模式切换/切层）重绘地图
func redraw() -> void:
	_draw_map()

func _color_for(st: String) -> Color:
	match st:
		"CURRENT": return Color(1.0, 0.9, 0.4)
		"VISITED": return Color(0.6, 0.95, 0.7)
		"REVEALED": return Color(0.6, 0.6, 0.8)
		"BOSS_CLEARED": return Color(0.5, 0.9, 1.0)
		_: return Color(0.4, 0.4, 0.5)  # LOCKED
