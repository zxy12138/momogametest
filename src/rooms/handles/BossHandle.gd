## Boss 手柄：在 Boss 房场景里直接摆放（boss 贴图 + 名字，可拖）。
## boss_type 用 int + @export_enum（最可靠下拉）：b_bus / b_bug / b_pc 三种 Boss。
## 运行期 RoomManager 据此生成 Boss（Enemy.tscn 的 Boss 分支，保留已清空不刷 + 入场图逻辑）。
## 2026-08-16：Boss 全部双形态（form1 打空→变身→form2），旧 b_director/b_train/b_fear 已删除。
@tool
extends Node2D
class_name BossHandle

const BIDS := ["b_bus", "b_bug", "b_pc"]

@export_enum("b_bus:梦魇公车", "b_bug:昆虫僵尸", "b_pc:加班电脑老板")
var boss_type: int = 0

## 逐实例 Boss 体型倍率（0.3~3.0）：编辑器实时预览缩放；运行期 RoomManager 刷 Boss 时应用到 sprite 与碰撞框。
@export_range(0.3, 3.0, 0.05) var boss_scale_mult: float = 1.0:
	set(v):
		boss_scale_mult = v
		if Engine.is_editor_hint() and is_inside_tree():
			_redraw()

var _last_type := -1


func _ready() -> void:
	if Engine.is_editor_hint():
		_last_type = boss_type
		_redraw()
	else:
		visible = false


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _last_type != boss_type:
		_last_type = boss_type
		_redraw()


## 当前选中的 boss id（供 RoomManager 生成 Boss）。
func boss_id() -> String:
	return BIDS[clampi(boss_type, 0, BIDS.size() - 1)]


func _redraw() -> void:
	for c in get_children():
		c.queue_free()
	var bid: String = boss_id()
	var ed: Dictionary = {}
	var raw: Variant = Enemies.get_boss(bid)
	if raw is Dictionary:
		ed = raw
	# 双形态预览：形态1 首帧（form1.idle/walk_down），不显示名字/形态标签（2026-08-16 去场景文字）
	var f1: Dictionary = ed.get("form1", {})
	# 全局类型级 Boss 缩放/碰撞（插件面板按类型统一调）× 逐实例 BossHandle 微调，
	# 与运行期 RoomManager._spawn_boss / Boss._apply_boss_scale / _apply_form_cb 一致——
	# 让场景里拖动插件滑块时该类型所有 Boss 预览实时变化。
	var g_scale: float = ScaleConfig.get_boss_scale(bid)
	var g_coll: float = ScaleConfig.get_boss_collision(bid)
	var eff_scale: float = float(f1.get("scale", 1.0)) * g_scale * boss_scale_mult
	var cb_sc: float = float(f1.get("scale", 1.0)) * g_scale * boss_scale_mult * g_coll
	var tex_path: String = str(f1.get("idle", f1.get("walk_down", "")))
	var tex := load(tex_path) as Texture2D
	if tex != null:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.hframes = maxi(int(f1.get("fi", f1.get("fwd", 8))), 1)
		sp.frame = 0
		sp.scale = Vector2(0.45, 0.45) * eff_scale
		sp.z_index = 90
		add_child(sp)
	# 半透明底框提示：按 ScaleConfig 形状（矩形/三角/圆/多边形）+ 中心偏移绘制，
	# 与运行期 Boss._apply_form_cb / Enemy._shape_points 完全一致（插件调形状实时可见）。
	var cb: Vector4 = f1.get("cb", Vector4(80, 90, 0, 4))
	var shape := int(ScaleConfig.get_boss_shape(bid, ScaleConfig.SHAPE_RECT))
	var w := float(ScaleConfig.get_boss_w(bid, cb.x))
	var h := float(ScaleConfig.get_boss_h(bid, cb.y))
	var ox := float(ScaleConfig.get_boss_ox(bid, cb.z))
	var oy := float(ScaleConfig.get_boss_oy(bid, cb.w))
	var poly := ScaleConfig.get_boss_poly(bid)
	var sc: float = cb_sc
	var off := Vector2(ox * sc, oy * sc - 4.0)
	var sq := Polygon2D.new()
	var pp := PackedVector2Array()
	for v in Enemy._shape_points(shape, w, h, poly, sc):
		pp.append(v + off)
	sq.polygon = pp
	sq.color = Color(1.0, 0.3, 0.3, 0.10)
	sq.z_index = 89
	add_child(sq)
