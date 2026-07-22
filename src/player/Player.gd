# 弥绘（玩家）：8 向移动 + 鼠标瞄准 + 攻击 + 暴击(经 Weapon) + 梦食 + 终极技能 + 升级成长
extends CharacterBody2D
class_name Player

const SPR = "res://assets/sprites/player/"

var _anim := "idle"
var _atk_timer := 0.0
var _ult_cd := 0.0
var _invuln := 0.0
var _dash_t := 0.0
var _dash_dir := Vector2.ZERO
var _dead := false
var _aim := Vector2.RIGHT
var _speed_status := 1.0   # 来自减速/冰冻（玩家本身不用，预留）
var _sprite: AnimatedSprite2D


func _ready() -> void:
	add_to_group("player")
	_sprite = get_node("Sprite")
	var spec := {
		"idle":   [SPR+"A-001_idle.png", 32, 32, 4, 12],
		"walk":   [SPR+"A-002_walk.png", 32, 32, 6, 12],
		"run":    [SPR+"A-003_run.png", 32, 32, 6, 16],
		"jump":   [SPR+"A-004_jump.png", 32, 32, 3, 12],
		"hurt":   [SPR+"A-005_hurt.png", 32, 32, 2, 12],
		"attack": [SPR+"A-007_attack.png", 32, 32, 4, 14],
		"dead":   [SPR+"A-006_dead.png", 32, 32, 6, 12],
		"ult":    [SPR+"A-008_ult.png", 32, 32, 8, 14],
		"true":   [SPR+"A-009_true.png", 32, 32, 4, 12],
	}
	_sprite.sprite_frames = GameManager.make_frames(spec)
	_sprite.play("idle")


func _physics_process(delta: float) -> void:
	if _dead:
		z_index = int(global_position.y)
		return
	if GameManager.input_locked:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_anim_update(delta)
	var dir := _input_dir()
	var spd := GameManager.move_speed * _speed_status
	if _dash_t > 0:
		_dash_t -= delta
		velocity = _dash_dir * 620.0
	else:
		velocity = dir * spd
	move_and_slide()

	# 瞄准
	var mp := get_global_mouse_position()
	_aim = (mp - global_position)
	if _aim.length() < 4:
		_aim = Vector2.RIGHT if _sprite.flip_h else Vector2.LEFT
	else:
		_aim = _aim.normalized()
	_sprite.flip_h = _aim.x < 0

	# 攻击
	var firing := Input.is_action_pressed("attack")
	get_node("Weapon").call("process", delta, _aim, firing)

	# 终极技能：噩梦吞噬（每房间一次）
	_ult_cd -= delta
	if Input.is_action_just_pressed("ultimate") and _ult_cd <= 0:
		_cast_ult()

	z_index = int(global_position.y)


func _input_dir() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_action_pressed("move_up"): v.y -= 1
	if Input.is_action_pressed("move_down"): v.y += 1
	if Input.is_action_pressed("move_left"): v.x -= 1
	if Input.is_action_pressed("move_right"): v.x += 1
	return v.normalized()


func _anim_update(delta: float) -> void:
	if _atk_timer > 0:
		_atk_timer -= delta
	var next := "idle"
	if _atk_timer > 0:
		next = "attack"
	elif velocity.length() > 12:
		next = "walk"
	elif GameManager.level >= 26:
		next = "true"
	else:
		next = "idle"
	if next != _anim:
		_anim = next
		if _sprite.sprite_frames.has_animation(next):
			_sprite.play(next)


func play_attack() -> void:
	_atk_timer = 0.30


func dash(dir: Vector2) -> void:
	_dash_dir = dir
	_dash_t = 0.14


func shake(dur: float, mag: float) -> void:
	var cam := get_node("Camera")
	var t := get_tree().create_tween()
	for i in 6:
		t.tween_property(cam, "offset", Vector2(randf_range(-mag, mag), randf_range(-mag, mag)), dur / 6.0)
	t.tween_property(cam, "offset", Vector2.ZERO, dur / 6.0)


func hit_by(dmg: float) -> void:
	if _dead or _invuln > 0:
		return
	GameManager.damage_player(dmg)
	_invuln = 0.6
	_sprite.modulate = Color(1, 0.4, 0.4)
	var t := get_tree().create_tween()
	t.tween_property(_sprite, "modulate", Color(1, 1, 1), 0.3)
	if GameManager.hp <= 0:
		_on_died(true)


func _cast_ult() -> void:
	_ult_cd = 9999.0   # 每房间一次，进房由 Game 重置
	_anim = "ult"
	_sprite.play("ult")
	GameManager.fx("res://assets/fx/fx_levelup.png", global_position, 64, 64, 8, 0.8)
	var dmg: int = int(45 * GameManager.attack_mult)
	for en in get_tree().get_nodes_in_group("enemy"):
		var e := en as Node2D
		if e == null or not e.has_method("take_damage"):
			continue
		e.call("take_damage", dmg, true, "", 0.0)


func reset_ult() -> void:
	_ult_cd = 0.0

# HUD 查询：噩梦吞噬是否就绪（每房间一次，进房由 Game 重置 _ult_cd=0）
func ult_ready() -> bool:
	return _ult_cd <= 0.0


func _on_died(_force := false) -> void:
	if _dead:
		return
	_dead = true
	_anim = "dead"
	_sprite.play("dead")
	velocity = Vector2.ZERO
	# 死亡演出后由 Game 接入死亡流程
	var t := get_tree().create_tween()
	t.tween_callback(func():
		var sc := get_tree().current_scene
		if sc != null and sc.has_method("on_player_died"):
			sc.call("on_player_died")
	).set_delay(1.0)
