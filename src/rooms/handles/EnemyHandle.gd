@tool
extends Node2D
class_name EnemyHandle

## 敌人手柄：房间场景里直接摆放（青=普通 / 紫=精英方块 + 中文名，可拖）。
## enemy_type 用 int + @export_enum（Godot 最可靠的下拉方案——String+@export_enum 在部分版本 Inspector 下拉失效）。
## 运行期 RoomManager 据此在节点位置刷怪，手柄隐藏。

const IDS := ["alarm_clock", "lamp", "dog", "mower", "road_daredevil", "office_ghost", "spider", "hypno_tv", "centipede", "zombie", "overtime1", "kpi_group", "hardware_core", "printer2", "overtime2", "overtime3"]

@export_enum("alarm_clock", "lamp", "dog", "mower", "road_daredevil", "office_ghost", "spider", "hypno_tv", "centipede", "zombie", "overtime1", "kpi_group", "hardware_core", "printer2", "overtime2", "overtime3")
var enemy_type: int = 0

## 怪物大小倍率：房间编辑器里调（0.1~3.0），预览实时缩放；运行期 RoomManager 刷怪时应用到 Enemy。
@export_range(0.1, 3.0, 0.05) var scale_mult: float = 1.0:
	set(v):
		scale_mult = v
		# @tool 节点在脚本注册/序列化期可能未入树，此时 get_children 安全但 _redraw 的 add_child 无意义，跳过
		if Engine.is_editor_hint() and is_inside_tree():
			_redraw()

## 碰撞范围倍率（独立于 size 的碰撞框缩放，0.3~3.0）；仅放大身体碰撞/受击框，不动 sprite 视觉大小。
## 预览方块同步缩放，便于直观看到碰撞范围变化。
@export_range(0.3, 3.0, 0.05) var collision_mult: float = 1.0:
	set(v):
		collision_mult = v
		if Engine.is_editor_hint() and is_inside_tree():
			_redraw()

var _last_type := -1


func _ready() -> void:
	if Engine.is_editor_hint():
		_last_type = enemy_type
		_redraw()
	else:
		visible = false


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _last_type != enemy_type:
		_last_type = enemy_type
		_redraw()


## 当前选中的敌人 id（供 RoomManager 刷怪）。
func enemy_id() -> String:
	return IDS[clampi(enemy_type, 0, IDS.size() - 1)]


func _redraw() -> void:
	for c in get_children():
		c.queue_free()
	var eid: String = enemy_id()
	var ed: Dictionary = {}
	var raw: Variant = Enemies.get_enemy(eid)
	if raw is Dictionary:
		ed = raw
	var elite: bool = bool(ed.get("is_elite", false))
	var nm: String = str(ed.get("name", eid))
	var col := Color(0.3, 0.9, 0.9) if not elite else Color(0.8, 0.5, 1.0)
	# 全局类型级缩放/碰撞（插件面板按类型统一调，应用到所有同类型怪）× 逐实例手柄微调，
	# 编辑器预览与运行期 RoomManager._spawn_enemy 完全一致——这样在场景里拖动插件滑块能实时看到
	# 该类型所有怪的大小 / 碰撞范围变化（之前手柄预览只读逐实例值，全局调节看不到效果）。
	var g_scale: float = ScaleConfig.get_enemy_scale(eid)
	var g_coll: float = ScaleConfig.get_enemy_collision(eid)
	var eff_scale: float = g_scale * scale_mult
	var eff_coll: float = g_coll * collision_mult
	# 半透明底框（青=普通 / 紫=精英），按 ScaleConfig 形状（矩形/三角/圆/多边形）+ 中心偏移绘制，
	# 直观反映该怪实际碰撞范围（与运行期 _apply_collision_box / Enemy._shape_points 完全一致——
	# 插件面板里调形状/尺寸/中心点，场景里所有同类型怪的预览实时变化）。
	var cb: Vector4 = Enemy.CB.get(eid, Vector4(32, 32, 0, 0))
	var shape := int(ScaleConfig.get_enemy_shape(eid, ScaleConfig.SHAPE_RECT))
	var w := float(ScaleConfig.get_enemy_w(eid, cb.x))
	var h := float(ScaleConfig.get_enemy_h(eid, cb.y))
	var ox := float(ScaleConfig.get_enemy_ox(eid, cb.z))
	var oy := float(ScaleConfig.get_enemy_oy(eid, cb.w))
	var poly := ScaleConfig.get_enemy_poly(eid)
	var sc := eff_scale * eff_coll
	var off := Vector2(ox * sc, oy * sc - 4.0)
	var sq := Polygon2D.new()
	var pp := PackedVector2Array()
	for v in Enemy._shape_points(shape, w, h, poly, sc):
		pp.append(v + off)
	sq.polygon = pp
	sq.color = Color(col.r, col.g, col.b, 0.15)
	sq.z_index = 89
	add_child(sq)
	# 敌人贴图第一帧（序列帧：hframes=帧数 取第 0 帧，scale 0.45 与运行期一致）
	# 直接用 load() 加载：Enemies 是 class_name 全局类，编辑器预览期可安全访问（不用 autoload）
	# 无 idle 的怪（如巡逻怪闹钟）→ 兜底用第一个方向动画（walk_down）预览
	var tex_path := str(ed.get("idle", ""))
	var fkey := "fi"
	if tex_path == "":
		tex_path = str(ed.get("walk_down", ""))
		fkey = "fwd"
		if tex_path == "":
			tex_path = str(ed.get("walk", ""))
			fkey = "fwk"
	var tex := load(tex_path) as Texture2D
	if tex != null:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.hframes = maxi(int(ed.get(fkey, 8)), 1)
		sp.frame = 0
		sp.scale = Vector2(0.45, 0.45) * eff_scale
		sp.z_index = 90
		add_child(sp)
	# 场景文字已去除（2026-08-16）：不显示怪名标签，仅保留精灵预览。
