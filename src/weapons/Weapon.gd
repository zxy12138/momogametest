# 武器逻辑（玩家子节点）。读取 GameManager.get_weapon() 数据驱动。
# 暴击：GM.roll_crit()；暴击额外伤害 +GM.crit_dmg；Boss 虚弱窗口由 Enemy.take_damage 处理。
extends Node2D
class_name Weapon

const PROJ = preload("res://src/weapons/Projectile.tscn")

var _cd := 0.0
var _charging := false
var _charge_t := 0.0
var _spr : Sprite2D
var _held_id : String = ""


func process(delta: float, aim: Vector2, firing: bool) -> void:
	_cd -= delta
	var w := GameManager.get_weapon()
	if w == null:
		return
	# 手持武器视觉：武器切换时重建贴图，每帧更新朝向/翻转
	if _held_id != w.get("name", ""):
		_held_id = w.get("name", "")
		if _spr != null:
			_spr.queue_free()
			_spr = null
		_make_held(w)
	_update_held(aim)
	var cd: float = w["cooldown"] * GameManager.skill_cd_mult * GameManager.atk_speed_mult

	if w.get("charge", false):
		if firing and _cd <= 0:
			_charging = true
		if _charging:
			_charge_t = mini(_charge_t + delta, 1.2)
			if not firing:
				var ratio := clampf(_charge_t / 1.0, 0.2, 1.0)
				_do_fire(aim, ratio)
				_charging = false
				_cd = cd
	else:
		if firing and _cd <= 0:
			_do_fire(aim, 1.0)
			_cd = cd


func _make_held(w: Dictionary) -> void:
	_spr = Sprite2D.new()
	var tex := GameManager.load_tex(w.get("icon", ""))
	if tex == null:
		return
	_spr.texture = tex
	_spr.position = Vector2(12, -2)
	_spr.z_index = 8
	add_child(_spr)


func _update_held(aim: Vector2) -> void:
	if _spr == null:
		return
	var face := -1.0 if aim.x < 0 else 1.0
	_spr.flip_h = face < 0
	_spr.position = Vector2(12.0 * face, -2.0)


func _do_fire(aim: Vector2, ratio: float) -> void:
	var w := GameManager.get_weapon()
	var player := get_parent() as Node2D
	var is_crit: bool = GameManager.roll_crit() or w.get("always_crit", false)
	var dmg: int = int(w["dmg"] * GameManager.attack_mult * ratio)
	if is_crit:
		dmg += GameManager.crit_dmg

	if is_crit:
		player.call("shake", 0.12, 3)
		player.call("play_attack")
		GameManager.fx("res://assets/fx/FX-001_crit_trigger_orange_flash.png", player.global_position, 48, 48, 5, 0.45)

	if w["kind"] == "ranged":
		_spawn_proj(player.global_position + aim * 16, aim, w, dmg, is_crit)
	else:
		_melee(player.global_position, aim, w, dmg, is_crit)


func _spawn_proj(pos: Vector2, aim: Vector2, w: Dictionary, dmg: int, is_crit: bool) -> void:
	var p := PROJ.instantiate() as Area2D
	# 必须在 add_child（触发 _ready 加载贴图）之前把所有属性设好，否则贴图永远空
	p.set("direction", aim)
	p.set("speed", w.get("proj_speed", 320))
	p.set("damage", dmg)
	p.set("is_crit", is_crit)
	p.set("pierce", w.get("pierce", 0))
	p.set("bounce", w.get("bounce", 0))
	p.set("aoe", w.get("aoe", 0.0))
	p.set("from_player", true)
	p.set("effects", w.get("effect", ""))
	p.set("effect_time", w.get("effect_time", 0.0))
	p.set("texture_path", w.get("proj", ""))
	_spawn(p, pos)


func _melee(pos: Vector2, aim: Vector2, w: Dictionary, dmg: int, is_crit: bool) -> void:
	var reach: float = w.get("reach", 40.0)
	var arc: float = deg_to_rad(w.get("arc", 90))
	var center := pos + aim * reach * 0.55
	# 视觉弧线
	GameManager.fx("res://assets/fx/FX-015_hammer_slam_shockwave.png", center, 64, 16, 5, 0.18)
	# 直接结算范围内的敌人
	for en in get_tree().get_nodes_in_group("enemy"):
		var e := en as Node2D
		if e == null or not e.has_method("take_damage"):
			continue
		var to := e.global_position - pos
		var dist := to.length()
		if dist > reach:
			continue
		var ang := aim.angle_to(to)
		ang = fmod(ang + PI, TAU) - PI
		if abs(ang) > arc * 0.5:
			continue
		e.call("take_damage", dmg, is_crit, w.get("effect", ""), w.get("effect_time", 0.0))
		# 控制效果
		if w.get("slow", 0.0) > 0:
			e.call("apply_status", "slow", w["slow"])
		elif w.get("freeze", 0.0) > 0:
			e.call("apply_status", "freeze", w["freeze"])
		if w.get("knockback", 0.0) > 0:
			e.call("knockback", -to.normalized() * w["knockback"])
	# 位移武器（长枪）：向前突进
	if w.get("dash", false):
		get_parent().call("dash", aim)


func _spawn(node: Node2D, pos: Vector2) -> void:
	node.global_position = pos
	node.z_index = int(pos.y)
	var sc := get_tree().current_scene
	if sc != null:
		sc.add_child(node)
