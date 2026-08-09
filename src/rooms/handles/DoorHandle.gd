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


func _ready() -> void:
	if Engine.is_editor_hint():
		_redraw()
	else:
		visible = false   # 运行期由 RoomManager 生成真实门，手柄隐藏


func _process(_delta: float) -> void:
	# 位置移动时（拖动）实时重算箭头方向
	if Engine.is_editor_hint():
		var ch := _current_arrow()
		if ch != _last_arrow:
			_last_arrow = ch
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
		c.queue_free()
	var arrow: String = _current_arrow()
	var typ: String = _target_type_zh()
	var main_text: String = ("%s %s" % [arrow, typ]) if typ != "" else ("%s %s" % [arrow, _target])
	_last_arrow = arrow
	# 主标签（箭头 + 类型）
	var lab := Label.new()
	lab.text = main_text
	lab.position = Vector2(14, -22)
	lab.add_theme_font_size_override("font_size", 16)
	lab.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lab.add_theme_constant_override("outline_size", 4)
	lab.z_index = 100
	add_child(lab)
	# 副标签（target id，如 r3）
	var id_lab := Label.new()
	id_lab.text = "→ %s" % _target
	id_lab.position = Vector2(14, -2)
	id_lab.add_theme_font_size_override("font_size", 11)
	id_lab.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	id_lab.z_index = 100
	add_child(id_lab)
	# 门框小图标（绿色三角形，进游戏时 RoomManager 会替换为真实门框贴图）
	var tri := Polygon2D.new()
	tri.polygon = PackedVector2Array([Vector2(0, -10), Vector2(18, 0), Vector2(0, 10)])
	tri.color = Color(0.5, 1.0, 0.6, 0.7)
	tri.z_index = 99
	add_child(tri)
