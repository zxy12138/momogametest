@tool
extends Node2D
class_name DoorHandle

## 门手柄：在房间场景 f{层}_{房}.tscn 里直接摆放
## （编辑器可视化 = 箭头 + 目标房类型 + target id，可直接拖）。
## 目标房类型从 LevelData 全局类查（"起点"/"战斗"/"精英"/"驿站"/"BOSS"）。
## 箭头方向按门位置自动推断：上方=↑ / 下方=↓ / 左=← / 右=→。
## 运行期 RoomManager 据此生成真实门（Area2D + 门框贴图）。

var _target := ""
var _layer := 1

@export var target: String:
	get:
		return _target
	set(v):
		if _target != v:
			_target = v
			if Engine.is_editor_hint():
				_redraw()

@export var layer: int = 1:
	get:
		return _layer
	set(v):
		if _layer != v:
			_layer = v
			if Engine.is_editor_hint():
				_redraw()

## 门判定框尺寸（矩形 宽×高，世界单位 px）：编辑器里拖右下角黄点（x=宽、y=高）或 Inspector 改 x/y，
## 运行期据此生成矩形碰撞判定框。门是长方形，宽高独立。
var _door_size: Vector2 = Vector2(44.0, 44.0)
@export var door_size: Vector2 = Vector2(44.0, 44.0):
	get:
		return _door_size
	set(v):
		if _door_size != v:
			_door_size = v
			if Engine.is_editor_hint():
				_redraw()

## 尺寸手柄（判定框右下角可拖拽的黄色小方块）：拖动 x 改宽、y 改高。
var _size_handle: DoorSizeHandle = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_ensure_size_handle()
		# 打开场景时以 door_size 为准，把手柄复位到判定框右下角
		if _size_handle != null and is_instance_valid(_size_handle):
			_size_handle.position = Vector2(door_size.x * 0.5, door_size.y * 0.5)
		_redraw()
	else:
		visible = false   # 运行期由 RoomManager 生成真实门，手柄隐藏


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		# 位置移动时（拖动）实时重算箭头方向
		var ch := _current_arrow()
		if ch != _last_arrow:
			_last_arrow = ch
			_redraw()
		# 尺寸手柄被拖动 → 实时更新 door_size（x=宽、y=高，矩形）
		if _size_handle != null and is_instance_valid(_size_handle):
			var hp := _size_handle.position
			var w: float = clampf(2.0 * absf(hp.x), 16.0, 400.0)
			var h: float = clampf(2.0 * absf(hp.y), 16.0, 400.0)
			var ns := Vector2(w, h)
			if (ns - _door_size).length() > 0.5:
				_door_size = ns
				_redraw()


var _last_arrow := ""


## 目标房类型中文名（查 LevelData 全局类，编辑器/运行期均可安全访问）
func _target_type_zh() -> String:
	if _target == "" or _layer <= 0:
		return ""
	var L: Dictionary = LevelData.get_layer(_layer)
	var rooms_d: Dictionary = L.get("rooms", {}) as Dictionary
	if not rooms_d.has(_target):
		return ""
	var t: String = str((rooms_d[_target] as Dictionary).get("type", ""))
	match t:
		"combat": return "战斗"
		"elite": return "精英"
		"boss": return "BOSS"
		"inn": return "驿站"
		"start": return "起点"
		_: return ""


## 按门位置（房间局部坐标）自动推断箭头方向
func _current_arrow() -> String:
	# 哪边轴占绝对值更大，就用那一边
	if absf(position.x) > absf(position.y):
		return "←" if position.x < 0 else "→"
	if position.y != 0:
		return "↑" if position.y < 0 else "↓"
	return "→"


func _redraw() -> void:
	for c in get_children():
		if c == _size_handle:
			continue   # 保留尺寸手柄（它独立持久，拖动位置不能每次重建丢失）
		c.queue_free()
	var arrow: String = _current_arrow()
	var typ: String = _target_type_zh()
	_last_arrow = arrow
	# 场景文字已去除（2026-08-16）：不显示「箭头+类型」「→ r3」标签，仅保留门判定框可视化。
	# 门判定框可视化（半透明绿色矩形 + 边框）：与运行期 RoomManager._add_door_visual 完全一致，
	# 让用户在编辑器场景里就能直接看到门的判定范围，方便拖动对齐门外观（所见即所得）。
	# 勾选「隐藏门判定框」时，编辑器与运行期一并隐藏。
	if not BlockedHandle.is_door_visual_hidden():
		var half_w := door_size.x * 0.5
		var half_h := door_size.y * 0.5
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(-half_w, -half_h), Vector2(half_w, -half_h),
			Vector2(half_w, half_h), Vector2(-half_w, half_h),
		])
		poly.color = Color(0.3, 1.0, 0.4, 0.28)
		poly.z_index = 99
		add_child(poly)
		var frame := Line2D.new()
		frame.points = PackedVector2Array([
			Vector2(-half_w, -half_h), Vector2(half_w, -half_h),
			Vector2(half_w, half_h), Vector2(-half_w, half_h), Vector2(-half_w, -half_h),
		])
		frame.width = 2
		frame.default_color = Color(0.3, 1.0, 0.4, 0.9)
		frame.z_index = 99
		add_child(frame)


## 确保尺寸手柄存在（首次创建或从已保存场景复用）。设 owner 才能在编辑器里选中/拖动。
func _ensure_size_handle() -> void:
	if _size_handle != null and is_instance_valid(_size_handle):
		return
	for c in get_children():
		if c is DoorSizeHandle:
			_size_handle = c
			return
	_size_handle = DoorSizeHandle.new()
	_size_handle.name = "SizeHandle"
	add_child(_size_handle)
	_size_handle.owner = get_tree().edited_scene_root if is_inside_tree() else null
	_size_handle.position = Vector2(door_size.x * 0.5, door_size.y * 0.5)
