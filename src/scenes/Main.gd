# 《梦境逐影》主菜单（Control 根，项目入口场景）
# 新游戏 -> 选武器；继续 -> 读档；退出。
extends Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 标题图（占位，可一键替换 assets/ui/ui_title.png）
	var title := TextureRect.new()
	title.texture = GameManager.load_tex("res://assets/ui/ui_title.png")
	if title.texture != null:
		title.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		title.size = Vector2(420, 130)
		title.position = Vector2(get_viewport_rect().size.x / 2 - 210, 60)
		add_child(title)

	var sub := Label.new()
	sub.text = "献给弥绘的庆生特典 · Dream Chaser"
	sub.position = Vector2(get_viewport_rect().size.x / 2 - 160, 210)
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0))
	add_child(sub)

	var cx := get_viewport_rect().size.x / 2
	var nb := Button.new()
	nb.text = "新游戏"
	nb.position = Vector2(cx - 90, 270)
	nb.size = Vector2(180, 44)
	nb.pressed.connect(_new_game)
	add_child(nb)

	var cb := Button.new()
	cb.text = "继续"
	cb.position = Vector2(cx - 90, 326)
	cb.size = Vector2(180, 44)
	cb.disabled = not SaveManager.has_save()
	cb.pressed.connect(_continue)
	add_child(cb)

	var eb := Button.new()
	eb.text = "退出"
	eb.position = Vector2(cx - 90, 382)
	eb.size = Vector2(180, 40)
	eb.pressed.connect(_quit)
	add_child(eb)

func _new_game() -> void:
	get_tree().change_scene_to_file("res://src/scenes/WeaponSelect.tscn")

func _continue() -> void:
	var data := SaveManager.load_game()
	if data.is_empty():
		return
	SaveManager.apply_to_state(data)
	get_tree().change_scene_to_file("res://src/scenes/Game.tscn")

func _quit() -> void:
	get_tree().quit()
