# 《梦境逐影》死亡演出 CG（Control 根）
# 占位 CG 图（可一键替换 assets/ui/cg_death_a.png）；跳过 -> 重试 / 回主菜单。
extends Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.02, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# CG 图（占位，缺图也不崩）
	var cg := TextureRect.new()
	cg.texture = GameManager.load_tex("res://assets/ui/cg_death_a.png")
	if cg.texture != null:
		cg.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		cg.size = Vector2(640, 360)
		cg.position = get_viewport_rect().size / 2 - cg.size / 2
		add_child(cg)

	var cap := Label.new()
	cap.text = "梦境崩解……弥绘的笑声渐渐远去。"
	cap.position = Vector2(get_viewport_rect().size.x / 2 - 200, get_viewport_rect().size.y - 120)
	cap.add_theme_font_size_override("font_size", 18)
	cap.add_theme_color_override("font_color", Color(0.9, 0.85, 0.9))
	add_child(cap)

	# 跳过（右上）
	var skip := Button.new()
	skip.text = "跳过 ▶"
	skip.position = Vector2(get_viewport_rect().size.x - 110, 16)
	skip.pressed.connect(_show_retry)
	add_child(skip)

	# 数秒后自动出现重试界面
	var tm := get_tree().create_timer(3.5)
	tm.one_shot = true
	tm.connect("timeout", _show_retry)

func _show_retry() -> void:
	if has_node("RetryPanel"):
		return
	var c := Control.new()
	c.name = "RetryPanel"
	c.position = get_viewport_rect().size / 2 - Vector2(150, 70)
	var panel := ColorRect.new()
	panel.size = Vector2(300, 140)
	panel.color = Color(0.10, 0.08, 0.16, 0.95)
	c.add_child(panel)
	var t := Label.new()
	t.text = "要再入梦境吗？"
	t.position = Vector2(20, 16)
	t.add_theme_font_size_override("font_size", 16)
	c.add_child(t)
	var retry := Button.new()
	retry.text = "重试本层"
	retry.position = Vector2(20, 56)
	retry.pressed.connect(_retry)
	c.add_child(retry)
	var menu := Button.new()
	menu.text = "返回主菜单"
	menu.position = Vector2(20, 92)
	menu.pressed.connect(_menu)
	c.add_child(menu)
	add_child(c)

func _retry() -> void:
	GameManager.apply_death()
	get_tree().change_scene_to_file("res://src/scenes/Game.tscn")

func _menu() -> void:
	get_tree().change_scene_to_file("res://src/scenes/Main.tscn")
