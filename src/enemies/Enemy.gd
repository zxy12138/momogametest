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
var _outline: AnimatedSprite2D = null   # 黑色描边节点（_outline 兄弟图，跟随 sprite 动画）
# 状态
var _slow_t := 0.0
var _freeze_t := 0.0
var _para_t := 0.0
var _burn_t := 0.0
var _burn_acc := 0.0
var _kb_t := 0.0
var _kb_dir := Vector2.ZERO
var _spawn_t := 0.0
# 攻击朝向（用于攻击/死亡动画选 left/right 镜像版）
var _facing_left := false
# 当前攻击动画基名："attack"（普通/远程）或 "melee"（混合怪近战）
var _atk_anim := "attack"

# 碰撞框配置：每怪的方形判定框（贴合身体 bbox，替换原 CircleShape2D 半径 41）。
# 值 = Vector4(宽, 高, 偏移x, 偏移y)，世界单位（已含 sprite scale 0.45），偏移=身体 bbox 中心相对帧中心。
# 由 tools/analyze_enemy_collision.py 扫描 walk_down/idle 第一帧 bbox 生成。
const CB := {
	"alarm_clock": Vector4(50, 50, 0, 4),
	"lamp": Vector4(29, 53, 2, 2),
	"dog": Vector4(32, 42, 0, 8),
	"mower": Vector4(54, 51, 0, 3),
	"road_daredevil": Vector4(47, 51, -3, 3),
	"office_ghost": Vector4(30, 52, 0, 2),
	"spider": Vector4(54, 47, 0, 5),
	"hypno_tv": Vector4(49, 54, 1, 2),
	"centipede": Vector4(53, 54, 0, 2),
	"zombie": Vector4(28, 54, 0, 2),
	"overtime1": Vector4(30, 50, 0, 4),
	"kpi_group": Vector4(38, 49, 0, 4),
	"hardware_core": Vector4(40, 52, 0, 1),
	"printer2": Vector4(39, 51, 0, 3),
	"overtime2": Vector4(32, 54, 0, 2),
	"overtime3": Vector4(47, 54, 0, 2),
}


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
	# 动画键 → 帧数字段映射（每方向独立帧数：fwd/fwr/fwu/fwl/fi/fa/fd，缺省 8）
	# *_left 镜像版帧数与主键一致（attack_left 用 fa、dead_left 用 fd、melee_left 用 fa）
	var anim_frame_key := {
		"idle": "fi", "walk": "fwk", "walk_down": "fwd", "walk_right": "fwr",
		"walk_up": "fwu", "walk_left": "fwl",
		"attack": "fa", "attack_left": "fa", "dead": "fd", "dead_left": "fd",
		"melee": "fme", "melee_left": "fme",
	}
	# 动画速度（2026-08-16 调优：原 idle 8/walk 12/attack 14 偏快显鬼畜，整体降 ~30% 更沉稳）
	var anim_fps := {"idle": 6.0, "walk": 8.0, "walk_down": 8.0, "walk_right": 8.0,
		"walk_up": 8.0, "walk_left": 8.0, "attack": 10.0, "attack_left": 10.0,
		"dead": 8.0, "dead_left": 8.0, "melee": 10.0, "melee_left": 10.0}
	var spec := {}
	for anim: String in anim_frame_key.keys():
		if _data.has(anim):
			spec[anim] = [_data[anim], fw, fh, _data.get(anim_frame_key[anim], 8), anim_fps[anim]]
	_sprite.sprite_frames = GameManager.make_frames(spec)
	if _sprite.sprite_frames.has_animation("idle"):
		_sprite.play("idle")
	else:
		# 无 idle（如巡逻怪）：播第一个可用动画兜底
		var names := _sprite.sprite_frames.get_animation_names()
		if names.size() > 0:
			_sprite.play(names[0])
	_sprite.scale = Vector2(0.45, 0.45)  # 与玩家同比例缩小；仅视觉，碰撞由 _apply_collision_box 设置
	_apply_scale_mult()  # 场景/刷怪层设置的大小倍率（默认 1.0）
	_apply_collision_box()  # 方形判定框贴合身体（替换原圆形半径 41）
	_add_shadow()  # 脚下椭圆阴影
	_add_outline(spec)  # 黑色描边
	# 初始攻击冷却（2026-08-16 调优：原 0.3~1.5s 一见面就疯狂攻击 → 1.0~2.5s 进场先观察）
	_atk_cd = randf_range(1.0, 2.5)
	_spawn_t = 0.2
	var hb := get_node("Hitbox")
	hb.connect("body_entered", _on_hit_player)


## 脚下半透明椭圆阴影：让怪物视觉上"落地"，不漂浮。
func _add_shadow() -> void:
	if get_node_or_null("Shadow") != null:
		return
	var cb: Vector4 = CB.get(_eid, Vector4(32, 32, 0, 0))
	var w: float = cb.x * _scale_mult
	var h: float = cb.y * _scale_mult
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	var pts := PackedVector2Array()
	var n := 16
	for i in n:
		var ang := TAU * i / float(n)
		pts.append(Vector2(cos(ang) * w * 0.5, sin(ang) * w * 0.22))
	shadow.polygon = pts
	shadow.color = Color(0, 0, 0, 0.25)
	shadow.position = Vector2(0, h * 0.5 - 2.0)   # 脚底位置
	shadow.z_index = -10   # 在角色 sprite 后面
	add_child(shadow)


## 黑色描边：用 _outline 兄弟图构建 Outline 节点，跟随 sprite 动画（复用 Player 的描边机制）。
func _add_outline(spec: Dictionary) -> void:
	var spec_edge := {}
	for k in spec:
		var e: Array = spec[k]
		var p: String = e[0]
		var ep: String = p.get_basename() + "_outline." + p.get_extension()
		if ResourceLoader.exists(ep):
			spec_edge[k] = [ep, e[1], e[2], e[3], e[4]]
	if spec_edge.is_empty():
		return
	_outline = AnimatedSprite2D.new()
	_outline.name = "Outline"
	_outline.sprite_frames = GameManager.make_frames(spec_edge)
	_outline.modulate = Color(0, 0, 0, 0.6)   # 黑色描边
	_outline.scale = _sprite.scale
	_outline.position = _sprite.position
	_outline.z_index = -1   # 在角色 sprite 后面
	add_child(_outline)


## 每帧同步描边节点到 sprite 的动画/帧/翻转（Outline 不自动播放，作为 sprite 的"影子"）。
func _sync_outline() -> void:
	if _outline == null:
		return
	_outline.stop()
	_outline.animation = _sprite.animation
	_outline.frame = _sprite.frame
	_outline.flip_h = _sprite.flip_h
	_outline.scale = _sprite.scale
	_outline.position = _sprite.position


## 房间编辑器调整怪物大小：scale_mult 倍率（视觉 sprite 缩放 + 碰撞/受击半径同步缩放）。
## 由 RoomManager 在刷怪时调用（handle 上配置的 scale_mult）；默认 1.0 不变。
var _scale_mult := 1.0
var _collision_mult := 1.0
func set_scale_mult(sm: float) -> void:
	_scale_mult = maxf(0.1, sm)
	_apply_scale_mult()

## 独立碰撞范围倍率（仅放大碰撞框，不动 sprite 视觉大小）。
func set_collision_mult(cm: float) -> void:
	_collision_mult = maxf(0.1, cm)
	_apply_collision_box()


func _apply_scale_mult() -> void:
	if _sprite == null:
		return
	_sprite.scale = Vector2(0.45, 0.45) * _scale_mult
	_apply_collision_box()


## 把形状参数（shape/w/h/ox/oy/poly）按 CB 基础值补全后，应用到身体碰撞框 + 受击框。
## 形状：0 矩形(RectangleShape2D) / 1 三角形(CollisionPolygon2D) / 2 圆(CircleShape2D) / 3 多边形(CollisionPolygon2D)。
## 三角/多边形走 CollisionPolygon2D；矩形/圆走 CollisionShape2D。两套节点并存，按形状启用其一、禁用另一。
## 尺寸/中心点的最终值 = ScaleConfig 基础值 × (scale_mult × collision_mult)，与编辑器预览完全一致。
func _apply_collision_box() -> void:
	var cb: Vector4 = CB.get(_eid, Vector4(32, 32, 0, 0))
	var sc := _scale_mult * _collision_mult
	var shape := int(ScaleConfig.get_enemy_shape(_eid, ScaleConfig.SHAPE_RECT))
	var w := float(ScaleConfig.get_enemy_w(_eid, cb.x))
	var h := float(ScaleConfig.get_enemy_h(_eid, cb.y))
	var ox := float(ScaleConfig.get_enemy_ox(_eid, cb.z))
	var oy := float(ScaleConfig.get_enemy_oy(_eid, cb.w))
	var poly := ScaleConfig.get_enemy_poly(_eid)
	_apply_shape_to_colliders(shape, w, h, ox, oy, poly, sc)


## 返回形状对应的「局部多边形顶点」（中心在原点，已乘缩放 sc）。
## 矩形/圆统一用矩形近似（圆在运行期改用 CircleShape2D，这里仅为兜底/预览）；三角与多边形返回真实顶点。
static func _shape_points(shape: int, w: float, h: float, poly: PackedVector2Array, sc: float) -> PackedVector2Array:
	if shape == ScaleConfig.SHAPE_TRI:
		var hw := w * 0.5 * sc
		var hh := h * 0.5 * sc
		return PackedVector2Array([Vector2(-hw, hh), Vector2(hw, hh), Vector2(0.0, -hh)])
	if shape == ScaleConfig.SHAPE_CIRCLE:
		var r := 0.5 * w * sc
		var pp := PackedVector2Array()
		var n := 24
		for i in n:
			var a := TAU * float(i) / float(n)
			pp.append(Vector2(cos(a) * r, sin(a) * r))
		return pp
	if shape == ScaleConfig.SHAPE_POLY and poly.size() >= 3:
		var pp := PackedVector2Array()
		for v in poly:
			pp.append(v * sc)
		return pp
	# 矩形 / 退化兜底
	var hw := w * 0.5 * sc
	var hh := h * 0.5 * sc
	return PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])


## 把解析后的形状参数应用到身体碰撞框 + 受击框（两者同形同尺寸同偏移）。
func _apply_shape_to_colliders(shape: int, w: float, h: float, ox: float, oy: float, poly: PackedVector2Array, sc: float) -> void:
	var off := Vector2(ox * sc, oy * sc - 4.0)   # -4 对齐 sprite.position.y = -4 的视觉身体中心
	var pts := _shape_points(shape, w, h, poly, sc)
	_set_collider(get_node_or_null("CollisionShape2D"), get_node_or_null("CollisionPolygon2D"), shape, w, h, sc, off, pts)
	_set_collider(get_node_or_null("Hitbox/CollisionShape2D"), get_node_or_null("Hitbox/CollisionPolygon2D"), shape, w, h, sc, off, pts)


## 对单个碰撞器（身体或受击）按形状设置：三角/多边形→CollisionPolygon2D，矩形/圆→CollisionShape2D。
func _set_collider(cs: CollisionShape2D, cp: CollisionPolygon2D, shape: int, w: float, h: float, sc: float, off: Vector2, pts: PackedVector2Array) -> void:
	if shape == ScaleConfig.SHAPE_TRI or shape == ScaleConfig.SHAPE_POLY:
		if cs != null:
			cs.disabled = true
		if cp != null:
			cp.disabled = false
			cp.position = off
			cp.polygon = pts
	else:
		if cp != null:
			cp.disabled = true
		if cs != null:
			cs.disabled = false
			cs.position = off
			if shape == ScaleConfig.SHAPE_CIRCLE:
				var sh := CircleShape2D.new()
				sh.radius = 0.5 * w * sc
				cs.shape = sh
			else:
				var sh := RectangleShape2D.new()
				sh.size = Vector2(w, h) * sc
				cs.shape = sh


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
	_sync_outline()   # 描边节点跟随 sprite 动画/帧/翻转
	if _dead:
		return
	if GameManager.cutscene_frozen:
		# 演出期间（f1_r3/r4 进入关卡演出）：敌人暂停，静止展示不行动
		velocity = Vector2.ZERO
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
	var hr: float = float(_data.get("hybrid_range", 220))
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
				_atk_cd = _data.get("atk_cd", 2.6)
				_shoot(player.global_position)
		"aoe":
			velocity = (dir * speed) if dist > _data.get("aoe_radius", 60) else Vector2.ZERO
			_atk_cd -= delta
			if _atk_cd <= 0:
				_atk_cd = _data.get("atk_cd", 3.2)
				_pulse(player.global_position)
		"patrol":
			# 巡逻怪（如闹钟怪）：始终锁定玩家直线追击（不巡逻不脱离），
			# 移动动画按追击方向切换；近身（atk_range 内）按 atk_cd 周期近战攻击。
			velocity = dir * speed
			_atk_cd -= delta
			if _atk_cd <= 0 and dist < float(_data.get("atk_range", 90)):
				_atk_cd = float(_data.get("atk_cd", 2.2))
				_melee_attack("attack")
		"hybrid":
			# 混合怪（蜘蛛/蜈蚣）：远距远程弹幕、近身近战攻击
			if dist > hr:
				# 远程：保持距离 + 弹幕
				if dist > hr * 1.2:
					velocity = dir * speed
				elif dist < hr * 0.6:
					velocity = -dir * speed * 0.8
				else:
					velocity = Vector2.ZERO
				_atk_cd -= delta
				if _atk_cd <= 0:
					_atk_cd = float(_data.get("atk_cd", 2.8))
					_shoot(player.global_position)
			else:
				# 近战：追击 + 近战攻击（melee 动画）
				velocity = dir * speed
				_atk_cd -= delta
				if _atk_cd <= 0 and dist < float(_data.get("melee_range", 80)):
					_atk_cd = float(_data.get("melee_cd", 2.2))
					_melee_attack("melee")
	move_and_slide()

	# 更新朝向（攻击/死亡动画选 attack_left/dead_left 镜像版的依据）
	if absf(dir.x) > 0.1:
		_facing_left = dir.x < 0

	# 攻击动画（按朝向选 attack/melee 或 *_left 镜像版）
	if _atk_timer > 0:
		_atk_timer -= delta
		var anim_name := _atk_anim
		if _facing_left and _sprite.sprite_frames.has_animation(_atk_anim + "_left"):
			anim_name = _atk_anim + "_left"
		if _anim != anim_name:
			_anim = anim_name
			_sprite.play(anim_name)
	elif velocity.length() > 5.0 and _data.has("walk_down"):
		# 多方向怪：按移动方向选动画（下/右/上/左）
		_play_dir_anim(velocity)
	elif velocity.length() > 5.0 and _data.has("walk"):
		# 单面 walk 怪：移动播 walk + 翻转
		if _anim != "walk":
			_anim = "walk"
			_sprite.play("walk")
		_sprite.flip_h = velocity.x < 0
	elif _anim != "idle" and _sprite.sprite_frames.has_animation("idle"):
		_anim = "idle"
		_sprite.play("idle")
		_sprite.flip_h = velocity.x < 0


func _shoot(target_pos: Vector2) -> void:
	_atk_anim = "attack"   # 远程攻击动画
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


# 近战攻击：播攻击动画（anim_base="attack" 普通近战 / "melee" 混合怪近战），
# 并**主动对范围内玩家造成接触伤害**（不再只靠 Hitbox body_entered 触发，
# 否则玩家站在近战攻击距离但碰撞圈未贴脸时无伤害）。
func _melee_attack(anim_base: String = "attack") -> void:
	_atk_anim = anim_base
	_atk_timer = 0.5
	var reach: float = float(_data.get("melee_range", _data.get("atk_range", 80)))
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and global_position.distance_to(p.global_position) <= reach:
		GameManager.damage_player(contact_dmg)


# 多方向怪按移动方向选动画：主方向 x → walk_right/walk_left；主方向 y → walk_down/walk_up。
# 同时更新 _facing_left（供攻击/死亡动画选镜像版）。
func _play_dir_anim(v: Vector2) -> void:
	var anim_name := "walk_right"
	_sprite.flip_h = false
	if absf(v.x) > absf(v.y):
		if v.x < 0 and _sprite.sprite_frames.has_animation("walk_left"):
			anim_name = "walk_left"   # 专属向左动画（素材反向制作）
			_facing_left = true
		else:
			_sprite.flip_h = v.x < 0  # 无 walk_left：flip_h 镜像 right
			_facing_left = v.x < 0
			anim_name = "walk_right"
	else:
		anim_name = "walk_down" if v.y > 0 else "walk_up"
	if _anim != anim_name:
		_anim = anim_name
		_sprite.play(anim_name)


func _spawn_proj(pos: Vector2, dir: Vector2, dmg: int, spd: float, tex: String, homing: bool) -> void:
	var p := PROJ.instantiate() as Area2D
	p.global_position = pos
	p.set("direction", dir)
	p.set("speed", spd)
	p.set("damage", dmg)
	p.set("from_player", false)
	p.set("homing", homing)
	p.set("texture_path", tex)
	p.set("proj_frames", int(_data.get("proj_frames", 1)))
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


## 调试用（F11 秒杀）：无视一切状态直接击杀（供测试地图秒清怪）。
func kill_now() -> void:
	if _dead:
		return
	hp = 0
	_die(false)


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
		# 有逐帧死亡动画：按朝向选 dead/dead_left，播放后 queue_free
		var dname := "dead"
		if _facing_left and _sprite.sprite_frames.has_animation("dead_left"):
			dname = "dead_left"
		_sprite.play(dname)
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
		# _die 可能由弹道命中（body_entered 物理回调）触发，此时 add_child 新 Area2D 会
		# 报 "flushing queries"；延迟到物理 flush 结束后再挂载。
		sc.call_deferred("add_child", pk)
