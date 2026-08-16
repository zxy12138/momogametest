@tool
extends Node2D
class_name BlockedHandle

## 禁区手柄：PS 风格多边形编辑器。
##   矩形模式 (shape_type=0)：用 rect_size（中心=此节点 position）。
##   多边形模式 (shape_type=1)：每个顶点是子 PolygonPointHandle 节点（@tool，可拖、可在 SceneTree 看到）。
## 运行期 RoomManager 据此生成无形碰撞墙（StaticBody2D + CollisionShape/CollisionPolygon2D）。

## 形状类型：0=矩形 / 1=多边形（多边形模式时顶点=子 PolygonPointHandle 节点位置）
@export var shape_type: int = 1

## 矩形模式尺寸（shape_type=0 时用）
@export var rect_size: Vector2 = Vector2(120.0, 120.0)

## 多边形模式顶点的"备份"（运行时由子节点位置填充，编辑器手动改 Inspector 也可写入子节点）
@export var points: PackedVector2Array = PackedVector2Array()

@export var rotation_deg: float = 0.0

## 手动创建（+ 禁区按钮）时是否自动补默认 4 点（编辑器体验）；脚本生成（黑白图导入等）置 false，
## 由生成器自己添加顶点，避免 _ready 自动补点 + 生成器加点 = 顶点重复叠加（形状错乱）。
@export var auto_seed_points: bool = true

## 多边形最小顶点数（不能删到少于这个）
const _MIN_POINTS: int = 3

## 插件「隐藏禁区可视化（测试）」全局开关（编辑器测试用，不写 visible、不污染场景）。
## 运行期（非编辑器进程）不受影响：F5/F6 是新进程，静态变量不共享。
static var s_hidden_all: bool = false

## 项目设置键：把「隐藏禁区可视化」持久化到 project.godot，
## 让运行期（F5/F6 是新进程）也能读到——插件勾选隐藏后，进游戏同样不显示红色禁区。
const HIDE_VISUAL_SETTING := "momogame/hide_blocked_visuals"


## 运行期读取：是否隐藏禁区红色可视化（默认 false）。
static func is_visual_hidden() -> bool:
	return bool(ProjectSettings.get_setting(HIDE_VISUAL_SETTING, false))


## 编辑器写入：勾选/取消「隐藏禁区可视化」时持久化，供运行期读取。
static func set_visual_hidden(hide: bool) -> void:
	ProjectSettings.set_setting(HIDE_VISUAL_SETTING, hide)
	ProjectSettings.save()


## 项目设置键：门判定框可视化隐藏开关（插件「隐藏门判定框」写入、运行期与编辑器 DoorHandle 读取）。
const HIDE_DOOR_VISUAL_SETTING := "momogame/hide_door_visuals"


## 读取：是否隐藏门判定框可视化（默认 false=显示）。编辑器 DoorHandle 与运行期 RoomManager 共用。
static func is_door_visual_hidden() -> bool:
	return bool(ProjectSettings.get_setting(HIDE_DOOR_VISUAL_SETTING, false))


## 写入：勾选/取消「隐藏门判定框」时持久化。
static func set_door_visual_hidden(hide: bool) -> void:
	ProjectSettings.set_setting(HIDE_DOOR_VISUAL_SETTING, hide)
	ProjectSettings.save()


func _ready() -> void:
	if Engine.is_editor_hint():
		# 编辑器下强制可见：修复历史污染（旧版开关可能把 visible=false 存进 .tscn，导致红框不显示）
		visible = true
		if shape_type == 1:
			if _point_count() == 0 and points.size() >= 3:
				# 数据修复：早期黑白图导入未设子顶点 owner → 保存后子点丢失，但有 points；
				# 自动从 points 恢复子顶点，红框 + 可拖顶点都回来
				_ensure_polygon_points()
			elif auto_seed_points:
				# 多边形模式：自动补默认点（仅当 auto_seed_points 开启，且当前没有任何 PolygonPointHandle 子节点）
				_ensure_polygon_points()
		_redraw()
	else:
		visible = false


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_redraw()


## 收集子 PolygonPointHandle 位置作为多边形点（房间局部坐标，相对父 BlockedHandle）。
func collect_polygon_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for c in get_children():
		if c is PolygonPointHandle:
			pts.append(c.position)
	return pts


## 外部（插件面板 + 顶点）调用：往多边形追加一个顶点。
## 默认位置 = 多边形几何中心（顶点平均）：新点落在形状内部，拖到边上拉出即可，不破坏外围轮廓。
func add_polygon_point(pos: Vector2 = Vector2.ZERO) -> void:
	if pos == Vector2.ZERO:
		var cnt := 0
		var sum := Vector2.ZERO
		for c in get_children():
			if c is PolygonPointHandle:
				sum += c.position
				cnt += 1
		pos = sum / cnt if cnt > 0 else Vector2.ZERO
	var c := PolygonPointHandle.new()
	c.idx = _point_count()
	add_child(c)
	c.owner = get_tree().edited_scene_root if is_inside_tree() else null
	c.position = pos
	_redraw()


## 外部（插件面板 - 顶点）调用：删最后一个顶点（至少留 _MIN_POINTS 个）。
func remove_last_polygon_point() -> void:
	var pts: Array[PolygonPointHandle] = []
	for c in get_children():
		if c is PolygonPointHandle:
			pts.append(c)
	if pts.size() <= _MIN_POINTS:
		return
	pts[pts.size() - 1].queue_free()
	_redraw()


## 重新编号所有子多边形顶点（idx 与数组顺序一致）。
func renumber_points() -> void:
	var i := 0
	for c in get_children():
		if c is PolygonPointHandle:
			c.idx = i
			i += 1


func _point_count() -> int:
	var n := 0
	for c in get_children():
		if c is PolygonPointHandle:
			n += 1
	return n


func _ensure_polygon_points() -> void:
	if _point_count() > 0:
		return
	# 优先从 points（暴露的导出）写入；若 points 也空则建默认三角形
	if points.size() >= 3:
		for i in points.size():
			var p := PolygonPointHandle.new()
			p.idx = i
			add_child(p)
			p.owner = get_tree().edited_scene_root if is_inside_tree() else null
			p.position = points[i]
		return
	# 默认：正方形 4 个点（边长 120，直观且方便拖成矩形/多边形）
	var r := 60.0
	for i in 4:
		var p := PolygonPointHandle.new()
		p.idx = i
		add_child(p)
		p.owner = get_tree().edited_scene_root if is_inside_tree() else null
		p.position = Vector2(
			r if (i == 1 or i == 2) else -r,
			r if (i == 2 or i == 3) else -r
		)


## 把本手柄（中心点）移动到多边形顶点的几何中心（顶点平均位置）。
## 顶点世界位置保持不变（反向补偿），图形不跳；仅中心手柄对齐图形中心，方便整体拖动。
func center_to_polygon_center() -> void:
	var pts: Array[PolygonPointHandle] = []
	for c in get_children():
		if c is PolygonPointHandle:
			pts.append(c)
	if pts.size() < 2:
		return
	var c := Vector2.ZERO
	for p in pts:
		c += p.position
	c /= pts.size()
	# 父节点中心移到几何中心，顶点反向补偿 → 图形在世界中不动，中心对齐
	position += c
	for p in pts:
		p.position -= c
	_redraw()


func _redraw() -> void:
	for c in get_children():
		if c is PolygonPointHandle:
			continue   # 保留顶点子节点
		c.queue_free()
	# 全局隐藏（插件「隐藏禁区可视化」）：清空可视化子节点后直接返回，不绘制红框/边框。
	# 用静态标志 + 持久化设置两者判断：s_hidden_all 是编辑器会话内即时开关，is_visual_hidden()
	# 读 project.godot 持久化值——否则关掉软件重开后静态标志重置，禁区又会显示（须重新勾选）。
	if s_hidden_all or is_visual_hidden():
		return
	# 收集点（多边形模式优先读子节点，否则回退 points；矩形模式用 rect_size）
	var pts: PackedVector2Array
	var is_poly: bool = shape_type == 1
	if is_poly:
		pts = collect_polygon_points()
		# 兜底：子顶点丢失（早期导入未设 owner 导致保存时丢失）但 points 有数据时，用 points 绘制，
		# 保证红框仍显示；用户可再点「+ 顶点」重建子节点。
		if pts.size() < 3 and points.size() >= 3:
			pts = points
		if pts.size() < 3:
			return   # 点不足时不绘制（避免报错）
		# 同步导出 points（让 Inspector 看得到）
		points = pts
	else:
		var hw: float = rect_size.x / 2.0
		var hh: float = rect_size.y / 2.0
		pts = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
	var rot: float = deg_to_rad(rotation_deg)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.rotation = rot
	poly.color = Color(0.8, 0.2, 0.2, 0.35)
	poly.z_index = 85
	add_child(poly)
	var frame := Line2D.new()
	var fp := pts.duplicate()
	fp.append(pts[0])
	frame.points = fp
	frame.rotation = rot
	frame.width = 2
	frame.default_color = Color(1.0, 0.4, 0.4, 0.8)
	frame.z_index = 86
	add_child(frame)
	renumber_points()
