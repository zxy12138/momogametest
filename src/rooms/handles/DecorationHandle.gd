@tool
extends Node2D
class_name DecorationHandle

## 装饰素材手柄：指向序列帧插件生成的 AnimatedSprite2D .tscn（场景路径），房间场景里摆放。
## 运行期 RoomManager 实例化并自动播放（autoplay="default"），随房间销毁。
## 字段与 DecorationPlacement 一一对应。

@export var scene_path: String = ""
@export var scale_xy := Vector2.ONE
@export var rotation_deg := 0.0
@export var flip_h := false
@export var flip_v := false

func _ready() -> void:
	if Engine.is_editor_hint():
		_redraw()
	else:
		visible = false

func _redraw() -> void:
	for c in get_children():
		c.queue_free()
	var sq := Polygon2D.new()
	sq.polygon = PackedVector2Array([Vector2(-18, -18), Vector2(18, -18), Vector2(18, 18), Vector2(-18, 18)])
	sq.color = Color(0.95, 0.8, 0.4, 0.4)
	sq.z_index = 87
	add_child(sq)
	# 场景文字已去除（2026-08-16）：不显示「装饰:xx」标签，仅保留方块提示。
