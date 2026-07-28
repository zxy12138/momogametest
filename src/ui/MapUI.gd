# 《梦境逐影》网状地图 UI（CanvasLayer）
# M 键开关；从 MapData 渲染房间网，连线相邻房间；
# 点击「已探明/已通/当前」房间 -> 当前场景的 transition_to(rid) 进行传送。
extends CanvasLayer

const TYPE_LABEL = {
	"start": "起点",
	"combat": "战斗",
	"elite": "精英",
	"inn": "驿站",
	"boss": "BOSS",
}

var _panel: Control = null
var _links: Node2D = null
var _room_btns: Array = []
var _layer_btns: Array = []
var _open := false

func _ready() -> void:
	_build_panel()
	_panel.visible = false
	_open = false

func _build_panel() -> void:
	_panel = Control.new()
	_panel.mouse_filter = 1  # 拦截点击，避免穿透到游戏世界
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
	dim.mouse_filter = 1
	dim.size = _panel.size
	_panel.add_child(dim)

	var title := Label.new()
	title.name = "Title"
	title.text = "梦境地图  ·  按 M 或 ESC 关闭"
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
	if is_instance_valid(_links):
		_links.queue_free()
	_links = Node2D.new()
	_panel.add_child(_links)

	# 合并地图：三层合一视图（保证已构建）
	if MapData.merged.is_empty():
		MapData.build_merged()
	var m: Dictionary = MapData.merged

	var pad := 90.0
	var vw := get_window().get_visible_rect().size.x
	var vh := get_window().get_visible_rect().size.y
	var map_w := vw - 2.0 * pad
	var map_h := vh - 2.0 * pad - 60.0

	# gx/gy ∈ [0,1] -> 画布坐标（复用原 [0,1] 缩放逻辑）
	var pos_of: Dictionary = {}
	for key in m.keys():
		var node: Dictionary = m[key]
		var gx: float = node.get("gx", 0.0)
		var gy: float = node.get("gy", 0.0)
		pos_of[key] = Vector2(pad + gx * map_w, 60.0 + pad + gy * map_h)

	# 连线（层内 + 跨层楼梯）
	for key in m.keys():
		var node: Dictionary = m[key]
		var from: Vector2 = pos_of.get(key, Vector2.ZERO)
		for lk in node.get("links", []):
			if pos_of.has(lk):
				var ln := Line2D.new()
				ln.points = PackedVector2Array([from, pos_of[lk]])
				ln.width = 2.0
				ln.default_color = Color(0.5, 0.5, 0.7, 0.55)
				_links.add_child(ln)

	# 节点按钮（文本含层号，如 f1-r1）
	for key in m.keys():
		var node: Dictionary = m[key]
		var sp: Vector2 = pos_of.get(key, Vector2.ZERO)
		var st: String = node.get("state", "VISITED")
		var tele: bool = MapData.merged_teleportable(key)
		var b := Button.new()
		b.position = sp - Vector2(36, 22)
		b.size = Vector2(72, 44)
		# 沿用上一轮"未探明"逻辑：仅已探明/当前/Boss已清 或 梦境感知 才显示类型
		var show_type: bool = (st in ["VISITED", "CURRENT", "BOSS_CLEARED"]) or MapData.perception
		var typ: String = node.get("type", "")
		var type_txt: String = TYPE_LABEL.get(typ, "?") if show_type else "未探明"
		b.text = key + "\n" + type_txt
		b.add_theme_font_size_override("font_size", 12)
		b.modulate = _color_for(st)
		b.disabled = not tele
		b.pressed.connect(_on_room_pressed.bind(key))
		_panel.add_child(b)
		_room_btns.append(b)

	for lb in _layer_btns:
		lb.visible = GameManager.dev_mode

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
