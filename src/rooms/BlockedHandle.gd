@tool
extends Node2D
class_name BlockedHandle

## 禁区可视化编辑手柄（仅编辑器内由 RoomLayoutEditor 实例化）。
## - 中心点 = 本节点的 position：在 2D 视口直接拖拽移动整个禁区。
## - 旋转：在 Inspector 填 rotation_deg，或用视口旋转 gizmo（修改 Node2D.rotation）。
## - 形状：shape_type=0 用矩形(rect_size)；shape_type=1 用多边形(points，局部坐标可表达不规则物体)。
## RoomLayoutEditor 在保存(.tres)时把上述属性回写到 RectDef。

const MODE_RECT := 0
const MODE_POLY := 1

@export var shape_type: int = MODE_RECT:
	set(v):
		shape_type = v
		queue_redraw()
@export var rect_size: Vector2 = Vector2(120.0, 120.0):
	set(v):
		rect_size = v
		queue_redraw()
@export var points: PackedVector2Array = []:
	set(v):
		points = v
		queue_redraw()
@export var rotation_deg: float = 0.0:
	set(v):
		rotation_deg = v
		self.rotation = deg_to_rad(v)
		queue_redraw()

var _label: Label = null

func _ready() -> void:
	_label = Label.new()
	_label.text = "禁区"
	_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	add_child(_label)
	queue_redraw()

## 返回局部多边形顶点：矩形→4 角；多边形→points（points 为相对 center 的局部坐标）。
func _local_points() -> PackedVector2Array:
	if shape_type == MODE_POLY and points.size() >= 3:
		return points
	var hw: float = rect_size.x / 2.0
	var hh: float = rect_size.y / 2.0
	return PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])

func _draw() -> void:
	var pts: PackedVector2Array = _local_points()
	if pts.size() < 3:
		return
	var cols: Array[Color] = []
	cols.resize(pts.size())
	var fill := Color(1.0, 0.3, 0.3, 0.35)
	for k in pts.size():
		cols[k] = fill
	draw_polygon(pts, cols)
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(1.0, 0.4, 0.4), 2.0)
	if _label != null:
		_label.position = Vector2(pts[0].x, pts[0].y - 16.0)
