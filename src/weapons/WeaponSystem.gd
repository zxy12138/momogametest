# 《梦境逐影》武器系统（玩家子节点，挂在 Player 下的 "Weapon" 节点）。
# 设计：单武器持有（loadout 至多 1 把），武器图标悬浮在玩家身旁；
# 开局地面随机 3 把，F 拾取选定后武器出现；每新房掉 1~2 把，F 替换。
# 鼠标攻击时武器按其 atk 行为出手并播放冲推动画。
# 攻击形态 atk：ranged_bolt / melee_arc / melee_ring / ranged_arrow / melee_slam / melee_fan / melee_line / ranged_spin
extends Node2D
class_name WeaponSystem

const PROJ = preload("res://src/weapons/Projectile.tscn")
const FX = "res://assets/weapons/fx/"

# atk -> 近战特效文件名（与 Weapons.gd 的 fx 路径对应；远程用弹体本身）
const FXID := {
	"melee_arc": "sword", "melee_ring": "scythe", "melee_slam": "hammer",
	"melee_fan": "whip", "melee_line": "spear",
}
# 近战特效原生半径（px），用于按 reach 缩放
const FXR := {"melee_arc": 48.0, "melee_ring": 85.0, "melee_slam": 48.0, "melee_fan": 65.0, "melee_line": 55.0}

var _loadout: Array[String] = []
var _active: int = 0
var _cd := 0.0
var _t := 0.0
var _lunge := Vector2.ZERO   # 攻击瞬间冲刺偏移：只在挥砍动画(0.18s)期间叠加，稳态必须为 ZERO
var _orbit: Array[Sprite2D] = []
var _content_offsets: Array[Vector2] = []   # 每把武器的贴图内容中心补偿（旋转时让内容落在轴线上）
var _swing_t := -1.0   # 挥砍动画进度：>=0 表示正在挥砍（0→1，时长 0.18s），<0 表示静止


# ---- 外部接口（Game / WeaponSelect / 拾取调用）----

## 设定 3 槽武器栏。ids 为空时随机抽 3 把。
func setup_loadout(ids: Array) -> void:
	_loadout.clear()
	for x in ids:
		_loadout.append(str(x))
	if _loadout.is_empty():
		_loadout = Weapons.pick_three()
	_active = 0
	_rebuild_orbit()
	_sync_active()


## 当前主武器 id（供拾取逻辑判断）。
func get_active_id() -> String:
	if _active < _loadout.size():
		return _loadout[_active]
	return ""


## 把主武器槽替换为 wid（地面拾取时调用）。单武器模式：直接持有 wid。
func replace_active(wid: String) -> void:
	if _loadout.is_empty():
		# 首次拾取（开局 3 选 1）：loadout 为空，直接装备为单武器
		setup_loadout([wid])
		return
	if _active >= _loadout.size():
		_active = 0
	_loadout[_active] = wid
	var sp := _orbit[_active] if _active < _orbit.size() else null
	if sp != null:
		var tex := GameManager.load_tex(Weapons.get_icon_path(wid))
		if tex != null:
			sp.texture = tex
			if _active < _content_offsets.size():
				_content_offsets[_active] = _calc_content_offset(tex)
	_sync_active()


# ---- 每帧（由 Player.gd 调用，签名需匹配）----
func process(delta: float, aim: Vector2, firing: bool) -> void:
	_cd -= delta
	_update_orbit(delta, aim)
	if _loadout.is_empty():
		return   # 未拾取武器：不自动补，等地面 3 选 1 拾取后 setup_loadout
	if Input.is_action_just_pressed("switch_weapon"):
		_cycle_active()
	var w: Dictionary = Weapons.get_weapon(_loadout[_active])
	if w.is_empty():
		return
	var sm: float = GameManager.skill_cd_mult
	var am: float = GameManager.atk_speed_mult
	var cd: float = float(w["cooldown"]) * sm * am
	if firing and _cd <= 0.0:
		_attack(aim, w)
		_cd = cd


## 释放当前武器专属技能（Player E 键调用；蓝条已由 GameManager.spend_mana 消耗）。
## 8 种技能按 type 差异化执行（见 Weapons.DATA[wid].skill）。
func cast_skill(aim: Vector2) -> void:
	if _loadout.is_empty() or _active >= _loadout.size():
		return
	var w: Dictionary = Weapons.get_weapon(_loadout[_active])
	if w.is_empty() or not w.has("skill"):
		return
	var sk: Dictionary = w["skill"]
	var player := get_parent() as Node2D
	if player == null:
		return
	var mult: float = float(sk.get("mult", 3.0))
	var dmg: int = int(float(w["dmg"]) * GameManager.attack_mult * mult)
	var ppos := player.global_position
	match str(sk.get("type", "")):
		"burst_ranged":  # staff 星尘陨落：5 发光弹（轻微散布）
			for i in 5:
				var dir := aim.rotated((float(i) - 2.0) * 0.08)
				_spawn_skill_proj(ppos + dir * 18.0, dir, dmg, float(sk.get("proj_speed", 520)), int(sk.get("pierce", 3)))
		"burst_melee":   # sword 剑气纵横：前方长矩形直线贯穿
			_skill_line(ppos, aim, dmg, float(sk.get("length", 200)), float(sk.get("width", 40)))
		"aoe_ring":      # scythe 死亡之环：360° 大环斩
			_skill_ring(ppos, dmg, float(sk.get("radius", 130)))
		"aoe_fan":       # bow 追星箭雨：前方 60° 扇形 8 箭
			var n: int = int(sk.get("arrows", 8))
			var arc: float = deg_to_rad(float(sk.get("arc", 60)))
			for i in n:
				var t: float = (float(i) / maxf(1.0, float(n - 1)) - 0.5)
				var dir := aim.rotated(t * arc)
				_spawn_skill_proj(ppos + dir * 18.0, dir, dmg, float(sk.get("proj_speed", 620)), 1)
		"aoe_blast":     # hammer 大地震裂：大范围冲击波 + 击退
			_skill_blast(ppos, dmg, float(sk.get("radius", 220)), float(sk.get("knockback", 150)))
		"control":       # whip 缚梦鞭锁：扇形内定身（paralyze）
			_skill_control(ppos, aim, dmg, float(sk.get("arc", 90)), float(sk.get("radius", 150)), float(sk.get("stun", 2.0)))
		"dash_pierce":   # spear 突袭连刺：向前冲刺 + 路径贯穿
			if player.has_method("dash"):
				player.call("dash", aim)
			_skill_line(ppos, aim, dmg, float(sk.get("dash_dist", 120)), 50.0)
		"buff_aoe":      # axe 暴风战斧：攻速 buff + 周围 AOE
			_skill_buff_aoe(ppos, dmg, float(sk.get("radius", 100)), float(sk.get("atk_speed_bonus", 0.5)), float(sk.get("buff_time", 3.0)))


# ---------------- 武器技能效果 ----------------

## 技能弹（高伤弹体，参数独立于普通攻击）
func _spawn_skill_proj(pos: Vector2, dir: Vector2, dmg: int, speed: float, pierce: int) -> void:
	var p := PROJ.instantiate() as Area2D
	p.set("direction", dir)
	p.set("speed", speed)
	p.set("damage", dmg)
	p.set("is_crit", false)
	p.set("pierce", pierce)
	p.set("bounce", 0)
	p.set("aoe", 0.0)
	p.set("from_player", true)
	p.set("effects", "")
	p.set("effect_time", 0.0)
	var wp: Dictionary = Weapons.get_weapon(_loadout[_active]) if _active < _loadout.size() else {}
	p.set("texture_path", wp.get("proj", ""))
	_spawn(p, pos)


## 前方矩形直线伤害（剑气/突刺）：宽 width、长 length 的矩形区域内敌人全伤。
func _skill_line(pos: Vector2, aim: Vector2, dmg: int, length: float, width: float) -> void:
	var fwd := aim.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	for en in get_tree().get_nodes_in_group("enemy"):
		var e := en as Node2D
		if e == null or not e.has_method("take_damage"):
			continue
		var rel := e.global_position - pos
		var along: float = rel.dot(fwd)
		if along < 0.0 or along > length:
			continue
		var across: float = absf(rel.dot(right))
		if across > width * 0.5:
			continue
		e.call("take_damage", dmg, false, "", 0.0)


## 360° 环斩（镰刀）：周围 radius 内全伤。
func _skill_ring(pos: Vector2, dmg: int, radius: float) -> void:
	for en in get_tree().get_nodes_in_group("enemy"):
		var e := en as Node2D
		if e == null or not e.has_method("take_damage"):
			continue
		if e.global_position.distance_to(pos) <= radius:
			e.call("take_damage", dmg, false, "", 0.0)


## 大范围冲击波 + 击退（锤）。
func _skill_blast(pos: Vector2, dmg: int, radius: float, knockback: float) -> void:
	for en in get_tree().get_nodes_in_group("enemy"):
		var e := en as Node2D
		if e == null or not e.has_method("take_damage"):
			continue
		var to := e.global_position - pos
		var dist := to.length()
		if dist > radius:
			continue
		e.call("take_damage", dmg, false, "", 0.0)
		if e.has_method("knockback") and dist > 1.0:
			e.call("knockback", to.normalized() * knockback)


## 扇形控制（鞭）：aim 朝向 ±arc/2 内、radius 内敌人定身（paralyze）。
func _skill_control(pos: Vector2, aim: Vector2, dmg: int, arc_deg: float, radius: float, stun: float) -> void:
	for en in get_tree().get_nodes_in_group("enemy"):
		var e := en as Node2D
		if e == null or not e.has_method("take_damage"):
			continue
		var to := e.global_position - pos
		var dist := to.length()
		if dist > radius:
			continue
		var ang := aim.angle_to(to)
		ang = fmod(ang + PI, TAU) - PI
		if abs(ang) > deg_to_rad(arc_deg) * 0.5:
			continue
		e.call("take_damage", dmg, false, "", 0.0)
		if e.has_method("apply_status"):
			e.call("apply_status", "paralyze", stun)


## 攻速增益 + 周围 AOE（斧）：临时提升 GameManager.atk_speed_mult。
func _skill_buff_aoe(pos: Vector2, dmg: int, radius: float, atk_speed_bonus: float, buff_time: float) -> void:
	for en in get_tree().get_nodes_in_group("enemy"):
		var e := en as Node2D
		if e == null or not e.has_method("take_damage"):
			continue
		if e.global_position.distance_to(pos) <= radius:
			e.call("take_damage", dmg, false, "", 0.0)
	var base: float = GameManager.atk_speed_mult
	GameManager.atk_speed_mult = base + atk_speed_bonus
	var t := create_tween()
	t.tween_interval(buff_time)
	t.tween_callback(func():
		GameManager.atk_speed_mult = base
	)


# ---- 内部 ----

func _attack(aim: Vector2, w: Dictionary) -> void:
	var player := get_parent() as Node2D
	if player == null:
		return
	var is_crit: bool = GameManager.roll_crit() or w.get("always_crit", false)
	var dmg: int = int(float(w["dmg"]) * GameManager.attack_mult)
	if is_crit:
		dmg += GameManager.crit_dmg

	# 主武器攻击动画：武器沿弧线挥砍（由 _update_orbit 的 _swing_t 驱动）+ 冲推
	_lunge = aim * 18.0
	_swing_t = 0.0
	# 同步玩家角色攻击动画（Player.play_attack 设 _atk_timer=0.30，_anim_update 据此切到 attack 动画）
	if player.has_method("play_attack"):
		player.call("play_attack")
	var asp := _orbit[_active] if _active < _orbit.size() else null
	if asp != null:
		var tw := create_tween()
		var bs := Vector2(0.15, 0.15)
		tw.tween_property(asp, "scale", bs * 1.35, 0.06)
		tw.tween_property(asp, "scale", bs, 0.12)

	# 攻击时角色不切帧（用户要求：角色保持待机/移动，只有武器挥砍变化）
	if is_crit:
		player.call("shake", 0.12, 3)
		GameManager.fx("res://assets/fx/FX-001_crit_trigger_orange_flash.png", player.global_position, 48, 48, 5, 0.45)

	var atk: String = w.get("atk", "")
	if atk in ["ranged_bolt", "ranged_arrow", "ranged_spin"]:
		_spawn_proj(player.global_position + aim * 18.0, aim, w, dmg, is_crit)
	else:
		_melee(player.global_position, aim, w, dmg, is_crit)


func _spawn_proj(pos: Vector2, aim: Vector2, w: Dictionary, dmg: int, is_crit: bool) -> void:
	var p := PROJ.instantiate() as Area2D
	p.set("direction", aim)
	p.set("speed", float(w.get("proj_speed", 320)))
	p.set("damage", dmg)
	p.set("is_crit", is_crit)
	p.set("pierce", int(w.get("pierce", 0)))
	p.set("bounce", int(w.get("bounce", 0)))
	p.set("aoe", float(w.get("aoe", 0.0)))
	p.set("from_player", true)
	p.set("effects", w.get("effect", ""))
	p.set("effect_time", float(w.get("effect_time", 0.0)))
	p.set("texture_path", w.get("proj", ""))
	if w.get("spin", false):
		p.set("spin", true)
	_spawn(p, pos)


func _melee(pos: Vector2, aim: Vector2, w: Dictionary, dmg: int, is_crit: bool) -> void:
	var reach: float = float(w.get("reach", 46.0))
	var arc_deg: float = float(w.get("arc", 90))
	var aoe: float = float(w.get("aoe", 0.0))
	var ring: bool = arc_deg >= 360.0
	var center := pos + aim * reach * 0.5
	for en in get_tree().get_nodes_in_group("enemy"):
		var e := en as Node2D
		if e == null or not e.has_method("take_damage"):
			continue
		var to := e.global_position - pos
		var dist := to.length()
		var hit := false
		if ring:
			hit = dist <= reach
		else:
			if dist <= reach:
				var ang := aim.angle_to(to)
				ang = fmod(ang + PI, TAU) - PI
				if abs(ang) <= deg_to_rad(arc_deg) * 0.5:
					hit = true
		if not hit and aoe > 0.0:
			if e.global_position.distance_to(center) <= aoe:
				hit = true
		if not hit:
			continue
		e.call("take_damage", dmg, is_crit, w.get("effect", ""), float(w.get("effect_time", 0.0)))
		if float(w.get("slow", 0.0)) > 0.0:
			e.call("apply_status", "slow", w["slow"])
		elif float(w.get("freeze", 0.0)) > 0.0:
			e.call("apply_status", "freeze", w["freeze"])
		if float(w.get("knockback", 0.0)) > 0.0:
			e.call("knockback", -to.normalized() * float(w["knockback"]))
	if bool(w.get("dash", false)):
		get_parent().call("dash", aim)
	_melee_fx(w, center, aim, reach, aoe)


func _melee_fx(w: Dictionary, center: Vector2, aim: Vector2, reach: float, aoe: float) -> void:
	var atk: String = w.get("atk", "")
	if not FXID.has(atk):
		return
	var path: String = FX + "weapon_fx_" + str(FXID[atk]) + ".png"
	var tex := GameManager.load_tex(path)
	if tex == null:
		return
	var sc := get_tree().current_scene
	if sc == null:
		return
	var nat_r: float = FXR.get(atk, 48.0)
	var scale_v: float = reach / nat_r
	var rot: float = 0.0
	if atk == "melee_slam":
		scale_v = (reach + aoe) / nat_r
	elif atk != "melee_ring":
		rot = aim.angle()
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.global_position = center
	sp.rotation = rot
	sp.z_index = 50
	sp.scale = Vector2(scale_v * 0.6, scale_v * 0.6)
	sc.add_child(sp)
	var tw := get_tree().create_tween()
	tw.tween_property(sp, "scale", Vector2(scale_v, scale_v), 0.08)
	tw.parallel().tween_property(sp, "modulate:a", 0.0, 0.22)
	tw.tween_callback(Callable(sp, "queue_free"))


func _spawn(node: Node2D, pos: Vector2) -> void:
	node.global_position = pos
	node.z_index = int(pos.y)
	var sc := get_tree().current_scene
	if sc != null:
		sc.add_child(node)


func _update_orbit(delta: float, aim: Vector2) -> void:
	_t += delta
	# 攻击冲刺偏移：每帧快速收敛到 ZERO（非挥砍时绝不允许残留，否则武器偏离轨道）。
	_lunge = _lunge.lerp(Vector2.ZERO, 0.5)
	var n: int = _orbit.size()
	for i in n:
		var sp: Sprite2D = _orbit[i]
		if n == 1:
			# 单武器模式：平时以角色中心为旋转轴心、360° 环绕，位置与朝向都跟随鼠标方向
			# （武器停在"角色→鼠标"方向的圆周上）；攻击时从身后沿弧线挥砍到前方（0.18s，纯运动）。
			if _swing_t >= 0.0:
				_swing_t += delta / 0.18
				if _swing_t >= 1.0:
					_swing_t = -1.0
			var target_angle: float = aim.angle()
			# 贴图内容补偿：把武器"内容中心"对齐到角色→鼠标轴线（贴图中心≠内容中心时视觉才不偏）
			if i < _content_offsets.size():
				sp.offset = _content_offsets[i]
			if _swing_t >= 0.0:
				# 挥砍：从 aim-1.6 弧摆到 aim+0.4（约 115°），半径与环绕一致，带冲刺偏移
				var a0: float = target_angle - 1.6
				var ang: float = a0 + _swing_t * 2.0
				sp.rotation = ang
				sp.position = Vector2(cos(ang), sin(ang)) * 46.0 + _lunge
			else:
				# 稳态：严格以角色中心为轴、半径 46、尖端朝向鼠标——不带 _lunge（避免攻击后偏移）
				sp.rotation = target_angle
				sp.position = Vector2(cos(target_angle), sin(target_angle)) * 46.0
		else:
			var ang: float = _t * 0.7 + float(i) * TAU / float(n)
			var base := Vector2(cos(ang), sin(ang)) * 64.0
			if i == _active:
				base += _lunge
			sp.position = base


func _cycle_active() -> void:
	if _loadout.size() == 0:
		return
	_active = (_active + 1) % _loadout.size()
	_sync_active()


func _sync_active() -> void:
	if _active >= _loadout.size():
		_active = 0
	if _loadout.size() > 0:
		GameManager.weapon_id = _loadout[_active]
		GameManager.emit_signal("stats_changed")
	for i in _orbit.size():
		var active: bool = (i == _active)
		_orbit[i].modulate = Color(1.0, 1.0, 1.0) if active else Color(0.5, 0.5, 0.6)
		_orbit[i].scale = Vector2(0.15, 0.15) if active else Vector2(0.11, 0.11)


func _rebuild_orbit() -> void:
	for s in _orbit:
		s.queue_free()
	_orbit.clear()
	_content_offsets.clear()
	for i in _loadout.size():
		var sp := Sprite2D.new()
		var tex := GameManager.load_tex(Weapons.get_icon_path(_loadout[i]))
		if tex != null:
			sp.texture = tex
		sp.z_index = 9
		# 贴图内容中心补偿：武器旋转后"内容"沿轴线摆放，尖端精确指向鼠标（贴图中心≠内容中心时修正）
		_content_offsets.append(_calc_content_offset(tex))
		# 武器自身椭圆阴影（子节点随 sprite 缩放；sprite 基准 0.15 缩放，故阴影倍率放大补偿）
		var sh := HandleUtil.shadow_polygon(Vector2(3.6, 1.5))
		sh.position = Vector2(0, 14)
		sh.z_index = 8
		sp.add_child(sh)
		add_child(sp)
		_orbit.append(sp)


## 计算贴图"内容中心 → 贴图中心"的偏移向量。
## 武器贴图绘制时内容往往不在正中心（如剑尖偏右/偏左），直接 centered 旋转会让武器视觉上
## 不指向鼠标。返回 offset 使内容中心平移到贴图原点——旋转后内容中心正好落在角色→鼠标轴线上。
## 注：get_image() 仅对非图集贴图可靠；图集(AtlasTexture)或失败时返回 ZERO（不补偿）。
func _calc_content_offset(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2.ZERO
	var img := tex.get_image()
	if img == null:
		return Vector2.ZERO
	var bbox := img.get_used_rect()
	if bbox.size.x <= 0 or bbox.size.y <= 0:
		return Vector2.ZERO
	# get_used_rect() 返回 Vector2i，需显式转 Vector2 再做浮点运算
	var content_c := Vector2(bbox.position) + Vector2(bbox.size) * 0.5
	var tex_c := Vector2(img.get_size()) * 0.5
	return tex_c - content_c
