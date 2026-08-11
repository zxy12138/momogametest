@tool
# 弥绘（玩家）：8 向移动 + 鼠标瞄准 + 攻击 + 暴击(经 Weapon) + 梦食 + 终极技能 + 升级成长
# @tool：让 _ready() 在编辑器里也运行，从而把 sprite_frames 构建出来，2D 视图可直接预览角色动画。
# 游戏逻辑（输入/武器/终极）一律用 Engine.is_editor_hint() 挡在编辑器外，避免编辑器里刷怪/发射。
extends CharacterBody2D
class_name Player

const SPR = "res://assets/sprites/player/"
const SPR_MOMO = SPR + "momo_packed/"   # 8 向 momo 立绘紧凑打包目录（tools/pack_momo.py 生成）

@export var sprite_height_px: float = 42.0:
	# @tool 可视化调整：编辑器改这个数，setter 立刻把 Sprite scale 应用上，
	# 2D 视口能实时看到角色大小变化（无需重新打开场景）。
	# 40~60 适合"主角立绘"占比，增大=更有存在感，减小=更远景。
	set(v):
		sprite_height_px = max(8.0, v)
		_apply_sprite_scale()

var _anim := "idle"
var _atk_timer := 0.0
var _invuln := 0.0
var _dash_t := 0.0
var _dash_dir := Vector2.ZERO
var _dead := false
var _aim := Vector2.RIGHT
var _speed_status := 1.0   # 来自减速/冰冻（玩家本身不用，预留）
var _sprite: AnimatedSprite2D
var _outline: AnimatedSprite2D  # 描边子节点：用 _edge 兄弟图 sprite_frames 同步动画
# 描边控制：平时柔和（modulate.a 较低），攻击/终极/受伤时提亮，强化打击感
@export var outline_color: Color = Color(0.4, 0.7, 1.0)  # 蓝白描边（可在 Inspector 调）
@export var outline_alpha_idle: float = 0.5               # 平时柔和描边
@export var outline_alpha_focus: float = 1.0              # 攻击/终极/受伤时提亮
# 参考帧高：用于把"目标视觉高"换算成 sprite scale（各动作 fh 接近 114~117，取 116）
const FRAME_REF_H: float = 116.0


func _ready() -> void:
	# 相机改由 Game.gd 每帧直接驱动 viewport.canvas_transform（见 _update_camera），
	# 不再依赖 Camera2D.current / make_current()（本 Godot 版本 make_current 不接管视口）。
	# Camera2D 节点已在 .tscn 设为 enabled=false，避免与手动 transform 冲突。
	add_to_group("player")
	_sprite = get_node("Sprite")
	# 玩家 momo 新立绘：8 向走路 + 待机 (idea) + 死亡 + 攻击，每张 4x3 网格 10 帧紧凑打包（momo_packed/）。
	# 8 向走路动画命名：walk_up/walk_down/walk_left/walk_right/walk_leftup/walk_rightup/walk_leftdown/walk_rightdown
	#   walk_up    = 向上（背对镜头）   walk_down   = 向下（面对镜头）
	#   walk_left  = 向左（镜像自 right） walk_right = 向右
	#   walk_leftup = 左上（源直出）     walk_rightup = 右上（镜像）
	#   walk_leftdown = 左下（镜像）     walk_rightdown = 右下（源直出）
	# 战斗动作（jump/hurt/ult/true）暂用旧 miai 素材占位，等 momo 战斗动作到位再换。
	var spec := {
		# 8 向走路（momo 新立绘，10 帧）
		"walk_up":        [SPR_MOMO+"walk_up.png",        62, 116, 10, 12],
		"walk_down":      [SPR_MOMO+"walk_down.png",      62, 117, 10, 12],
		"walk_left":      [SPR_MOMO+"walk_left.png",      57, 115, 10, 12],
		"walk_right":     [SPR_MOMO+"walk_right.png",     57, 115, 10, 12],
		"walk_leftup":    [SPR_MOMO+"walk_leftup.png",    60, 114, 10, 12],
		"walk_rightup":   [SPR_MOMO+"walk_rightup.png",   60, 114, 10, 12],
		"walk_leftdown":  [SPR_MOMO+"walk_leftdown.png",  67, 116, 10, 12],
		"walk_rightdown": [SPR_MOMO+"walk_rightdown.png", 67, 116, 10, 12],
		# 待机（idea = 发呆呼吸，10 帧慢速）
		"idle":           [SPR_MOMO+"idea.png",           63, 116, 10, 8],
		# 死亡（10 帧，不循环）
		"dead":           [SPR_MOMO+"dead.png",           95, 114, 10, 12],
		# 攻击（10 帧；武器方向由 WeaponSystem 按鼠标方向叠加）
		"attack":         [SPR_MOMO+"attack.png",         100, 115, 10, 14],
		# 战斗动作（miai 旧素材占位）
		"jump":   [SPR+"A-004_miai_jump.png",             130, 250, 3, 12],
		"hurt":   [SPR+"A-005_miai_hurt.png",             130, 250, 2, 12],
		"ult":    [SPR+"A-008_miai_ultimate_skill.png",   130, 250, 8, 14],
		"true":   [SPR+"A-009_miai_true_form_idle.png",   130, 250, 4, 12],
	}
	if GameManager != null and "make_frames" in GameManager:
		_sprite.sprite_frames = GameManager.make_frames(spec)
		# 描边 sprite frames：用 _outline 兄弟图（由 alpha 扩张生成的无网格线描边环，与 main 同尺寸）
		_outline = get_node_or_null("Outline")
		if _outline != null:
			var spec_edge := {}
			for k in spec:
				var e: Array = spec[k]
				var p: String = e[0]
				var ext := p.get_extension()
				var base := p.get_basename()
				spec_edge[k] = [base + "_outline." + ext, e[1], e[2], e[3], e[4]]
			_outline.sprite_frames = GameManager.make_frames(spec_edge)
			_outline.modulate = Color(outline_color.r, outline_color.g, outline_color.b, outline_alpha_idle)
	_apply_sprite_scale()  # @export sprite_height_px 通过 setter 已触发一次，此处兜底（编辑器实例化时 setter 早于 _ready 跑且 _sprite 尚未 get_node）
	if _sprite.sprite_frames != null:
		_sprite.play("idle")
	if _outline != null and _outline.sprite_frames != null:
		_outline.play("idle")


## 把 sprite_height_px 应用到 _sprite 和 _outline 的 scale 与 position（脚底对齐碰撞中心）。
## 抽取为函数供 setter 与 _ready 复用，未初始化时静默返回。
func _apply_sprite_scale() -> void:
	if _sprite == null:
		return
	var s: float = sprite_height_px / FRAME_REF_H
	_sprite.scale = Vector2(s, s)
	_sprite.position = Vector2(0, -sprite_height_px * 0.5 + 2.0)
	if _outline != null:
		_outline.scale = Vector2(s, s)
		_outline.position = _sprite.position


## 同步播放某个动画：主 Sprite + 描边 Outline 都切到同一动画帧。
func _play_anim(name: String) -> void:
	if _sprite != null and _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(name):
		_sprite.play(name)
	if _outline != null and _outline.sprite_frames != null and _outline.sprite_frames.has_animation(name):
		_outline.play(name)


## 设置描边可见性（0=隐藏，1=最亮）。攻击/终极/受伤时调 focus，平时调 idle。
func _set_outline_alpha(a: float) -> void:
	if _outline != null:
		_outline.modulate = Color(outline_color.r, outline_color.g, outline_color.b, a)


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

	# 武器技能：E 键释放（蓝条就绪才可，GameManager.spend_mana 消耗全蓝）
	if Input.is_action_just_pressed("ultimate") and GameManager.skill_ready():
		_cast_skill()

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
		next = "walk_left"  # dash 暂复用左行（_dash_dir 由 dash() 决定）
	elif moving:
		# 8 向 atan2 按输入方向选动画（每个扇区显式写上下界，避免"小于阈值"链在负角度错配）：
		# 屏幕坐标系 y 向下：right=0° / down=+90° / left=±180° / up=-90°
		var deg := rad_to_deg(atan2(velocity.y, velocity.x))
		if deg >= -22.5 and deg < 22.5:          next = "walk_right"
		elif deg >= 22.5 and deg < 67.5:         next = "walk_rightdown"
		elif deg >= 67.5 and deg < 112.5:        next = "walk_down"
		elif deg >= 112.5 and deg < 157.5:       next = "walk_leftdown"
		elif deg >= 157.5 or deg < -157.5:       next = "walk_left"
		elif deg >= -157.5 and deg < -112.5:     next = "walk_leftup"
		elif deg >= -112.5 and deg < -67.5:      next = "walk_up"
		else:                                    next = "walk_rightup"  # [-67.5, -22.5)
		# 8 向独立图，不需要 flip_h
	elif GameManager.level >= 26:
		next = "true"
	else:
		next = "idle"
	if next != "" and next != _anim:
		_anim = next
		_play_anim(next)
		# 攻击/终极时描边提亮强化打击感，平时柔和
		var focus := (next == "attack" or next == "ult")
		_set_outline_alpha(outline_alpha_focus if focus else outline_alpha_idle)


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
	_set_outline_alpha(outline_alpha_focus)  # 受伤时描边亮一下
	var t := get_tree().create_tween()
	t.tween_property(_sprite, "modulate", Color(1, 1, 1), 0.3)
	# 描边 0.3s 后回到柔和
	t.parallel().tween_property(_outline, "modulate",
		Color(outline_color.r, outline_color.g, outline_color.b, outline_alpha_idle), 0.3)
	if GameManager.hp <= 0:
		_on_died(true)


func _cast_skill() -> void:
	# E 键武器技能：蓝条已由 GameManager.spend_mana 消耗（skill_ready 已在入口判断）
	if not GameManager.spend_mana():
		return
	_anim = "attack"
	_play_anim("attack")
	_set_outline_alpha(outline_alpha_focus)
	GameManager.fx("res://assets/fx/FX-024_level_up_effect.png", global_position, 64, 64, 8, 0.6)
	# 由武器系统执行当前武器的专属技能
	var wpn := get_node_or_null("Weapon")
	if wpn != null and wpn.has_method("cast_skill"):
		wpn.call("cast_skill", _aim)


# HUD 查询：武器技能是否就绪（蓝条 ≥99%）
func skill_ready() -> bool:
	return GameManager.skill_ready()


func _on_died(_force := false) -> void:
	if _dead:
		return
	_dead = true
	_anim = "dead"
	_play_anim("dead")
	_set_outline_alpha(outline_alpha_focus)  # 死亡时描边强烈
	velocity = Vector2.ZERO
	# 死亡演出后由 Game 接入死亡流程
	var t := get_tree().create_tween()
	t.tween_callback(func():
		var sc := get_tree().current_scene
		if sc != null and sc.has_method("on_player_died"):
			sc.call("on_player_died")
	).set_delay(1.0)
