@tool
extends Node2D
class_name MapLayoutEditor

## 可视化地图布局编辑器（@tool 工具场景，直接打开本 .tscn 使用）。
## 功能：
##   - 按 LevelData 拓扑摆出所有房间格子（三层三栏），邻居之间画贝塞尔 S 型连线
##   - 鼠标左键拖动格子 -> 位置写入 MapLayoutData（归一化），线跟随移动
##   - 滚轮缩放（以鼠标为中心），中键拖动平移画布
##   - 点「保存布局」按钮 或 Ctrl+S 场景 -> 写回 res://src/data/map_layout.tres
## 运行期地图（MapData.build_merged）优先读该 .tres，未配置的房间回退 LevelData.pos。
## 坐标空间与运行期 MapUI 一致（1280x720 + pad），所见即所得。

const LAYOUT_PATH := "res://src/data/map_layout.tres"
const W := 1280.0
const H := 720.0
const PAD_X := 77.0
const PAD_Y_TOP := 61.0
const PAD_Y_BOT := 54.0
const MAP_W := W - 2.0 * PAD_X
const MAP_H := H - PAD_Y_TOP - PAD_Y_BOT
const CELL_SIZE := Vector2(76.0, 50.0)

const TYPE_LABEL := {
	"start": "起点", "combat": "战斗", "elite": "精英", "inn": "驿站", "boss": "BOSS",
}
const TYPE_COLOR := {
	"start": Color(0.9, 0.85, 0.4),
	"combat": Color(0.6, 0.8, 0.9),
	"elite": Color(0.85, 0.55, 0.9),
	"inn": Color(0.6, 0.9, 0.6),
	"boss": Color(0.95, 0.45, 0.45),
}

var _layout: MapLayoutData = null
var _container: Node2D = null
var _cells: Dictionary = {}        # key("f1-r1") -> {node: Node2D, floor: int, rid: String}
var _links: Array[Line2D] = []     # 当前所有连线（拖拽时按需更新 points）
var _cell_links: Dictionary = {}   # key -> Array[Line2D]（该格子参与的连线，便于局部刷新）
var _last_pos: Dictionary = {}     # key -> 上次记录的格子位置（_process 轮询检测移动）

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_layout = (load(LAYOUT_PATH) as MapLayoutData) if ResourceLoader.exists(LAYOUT_PATH) else MapLayoutData.new()
	_build_ui()

# ---------------------------------------------------------------- 构建
func _build_ui() -> void:
	_container = Node2D.new()
	add_child(_container)
	# 背景：Maps_001.png 铺满画布（与运行期 MapUI 完全一致的 KEEP_ASPECT_COVERED + 铺满），所见即所得
	var bg_tex: Texture2D = load("res://assets/ui/map/Maps_001.png") as Texture2D
	if bg_tex != null:
		var bg := TextureRect.new()
		bg.name = "MapBg"
		bg.texture = bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.size = Vector2(W, H)
		bg.position = Vector2.ZERO
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不拦截格子点击/拖拽
		_container.add_child(bg)
		_container.move_child(bg, 0)
	# 画布边框（提示可摆放区域，即运行期地图区）
	var frame := Line2D.new()
	frame.points = PackedVector2Array([
		Vector2(PAD_X, PAD_Y_TOP), Vector2(W - PAD_X, PAD_Y_TOP),
		Vector2(W - PAD_X, H - PAD_Y_BOT), Vector2(PAD_X, H - PAD_Y_BOT), Vector2(PAD_X, PAD_Y_TOP),
	])
	frame.width = 2.0
	frame.default_color = Color(0.6, 0.7, 1.0, 0.4)
	_container.add_child(frame)
	# 说明 + 保存按钮
	var info := Label.new()
	info.text = "直接拖格子调位置（编辑器原生拖拽）· 滚轮缩放/中键平移是编辑器视口自带 · 保存写回 map_layout.tres"
	info.position = Vector2(12, 10)
	info.add_theme_font_size_override("font_size", 14)
	add_child(info)
	var save_btn := Button.new()
	save_btn.text = "💾 保存布局"
	save_btn.position = Vector2(W - 140, 10)
	save_btn.size = Vector2(128, 34)
	save_btn.pressed.connect(_save_layout)
	add_child(save_btn)
	# 格子
	var layers: Dictionary = {1: LevelData.get_layer(1), 2: LevelData.get_layer(2), 3: LevelData.get_layer(3)}
	for fi in layers.keys():
		var floor_i: int = int(fi)
		var layer: Dictionary = layers[fi] as Dictionary
		if layer == null:
			continue
		for rid in (layer.get("rooms", {}) as Dictionary).keys():
			var d: Dictionary = (layer["rooms"][rid] as Dictionary)
			var key := "f%d-%s" % [floor_i, rid]
			var pos := _pos_for(key, floor_i, rid, d)
			var cell := _make_cell(key, String(rid), String(d.get("type", "")), _to_pix(pos, floor_i))
			_cells[key] = {"node": cell, "floor": floor_i, "rid": String(rid)}
	# 连线（在所有格子之后，线在格子下方）
	_rebuild_links()

func _pos_for(key: String, floor_i: int, rid: String, d: Dictionary) -> Vector2:
	if _layout != null and _layout.positions.has(key):
		return _layout.positions[key] as Vector2
	var pos: Array = d.get("pos", [0.5, 0.5])
	var px: float = pos[0] if pos.size() > 0 else 0.5
	var py: float = pos[1] if pos.size() > 1 else 0.5
	return Vector2(px, py)

func _col_start(floor_i: int) -> float:
	return float(floor_i - 1) / 3.0

## 归一化 pos -> 画布像素（与运行期 MapUI 三栏映射一致）
func _to_pix(pos: Vector2, floor_i: int) -> Vector2:
	var gx := _col_start(floor_i) + pos.x * (1.0 / 3.0)
	return Vector2(PAD_X + gx * MAP_W, PAD_Y_TOP + pos.y * MAP_H)

## 画布像素 -> 归一化 pos（按该格子所在层反推层内 x）
func _from_pix(pix: Vector2, floor_i: int) -> Vector2:
	var gx := (pix.x - PAD_X) / MAP_W
	var gy := (pix.y - PAD_Y_TOP) / MAP_H
	var col_start := _col_start(floor_i)
	return Vector2(clampf((gx - col_start) * 3.0, 0.0, 1.0), clampf(gy, 0.0, 1.0))

# ---------------------------------------------------------------- 格子
func _make_cell(key: String, rid: String, typ: String, pix: Vector2) -> Node2D:
	var root := Node2D.new()
	root.position = pix
	var col: Color = TYPE_COLOR.get(typ, Color(0.7, 0.7, 0.7)) as Color
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-CELL_SIZE.x / 2, -CELL_SIZE.y / 2), Vector2(CELL_SIZE.x / 2, -CELL_SIZE.y / 2),
		Vector2(CELL_SIZE.x / 2, CELL_SIZE.y / 2), Vector2(-CELL_SIZE.x / 2, CELL_SIZE.y / 2),
	])
	poly.color = Color(col.r, col.g, col.b, 0.55)
	root.add_child(poly)
	var bd := Line2D.new()
	bd.points = PackedVector2Array([
		Vector2(-CELL_SIZE.x / 2, -CELL_SIZE.y / 2), Vector2(CELL_SIZE.x / 2, -CELL_SIZE.y / 2),
		Vector2(CELL_SIZE.x / 2, CELL_SIZE.y / 2), Vector2(-CELL_SIZE.x / 2, CELL_SIZE.y / 2),
		Vector2(-CELL_SIZE.x / 2, -CELL_SIZE.y / 2),
	])
	bd.width = 2.0
	bd.default_color = col
	root.add_child(bd)
	var lab := Label.new()
	lab.text = rid + "\n" + TYPE_LABEL.get(typ, typ)
	lab.position = Vector2(-CELL_SIZE.x / 2 + 4, -CELL_SIZE.y / 2 + 2)
	lab.size = Vector2(CELL_SIZE.x - 8, CELL_SIZE.y - 4)
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Color(1, 1, 1))
	root.add_child(lab)
	_container.add_child(root)
	# 关键：owner 设为编辑场景根 -> 2D 视口能直接点选并拖动格子（编辑器原生拖拽，脚本收不到视口输入）
	if is_inside_tree() and get_tree().edited_scene_root != null:
		root.owner = get_tree().edited_scene_root
	_last_pos[key] = pix
	return root

# ---------------------------------------------------------------- 连线
func _neighbors_of(key: String, floor_i: int, rid: String) -> Array:
	var layer: Dictionary = LevelData.get_layer(floor_i)
	if layer == null:
		return []
	var rooms_l: Dictionary = layer.get("rooms", {}) as Dictionary
	var d: Dictionary = rooms_l.get(rid, {}) as Dictionary
	var out: Array = []
	for nb in d.get("neighbors", []):
		out.append("f%d-%s" % [floor_i, String(nb)])
	return out

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

func _rebuild_links() -> void:
	for ln in _links:
		if is_instance_valid(ln):
			ln.queue_free()
	_links.clear()
	_cell_links.clear()
	for key in _cells.keys():
		_cell_links[key] = []
	for key in _cells.keys():
		var info: Dictionary = _cells[key]
		for nb in _neighbors_of(key, int(info["floor"]), String(info["rid"])):
			if String(key) > String(nb):
				continue
			if not _cells.has(nb):
				continue
			var ln := Line2D.new()
			ln.points = _bezier_pts((info["node"] as Node2D).position, (_cells[nb]["node"] as Node2D).position, 0.32, 24)
			ln.width = 4.0
			ln.default_color = Color(0.35, 0.35, 0.4, 0.9)
			ln.antialiased = true
			_container.add_child(ln)
			_container.move_child(ln, 1)  # 线在格子下方（格子是之后加的）
			_links.append(ln)
			_cell_links[key].append(ln)
			_cell_links[nb].append(ln)

func _refresh_links_for(key: String) -> void:
	var info: Dictionary = _cells[key]
	for ln in _cell_links.get(key, []):
		# 该线两端：找到另一端格子重算
		var a: Vector2 = (info["node"] as Node2D).position
		var b := a
		for k2 in _cells.keys():
			if k2 == key:
				continue
			if _cell_links.get(k2, []).has(ln):
				b = (_cells[k2]["node"] as Node2D).position
				break
		ln.points = _bezier_pts(a, b, 0.32, 24)

# ---------------------------------------------------------------- 移动检测
# 编辑器原生拖拽格子（owner 已设）改的是节点 position，这里轮询检测并刷新连线。
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	for key in _cells.keys():
		var cell := _cells[key]["node"] as Node2D
		if cell == null or not is_instance_valid(cell):
			continue
		var prev: Vector2 = _last_pos.get(key, cell.position)
		if not cell.position.is_equal_approx(prev):
			_last_pos[key] = cell.position
			_refresh_links_for(key)

# ---------------------------------------------------------------- 保存
func _save_layout() -> void:
	if _layout == null:
		return
	for key in _cells.keys():
		var cell := _cells[key]["node"] as Node2D
		_layout.positions[key] = _from_pix(cell.position, int(_cells[key]["floor"]))
	var err := ResourceSaver.save(_layout, LAYOUT_PATH)
	if err == OK:
		print("[MapLayoutEditor] 布局已保存 -> ", LAYOUT_PATH)
	else:
		push_error("MapLayoutEditor: 保存失败 %d" % err)

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE and Engine.is_editor_hint():
		_save_layout()
