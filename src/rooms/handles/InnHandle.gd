@tool
extends BlockedHandle
class_name InnHandle

## 驿站判定框手柄：复用禁区（BlockedHandle）的矩形/多边形拖拽编辑机制，
## 颜色用蓝色区分，且不受「隐藏禁区可视化」开关影响。
## 运行期 RoomManager 据此生成 Area2D；玩家靠近按 F 弹确认回满血。


func _redraw() -> void:
	for c in get_children():
		if c is PolygonPointHandle:
			continue   # 保留顶点子节点
		c.queue_free()
	# 收集点（多边形模式优先读子节点，否则回退 points；矩形模式用 rect_size）
	var pts: PackedVector2Array
	var is_poly: bool = shape_type == 1
	if is_poly:
		pts = collect_polygon_points()
		if pts.size() < 3 and points.size() >= 3:
			pts = points
		if pts.size() < 3:
			return
		points = pts
	else:
		var hw: float = rect_size.x / 2.0
		var hh: float = rect_size.y / 2.0
		pts = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
	var rot: float = deg_to_rad(rotation_deg)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.rotation = rot
	poly.color = Color(0.35, 0.6, 1.0, 0.35)   # 蓝色半透明
	poly.z_index = 85
	add_child(poly)
	var frame := Line2D.new()
	var fp := pts.duplicate()
	fp.append(pts[0])
	frame.points = fp
	frame.rotation = rot
	frame.width = 2
	frame.default_color = Color(0.4, 0.7, 1.0, 0.8)
	frame.z_index = 86
	add_child(frame)
	renumber_points()
