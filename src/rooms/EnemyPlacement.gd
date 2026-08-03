@tool
extends Node2D
class_name EnemyPlacement

## 编辑器里拖拽的敌人占位手柄。enemy_id 用 @export_enum 枚举（来自美术素材清单的普通小怪/精英，
## 共 15 种可放置类型；Boss 不通过此手柄放置，由 Boss 房 _start_boss_intro 演出生成）。
## 视觉：普通=青色方块、精英=紫色方块，并显示中文名，便于在 2D 视口辨认与摆放。
## 在 Scene 树选中手柄后，Inspector 里用下拉框选「类型」(enemy_id)；在视口拖动即设定位置。

const IDS := [
	"overtime_ghost", "kpi", "printer", "meeting", "phone",
	"commuter", "escalator", "rider", "revolving", "package",
	"message", "overdue", "rejected", "heart_beat", "elite_996"
]

var _eid: String = "overtime_ghost"

@export_enum("overtime_ghost", "kpi", "printer", "meeting", "phone", "commuter", "escalator", "rider", "revolving", "package", "message", "overdue", "rejected", "heart_beat", "elite_996")
var enemy_id: String:
	get:
		return _eid
	set(value):
		if _eid != value:
			_eid = value
			_redraw_shape()

func _ready() -> void:
	_redraw_shape()

## 根据 enemy_id 重建可视方块与标签（区分普通/精英配色）。
func _redraw_shape() -> void:
	for c in get_children():
		c.queue_free()
	var is_elite: bool = false
	var nm: String = _eid
	var ed: Dictionary = Enemies.get_enemy(_eid)
	if ed != null:
		is_elite = bool(ed.get("is_elite", false))
		nm = ed.get("name", _eid)
	var col := Color(0.30, 0.90, 1.0) if not is_elite else Color(0.75, 0.40, 0.95)
	var s := 22.0
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
	poly.color = col
	add_child(poly)
	var lab := Label.new()
	lab.text = ("精英·" if is_elite else "") + nm
	lab.position = Vector2(s + 6.0, -12.0)
	lab.add_theme_color_override("font_color", col)
	add_child(lab)
