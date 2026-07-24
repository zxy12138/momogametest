# 《梦境逐影》生日彩蛋（Control 根，最终 Boss 净化后触发）
# 占位 CG 图（可一键替换 assets/ui/CG-004_ending_birthday_cg.png）。
extends Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.04, 0.12, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var cg := TextureRect.new()
	cg.texture = GameManager.load_tex("res://assets/ui/CG-004_ending_birthday_cg.png")
	if cg.texture != null:
		cg.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		cg.size = Vector2(640, 360)
		cg.position = Vector2(get_viewport_rect().size.x / 2 - 320, 60)
		add_child(cg)

	var title := Label.new()
	title.text = "生日快乐，弥绘！"
	title.position = Vector2(get_viewport_rect().size.x / 2 - 150, 50)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	add_child(title)

	var msg := Label.new()
	msg.text = "谢谢你闯进她的梦。愿每个加班的深夜，都有人陪你打一场温柔的仗。"
	msg.position = Vector2(get_viewport_rect().size.x / 2 - 280, 440)
	msg.add_theme_font_size_override("font_size", 15)
	msg.add_theme_color_override("font_color", Color(0.95, 0.9, 1.0))
	add_child(msg)

	var btn := Button.new()
	btn.text = "回到主菜单"
	btn.position = Vector2(get_viewport_rect().size.x / 2 - 90, 480)
	btn.size = Vector2(180, 40)
	btn.pressed.connect(_menu)
	add_child(btn)

func _menu() -> void:
	get_tree().change_scene_to_file("res://src/scenes/Main.tscn")
