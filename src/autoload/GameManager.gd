# 《梦境逐影》全局状态管理器（Autoload 单例）
# 负责：等级/经验/暴击/属性成长/武器/词条/梦晶/存档引用/虚弱窗口/占位精灵切片。
extends Node

signal stats_changed
signal leveled_up(new_level)
signal died
signal weak_changed(is_weak)

# ---- 运行时状态 ----
var level := 1
var xp := 0
var xp_needed := 100
var max_hp := 100
var hp := 100
var crit_rate := 0.05
var crit_dmg := 150
var attack_mult := 1.0
var move_speed := 200.0
var skill_cd_mult := 1.0
var atk_speed_mult := 1.0
var dream_eat_base := 2.0
var dream_eat_bonus := 0
var extra_crit_flat := 0.0
var extra_crit_dmg := 0
var weapon_id := "staff"
var loadout: Array[String] = []   ## 三槽武器栏（悬浮三武器）：开局随机 3 把，主武器=loadout[0]
var weapon_swap_used := false
var upgraded_done := false
var dream_crystals := 0
var affixes := {}            # name -> stacks
var layer_index := 1
var current_room := "r1"
var boss_cleared := {}      # layer_idx -> true
var visited := {}            # room_id -> true（当前层，可传送）
var weak_window := false
var birthday := false
var input_locked := false   # 驿站/地图/死亡界面时锁输入
var dev_mode := false        # 开发者模式：地图内选层跳关（F2 切换；不再自动全开地图）

# 新游戏开场序列（醒来独白 + 镜头拉近）触发开关。
# 由 Main._new_game 置 true，经 Intro 一路带到 Game._ready，播放后清零。
# 「继续」/「死亡重开」不设置，因此不会重播开场。
var prologue_pending := false

# 通关标志：第3层Boss被击败后置 true，进入 Epilogue 剧情场景；
# 回到 Game._ready 时由 _enter_completed_state 消费并清零，触发「通关状态」UI。
var game_completed := false

const START_WEAPON := "staff"


func _ready() -> void:
	reset_run(START_WEAPON)


# ============ 新游戏 / 死亡重置 ============
func reset_run(wid: String) -> void:
	level = 1
	xp = 0
	xp_needed = xp_for_level(1)
	weapon_id = wid
	weapon_swap_used = false
	upgraded_done = false
	dream_crystals = 0
	affixes = {}
	layer_index = 1
	boss_cleared = {}
	visited = {}
	weak_window = false
	birthday = false
	input_locked = false   # 新一局必须解锁输入，否则重开后玩家被卡死（ESC→重新开始 即此坑）
	compute_stats()
	hp = max_hp
	emit_signal("stats_changed")


# 新游戏（选武器界面）：给定 3 把初始武器栏，主武器取第一把。
func reset_run_loadout(ids: Array) -> void:
	loadout.clear()
	for x in ids:
		loadout.append(String(x))
	var first := loadout[0] if loadout.size() > 0 else "staff"
	reset_run(first)


# 死亡后保留：等级/经验/已解锁传送点/武器选择；重置：词条/梦晶/武器升阶
func apply_death() -> void:
	# 武器回退到基础版（升阶需重新触发）
	if Weapons.can_upgrade(weapon_id) == false and weapon_id.ends_with("_adv"):
		weapon_id = weapon_id.replace("_adv", "")
	weapon_swap_used = false
	upgraded_done = false
	affixes = {}
	dream_crystals = 0
	weak_window = false
	compute_stats()
	hp = max_hp
	emit_signal("stats_changed")


# ============ 属性成长 ============
func compute_stats() -> void:
	var tf := level >= 26
	max_hp = 100 + (level - 1) * 8
	if level >= 10: max_hp += 20
	if level >= 20: max_hp += 20
	if level >= 30: max_hp += 20
	if tf: max_hp = int(max_hp * 1.1)

	var cap := 0.15
	if level >= 16: cap = 0.30
	crit_rate = mini(0.05 + (level - 1) * 0.01, cap)
	crit_dmg = 200 if tf else 150
	attack_mult = 1.0 + (level - 1) * 0.03
	move_speed = 200.0 * (1.0 + (level - 1) * 0.015)
	move_speed = mini(move_speed, 350.0)
	skill_cd_mult = clampf(1.0 - 0.005 * (level - 1), 0.8, 1.0)
	if tf:
		attack_mult *= 1.1
		move_speed *= 1.1
		crit_dmg += 50

	# 词条加成
	extra_crit_flat = affixes.get("致命感知", 0) * 0.05
	extra_crit_dmg = affixes.get("梦境锐化", 0) * 30
	atk_speed_mult = 0.8 if affixes.has("全力一击") else 1.0
	if affixes.has("全力一击"):
		attack_mult *= 1.4
	dream_eat_bonus = 8 if affixes.has("梦食强化") else 0
	crit_rate = clampf(crit_rate + extra_crit_flat, 0.0, 1.0)


# 暴击判定：基于当前 crit_rate 掷骰。Weapon 开火时调用。
func roll_crit() -> bool:
	return randf() < crit_rate


func xp_for_level(lvl: int) -> int:
	var t := {
		1:100,2:150,3:200,4:300,5:400,6:500,7:650,8:800,9:900,10:1000,
		11:1150,12:1300,13:1450,14:1500,15:1800,16:2000,17:2200,18:2300,19:2500,20:3000,
		21:3200,22:3500,23:3800,24:4000,25:5000
	}
	if t.has(lvl): return t[lvl]
	return 5000


func add_xp(amount: int) -> bool:
	xp += amount
	var leveled := false
	while xp >= xp_needed and level < 30:
		xp -= xp_needed
		level += 1
		xp_needed = xp_for_level(level)
		leveled = true
	compute_stats()
	emit_signal("stats_changed")
	if leveled:
		emit_signal("leveled_up", level)
	return leveled


func heal(amount: float) -> void:
	hp = mini(max_hp, hp + amount)
	emit_signal("stats_changed")


func damage_player(amount: float) -> void:
	hp -= amount
	if hp <= 0:
		hp = 0
		emit_signal("stats_changed")
		emit_signal("died")
	else:
		emit_signal("stats_changed")


# ============ 武器 ============
func get_weapon() -> Dictionary:
	var w = Weapons.get_weapon(weapon_id)
	if w == null:
		return {}
	return w


func swap_weapon(new_id: String) -> bool:
	if level < 4 or weapon_swap_used:
		return false
	weapon_id = new_id
	weapon_swap_used = true
	emit_signal("stats_changed")
	return true


func upgrade_weapon() -> bool:
	if level < 8 or upgraded_done:
		return false
	if not Weapons.can_upgrade(weapon_id):
		return false
	weapon_id = Weapons.get_weapon(weapon_id)["upg"]
	upgraded_done = true
	emit_signal("stats_changed")
	return true


# 击杀处理：经验 + 梦食回血（+暴击额外）
func on_kill(xp_reward: int, is_crit: bool) -> void:
	add_xp(xp_reward)
	var h := clampf(dream_eat_base + 0.3 * (level - 1), 2.0, 10.0)
	if is_crit:
		h += dream_eat_bonus
	heal(h)


func add_affix(name: String) -> void:
	affixes[name] = affixes.get(name, 0) + 1
	compute_stats()
	emit_signal("stats_changed")


func add_crystals(n: int) -> void:
	dream_crystals += n
	emit_signal("stats_changed")


func set_weak(w: bool) -> void:
	if weak_window != w:
		weak_window = w
		emit_signal("weak_changed", w)


# ============ 伤害飘字 ============
const FloatingTextScene = preload("res://src/fx/FloatingText.tscn")

func popup_damage(pos: Vector2, dmg: int, is_crit: bool) -> void:
	var ft := FloatingTextScene.instantiate()
	var sc := get_tree().current_scene
	if sc != null:
		sc.add_child(ft)
		ft.global_position = pos
	ft.popup(str(dmg), Color(1, 0.6, 0.1) if is_crit else Color(1, 1, 1), is_crit)


# ============ 一次性特效 ============
func fx(path: String, pos: Vector2, fw: int, fh: int, frames: int, life: float = 0.5) -> void:
	var tex := load_tex(path)
	if tex == null:
		return
	var asp := AnimatedSprite2D.new()
	var sf := SpriteFrames.new()
	sf.add_animation("p")
	sf.set_animation_speed("p", float(frames) / life)
	for i in frames:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame("p", at)
	asp.sprite_frames = sf
	asp.position = pos
	asp.play("p")
	var sc := get_tree().current_scene
	if sc != null:
		sc.add_child(asp)
	var t := get_tree().create_tween()
	t.tween_callback(asp.queue_free).set_delay(life)


# ============ 占位精灵切片 ============
func load_tex(path: String) -> Texture2D:
	# 用 load() 而非 ResourceLoader.exists()+load()：
	# load() 会规范化 "res://.../../..." 这类含 ".." 的路径，
	# exists() 不会，导致敌人弹道贴图（路径带 ../）判定失败返回 null。
	return load(path) as Texture2D


# spec: {动画名: [路径, 单帧宽, 单帧高, 帧数, fps, 行号=0]}
# 行号用于合并精灵图：第 row 行从 y=row*fh 起横向取 fr 帧。
func make_frames(spec: Dictionary) -> SpriteFrames:
	var sf := SpriteFrames.new()
	for anim in spec.keys():
		var a: Array = spec[anim]
		var path: String = a[0]
		var fw: int = a[1]; var fh: int = a[2]; var fr: int = a[3]
		var fps: float = a[4] if a.size() > 4 else 12.0
		var row: int = a[5] if a.size() > 5 else 0
		sf.add_animation(anim)
		sf.set_animation_speed(anim, fps)
		sf.set_animation_loop(anim, anim != "dead")
		var tex := load_tex(path)
		if tex != null:
			for i in fr:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * fw, row * fh, fw, fh)
				sf.add_frame(anim, at)
		else:
			# 兜底：1x1 洋红块，保证不崩
			var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
			img.fill(Color(1, 0, 1, 1))
			var t := ImageTexture.create_from_image(img)
			sf.add_frame(anim, t)
	return sf
