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
	var tex_path: String = str(f1.get("idle", f1.get("walk_down", "")))
	var tex := load(tex_path) as Texture2D
	if tex != null:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.hframes = maxi(int(f1.get("fi", f1.get("fwd", 8))), 1)
		sp.frame = 0
		sp.scale = Vector2(0.45, 0.45) * float(f1.get("scale", 1.0))
		sp.z_index = 90
		add_child(sp)
	# 半透明底框提示（按形态1 CB 大致尺寸）
	var cb: Vector4 = f1.get("cb", Vector4(80, 90, 0, 4))
	var sc: float = float(f1.get("scale", 1.0))
	var sq := Polygon2D.new()
	sq.polygon = PackedVector2Array([
		Vector2(-cb.x * sc * 0.5 - 10, -cb.y * sc * 0.5 - 20),
		Vector2(cb.x * sc * 0.5 + 10, -cb.y * sc * 0.5 - 20),
		Vector2(cb.x * sc * 0.5 + 10, cb.y * sc * 0.5 + 20),
		Vector2(-cb.x * sc * 0.5 - 10, cb.y * sc * 0.5 + 20)])
	sq.color = Color(1.0, 0.3, 0.3, 0.10)
	sq.z_index = 89
	add_child(sq)
