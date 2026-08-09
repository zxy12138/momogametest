@tool
extends Node2D
class_name SpawnPointHandle

## 角色出生点手柄：房间场景里直接摆放（绿色菱形 + 标签，可拖），节点 position 即出生点（房间局部坐标）。
## 运行期 Game._swap 在首进/无来源房间时用此位置出生（过门进入仍走门逻辑）。
## 每个房间最多放一个；RoomManager.spawn_point_position 优先读它，无则回退 .tres。

func _ready() -> void:
	if Engine.is_editor_hint():
		_redraw()
	else:
		visible = false

func _redraw() -> void:
	for c in get_children():
		c.queue_free()
	var dia := Polygon2D.new()
	dia.polygon = PackedVector2Array([Vector2(0, -20), Vector2(14, 0), Vector2(0, 20), Vector2(-14, 0)])
	dia.color = Color(0.3, 1.0, 0.4, 0.6)
	dia.z_index = 88
	add_child(dia)
	var lab := Label.new()
	lab.text = "出生点"
	lab.position = Vector2(-26, 16)
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	lab.z_index = 89
	add_child(lab)
