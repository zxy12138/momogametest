@tool
extends Node2D
class_name DoorSizeHandle

## 门判定框「尺寸手柄」：DoorHandle 的子节点，拖动它即可实时调整判定框矩形大小。
## 位置 = 判定框右下角（相对门中心 DoorHandle 原点），DoorHandle._process 每帧读它算 door_size（x=宽、y=高）。
## 与禁区顶点 PolygonPointHandle 同理：设 owner 后才能在编辑器里被选中、拖动。


func _ready() -> void:
	_redraw()


func _process(_delta: float) -> void:
	_redraw()


func _redraw() -> void:
	for c in get_children():
		c.queue_free()
	# 黄色实心小方块（醒目，表示「拖我调大小」）
	var box := Polygon2D.new()
	box.polygon = PackedVector2Array([
		Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5),
	])
	box.color = Color(1.0, 0.85, 0.2, 0.95)
	box.z_index = 99
	add_child(box)
	# 深色边框
	var frame := Line2D.new()
	frame.points = PackedVector2Array([
		Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5), Vector2(-5, -5),
	])
	frame.width = 2
	frame.default_color = Color(0.35, 0.25, 0.0, 0.9)
	frame.z_index = 99
	add_child(frame)
