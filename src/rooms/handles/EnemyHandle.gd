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
	# 半透明底框（青=普通 / 紫=精英），提示这是可编辑手柄区域
	var sq := Polygon2D.new()
	sq.polygon = PackedVector2Array([Vector2(-40, -40), Vector2(40, -40), Vector2(40, 40), Vector2(-40, 40)])
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
		sp.scale = Vector2(0.45, 0.45) * scale_mult
		sp.z_index = 90
		add_child(sp)
	# 场景文字已去除（2026-08-16）：不显示怪名标签，仅保留精灵预览。
