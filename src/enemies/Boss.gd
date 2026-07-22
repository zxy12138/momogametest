# Boss（继承 Enemy）：多阶段 + 弱点窗口（最终 Boss）+ 击败触发房间净化
# 用脚本路径继承而非 class_name，避免无头模式下全局 class 注册表未登记 "Enemy" 导致解析失败。
extends "res://src/enemies/Enemy.gd"
class_name Boss

var _phases := []
var _patterns := []
var _phase_idx := 0
var _final := false
var _layer := 1
var _pattern_cd := 1.5
var _spin_a := 0.0


func setup(bid: String) -> void:
	_eid = bid
	var b: Dictionary = Enemies.get_boss(bid)
	if b == null:
		queue_free()
		return
	_data = b
	hp = float(b["hp"]); max_hp = hp
	xp = 200
	behavior = "chase"
	speed = 55.0
	contact_dmg = 16.0
	_phases = b["phases"]
	_patterns = b["phase_patterns"]
	_final = b.get("final", false)
	_layer = int(b["layer"])
	add_to_group("enemy")
	_sprite = get_node("Sprite")
	var fw: int = b["fw"]; var fh: int = b["fh"]
	var spec := {
		"idle":   [b["sprite_idle"], fw, fh, b["fi"], 8],
		"attack": [b["sprite_attack"], fw, fh, b["fa"], 10],
	}
	_sprite.sprite_frames = GameManager.make_frames(spec)
	_sprite.play("idle")
	var r := mini(fw, fh) * 0.35
	get_node("CollisionShape2D").shape.radius = r
	get_node("Hitbox/CollisionShape2D").shape.radius = r
	get_node("Hitbox").connect("body_entered", _on_hit_player)
	_pattern_cd = 1.5


func is_boss() -> bool:
	return true


func _physics_process(delta: float) -> void:
	z_index = int(global_position.y)
	if _dead:
		return
	_tick_status(delta)
	_check_phase()

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_p := player.global_position - global_position
	var dist := to_p.length()
	var dir := to_p.normalized() if dist > 0.1 else Vector2.ZERO
	var spd := speed
	if behavior == "charge":
		spd = speed * 3.0
	velocity = dir * spd
	move_and_slide()

	_pattern_cd -= delta
	if _pattern_cd <= 0 and player != null:
		_do_pattern(_patterns[_phase_idx], player.global_position, dir)
	_pattern_cd = _next_cd()


func _check_phase() -> void:
	if _phase_idx >= _phases.size():
		return
	if hp <= max_hp * _phases[_phase_idx]:
		_phase_idx += 1
		_anim = "attack"
		_sprite.play("attack")
		GameManager.fx("res://assets/fx/fx_levelup.png", global_position, 64, 64, 8, 0.8)
		if _final:
			GameManager.set_weak(true)
			# create_timer 返回的是 SceneTreeTimer（RefCounted，非 Node），不可 add_child
			get_tree().create_timer(2.5).timeout.connect(func(): GameManager.set_weak(false))


func _next_cd() -> float:
	var base := 2.2 - _phase_idx * 0.45
	if behavior == "frenzy" or behavior == "spin":
		base *= 0.5
	return maxf(base, 0.5)


func _do_pattern(p: String, target: Vector2, dir: Vector2) -> void:
	_anim = "attack"
	_sprite.play("attack")
	match p:
		"summon":
			behavior = "chase"
			for i in 2:
				_spawn_minion(target + Vector2(randf_range(-60, 60), randf_range(-40, 40)))
		"cards", "radial":
			_radial(12, 220)
		"spin":
			behavior = "spin"
			_spin_a += 0.4
			for i in 4:
				var a := _spin_a + i * TAU / 4.0
				_spawn_proj(global_position, Vector2(cos(a), sin(a)), 10, 240, "res://assets/weapons/projectiles/p_staff.png", false)
		"charge":
			behavior = "charge"
		"slam":
			behavior = "chase"
			GameManager.fx("res://assets/fx/fx_shockwave.png", target, 64, 16, 5, 0.5)
			if target.distance_to(global_position) < 120:
				GameManager.damage_player(18)
		"ddl":
			behavior = "aoe"
			GameManager.fx("res://assets/fx/fx_shockwave.png", target, 64, 16, 5, 0.5)
			if target.distance_to(global_position) < 110:
				GameManager.damage_player(20)
		"crash", "frenzy":
			behavior = "frenzy"
			_radial(16, 260)


func _radial(n: int, spd: float) -> void:
	for i in n:
		var a := TAU * float(i) / float(n) + randf_range(-0.1, 0.1)
		_spawn_proj(global_position, Vector2(cos(a), sin(a)), 10, spd, "res://assets/weapons/projectiles/p_staff.png", false)


func _spawn_minion(pos: Vector2) -> void:
	var pool: Array = Enemies.enemies_of_layer(_layer)
	if pool.is_empty():
		return
	var eid: String = pool[randi_range(0, pool.size() - 1)]
	var sc := get_tree().current_scene
	if sc != null and sc.has_method("spawn_enemy"):
		sc.spawn_enemy(eid, pos)


func _die(_is_crit: bool) -> void:
	_dead = true
	GameManager.set_weak(false)
	GameManager.fx("res://assets/fx/fx_levelup.png", global_position, 64, 64, 8, 1.0)
	# 掉落梦晶
	var sc := get_tree().current_scene
	if sc != null:
		for i in 5:
			var pk := load("res://src/fx/Pickup.tscn").instantiate() as Area2D
			pk.set("kind", "crystal")
			pk.set("value", 20)
			pk.global_position = global_position + Vector2(randf_range(-40, 40), randf_range(-30, 30))
			sc.add_child(pk)
		if sc.has_method("on_boss_defeated"):
			sc.call("on_boss_defeated", _layer, self)
	velocity = Vector2.ZERO
	var t := get_tree().create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.6)
	t.tween_callback(queue_free).set_delay(0.6)
