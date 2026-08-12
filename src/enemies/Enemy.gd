# 敌人（通用）：行为 chase / shooter / charger / aoe；支持减速/冰冻/灼烧/麻痹/击退。
@tool
extends CharacterBody2D
class_name Enemy

const PROJ = preload("res://src/weapons/Projectile.tscn")

## 场景里直接摆放怪物时填写的类型 id（如 "overtime_ghost" / "elite_996"）；
## _ready 会自动按它 setup。动态刷怪由 RoomManager 在 add_child 前调 setup()，
## 此时 _eid 已非空，_ready 不再重复 build（幂等）。
@export var eid: String = ""

var _data := {}
var _eid := ""
var hp := 30.0
var max_hp := 30.0
var xp := 8
var speed := 60.0
var behavior := "chase"
var contact_dmg := 10.0
var _atk_cd := 0.0
var _atk_timer := 0.0
var _dead := false
var _anim := "idle"
var _sprite: AnimatedSprite2D
# 状态
var _slow_t := 0.0
var _freeze_t := 0.0
var _para_t := 0.0
var _burn_t := 0.0
var _burn_acc := 0.0
var _kb_t := 0.0
var _kb_dir := Vector2.ZERO
var _spawn_t := 0.0


func setup(eid: String) -> void:
	_eid = eid
	_data = Enemies.get_enemy(eid)
	if _data == null:
		queue_free()
		return
	hp = float(_data["hp"]); max_hp = hp
	xp = int(_data["xp"]); speed = float(_data["speed"])
	behavior = _data["behavior"]; contact_dmg = float(_data.get("contact_dmg", 8))
	add_to_group("enemy")
	_sprite = get_node("Sprite")
	var fh: int = _data["fh"]; var fw: int = _data["fw"]
	var spec := {
		"idle":   [_data["idle"], fw, fh, _data["fi"], 8],
		"attack": [_data["attack"], fw, fh, _data["fa"], 14],
	}
	if _data.has("walk"):
		spec["walk"] = [_data["walk"], fw, fh, _data.get("fwk", _data["fi"]), 12]
	if _data.has("dead"):
		spec["dead"] = [_data["dead"], fw, fh, _data.get("fd", _data["fa"]), 12]
	_sprite.sprite_frames = GameManager.make_frames(spec)
	_sprite.play("idle")
	_sprite.scale = Vector2(0.45, 0.45)  # 与玩家同比例缩小（玩家 0.28/原 0.6≈0.467，取 0.45），战斗场景人物比例协调；仅视觉，碰撞半径不变
	var r := mini(fw, fh) * 0.32
	get_node("CollisionShape2D").shape.radius = r
	get_node("Hitbox/CollisionShape2D").shape.radius = r
	_atk_cd = randf_range(0.3, _data.get("atk_cd", 1.5))
	_spawn_t = 0.2
	var hb := get_node("Hitbox")
	hb.connect("body_entered", _on_hit_player)


func is_boss() -> bool:
	return false


# 编辑器预览：独立打开 Enemy.tscn 时构建一个示例敌人精灵（idle 动画可见）。
# 场景里直接摆放的敌人：Inspector 填 eid → _ready 自动 setup（编辑器/运行期一致）。
# 被 Game/RoomManager 在编辑器里实例化时，setup() 已在 add_child 前调用，_eid 非空，此处跳过，避免重复 build。
func _ready() -> void:
	if _eid == "" and eid != "":
		setup(eid)
	elif Engine.is_editor_hint() and _eid == "":
		setup("overtime_ghost")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	z_index = int(global_position.y)
	if _dead:
		return
	_tick_status(delta)
	if _kb_t > 0:
		_kb_t -= delta
		velocity = _kb_dir * 380.0
		move_and_slide()
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_p := player.global_position - global_position
	var dist := to_p.length()
	var dir := to_p.normalized() if dist > 0.1 else Vector2.ZERO
	match behavior:
		"chase", "charger":
			velocity = dir * speed
		"shooter":
			if dist > _data.get("atk_range", 280) * 0.85:
				velocity = dir * speed
			elif dist < _data.get("atk_range", 280) * 0.4:
				velocity = -dir * speed * 0.8
			else:
				velocity = Vector2.ZERO
			_atk_cd -= delta
			if _atk_cd <= 0:
				_atk_cd = _data.get("atk_cd", 1.5)
				_shoot(player.global_position)
		"aoe":
			velocity = (dir * speed) if dist > _data.get("aoe_radius", 60) else Vector2.ZERO
			_atk_cd -= delta
			if _atk_cd <= 0:
				_atk_cd = _data.get("atk_cd", 2.2)
				_pulse(player.global_position)
	move_and_slide()

	# 攻击动画
	if _atk_timer > 0:
		_atk_timer -= delta
		if _anim != "attack":
			_anim = "attack"
			_sprite.play("attack")
	elif velocity.length() > 5.0 and _data.has("walk"):
		# 移动时播走路（有 walk 动画的敌人）
		if _anim != "walk":
			_anim = "walk"
			_sprite.play("walk")
		_sprite.flip_h = dir.x < 0
	elif _anim != "idle":
		_anim = "idle"
		_sprite.play("idle")
		_sprite.flip_h = dir.x < 0


func _shoot(target_pos: Vector2) -> void:
	_atk_timer = 0.25
	var n: int = int(_data.get("bullet", 1))
	var spread: float = deg_to_rad(_data.get("spread", 0.0) * 57.3)
	var base := (target_pos - global_position).normalized()
	for i in n:
		var a := 0.0
		if n > 1:
			a = lerp(-spread, spread, float(i) / float(n - 1))
		var d := base.rotated(a)
		_spawn_proj(global_position + d * 14, d, _data.get("proj_dmg", 8), _data.get("proj_speed", 240), _data.get("proj", ""), _data.get("homing", false))


func _pulse(_target: Vector2) -> void:
	_atk_timer = 0.3
	var rad: float = _data.get("aoe_radius", 60)
	GameManager.fx("res://assets/fx/FX-015_hammer_slam_shockwave.png", global_position, 64, 16, 5, 0.4)
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and global_position.distance_to(p.global_position) <= rad:
		GameManager.damage_player(_data.get("proj_dmg", 12))
		var kb: int = _data.get("knockback", 0)
		if kb > 0 and p.has_method("hit_by"):
			pass  # 击退在玩家侧处理较复杂，这里仅造成直接伤害


func _spawn_proj(pos: Vector2, dir: Vector2, dmg: int, spd: float, tex: String, homing: bool) -> void:
	var p := PROJ.instantiate() as Area2D
	p.global_position = pos
	p.set("direction", dir)
	p.set("speed", spd)
	p.set("damage", dmg)
	p.set("from_player", false)
	p.set("homing", homing)
	p.set("texture_path", tex)
	p.z_index = int(pos.y)
	var sc := get_tree().current_scene
	if sc != null:
		sc.add_child(p)


func _on_hit_player(body: Node) -> void:
	if _dead or not body.is_in_group("player"):
		return
	if body.has_method("hit_by"):
		body.call("hit_by", contact_dmg)


func _tick_status(delta: float) -> void:
	var mult := 1.0
	if _freeze_t > 0:
		_freeze_t -= delta
		mult = 0.15
		_sprite.modulate = Color(0.6, 0.8, 1.0)
	elif _slow_t > 0:
		_slow_t -= delta
		mult = 0.5
		_sprite.modulate = Color(0.7, 0.7, 1.0)
	else:
		_sprite.modulate = Color(1, 1, 1)
	speed = float(_data.get("speed", speed)) * mult
	if _para_t > 0:
		_para_t -= delta
		speed = 0.0
	if _burn_t > 0:
		_burn_t -= delta
		_burn_acc += delta
		if _burn_acc >= 0.5:
			_burn_acc = 0.0
			_take_burn(4)


func apply_status(type: String, time: float) -> void:
	match type:
		"slow": _slow_t = maxf(_slow_t, time)
		"freeze": _freeze_t = maxf(_freeze_t, time)
		"paralyze": _para_t = maxf(_para_t, time)
		"burn", "dot": _burn_t = maxf(_burn_t, time)


func knockback(vec: Vector2) -> void:
	_kb_dir = vec
	_kb_t = 0.18


func take_damage(dmg: int, is_crit: bool, effect: String, effect_time: float) -> void:
	if _dead:
		return
	# Boss 虚弱窗口：翻倍 + 强制暴击
	if GameManager.weak_window and is_boss():
		dmg = int(dmg * 2)
		is_crit = true
	hp -= dmg
	GameManager.popup_damage(global_position, dmg, is_crit)
	_sprite.modulate = Color(1, 1, 1)
	var t := get_tree().create_tween()
	t.tween_property(_sprite, "modulate", Color(1, 0.3, 0.3), 0.08)
	t.tween_property(_sprite, "modulate", Color(1, 1, 1), 0.12)
	if effect != "" and effect_time > 0:
		apply_status(effect, effect_time)
	if hp <= 0:
		_die(is_crit)


func _take_burn(d: int) -> void:
	if _dead:
		return
	hp -= d
	GameManager.popup_damage(global_position, d, false)
	if hp <= 0:
		_die(false)


func _die(is_crit: bool) -> void:
	_dead = true
	GameManager.on_kill(xp, is_crit)
	_drop()
	velocity = Vector2.ZERO
	if _data.has("dead") and _sprite.sprite_frames.has_animation("dead"):
		# 有逐帧死亡动画：播放后 queue_free
		_sprite.play("dead")
		_sprite.connect("animation_finished", _on_dead_finished, CONNECT_ONE_SHOT)
	else:
		# 无死亡动画：沿用旧版淡出+溶解
		GameManager.fx("res://assets/fx/FX-023_kill_dissolve_effect.png", global_position, 32, 32, 5, 0.4)
		var t := get_tree().create_tween()
		t.tween_property(self, "modulate:a", 0.0, 0.35)
		t.tween_callback(queue_free).set_delay(0.35)


func _on_dead_finished() -> void:
	queue_free()


func _drop() -> void:
	var pk := load("res://src/fx/Pickup.tscn").instantiate() as Area2D
	pk.set("kind", "xp")
	pk.set("value", xp)
	pk.global_position = global_position + Vector2(randf_range(-6, 6), randf_range(-6, 6))
	pk.z_index = int(global_position.y)
	var sc := get_tree().current_scene
	if sc != null:
		sc.add_child(pk)
