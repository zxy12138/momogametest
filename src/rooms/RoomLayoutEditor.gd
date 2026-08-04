@tool
extends Node2D
class_name RoomLayoutEditor

## 编辑器专用场景：可视化拖拽编辑单个房间的布局（门 / 各类型敌人数量 / 出生点 / 禁区 / 背景）。
## 用法：
##   1. 在 Godot 中打开 res://src/rooms/RoomLayoutEditor.tscn
##   2. Inspector 的「房间布局编辑」分组设 floor_idx（层 1/2/3）与 room_id（如 "r2"）→ 视口即时显示
##   3. 门：直接拖绿色菱形手柄到想要的位置
##   4. 敌人放置：在「敌人放置（各类型数量）」分组里，每种怪物各占一行，直接改 count(数量)；
##      视口里即时出现对应数量的可拖拽方块手柄（青色=普通/紫色=精英）；选中手柄在视口拖动设位置
##   5. 出生点：拖绿色「出生点」菱形手柄到角色初始位置（和门一样可拖）
##   6. 禁区：把「Blocked Count」调大，红色手柄出现；拖拽移动中心，视口旋转 gizmo 或 Inspector 填 rotation_deg 旋转；
##      选中手柄在 Inspector 里改 shape_type(0矩形/1多边形)、rect_size 或 points(多边形局部顶点) 定义不规则形状
##   7. 按 Ctrl+S：PRE_SAVE 把位置/数量写回 res://src/rooms/layouts/{层}_{房}.tres
##   8. F5 运行，RoomManager 自动读取该 .tres 生效
##
## 注意：手柄会随场景保存临时写进 RoomLayoutEditor.tscn（仅臃肿，无害）；
##       重新打开场景时 _rebuild 会清掉它们并按 .tres 重建，不影响数据。

const W := 880.0
const H := 500.0

## 房间选择（切换时 2D 视口即时重绘）。用 backing field + get/set 避免 setter 内 self 赋值导致无限递归。
@export_group("房间布局编辑 (Room Layout)")
var _floor_idx: int = 1
var _room_id: String = "r1"

@export var floor_idx: int:
	get:
		return _floor_idx
	set(value):
		if _floor_idx != value:
			_floor_idx = value
			_rebuild()

@export var room_id: String:
	get:
		return _room_id
	set(value):
		if _room_id != value:
			_room_id = value
			_rebuild()

## 各类型敌人数量：每种敌人一行（enemy_id 下拉 + count 数量）。
## 运行期按 count 生成对应数量的可拖拽手柄，位置由你在视口摆放。
## 该列表按房间保存在 RoomLayout.enemy_specs（随 .tres 落盘），切换房间会自动重载。
@export_group("敌人放置 (各类型数量)")
@export var enemy_specs: Array[EnemyTypeCount] = []

## 禁区数量：调大即在房间中心生成新的红色可拖方块手柄。
@export_group("禁区 (Blocked)")
var _blocked_count: int = 0

@export var blocked_count: int:
	get:
		return _blocked_count
	set(value):
		var n := maxi(0, value)
		if n == _blocked_count:
			return
		_adjust_blocked(n)
		_blocked_count = n

var _layout: RoomLayout
var _door_markers: Array[Node2D] = []
var _enemy_markers: Array[Node2D] = []
var _spawn_marker: Node2D = null
var _blocked_rects: Array[Node2D] = []
var _spec_snapshot: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild()


func _rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	for c in get_children():
		c.queue_free()
	_door_markers.clear()
	_enemy_markers.clear()
	_blocked_rects.clear()
	_spawn_marker = null
	_ensure_layout()
	_load_specs_into_editor()
	_build_bg()
	_build_doors()
	_build_enemies()
	_build_spawn()
	_build_blocked()
	queue_redraw()
	_snapshot_specs()


func _ensure_layout() -> void:
	var path := _layout_path()
	if FileAccess.file_exists(path):
		_layout = load(path) as RoomLayout
	else:
		_layout = RoomLayout.new()


func _layout_path() -> String:
	return "res://src/rooms/layouts/%d_%s.tres" % [floor_idx, room_id]


func _neighbors() -> Array:
	var L: Dictionary = LevelData.get_layer(floor_idx)
	if L == null:
		return []
	var room_d: Dictionary = L["rooms"].get(room_id, {}) as Dictionary
	return room_d.get("neighbors", [])


## 让动态生成的节点被编辑器当作「可编辑实例」的一部分，2D 视口才能点选并拖拽。
func _set_owner(n: Node) -> void:
	# 脚本注册期(无场景树)可能触发 blocked_count setter → _adjust_blocked → 此处；
	# 此时 get_tree() 会抛 "data.tree is null"，故先以 is_inside_tree() 短路（安全，无树时返回 false）。
	if not is_inside_tree():
		return
	var esr := get_tree().edited_scene_root
	if esr != null:
		n.owner = esr


## 创建一个带实心菱形 + 文字标签的可拖拽手柄（替代难点中的 Marker2D）。
func _make_handle(label_text: String, color: Color, pos: Vector2, meta_key: String, meta_val: Variant) -> Node2D:
	var root := Node2D.new()
	root.position = pos
	var s := 16.0
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0.0, -s), Vector2(s, 0.0), Vector2(0.0, s), Vector2(-s, 0.0)])
	poly.color = color
	root.add_child(poly)
	var lab := Label.new()
	lab.text = label_text
	lab.position = Vector2(s + 6.0, -12.0)
	lab.add_theme_color_override("font_color", color)
	root.add_child(lab)
	if meta_key != "":
		root.set_meta(meta_key, meta_val)
	add_child(root)
	_set_owner(root)
	return root


func _build_bg() -> void:
	var path: String = LevelData.tile_path(floor_idx, room_id)
	# 背景基准变换：与运行期 RoomManager._build_floor 完全一致（含 bg_offset/bg_scale），
	# 保证编辑器里对视频/图片摆放的敌人·门·出生点，运行期精确落位。
	var base_pos := Vector2(-W / 2.0, -H / 2.0) + _layout.bg_offset
	var base_scale := Vector2(_layout.bg_scale, _layout.bg_scale)
	var r := TextureRect.new()
	r.name = "BG"
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.size = Vector2(W, H)
	r.position = base_pos
	r.scale = base_scale
	r.z_index = -100
	add_child(r)
	if path == "":
		return
	var res := load(path)
	if res is VideoStream:
		# 编辑器里也用 VideoStreamPlayer 播放动态背景，确保可视化摆放对齐运行期。
		# 关键：play() 必须在 add_child 之后调用（节点进入场景树），否则报 !is_inside_tree() 且不播放，
		# 底图又被隐藏 → 整个背景黑屏。call_deferred 保证整棵树就绪后的下一帧再播，与 RoomManager 一致。
		var vp := VideoStreamPlayer.new()
		vp.name = "BGVideo"
		vp.stream = res
		vp.expand = true
		vp.loop = true
		vp.autoplay = true          # 编辑器视口里 autoplay 能可靠触发播放
		vp.audio_track = -1
		vp.set_anchors_preset(Control.PRESET_TOP_LEFT)
		vp.size = Vector2(W, H)
		vp.position = base_pos
		vp.scale = base_scale
		vp.z_index = -100
		add_child(vp)
		vp.call_deferred("play")
		# 兜底：若同目录存在同名 .png 静帧（如 S_001_1.png），作为底图保留，
		# 即便编辑器里视频偶发不渲染也能看到房间布局来对齐敌人/门/出生点。
		var poster: String = path.get_basename() + ".png"
		if ResourceLoader.exists(poster):
			r.texture = load(poster) as Texture2D
		else:
			r.visible = false
	elif res is Texture2D:
		r.texture = res


func _build_doors() -> void:
	var edges: Array[Vector2] = [
		Vector2(0.0, -H / 2.0 + 26.0),
		Vector2(0.0, H / 2.0 - 26.0),
		Vector2(-W / 2.0 + 26.0, 0.0),
		Vector2(W / 2.0 - 26.0, 0.0)
	]
	var neigh: Array = _neighbors()
	for i in neigh.size():
		var nid: String = String(neigh[i])
		var pos: Vector2 = edges[i] if i < edges.size() else Vector2.ZERO
		for d in _layout.doors:
			if d.target == nid:
				pos = d.position
				break
		var h := _make_handle("门→" + nid, Color(0.5, 1.0, 0.6), pos, "target", nid)
		_door_markers.append(h)


## 把当前房间保存的 enemy_specs 载入编辑器数组（切换房间时调用，保证数量按房间保存）。
## 若 .tres 没有该字段则初始化为「全部 15 种、数量 0」。
func _load_specs_into_editor() -> void:
	enemy_specs = []
	if _layout == null or _layout.enemy_specs.is_empty():
		for id in EnemyPlacement.IDS:
			var c := EnemyTypeCount.new()
			c.enemy_id = id
			c.count = 0
			enemy_specs.append(c)
		return
	for s in _layout.enemy_specs:
		var c := EnemyTypeCount.new()
		c.enemy_id = s.enemy_id
		c.count = s.count
		enemy_specs.append(c)


## 按各类型数量生成可拖拽敌人手柄。
## - 实时编辑(count 变化)：保留当前已摆放手柄的位置（按类型匹配）。
## - 房间重载/切换：从已保存的 enemy_placements 恢复位置（_enemy_markers 为空时走此分支）。
func _build_enemies() -> void:
	var existing: Dictionary = {}
	if _enemy_markers.size() > 0:
		for m in _enemy_markers:
			var eid: String = m.enemy_id
			if not existing.has(eid):
				existing[eid] = []
			existing[eid].append(m.position)
	else:
		for def in _layout.enemy_placements:
			var eid: String = def.enemy_id
			if not existing.has(eid):
				existing[eid] = []
			existing[eid].append(def.pos)
	for m in _enemy_markers:
		m.queue_free()
	_enemy_markers.clear()
	for spec in enemy_specs:
		var eid: String = spec.enemy_id
		var want: int = maxi(0, int(spec.count))
		var pool: Array = existing.get(eid, [])
		for i in want:
			var h := EnemyPlacement.new()
			h.enemy_id = eid
			if i < pool.size():
				h.position = pool[i]
			else:
				h.position = Vector2(randf_range(-220.0, 220.0), randf_range(-120.0, 120.0))
			add_child(h)
			_set_owner(h)
			_enemy_markers.append(h)


## 出生点手柄（绿色菱形，和门一样可拖）。
func _build_spawn() -> void:
	var pos: Vector2 = Vector2.ZERO
	if _layout != null:
		pos = _layout.spawn_point
	if pos == Vector2.ZERO:
		pos = Vector2(0.0, 0.0)
	_spawn_marker = _make_handle("出生点", Color(0.4, 1.0, 0.5), pos, "", null)


func _build_blocked() -> void:
	for i in _layout.blocked.size():
		var rd: RectDef = _layout.blocked[i]
		var h := BlockedHandle.new()
		h.name = "Blocked_%d" % i
		h.position = rd.center
		h.rotation_deg = rd.rotation_deg
		h.shape_type = rd.shape_type
		h.rect_size = rd.size
		h.points = rd.points
		add_child(h)
		_set_owner(h)
		_blocked_rects.append(h)
	_blocked_count = _layout.blocked.size()


## 增删禁区手柄，保留已有手柄的中心/旋转/形状/尺寸。
func _adjust_blocked(n: int) -> void:
	var items: Array[Dictionary] = []
	for h in _blocked_rects:
		items.append({
			"position": h.position,
			"rotation_deg": h.rotation_deg,
			"shape_type": h.shape_type,
			"rect_size": h.rect_size,
			"points": h.points
		})
	for h in _blocked_rects:
		h.queue_free()
	_blocked_rects.clear()
	for i in n:
		var h := BlockedHandle.new()
		h.name = "Blocked_%d" % i
		if i < items.size():
			var it: Dictionary = items[i]
			h.position = it.get("position", Vector2(0.0, 130.0))
			h.rotation_deg = it.get("rotation_deg", 0.0)
			h.shape_type = it.get("shape_type", 0)
			h.rect_size = it.get("rect_size", Vector2(120.0, 120.0))
			h.points = it.get("points", PackedVector2Array())
		else:
			h.position = Vector2(0.0, 130.0)
		add_child(h)
		_set_owner(h)
		_blocked_rects.append(h)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(Rect2(-W / 2.0, -H / 2.0, W, H), Color(0.3, 0.6, 1.0, 0.0), false, 2.0)


# 编辑器里编辑 enemy_specs 的 count/类型时，Inspector 不会触发 setter，
# 故在 _process 监听变化并重建手柄（仅 @tool 下运行）。
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_watch_specs()


func _watch_specs() -> void:
	var changed := false
	if _spec_snapshot.get("_len", -1) != enemy_specs.size():
		changed = true
	else:
		for i in enemy_specs.size():
			var s: EnemyTypeCount = enemy_specs[i]
			var prev: Dictionary = _spec_snapshot.get("k%d" % i, {})
			if prev.get("id", "") != s.enemy_id or prev.get("cnt", -1) != s.count:
				changed = true
				break
	if changed:
		_build_enemies()
		_snapshot_specs()


func _snapshot_specs() -> void:
	_spec_snapshot = {"_len": enemy_specs.size()}
	for i in enemy_specs.size():
		var s: EnemyTypeCount = enemy_specs[i]
		_spec_snapshot["k%d" % i] = {"id": s.enemy_id, "cnt": s.count}


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE and Engine.is_editor_hint():
		_save_layout()


func _save_layout() -> void:
	if _layout == null:
		_layout = RoomLayout.new()
	# 不要直接 clear()/append() 已加载 .tres 的数组——Godot 会把未覆盖的默认数组标记为只读，
	# 直接修改会报 "Array is in read-only state"。一律重新赋值新数组。
	var new_doors: Array[DoorDef] = []
	for m in _door_markers:
		var d := DoorDef.new()
		d.target = m.get_meta("target", "")
		d.position = m.position
		new_doors.append(d)
	_layout.doors = new_doors

	var new_placements: Array[EnemyPlacementDef] = []
	for m in _enemy_markers:
		var def := EnemyPlacementDef.new()
		def.enemy_id = m.enemy_id
		def.pos = m.position
		new_placements.append(def)
	_layout.enemy_placements = new_placements

	var new_specs: Array[EnemyTypeCount] = []
	for s in enemy_specs:
		var c := EnemyTypeCount.new()
		c.enemy_id = s.enemy_id
		c.count = s.count
		new_specs.append(c)
	_layout.enemy_specs = new_specs

	var new_blocked: Array[RectDef] = []
	for h in _blocked_rects:
		var rd := RectDef.new()
		rd.center = h.position
		rd.rotation_deg = rad_to_deg(h.rotation)
		rd.shape_type = h.shape_type
		rd.size = h.rect_size
		rd.points = h.points
		new_blocked.append(rd)
	_layout.blocked = new_blocked

	if _spawn_marker != null:
		_layout.spawn_point = _spawn_marker.position

	var path := _layout.resource_path if _layout.resource_path != "" else _layout_path()
	var err := ResourceSaver.save(_layout, path)
	if err != OK:
		push_error("RoomLayoutEditor: 保存布局失败 %s -> %d" % [path, err])
