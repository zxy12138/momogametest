# Boss（继承 Enemy）：双形态 —— 形态1 血量打空 → 播变身动画（无敌）→ 形态2 满血 → 打死通关。
# 用脚本路径继承而非 class_name，避免无头模式下全局 class 注册表未登记 "Enemy" 导致解析失败。
@tool
extends "res://src/enemies/Enemy.gd"
class_name Boss

# 当前形态：1=form1（无死亡，打空变身） 2=form2（有死亡，打死通关）
var _form := 1
var _form_data := {}          # 当前形态数据（form1/form2 之一）
var _frames_form1: SpriteFrames = null
var _frames_form2: SpriteFrames = null
var _frames_transform: SpriteFrames = null
var _transforming := false    # 变身动画播放中（无敌）
var _transform_t := 0.0
var _layer := 1
var _charge_cd := 0.0         # 公交冲撞冷却
var _summon_cd := 0.0         # 昆虫召唤冷却（form2 完全昆虫/电脑机可召唤）
var _spin_a := 0.0


func setup(bid: String) -> void:
	_eid = bid
	var b: Dictionary = Enemies.get_boss(bid)
	if b == null:
		queue_free()
		return
	_data = b
	_layer = int(b["layer"])
	add_to_group("enemy")
	_sprite = get_node("Sprite")
	# 预构建两套形态动画 + 变身动画
	_frames_form1 = _build_frames(b["form1"])
	_frames_form2 = _build_frames(b["form2"])
	_frames_transform = _build_transform_frames(b)
	# 开始形态1
	_enter_form(1, true)
	# 碰撞/受击信号
	get_node("Hitbox").connect("body_entered", _on_hit_player)


## 构建某形态的 SpriteFrames（复用 Enemy 的动画键体系）。
func _build_frames(fd: Dictionary) -> SpriteFrames:
	var fw: int = fd["fw"]; var fh: int = fd["fh"]
	var anim_frame_key := {
		"idle": "fi", "walk_down": "fwd", "walk_right": "fwr", "walk_up": "fwu", "walk_left": "fwl",
		"attack": "fa", "attack_left": "fa", "dead": "fd", "dead_left": "fd",
		"melee": "fme", "melee_left": "fme", "charge": "fch",
	}
	var anim_fps := {"idle": 8.0, "walk_down": 10.0, "walk_right": 10.0, "walk_up": 10.0, "walk_left": 10.0,
		"attack": 14.0, "attack_left": 14.0, "dead": 12.0, "dead_left": 12.0,
		"melee": 14.0, "melee_left": 14.0, "charge": 14.0}
	var spec := {}
	for anim: String in anim_frame_key.keys():
		if fd.has(anim):
			spec[anim] = [fd[anim], fw, fh, fd.get(anim_frame_key[anim], 8), anim_fps[anim]]
	return GameManager.make_frames(spec)


## 构建变身动画 SpriteFrames（Boss 本体身上播放，缩放到当前 boss 尺寸）。
func _build_transform_frames(b: Dictionary) -> SpriteFrames:
	var path: String = b.get("transform", "")
	var frames: int = int(b.get("transform_frames", 120))
	var fps: float = float(b.get("transform_fps", 30))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var spec := {"transform": [path, 192, 192, frames, fps]}
	return GameManager.make_frames(spec)


## 进入某形态：切换数据 + 动画 + 血量 + 碰撞。
func _enter_form(form: int, is_start: bool) -> void:
	_form = form
	var b: Dictionary = _data
	_form_data = b["form1"] if form == 1 else b["form2"]
	if form == 1:
		max_hp = float(b["hp1"])
		_sprite.sprite_frames = _frames_form1
	else:
		max_hp = float(b["hp2"])
		_sprite.sprite_frames = _frames_form2
	hp = max_hp
	speed = float(_form_data.get("speed", b.get("speed", 55)))
	behavior = str(_form_data.get("behavior", "chase"))
	contact_dmg = float(b.get("contact_dmg", 18))
	# 尺寸：sprite scale（素材切 192 帧格；base 1.0 = 视觉帧格约 192px，形态 scale 微调体型）
	var sc: float = float(_form_data.get("scale", 1.0))
	_sprite.scale = Vector2(sc, sc)
	_apply_form_cb(_form_data)
	_add_shadow_boss(sc)
	# 动画：idle 优先，无 idle 用 walk_down（公交）
	if _sprite.sprite_frames.has_animation("idle"):
		_sprite.play("idle")
	elif _sprite.sprite_frames.has_animation("walk_down"):
		_sprite.play("walk_down")
	if not is_start:
		GameManager.fx("res://assets/fx/FX-024_level_up_effect.png", global_position, 64, 64, 8, 0.8)


## 按形态 CB 设置方形判定框（宽高/偏移均乘 scale）。
func _apply_form_cb(fd: Dictionary) -> void:
	var cb: Vector4 = fd.get("cb", Vector4(80, 90, 0, 4))
	var sc: float = float(fd.get("scale", 1.0))
	var sz := Vector2(cb.x, cb.y) * sc
	var off := Vector2(cb.z * sc, cb.w * sc - 4.0)
	var cs := get_node_or_null("CollisionShape2D")
	if cs != null:
		var sh := RectangleShape2D.new()
		sh.size = sz
		cs.shape = sh
		cs.position = off
	var hs := get_node_or_null("Hitbox/CollisionShape2D")
	if hs != null:
		var hsh := RectangleShape2D.new()
		hsh.size = sz
		hs.shape = hsh
		hs.position = off


## Boss 阴影（按形态尺寸）。
func _add_shadow_boss(sc: float) -> void:
	if get_node_or_null("Shadow") != null:
		get_node("Shadow").queue_free()
	var cb: Vector4 = _form_data.get("cb", Vector4(80, 90, 0, 4))
	var w: float = cb.x * sc
	var h: float = cb.y * sc
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	var pts := PackedVector2Array()
	var n := 16
	for i in n:
		var ang := TAU * i / float(n)
		pts.append(Vector2(cos(ang) * w * 0.5, sin(ang) * w * 0.22))
	shadow.polygon = pts
	shadow.color = Color(0, 0, 0, 0.25)
	shadow.position = Vector2(0, h * 0.5 - 2.0)
	shadow.z_index = -10
	add_child(shadow)


func is_boss() -> bool:
	return true


# 编辑器预览：独立打开 Boss.tscn 时构建示例 Boss 精灵（idle 动画可见）。
func _ready() -> void:
	if Engine.is_editor_hint() and _eid == "":
		setup("b_bus")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	z_index = int(global_position.y)
	if _dead:
		return
	# 变身动画播放中：无敌 + 定身，播完自动进形态2
	if _transforming:
		velocity = Vector2.ZERO
		move_and_slide()
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
	var spd := speed
	if behavior == "charge":
		spd = speed * 3.0
	velocity = dir * spd
	move_and_slide()
	if absf(dir.x) > 0.1:
		_facing_left = dir.x < 0

	# 行为：按当前形态
	_tick_form_behavior(delta, player.global_position, dist, dir)


## 覆盖父类 _tick_status：Boss 每形态独立速度（从 _form_data.speed 读，不强制回退顶层 speed）。
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
	var base_spd: float = float(_form_data.get("speed", _data.get("speed", 55)))
	speed = base_spd * mult
	if _para_t > 0:
		_para_t -= delta
		speed = 0.0
	if _burn_t > 0:
		_burn_t -= delta
		_burn_acc += delta
		if _burn_acc >= 0.5:
			_burn_acc = 0.0
			_take_burn(4)


## 形态行为：公交冲撞 / 人形近战 / 昆虫·机器人·电脑机混合。
func _tick_form_behavior(delta: float, target: Vector2, dist: float, dir: Vector2) -> void:
	var fd: Dictionary = _form_data
	_atk_cd -= delta
	_charge_cd -= delta
	_summon_cd -= delta
	match behavior:
		"charger":
			# 公交形态：追击 + 周期冲撞 + 近身触手
			if _charge_cd <= 0 and dist > 120 and dist < 480:
				_charge_cd = float(fd.get("charge_cd", 3.2))
				behavior = "charge"
				_anim = "charge"
				_play_boss_anim("charge")
				get_tree().create_timer(0.9).timeout.connect(func():
					if is_instance_valid(self) and _form == 1:
						behavior = "charger")
			elif _atk_cd <= 0 and dist < float(fd.get("atk_range", 70)):
				_atk_cd = float(fd.get("atk_cd", 1.6))
				_melee_attack("attack")
			_play_move_anim()
		"patrol":
			# 人形态：锁定追击 + 近身拍巴掌（纯近战）
			if _atk_cd <= 0 and dist < float(fd.get("atk_range", 80)):
				_atk_cd = float(fd.get("atk_cd", 1.5))
				_melee_attack("melee")
			_play_move_anim()
		"hybrid":
			var hr: float = float(fd.get("hybrid_range", 240))
			if dist > hr:
				# 远程：保持距离 + 弹幕
				if dist > hr * 1.2:
					velocity = dir * speed
				elif dist < hr * 0.6:
					velocity = -dir * speed * 0.8
				else:
					velocity = Vector2.ZERO
				if _atk_cd <= 0:
					_atk_cd = float(fd.get("atk_cd", 1.8))
					_shoot(target)
			else:
				# 近战：追击 + 近战（melee）
				velocity = dir * speed
				if _atk_cd <= 0 and dist < float(fd.get("melee_range", 90)):
					_atk_cd = float(fd.get("melee_cd", 1.3))
					_melee_attack("melee")
			_play_move_anim()
		_:
			_play_move_anim()


## 播放移动/待机动画（无 idle 用 walk_down 兜底）。
func _play_move_anim() -> void:
	if _atk_timer > 0:
		return
	var fd: Dictionary = _form_data
	if velocity.length() > 5.0 and fd.has("walk_down"):
		_play_dir_anim(velocity)
	elif _anim != "idle" and _sprite.sprite_frames.has_animation("idle"):
		_anim = "idle"
		_sprite.play("idle")
		_sprite.flip_h = velocity.x < 0


## 播放 Boss 攻击动画（按朝向选 *_left）。
func _play_boss_anim(base: String) -> void:
	var name := base
	if _facing_left and _sprite.sprite_frames.has_animation(base + "_left"):
		name = base + "_left"
	if _sprite.sprite_frames.has_animation(name):
		_sprite.play(name)


func _melee_attack(anim_base: String = "attack") -> void:
	_atk_anim = anim_base
	_atk_timer = 0.5
	_play_boss_anim(anim_base)
	var reach: float = float(_form_data.get("melee_range", _form_data.get("atk_range", 80)))
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and global_position.distance_to(p.global_position) <= reach:
		GameManager.damage_player(contact_dmg)


func _shoot(target_pos: Vector2) -> void:
	var fd: Dictionary = _form_data
	_atk_anim = "attack"
	_atk_timer = 0.3
	_play_boss_anim("attack")
	var n: int = int(fd.get("bullet", 1))
	var spread: float = deg_to_rad(fd.get("spread", 0.0) * 57.3)
	var base := (target_pos - global_position).normalized()
	for i in n:
		var a := 0.0
		if n > 1:
			a = lerp(-spread, spread, float(i) / float(n - 1))
		var d := base.rotated(a)
		_spawn_proj(global_position + d * 18, d, fd.get("proj_dmg", 12), fd.get("proj_speed", 260), fd.get("proj", ""), false)


func _spawn_proj(pos: Vector2, dir: Vector2, dmg: int, spd: float, tex: String, homing: bool) -> void:
	var p := PROJ.instantiate() as Area2D
	p.global_position = pos
	p.set("direction", dir)
	p.set("speed", spd)
	p.set("damage", dmg)
	p.set("from_player", false)
	p.set("homing", homing)
	p.set("texture_path", tex)
	p.set("proj_frames", int(_form_data.get("proj_frames", 1)))
	p.set("proj_random", bool(_form_data.get("proj_random", false)))
	p.z_index = int(pos.y)
	var sc := get_tree().current_scene
	if sc != null:
		sc.add_child(p)


func _on_hit_player(body: Node) -> void:
	if _dead or _transforming or not body.is_in_group("player"):
		return
	if body.has_method("hit_by"):
		body.call("hit_by", contact_dmg)


func take_damage(dmg: int, is_crit: bool, effect: String, effect_time: float) -> void:
	if _dead or _transforming:
		return
	hp -= dmg
	GameManager.popup_damage(global_position, dmg, is_crit)
	_sprite.modulate = Color(1, 1, 1)
	var t := get_tree().create_tween()
	t.tween_property(_sprite, "modulate", Color(1, 0.3, 0.3), 0.08)
	t.tween_property(_sprite, "modulate", Color(1, 1, 1), 0.12)
	if effect != "" and effect_time > 0:
		apply_status(effect, effect_time)
	if hp <= 0:
		if _form == 1:
			_start_transform()   # 形态1：打空 → 变身
		else:
			_die(is_crit)


## 调试用（F11 秒杀）：形态1直接切形态2再死亡（跳过变身动画），形态2直接死亡。
func kill_now() -> void:
	if _dead or _transforming:
		return
	if _form == 1:
		_enter_form(2, false)
	hp = 0
	_die(false)


## 形态1打空：无敌 + 播变身动画，播完切形态2满血。
func _start_transform() -> void:
	_transforming = true
	velocity = Vector2.ZERO
	if _frames_transform != null and _sprite.sprite_frames != _frames_transform:
		_sprite.sprite_frames = _frames_transform
		_sprite.play("transform")
		_sprite.set_frame(0)
	# 变身动画播完（或缺失时延迟 2s）切形态2
	var dur := 2.0
	if _frames_transform != null and _sprite.sprite_frames.has_animation("transform"):
		dur = float(_data.get("transform_frames", 120)) / float(_data.get("transform_fps", 30))
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(self) and _transforming:
			_transforming = false
			_enter_form(2, false)
	)


func _die(is_crit: bool) -> void:
	_dead = true
	GameManager.set_weak(false)
	GameManager.fx("res://assets/fx/FX-024_level_up_effect.png", global_position, 64, 64, 8, 1.0)
	# 掉落梦晶（_die 可能由弹道命中即 body_entered 物理回调触发，add_child 新 Area2D 需延迟）
	var sc := get_tree().current_scene
	if sc != null:
		for i in 5:
			var pk := load("res://src/fx/Pickup.tscn").instantiate() as Area2D
			pk.set("kind", "crystal")
			pk.set("value", 20)
			pk.global_position = global_position + Vector2(randf_range(-40, 40), randf_range(-30, 30))
			sc.call_deferred("add_child", pk)
		if sc.has_method("on_boss_defeated"):
			sc.call("on_boss_defeated", _layer, self)
	velocity = Vector2.ZERO
	# 播放形态2死亡动画（dead/dead_left）
	if _form_data.has("dead"):
		var dname := "dead"
		if _facing_left and _sprite.sprite_frames.has_animation("dead_left"):
			dname = "dead_left"
		_sprite.play(dname)
		_sprite.connect("animation_finished", _on_dead_finished, CONNECT_ONE_SHOT)
	else:
		var t := get_tree().create_tween()
		t.tween_property(self, "modulate:a", 0.0, 0.6)
		t.tween_callback(queue_free).set_delay(0.6)
