@tool
extends BlockedHandle
class_name PortalHandle

## 测试传送门手柄：靠近按 F 一键跳转到结尾剧情（花海场景）。
## 复用禁区（BlockedHandle）的矩形/多边形拖拽编辑机制，紫色区分，
## 图标用门框贴图；运行期 RoomManager 据此生成 Area2D，玩家靠近提示、按 F 跳花海。
## 仅放置在 f1_r1（起点房），供测试「一键到结尾」。


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
	# 紫色半透明判定框
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.rotation = rot
	poly.color = Color(0.7, 0.4, 1.0, 0.35)
	poly.z_index = 85
	add_child(poly)
	var frame := Line2D.new()
	var fp := pts.duplicate()
	fp.append(pts[0])
	frame.points = fp
	frame.rotation = rot
	frame.width = 2
	frame.default_color = Color(0.8, 0.5, 1.0, 0.8)
	frame.z_index = 86
	add_child(frame)
	# 门图标（传送门视觉；素材暂缺，用 exists 守卫避免 load 失败报错）
	var tex: Texture2D = null
	if ResourceLoader.exists("res://assets/tiles/chuansongmen.png"):
		tex = load("res://assets/tiles/chuansongmen.png") as Texture2D
	if tex != null:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.hframes = 1
		spr.frame = 0
		spr.scale = Vector2(0.55, 0.55)
		spr.z_index = 87
		add_child(spr)
	renumber_points()
