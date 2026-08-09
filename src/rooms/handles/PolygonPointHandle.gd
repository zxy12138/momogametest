## 多边形顶点手柄：BlockedHandle 的子节点，每个顶点一个（@tool 可拖）。
## 父 BlockedHandle 在多边形模式 (shape_type=1) 时收集子节点位置作为多边形点。
## 用户体验：在 SceneTree 里看到 BlockedHandle 下面挂着 PolygonPoint_1/_2/_3…，左键拖动即可改形状（PS 风格）。
@tool
extends Node2D
class_name PolygonPointHandle

## 顶点编号（仅可视化编号用，方便用户识别"第几个点"）。
@export var idx: int = 0


func _ready() -> void:
	_redraw()


func _process(_delta: float) -> void:
	# @tool 实时刷新索引（父 BlockedHandle 重新编号时同步显示）
	_redraw()


func _redraw() -> void:
	for c in get_children():
		c.queue_free()
	# 紫色十字（清晰可见，便于在场景里拖动）
	var cross := Line2D.new()
	cross.points = PackedVector2Array([Vector2(-6, 0), Vector2(6, 0), Vector2(0, -6), Vector2(0, 6)])
	cross.width = 2
	cross.default_color = Color(1.0, 0.4, 1.0, 0.9)
	cross.z_index = 88
	add_child(cross)
	# 编号标签（显示在十字右侧）
	var lab := Label.new()
	lab.text = str(idx)
	lab.position = Vector2(8, -7)
	lab.add_theme_font_size_override("font_size", 10)
	lab.add_theme_color_override("font_color", Color(1.0, 0.7, 1.0))
	lab.z_index = 89
	add_child(lab)
