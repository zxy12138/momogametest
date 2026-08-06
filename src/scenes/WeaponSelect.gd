# 《梦境逐影》初始武器三选一（Control 根）
# 开局随机抽 3 把作为悬浮武器栏，点「开始游戏」进入 Game 场景。
extends Control

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var t := Label.new()
	t.text = "你的初始武器（随机三把 · 悬浮身边）"
	t.position = Vector2(get_viewport_rect().size.x / 2 - 190, 50)
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(0.9, 0.85, 1.0))
	add_child(t)

	var ids: Array[String] = Weapons.pick_three()
	var n := ids.size()
	var card_w := 200.0
	var gap := 30.0
	var total := float(n) * card_w + float(n - 1) * gap
	var x0 := (get_viewport_rect().size.x - total) / 2.0
	var y0 := 150.0
	for i in n:
		var c := _card(ids[i], Vector2(x0 + i * (card_w + gap), y0), card_w)
		add_child(c)

	var start := Button.new()
	start.text = "开始游戏"
	start.position = Vector2(get_viewport_rect().size.x / 2 - 90, 440)
	start.size = Vector2(180, 40)
	start.pressed.connect(func(): _start(ids))
	add_child(start)

	var back := Button.new()
	back.text = "返回主菜单"
	back.position = Vector2(get_viewport_rect().size.x / 2 - 90, 490)
	back.size = Vector2(180, 40)
	back.pressed.connect(_back)
	add_child(back)


func _card(wid: String, pos: Vector2, ww: float) -> Control:
	var w: Dictionary = Weapons.get_weapon(wid)
	var c := Control.new()
	c.position = pos
	var panel := ColorRect.new()
	panel.size = Vector2(ww, 250)
	panel.color = Color(0.12, 0.10, 0.20, 0.95)
	c.add_child(panel)

	var icon := TextureRect.new()
	icon.texture = GameManager.load_tex(Weapons.get_icon_path(wid))
	if icon.texture != null:
		icon.position = Vector2(ww / 2.0 - 32, 20)
		icon.size = Vector2(64, 64)
		c.add_child(icon)

	var nm := Label.new()
	nm.text = w["name"]
	nm.position = Vector2(10, 104)
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	c.add_child(nm)

	var kind := Label.new()
	kind.text = "类型：" + ("远程" if w["kind"] == "ranged" else "近战")
	kind.position = Vector2(10, 134)
	kind.add_theme_font_size_override("font_size", 13)
	c.add_child(kind)

	var dmg := Label.new()
	dmg.text = "基础伤害：" + str(w["dmg"])
	dmg.position = Vector2(10, 156)
	dmg.add_theme_font_size_override("font_size", 13)
	c.add_child(dmg)

	var cd := Label.new()
	cd.text = "攻速：" + str(snapped(1.0 / float(w["cooldown"]), 0.01)) + " 次/秒"
	cd.position = Vector2(10, 178)
	cd.add_theme_font_size_override("font_size", 13)
	c.add_child(cd)
	return c


func _start(ids: Array) -> void:
	GameManager.reset_run_loadout(ids)
	get_tree().change_scene_to_file("res://src/scenes/Game.tscn")


func _back() -> void:
	get_tree().change_scene_to_file("res://src/scenes/Main.tscn")
