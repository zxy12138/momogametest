@tool
extends Node2D
class_name NextDoorHandle

## 下一层传送门手柄：在 Boss 房场景里摆放（门框贴图 + ↑下一层 标签，可拖）。
## 运行期 RoomManager 据此生成传送门（初始隐藏+禁用），Boss 击败后 Game 调 enable_next_door() 启用。
## next_layer=0 时自动取当前层+1；层3 Boss 用结局流程则不摆此手柄。

@export var next_layer: int = 0
## 传送门判定框尺寸（运行期 Area2D 碰撞框 = 该尺寸；编辑器里可视化显示可拖对齐）
@export var door_size: Vector2 = Vector2(48, 48)

func _ready() -> void:
	if Engine.is_editor_hint():
		_redraw()
	else:
		visible = false


func _redraw() -> void:
	for c in get_children():
		c.queue_free()
	# 下一层门可视化：金色半透明矩形 + 边框（与运行期 _build_next_door 一致）。
	# 不用 chuansongmen.png —— 那是第一关「测试传送门(PortalHandle)」专用素材。
	# 金色框与运行期 Area2D 判定范围一致，让用户在编辑器里直接看到/调整门的碰撞范围（所见即所得）。
	var half_w := door_size.x * 0.5
	var half_h := door_size.y * 0.5
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-half_w, -half_h), Vector2(half_w, -half_h),
		Vector2(half_w, half_h), Vector2(-half_w, half_h),
	])
	poly.color = Color(1.0, 0.85, 0.3, 0.30)
	poly.z_index = 89
	add_child(poly)
	var frame := Line2D.new()
	frame.points = PackedVector2Array([
		Vector2(-half_w, -half_h), Vector2(half_w, -half_h),
		Vector2(half_w, half_h), Vector2(-half_w, half_h), Vector2(-half_w, -half_h),
	])
	frame.width = 2
	frame.default_color = Color(1.0, 0.85, 0.3, 0.95)
	frame.z_index = 89
	add_child(frame)
