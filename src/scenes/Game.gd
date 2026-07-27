# 游戏主玩法场景：房间切换 / 传送 / 驿站 / 词条 / 死亡 / 生日彩蛋
@tool
extends Node2D

const ROOM = preload("res://src/rooms/Room.tscn")
const ENEMY = preload("res://src/enemies/Enemy.tscn")
const DEATHCG = preload("res://src/ui/DeathCG.tscn")
const BIRTHDAY = preload("res://src/ui/Birthday.tscn")
# 预加载地面武器脚本。注意：headless 下全局 class_name 缓存不会重新扫描，
# 因此这里用 preload 拿脚本引用来 new()，类型统一按 Node2D 处理（成员走 call/get/set），
# 避免解析期依赖全局类型「WeaponPickup」导致 Parse Error。
const WeaponPickupScript := preload("res://src/weapons/WeaponPickup.gd")

var _room: Node = null
var _transitioning := false
var _layer_w := 880.0
var _layer_h := 500.0
var _toast: Label = null
var _inn_open := false
var _inn_panel_ref: Control = null
var _inn_near := false
var _pause_open := false
var _pause_overlay: Control = null
var _dev_label: Label = null
var _inn_prompt: Label = null
var _ui_layer: CanvasLayer = null

# ============ 开场序列 / 场景内武器拾取 ============
var _prologue_active := false
var _prologue_bubble: Control = null
var _prologue_end_timer: SceneTreeTimer = null
var _near_pickup: Node2D = null
var _pickups: Array[Node2D] = []
var _pickup_panel: Panel = null
var _pickup_label: Label = null
const _PICKUP_RADIUS := 64.0

# Fade 必须挂在 CanvasLayer（屏幕空间）下，否则会被相机 zoom+跟随推到屏幕外，
# 只在角落露出黑块（之前每次切场景右下角的黑屏即此）。
@onready var _fade_rect: ColorRect = $Fade/Rect


func _ready() -> void:
	# 进入可玩场景的唯一切入点：无论如何都要解锁输入，
	# 否则任何把 input_locked 设成 true 的路径（ESC 暂停/死亡/生日）在回到 Game 时都会卡死玩家。
	GameManager.input_locked = false
	# 编辑器预览：在场景编辑器里直接 build 一个示例世界（地板/墙/门/敌人/Boss 可见），
	# 不跑任何游戏逻辑（输入/淡入/信号/计时器）。运行期走下方真实逻辑。
	if Engine.is_editor_hint():
		_editor_build_preview()
		return
	_fade_rect.size = get_window().get_visible_rect().size
	_fade_rect.modulate.a = 1.0
	var t := get_tree().create_tween()
	t.tween_property(_fade_rect, "modulate:a", 0.0, 0.6)
	MapData.load_layer(GameManager.layer_index)
	_restore_map_progress()
	GameManager.connect("leveled_up", _on_level_up)
	# 专用屏幕空间 UI 层：所有动态面板/提示都挂这里，避免被相机 zoom+跟随推到屏幕外
	var ui := CanvasLayer.new()
	ui.name = "UILayer"
	ui.layer = 10
	add_child(ui)
	_ui_layer = ui
	_build_toast()
	_build_inn_prompt()
	_build_dev_label()
	_build_pickup_prompt()
	transition_to("r1", true)

	# 新游戏：先强制播放开场序列（醒来独白 + 镜头拉近），结束后才生成可选武器。
	# 「继续」/「死亡重开」不会置 prologue_pending，因此直接进正常玩法。
	if GameManager.prologue_pending:
		GameManager.prologue_pending = false
		GameManager.reset_run("")   # 新游戏开局：先无武器，拾取后才装备
		_play_prologue()


# 编辑器预览：在场景编辑器里 build 一个示例世界，方便直接看到房间/墙/门/敌人/Boss。
# 预览节点由 @tool 在编辑器运行时动态 add_child，请勿在预览存在时 Ctrl+S 保存 Game.tscn，
# 以免把预览节点写进场景文件；关闭场景重开即可自动清理。运行期不会走这里。
func _editor_build_preview() -> void:
	if get_node_or_null("World/Room") != null:
		return
	MapData.load_layer(1)
	var room := ROOM.instantiate() as Node2D
	$World.add_child(room)
	room.call("setup", "r1", MapData.room("r1"), 1, $World, self)
	# 顺手放两个敌人 + 一个 Boss，方便在编辑器里核对精灵与朝向
	var e1 := ENEMY.instantiate() as Node2D
	e1.call("setup", "overtime_ghost")
	e1.global_position = Vector2(-180, -40)
	room.add_child(e1)
	var e2 := ENEMY.instantiate() as Node2D
	e2.call("setup", "printer")
	e2.global_position = Vector2(160, 60)
	room.add_child(e2)
	var b := load("res://src/enemies/Boss.tscn").instantiate() as Node2D
	b.call("setup", "b_director")
	b.global_position = Vector2(0, -120)
	room.add_child(b)
	var p := get_node_or_null("World/Player")
	if p != null:
		p.global_position = Vector2(0, 0)
		# 预览时把相机锚点改居中（原 anchor_mode=1 固定左上会让房间偏到角落），
		# 仅改 live 节点、不写入场景，关闭重开即恢复。
		var cam := p.get_node_or_null("Camera")
		if cam != null:
			cam.anchor_mode = 0


# 续关：把已探明/已通房间状态还原到 MapData（load_layer 会重置 states）
func _restore_map_progress() -> void:
	for rid in GameManager.visited.keys():
		if MapData.states.has(rid):
			MapData.states[rid] = "VISITED"
	if GameManager.boss_cleared.get(GameManager.layer_index, false):
		for rid in MapData.rooms.keys():
			if MapData.room(rid).get("type", "") == "boss":
				MapData.states[rid] = "BOSS_CLEARED"

func _build_toast() -> void:
	_toast = Label.new()
	_toast.position = Vector2(20, 20)
	_toast.modulate.a = 0.0
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	_toast.z_index = 100
	_toast.mouse_filter = 2
	_ui_layer.add_child(_toast)


func toast(text: String) -> void:
	if _toast == null: return
	_toast.text = text
	_toast.modulate.a = 1.0
	var t := get_tree().create_tween()
	t.tween_property(_toast, "modulate:a", 0.0, 1.2).set_delay(1.6)


# ============ 房间切换 ============
func transition_to(rid: String, instant: bool = false) -> void:
	if _transitioning and not instant:
		return
	# 合并地图键（含 "-"）：如 "f2-r3"。先解析跨层并切层，再走原逐层逻辑。
	if rid.contains("-"):
		var parts: PackedStringArray = rid.split("-")
		if parts.size() >= 2:
			var floor_str: String = parts[0]
			var bare: String = parts[1]
			if floor_str.begins_with("f"):
				var target_floor: int = int(floor_str.substr(1))
				if target_floor >= 1 and target_floor <= 3 and target_floor != GameManager.layer_index:
					_switch_floor(target_floor, bare)
				rid = bare
			else:
				rid = bare
	if not MapData.rooms.has(rid):
		return
	_transitioning = true
	if instant:
		_swap(rid)
		var t := get_tree().create_tween()
		t.tween_property(_fade_rect, "modulate:a", 0.0, 0.5)
		t.tween_callback(func(): _transitioning = false)
	else:
		var t := get_tree().create_tween()
		t.tween_property(_fade_rect, "modulate:a", 1.0, 0.25)
		t.tween_callback(func():
			_swap(rid)
			var t2 := get_tree().create_tween()
			t2.tween_property(_fade_rect, "modulate:a", 0.0, 0.35)
			t2.tween_callback(func(): _transitioning = false)
		)


func _swap(rid: String) -> void:
	# 清理上一房间残留的弹道/拾取物（它们加在场景根，不随房间销毁）
	for n in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(n):
			n.queue_free()
	if _room != null:
		_room.queue_free()
		_room = null
	# 房间切换时清空场景内武器拾取物（它们随房间销毁，数组引用需同步清掉）
	_pickups.clear()
	_near_pickup = null
	_update_pickup_prompt("")
	_inn_near = false
	show_inn_prompt(false)
	MapData.enter_room(rid)
	GameManager.current_room = rid
	var room := ROOM.instantiate() as Node2D
	_room = room
	$World.add_child(room)
	room.call("setup", rid, MapData.room(rid), GameManager.layer_index, $World, self)
	var p: Node2D = $World/Player
	var type: String = MapData.room(rid).get("type", "")
	if type == "boss":
		p.global_position = Vector2(0, _layer_h / 2 - 60)
	else:
		p.global_position = Vector2(0, 0)
	p.reset_ult()
	# 起始房（r1）：若不是由开场序列负责生成武器（开场序列结束才摆出可选武器），
	# 则在此直接摆出初始武器——覆盖「重新开始后地面武器消失」的问题。
	if rid == "r1" and not GameManager.prologue_pending:
		_spawn_starter_weapons()


# 合并地图跨层跳转：直接加载目标层并把该房标为 CURRENT。
# 与 _go_next_layer（固定 +1、走门逻辑）区分，不破坏正常逐层玩法。
func _switch_floor(target: int, room: String) -> void:
	GameManager.layer_index = target
	MapData.load_layer(target)
	GameManager.emit_signal("stats_changed")
	MapData.sync_merged_current_with(room)
	# 切层后若地图仍开着，刷新合并地图高亮
	var mu := get_node_or_null("MapUI")
	if mu != null and mu.has_method("redraw") and mu.call("is_open"):
		mu.redraw()


# ============ Boss 击败 ============
func on_boss_defeated(layer: int, _boss: Node) -> void:
	MapData.mark_boss_cleared(GameManager.current_room)
	GameManager.boss_cleared[layer] = true
	SaveManager.save_game()
	toast("Boss 净化！梦境归于宁静")
	if layer < 3:
		_spawn_next_door(layer + 1)
	else:
		_birthday()


func _spawn_next_door(next_layer: int) -> void:
	var d := Area2D.new()
	d.name = "NextDoor"
	d.collision_layer = 8
	d.collision_mask = 1
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(48, 48)
	cs.shape = sh
	d.add_child(cs)
	d.position = Vector2(0, -_layer_h / 2 + 40)
	var cb := func(b: Node):
		if b.is_in_group("player"):
			_go_next_layer(next_layer)
	d.connect("body_entered", cb)
	$World.add_child(d)
	# 下一层传送门可见指示
	# 下一层传送门可见门框（贴图 T-003 开启动画门，取首帧静态显示）
	var door_tex := load("res://assets/tiles/T-003_door_frame_open_anim.png") as Texture2D
	var ds := door_tex.get_size()
	var dh := 96.0
	var fw := ds.x / 4.0
	var dw := dh * fw / ds.y
	var spr := Sprite2D.new()
	spr.texture = door_tex
	spr.hframes = 4
	spr.frame = 0
	spr.scale = Vector2(dw / fw, dh / ds.y)
	spr.position = d.position
	spr.z_index = 4
	$World.add_child(spr)
	var lab := Label.new()
	lab.text = "↑ 下一层"
	lab.position = d.position - Vector2(34, 14)
	lab.add_theme_font_size_override("font_size", 22)
	lab.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	lab.z_index = 6
	$World.add_child(lab)
	toast("通往下一层梦境的传送门已开启")


func _go_next_layer(next: int) -> void:
	GameManager.layer_index = next
	MapData.load_layer(next)
	GameManager.emit_signal("stats_changed")
	transition_to("r1", true)
	toast("进入 " + MapData.LAYER[next])


func spawn_enemy(eid: String, pos: Vector2) -> void:
	var e := ENEMY.instantiate() as Node2D
	e.call("setup", eid)
	e.global_position = pos
	e.z_index = int(pos.y)
	# Boss 召唤的小怪也归当前房间，随房销毁（避免跨房叠加）
	if _room != null:
		_room.add_child(e)
	else:
		$World.add_child(e)


# ============ 驿站 ============
func open_inn() -> void:
	if _inn_open:
		return
	_inn_open = true
	GameManager.input_locked = true
	_inn_panel_ref = _inn_panel()
	_ui_layer.add_child(_inn_panel_ref)
	show_inn_prompt(false)


func _inn_panel() -> Control:
	var c := Control.new()
	c.name = "InnPanel"
	c.mouse_filter = 0
	c.position = get_window().get_visible_rect().size / 2 - Vector2(150, 90)
	var bg := ColorRect.new()
	bg.size = Vector2(300, 180)
	bg.color = Color(0.12, 0.10, 0.20, 0.96)
	c.add_child(bg)
	c.add_child(_label("梦境驿站 · 24h 便利店", Vector2(20, 8), 16))

	var opts := []
	if GameManager.level >= 8 and Weapons.can_upgrade(GameManager.weapon_id) and not GameManager.upgraded_done:
		opts.append(["武器升阶", func():
			GameManager.upgrade_weapon()
			toast("武器已升阶！")
			_close_inn(c)])
	if GameManager.level >= 4 and not GameManager.weapon_swap_used:
		opts.append(["更换武器", func(): _inn_swap(c)])
	if GameManager.dream_crystals >= 15:
		opts.append(["梦晶·临时暴击 +5%（15 晶）", func():
			GameManager.add_crystals(-15)
			GameManager.add_affix("致命感知")
			toast("暴击率提升！")
			_close_inn(c)])
	opts.append(["离开驿站", func(): _close_inn(c)])

	var y := 36
	for o in opts:
		var b := _button(o[0], Vector2(20, y), Vector2(260, 22))
		b.connect("pressed", o[1])
		c.add_child(b)
		y += 30
	return c


func _inn_swap(panel: Control) -> void:
	for ch in panel.get_children():
		panel.remove_child(ch)
		ch.queue_free()
	panel.add_child(_label("选择新武器（仅一次）：", Vector2(20, 8), 15))
	var pool := Weapons.SWAP_POOL
	var y := 34
	for wid in pool:
		var w: Dictionary = Weapons.get_weapon(wid)
		var b := _button(w["name"], Vector2(20, y), Vector2(260, 22))
		b.connect("pressed", func():
			GameManager.swap_weapon(wid)
			toast("已更换：" + w["name"])
			_close_inn(panel))
		panel.add_child(b)
		y += 28


func _close_inn(panel: Control) -> void:
	_inn_open = false
	GameManager.input_locked = false
	panel.queue_free()
	_inn_panel_ref = null

func _on_inn_enter() -> void:
	_inn_near = true
	show_inn_prompt(true)

func _on_inn_exit() -> void:
	_inn_near = false
	show_inn_prompt(false)

func show_inn_prompt(v: bool) -> void:
	if _inn_prompt != null:
		_inn_prompt.visible = v

func _build_inn_prompt() -> void:
	_inn_prompt = Label.new()
	_inn_prompt.text = "按 F 开启驿站"
	_inn_prompt.position = Vector2(20, 52)
	_inn_prompt.add_theme_font_size_override("font_size", 16)
	_inn_prompt.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_inn_prompt.z_index = 100
	_inn_prompt.mouse_filter = 2
	_inn_prompt.visible = false
	_ui_layer.add_child(_inn_prompt)

func _build_dev_label() -> void:
	_dev_label = Label.new()
	_dev_label.text = "开发者模式 ON · F12 切换 · M 看全图 · 地图内选层跳关"
	_dev_label.position = Vector2(20, get_window().get_visible_rect().size.y - 40)
	_dev_label.add_theme_font_size_override("font_size", 13)
	_dev_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_dev_label.z_index = 100
	_dev_label.mouse_filter = 2
	_dev_label.visible = false
	_ui_layer.add_child(_dev_label)


# ============ 词条（升级时三选一） ============
func _on_level_up(_lvl: int) -> void:
	GameManager.input_locked = true
	var c := Control.new()
	c.name = "AffixPanel"
	c.position = get_window().get_visible_rect().size / 2 - Vector2(170, 110)
	var bg := ColorRect.new()
	bg.size = Vector2(340, 220)
	bg.color = Color(0.14, 0.10, 0.22, 0.97)
	c.add_child(bg)
	c.add_child(_label("梦境馈赠 · 选择一项强化", Vector2(20, 10), 16))
	var pool := ["致命感知", "梦境锐化", "破绽猎手", "连锁暴击", "梦食强化", "全力一击"]
	var picks := []
	while picks.size() < 3 and not pool.is_empty():
		picks.append(pool.pop_at(randi_range(0, pool.size() - 1)))
	var desc := {"致命感知": "暴击率 +5%", "梦境锐化": "暴击额外伤害 +30", "破绽猎手": "对减速/冰冻敌人暴击率 +10%",
		"连锁暴击": "暴击后 1.5s 下次攻击暴击率 +15%", "梦食强化": "暴击击杀额外回复 8 HP",
		"全力一击": "攻速 -20%，伤害 +40% 暴击额外 +50"}
	var y := 44
	for name in picks:
		var b := _button(name + " — " + desc[name], Vector2(20, y), Vector2(300, 26))
		b.connect("pressed", func():
			GameManager.add_affix(name)
			GameManager.input_locked = false
			c.queue_free())
		c.add_child(b)
		y += 32
	var skip := _button("跳过", Vector2(20, y), Vector2(300, 24))
	skip.connect("pressed", func():
		GameManager.input_locked = false
		c.queue_free())
	c.add_child(skip)
	_ui_layer.add_child(c)


# ============ 死亡 / 生日 ============
func on_player_died() -> void:
	GameManager.input_locked = true
	var t := get_tree().create_tween()
	t.tween_property(_fade_rect, "modulate:a", 1.0, 0.6)
	t.tween_callback(func():
		get_tree().change_scene_to_file(DEATHCG.resource_path)
	)


func _birthday() -> void:
	GameManager.birthday = true
	SaveManager.save_game()
	GameManager.input_locked = true
	var t := get_tree().create_tween()
	t.tween_property(_fade_rect, "modulate:a", 1.0, 0.8)
	t.tween_callback(func():
		get_tree().change_scene_to_file(BIRTHDAY.resource_path)
	)


# ============ 输入 / 暂停 / 开发者模式 ============
# 开场序列进行中：ESC 在这里优先被 _input 拦截并消费（跳过序列），
# 因此 _unhandled_input 直接 return，避免误触发暂停菜单。
func _input(event: InputEvent) -> void:
	if _prologue_active and event.is_action_pressed("ui_cancel"):
		_end_prologue()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _prologue_active:
		return
	if event.is_action_pressed("ui_cancel"):
		if _inn_open and _inn_panel_ref != null:
			_close_inn(_inn_panel_ref)
		else:
			# 地图开着时，ESC 直接返回（关地图），而不是再弹暂停菜单
			var mu: Node = get_node_or_null("MapUI")
			if mu != null and mu.has_method("is_open") and mu.call("is_open"):
				mu.call("close_map")
			elif _pause_open:
				_close_pause()
			else:
				_open_pause()
	elif event.is_action_pressed("interact"):
		if _near_pickup != null and not GameManager.input_locked:
			_pick_up_weapon(_near_pickup)
		elif _inn_near and not _inn_open and not _pause_open:
			open_inn()
	elif event.is_action_pressed("dev"):
		_toggle_dev()

# 冻结/解冻世界：暂停时停掉敌人+弹道物理，但不暂停整棵树（否则菜单无法交互）
func _freeze_world(freeze: bool) -> void:
	for n in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(n):
			n.set_physics_process(!freeze)
	for n in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(n):
			n.set_physics_process(!freeze)

func _open_pause() -> void:
	if _pause_open:
		return
	_pause_open = true
	GameManager.input_locked = true
	_freeze_world(true)
	var panel := Control.new()
	panel.name = "PausePanel"
	panel.mouse_filter = 1
	panel.position = get_window().get_visible_rect().size / 2 - Vector2(180, 130)
	panel.size = Vector2(360, 260)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.12, 0.96)
	bg.size = panel.size
	panel.add_child(bg)
	panel.add_child(_label("已暂停", Vector2(20, 12), 22))
	var opts := [
		["继续", func(): _close_pause()],
		["重新开始", func(): _restart_game()],
		["返回主菜单", func(): _return_menu()],
	]
	var y := 60
	for o in opts:
		var b := _button(o[0], Vector2(30, y), Vector2(300, 36))
		b.connect("pressed", o[1])
		panel.add_child(b)
		y += 48
	_ui_layer.add_child(panel)
	_pause_overlay = panel

func _close_pause() -> void:
	if not _pause_open:
		return
	_pause_open = false
	_freeze_world(false)
	if is_instance_valid(_pause_overlay):
		_pause_overlay.queue_free()
	_pause_overlay = null
	GameManager.input_locked = false

func _restart_game() -> void:
	_pause_open = false
	_freeze_world(false)
	if is_instance_valid(_pause_overlay):
		_pause_overlay.queue_free()
	_pause_overlay = null
	GameManager.reset_run(GameManager.weapon_id)
	GameManager.input_locked = false   # 双保险：重开必须解锁输入
	get_tree().change_scene_to_file("res://src/scenes/Game.tscn")

func _return_menu() -> void:
	_pause_open = false
	_freeze_world(false)
	if is_instance_valid(_pause_overlay):
		_pause_overlay.queue_free()
	_pause_overlay = null
	GameManager.input_locked = false   # 双保险：返回主菜单后也解锁输入
	get_tree().change_scene_to_file("res://src/scenes/Main.tscn")

func _toggle_dev() -> void:
	GameManager.dev_mode = not GameManager.dev_mode
	if _dev_label != null:
		_dev_label.visible = GameManager.dev_mode
	if GameManager.dev_mode:
		MapData.reveal_all()
		toast("开发者模式：开（按 M 看全图，地图内选层跳关）")
	else:
		toast("开发者模式：关")
	var mu := get_node_or_null("MapUI")
	if mu != null and mu.has_method("redraw"):
		mu.redraw()

func dev_goto_layer(l: int) -> void:
	if l < 1 or l > 3:
		return
	GameManager.layer_index = l
	MapData.load_layer(l)
	GameManager.emit_signal("stats_changed")
	transition_to("r1", true)
	toast("进入 " + MapData.LAYER[l])
	var mu := get_node_or_null("MapUI")
	if mu != null and mu.has_method("redraw"):
		mu.redraw()

# ============ 开场序列（醒来独白 + 镜头拉近） ============
func _play_prologue() -> void:
	_prologue_active = true
	GameManager.input_locked = true
	var cam := _player_camera()
	if cam != null:
		# 相机本就是 DRAG_CENTER 跟随玩家（见 Player.tscn），放大即自然形成
		# 以玩家为中心的脸部特写，无需改 anchor_mode（改回 FIXED_TOP_LEFT 会让角色钉死在屏幕左上角）。
		var tw := get_tree().create_tween()
		tw.tween_property(cam, "zoom", Vector2(3.4, 3.4), 0.8)
	# 0.5s 后头顶冒出对话框；序列总时长 3.4s 后自动结束（或按 ESC 跳过）
	get_tree().create_timer(0.5).timeout.connect(_show_prologue_dialogue)
	_prologue_end_timer = get_tree().create_timer(3.4)
	_prologue_end_timer.timeout.connect(_end_prologue)


func _show_prologue_dialogue() -> void:
	if not _prologue_active:
		return
	var p: Node2D = $World/Player
	var box := Control.new()
	box.name = "PrologueBubble"
	# 世界空间、挂在玩家头上；会随镜头拉近一起放大，形成特写感
	box.position = Vector2(-66, -92)
	p.add_child(box)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.14, 0.92)
	bg.size = Vector2(132, 50)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bg)
	var lab := Label.new()
	lab.text = "我醒来了，这是在哪……"
	lab.position = Vector2(6, 6)
	lab.size = Vector2(120, 40)
	lab.add_theme_font_size_override("font_size", 15)
	lab.add_theme_color_override("font_color", Color(1, 1, 1))
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lab)
	_prologue_bubble = box


func _end_prologue() -> void:
	if not _prologue_active:
		return
	_prologue_active = false
	if is_instance_valid(_prologue_end_timer):
		if _prologue_end_timer.is_connected("timeout", _end_prologue):
			_prologue_end_timer.timeout.disconnect(_end_prologue)
		_prologue_end_timer = null
	var cam := _player_camera()
	if cam != null:
		var tw := get_tree().create_tween()
		tw.tween_property(cam, "zoom", Vector2(2, 2), 0.6)
	if is_instance_valid(_prologue_bubble):
		_prologue_bubble.queue_free()
		_prologue_bubble = null
	GameManager.input_locked = false
	_spawn_starter_weapons()


func _player_camera() -> Camera2D:
	var p: Node2D = $World/Player
	return p.get_node_or_null("Camera") as Camera2D


# ============ 场景内武器拾取 / 交换 ============
func _physics_process(_delta: float) -> void:
	if _prologue_active or GameManager.input_locked or _room == null:
		if _near_pickup != null:
			_near_pickup = null
			_update_pickup_prompt("")
		return
	var p: Node2D = $World/Player
	var best: Node2D = null
	var best_d: float = INF
	for pk in _pickups:
		if not is_instance_valid(pk) or not bool(pk.call("can_interact")):
			continue
		var d: float = p.global_position.distance_to(pk.global_position)
		if d < _PICKUP_RADIUS and d < best_d:
			best_d = d
			best = pk
	_near_pickup = best
	if best != null:
		_update_pickup_prompt(String(best.call("prompt_text")))
	else:
		_update_pickup_prompt("")


func _build_pickup_prompt() -> void:
	_pickup_panel = Panel.new()
	_pickup_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := 220.0
	var h := 34.0
	_pickup_panel.position = get_window().get_visible_rect().size / 2 - Vector2(w / 2.0, 150.0)
	_pickup_panel.size = Vector2(w, h)
	_pickup_label = Label.new()
	_pickup_label.position = Vector2(10, 6)
	_pickup_label.add_theme_font_size_override("font_size", 15)
	_pickup_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_pickup_panel.add_child(_pickup_label)
	_pickup_panel.visible = false
	_ui_layer.add_child(_pickup_panel)


func _update_pickup_prompt(text: String) -> void:
	if _pickup_panel == null:
		return
	if text == "":
		_pickup_panel.visible = false
	else:
		_pickup_label.text = "[F] " + text
		_pickup_panel.visible = true


# 开场结束后 / 进入起始房时，在房间里摆出初始武器供选择。
# 已装备的那把不再摆地上（避免重复）；其余照常出现，保证「其余武器始终可换」。
func _spawn_starter_weapons() -> void:
	if _room == null:
		return
	var p: Node2D = $World/Player
	var starters: Array = Weapons.STARTERS
	var offsets := [Vector2(-90.0, 26.0), Vector2(0.0, 46.0), Vector2(90.0, 26.0)]
	for i in starters.size():
		var wid: String = starters[i]
		if wid == GameManager.weapon_id:
			continue
		var pk := _make_weapon_pickup(wid, p.global_position + offsets[i])
		_room.add_child(pk)
		_pickups.append(pk)


func _make_weapon_pickup(wid: String, pos: Vector2) -> Node2D:
	var pk: Node2D = WeaponPickupScript.new()
	pk.set("weapon_id", wid)
	pk.global_position = pos
	return pk


# 按 F 拾取/交换武器：若已持有武器，则旧武器掉到脚下（短暂免疫，避免瞬间又换回）。
func _pick_up_weapon(pk: Node2D) -> void:
	if not is_instance_valid(pk):
		return
	var wid: String = String(pk.get("weapon_id"))
	if GameManager.weapon_id == wid:
		return
	if GameManager.weapon_id != "":
		var drop := _make_weapon_pickup(GameManager.weapon_id, $World/Player.global_position + Vector2(0.0, 28.0))
		drop.call("just_dropped")
		if _room != null:
			_room.add_child(drop)
		else:
			$World.add_child(drop)
		_pickups.append(drop)
	GameManager.weapon_id = wid
	GameManager.emit_signal("stats_changed")
	var w: Dictionary = Weapons.get_weapon(wid)
	if w != null:
		toast("装备：" + w["name"])
	_pickups.erase(pk)
	pk.queue_free()


# ============ 小工具 ============
func _label(text: String, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	return b
