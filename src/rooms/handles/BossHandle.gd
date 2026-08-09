## Boss 手柄：在 Boss 房场景里直接摆放（boss 贴图 + 名字，可拖）。
## boss_type 用 int + @export_enum（最可靠下拉）：b_director / b_train / b_fear 三种 Boss。
## 运行期 RoomManager 据此生成 Boss（Enemy.tscn 的 Boss 分支，保留已清空不刷 + 入场图逻辑）。
## 取代旧「运行时自动生成 boss」——boss 位置/种类现在完全由场景手柄决定。
@tool
extends Node2D
class_name BossHandle

const BIDS := ["b_director", "b_train", "b_fear"]

@export_enum("b_director", "b_train", "b_fear")
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
	var nm: String = str(ed.get("name", bid))
	# Boss 贴图第一帧（sprite_idle 序列帧，scale 0.4 对齐 Boss 体型）
	var tex := load(str(ed.get("sprite_idle", ""))) as Texture2D
	if tex != null:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.hframes = maxi(int(ed.get("fi", 1)), 1)
		sp.frame = 0
		sp.scale = Vector2(0.4, 0.4)
		sp.z_index = 90
		add_child(sp)
	var lab := Label.new()
	lab.text = nm
	lab.position = Vector2(-40, 66)
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	lab.z_index = 91
	add_child(lab)
	# 半透明底框提示
	var sq := Polygon2D.new()
	sq.polygon = PackedVector2Array([Vector2(-45, -45), Vector2(45, -45), Vector2(45, 60), Vector2(-45, 60)])
	sq.color = Color(1.0, 0.3, 0.3, 0.12)
	sq.z_index = 89
	add_child(sq)
