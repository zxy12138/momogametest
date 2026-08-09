@tool
extends Node2D
class_name NextDoorHandle

## 下一层传送门手柄：在 Boss 房场景里摆放（门框贴图 + ↑下一层 标签，可拖）。
## 运行期 RoomManager 据此生成传送门（初始隐藏+禁用），Boss 击败后 Game 调 enable_next_door() 启用。
## next_layer=0 时自动取当前层+1；层3 Boss 用结局流程则不摆此手柄。

@export var next_layer: int = 0

func _ready() -> void:
	if Engine.is_editor_hint():
		_redraw()
	else:
		visible = false


func _redraw() -> void:
	for c in get_children():
		c.queue_free()
	var door_tex := load("res://assets/tiles/T-003_door_frame_open_anim.png") as Texture2D
	if door_tex != null:
		var ds := door_tex.get_size()
		var fw := ds.x / 4.0
		var dw := 96.0 * fw / ds.y
		var spr := Sprite2D.new()
		spr.texture = door_tex
		spr.hframes = 4
		spr.frame = 0
		spr.scale = Vector2(dw / fw, 96.0 / ds.y)
		spr.z_index = 90
		add_child(spr)
	var lab := Label.new()
	lab.text = "↑ 下一层"
	lab.position = Vector2(-34, -62)
	lab.add_theme_font_size_override("font_size", 16)
	lab.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	lab.z_index = 91
	add_child(lab)
