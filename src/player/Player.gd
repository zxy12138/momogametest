@tool
# 弥绘（玩家）：8 向移动 + 鼠标瞄准 + 攻击 + 暴击(经 Weapon) + 梦食 + 终极技能 + 升级成长
# @tool：让 _ready() 在编辑器里也运行，从而把 sprite_frames 构建出来，2D 视图可直接预览角色动画。
# 游戏逻辑（输入/武器/终极）一律用 Engine.is_editor_hint() 挡在编辑器外，避免编辑器里刷怪/发射。
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
	# 相机改由 Game.gd 每帧直接驱动 viewport.canvas_transform（见 _update_camera），
	# 不再依赖 Camera2D.current / make_current()（本 Godot 版本 make_current 不接管视口）。
	# Camera2D 节点已在 .tscn 设为 enabled=false，避免与手动 transform 冲突。
	add_to_group("player")
	_sprite = get_node("Sprite")
	# 合并图 A-001_all.png：1024x1024，8x8 格，每格 128x128，每行 8 帧。
	# 行映射：0=下走 1=右走 2=上走 3=左跑 4=待机 5=死亡 6/7 空。
	var spec := {
		"idle": [SPR+"A-001_all.png", 128, 128, 8, 5, 4],
		"walk_down": [SPR+"A-001_all.png", 128, 128, 8, 6, 0],
		"walk_right": [SPR+"A-001_all.png", 128, 128, 8, 6, 1],
		"walk_up": [SPR+"A-001_all.png", 128, 128, 8, 6, 2],
		"run_left": [SPR+"A-001_all.png", 128, 128, 8, 8, 3],
		"dead": [SPR+"A-001_all.png", 128, 128, 8, 8, 5],
		# 以下动作未纳入合并图，沿用独立文件
		"jump": [SPR+"A-004_miai_jump.png", 130, 250, 3, 12],
		"hurt": [SPR+"A-005_miai_hurt.png", 130, 250, 2, 12],
		"attack": [SPR+"A-007_miai_attack_windup.png", 130, 250, 4, 14],
		"ult": [SPR+"A-008_miai_ultimate_skill.png", 130, 250, 8, 14],
		"true": [SPR+"A-009_miai_true_form_idle.png", 130, 250, 4, 12],
	}
	if GameManager != null and "make_frames" in GameManager:
		_sprite.sprite_frames = GameManager.make_frames(spec)
	_sprite.scale = Vector2(0.28, 0.28)  # 缩小一半以上（0.6→0.28，约 53% 缩减）；仅缩视觉精灵，不影响碰撞
	if _sprite.sprite_frames != null:
		_sprite.play("idle")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _dead:
		z_index = int(global_position.y)
		return
	if _is_gm_locked():
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
	if _dead:
		return
	var next := ""
	var moving := velocity.length() > 12.0
	if _atk_timer > 0:
		next = "attack"
	elif _dash_t > 0:
		next = "run_left"
	elif moving and abs(velocity.x) >= abs(velocity.y):
		next = "walk_right"
		_sprite.flip_h = velocity.x < 0        # 右走行镜像为左向
	elif moving:
		next = "walk_down" if velocity.y > 0 else "walk_up"
		_sprite.flip_h = _aim.x < 0            # 上下行走按瞄准保持左右朝向
	elif GameManager.level >= 26:
		next = "true"
		_sprite.flip_h = _aim.x < 0
	else:
		next = "idle"
		_sprite.flip_h = _aim.x < 0            # 静止时朝向鼠标
	if next != "" and next != _anim:
		_anim = next
		if _sprite.sprite_frames.has_animation(next):
			_sprite.play(next)


func _is_gm_locked() -> bool:
	# 防御：GameManager 运行期若因缓存/加载问题未正常初始化（input_locked 不存在），直接读取会每帧刷屏。
	# 安全返回 false（不锁输入），保证游戏可运行、便于排查。
	if GameManager == null or not ("input_locked" in GameManager):
		return false
	return GameManager.input_locked


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
	GameManager.fx("res://assets/fx/FX-024_level_up_effect.png", global_position, 64, 64, 8, 0.8)
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
