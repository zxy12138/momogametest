# 房间 + RoomManager：地板/墙/门/驿站 + 按数据刷怪（离开重进即「魂式」刷新）
extends Node2D
class_name RoomManager

const ENEMY = preload("res://src/enemies/Enemy.tscn")
# Boss 继承 Enemy，若用 preload 会在 RoomManager 解析期就加载 Boss.gd，
# 此时 class_name Enemy 可能尚未注册，导致 "Could not find base class Enemy"。
# 改为运行期 load()：进入 Boss 房时 Enemy 早已注册，可安全解析。
const BOSS_PATH := "res://src/enemies/Boss.tscn"

var W := 880.0
var H := 500.0
var _rid := ""
var _data := {}
var _layer := 1
var _entities: Node = null
var _game: Node = null
var _floor: TextureRect
var _prefab := false  # 是否使用美术预制整图作背景（v4.0 试用）


func setup(rid: String, data: Dictionary, layer: int, entities: Node, game: Node) -> void:
	_rid = rid
	_data = data
	_layer = layer
	_entities = entities
	_game = game
	_build_floor()
	_build_walls()
	_build_doors()
	if _data.get("type", "") == "inn":
		_build_inn()
	_spawn_content()


func _build_floor() -> void:
	_floor = get_node("Floor") as TextureRect
	var img: String = _data.get("scene_img", "")
	if img != "":
		# 预制整图方案（v4.0 试用）：直接用美术预制的一图一房背景，墙体烘焙在图内；
		# 碰撞仍由 _build_walls 的无形墙负责，这里只做背景显示。
		_prefab = true
		_floor.texture = load(img) as Texture2D
		_floor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_floor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_floor.size = Vector2(W, H)
		_floor.position = Vector2(-W / 2, -H / 2)
		_floor.modulate = Color(1, 1, 1)
	else:
		_floor.texture = load("res://assets/tiles/T-000_base_dream_floor_tile_1.png") as Texture2D
		_floor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_floor.stretch_mode = TextureRect.STRETCH_TILE
		_floor.size = Vector2(W, H)
		_floor.position = Vector2(-W / 2, -H / 2)
		# 按层轻微染色，强化每层主题（克制，近 1.0 乘法）
		var tints := {1: Color(0.92, 0.96, 1.08), 2: Color(1.0, 1.0, 1.0), 3: Color(1.08, 0.92, 0.94)}
		_floor.modulate = tints.get(_layer, Color(1, 1, 1))
	# 地板永远在最底层：实体用 z_index=int(y) 做 Y 排序，上移时 y<0→z<0，
	# 若地板 z=0 会把上移的角色/敌人/弹道盖住而「消失」。
	_floor.z_index = -4000


func _build_walls() -> void:
	var sb := StaticBody2D.new()
	sb.name = "Walls"
	sb.collision_layer = 16
	add_child(sb)
	var th := 24.0
	_add_wall(sb, 0, -H / 2 - th / 2, W + 2 * th, th)
	_add_wall(sb, 0, H / 2 + th / 2, W + 2 * th, th)
	_add_wall(sb, -W / 2 - th / 2, 0, th, H + 2 * th)
	_add_wall(sb, W / 2 + th / 2, 0, th, H + 2 * th)
	if not _prefab:
		_build_wall_visuals(th)


func _add_wall(sb: Node, cx: float, cy: float, w: float, h: float) -> void:
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(w, h)
	cs.shape = sh
	cs.position = Vector2(cx, cy)
	sb.add_child(cs)


# 可见墙体贴图：沿四边平铺对应层墙瓦片；仅在 neighbors 存在的边留门洞，其余实墙不可穿。
func _build_wall_visuals(th: float) -> void:
	var wall_tex: Texture2D
	match _layer:
		1: wall_tex = load("res://assets/tiles/T-021_office_wall_tile_1.png") as Texture2D
		2: wall_tex = load("res://assets/tiles/T-031_subway_wall_tile_1.png") as Texture2D
		3: wall_tex = load("res://assets/tiles/T-041_warped_wall_animated.png") as Texture2D
		_: wall_tex = load("res://assets/tiles/T-001_base_wall_tile_1.png") as Texture2D
	var G := 64.0
	var n := mini(_data.get("neighbors", []).size(), 4)
	# TOP (i=0)
	if 0 < n:
		add_child(_wall_seg(wall_tex, -(W / 2 + th + G / 2) / 2, -H / 2 - th / 2, W / 2 + th - G / 2, th))
		add_child(_wall_seg(wall_tex, (W / 2 + th + G / 2) / 2, -H / 2 - th / 2, W / 2 + th - G / 2, th))
	else:
		add_child(_wall_seg(wall_tex, 0, -H / 2 - th / 2, W + 2 * th, th))
	# BOTTOM (i=1)
	if 1 < n:
		add_child(_wall_seg(wall_tex, -(W / 2 + th + G / 2) / 2, H / 2 + th / 2, W / 2 + th - G / 2, th))
		add_child(_wall_seg(wall_tex, (W / 2 + th + G / 2) / 2, H / 2 + th / 2, W / 2 + th - G / 2, th))
	else:
		add_child(_wall_seg(wall_tex, 0, H / 2 + th / 2, W + 2 * th, th))
	# LEFT (i=2)
	if 2 < n:
		add_child(_wall_seg(wall_tex, -W / 2 - th / 2, -(H / 2 + th + G / 2) / 2, th, H / 2 + th - G / 2))
		add_child(_wall_seg(wall_tex, -W / 2 - th / 2, (H / 2 + th + G / 2) / 2, th, H / 2 + th - G / 2))
	else:
		add_child(_wall_seg(wall_tex, -W / 2 - th / 2, 0, th, H + 2 * th))
	# RIGHT (i=3)
	if 3 < n:
		add_child(_wall_seg(wall_tex, W / 2 + th / 2, -(H / 2 + th + G / 2) / 2, th, H / 2 + th - G / 2))
		add_child(_wall_seg(wall_tex, W / 2 + th / 2, (H / 2 + th + G / 2) / 2, th, H / 2 + th - G / 2))
	else:
		add_child(_wall_seg(wall_tex, W / 2 + th / 2, 0, th, H + 2 * th))


func _wall_seg(tex: Texture2D, cx: float, cy: float, w: float, h: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_TILE
	r.size = Vector2(w, h)
	r.position = Vector2(cx - w / 2, cy - h / 2)
	r.z_index = -10
	return r


func _build_doors() -> void:
	var edges := [Vector2(0, -H / 2 + 26), Vector2(0, H / 2 - 26), Vector2(-W / 2 + 26, 0), Vector2(W / 2 - 26, 0)]
	var arrows := ["↑", "↓", "←", "→"]
	var neigh: Array = _data.get("neighbors", [])
	for i in mini(neigh.size(), edges.size()):
		var nid: String = neigh[i]
		var d := Area2D.new()
		d.name = "Door_" + nid
		d.collision_layer = 8
		d.collision_mask = 1
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(44, 44)
		cs.shape = sh
		d.add_child(cs)
		d.position = edges[i]
		var cb := func(b: Node):
			if b.is_in_group("player"):
				if _game != null and _game.has_method("transition_to"):
					_game.call("transition_to", nid)
		d.connect("body_entered", cb)
		add_child(d)
		# 可见门框（贴图 T-003 开启动画门，取首帧静态显示）+ 方向箭头，给玩家清晰的出口指引
		var door_tex := load("res://assets/tiles/T-003_door_frame_open_anim.png") as Texture2D
		var ds := door_tex.get_size()
		var dh := 96.0
		var fw := ds.x / 4.0  # T-003 为 4 帧横排动画表，单帧宽 = 总宽/4
		var dw := dh * fw / ds.y
		var spr := Sprite2D.new()
		spr.texture = door_tex
		spr.hframes = 4
		spr.frame = 0
		spr.scale = Vector2(dw / fw, dh / ds.y)
		spr.position = d.position
		spr.z_index = 4
		add_child(spr)
		var lab := Label.new()
		lab.text = arrows[i] + " " + _room_label(nid)
		lab.position = d.position - Vector2(34, 14)
		lab.add_theme_font_size_override("font_size", 22)
		lab.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
		lab.z_index = 6
		add_child(lab)

func _room_label(rid: String) -> String:
	var t: String = MapData.room(rid).get("type", "")
	match t:
		"combat": return "战斗"
		"elite": return "精英"
		"boss": return "BOSS"
		"inn": return "驿站"
		"start": return "起点"
		_: return "房间"

func _build_inn() -> void:
	var pad := Area2D.new()
	pad.name = "InnPad"
	pad.collision_layer = 8
	pad.collision_mask = 1
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(60, 60)
	cs.shape = sh
	pad.add_child(cs)
	var cb := func(b: Node):
		if b.is_in_group("player") and _game != null and _game.has_method("_on_inn_enter"):
			_game.call("_on_inn_enter")
	pad.connect("body_entered", cb)
	var cbx := func(b: Node):
		if b.is_in_group("player") and _game != null and _game.has_method("_on_inn_exit"):
			_game.call("_on_inn_exit")
	pad.connect("body_exited", cbx)
	add_child(pad)
	# 驿站地面贴图（T-050 休息站内景）+ 暖光标记
	var inn_tex := load("res://assets/tiles/T-050_dream_rest_stop_interior.png") as Texture2D
	var isz := inn_tex.get_size()
	var iscale: float = 130.0 / max(isz.x, isz.y)
	var decal := Sprite2D.new()
	decal.texture = inn_tex
	decal.scale = Vector2(iscale, iscale)
	decal.position = Vector2(0, 0)
	decal.z_index = -3000
	add_child(decal)
	var m := ColorRect.new()
	m.size = Vector2(150, 150); m.position = Vector2(-75, -75)
	m.color = Color(0.95, 0.85, 0.55, 0.35)
	add_child(m)
	var lab := Label.new()
	lab.text = "驿站"
	lab.position = Vector2(-22, -95)
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	lab.z_index = 6
	add_child(lab)


func _spawn_content() -> void:
	var type: String = _data.get("type", "combat")
	if type == "boss":
		var cleared: bool = GameManager.boss_cleared.get(_layer, false)
		if not cleared:
			_spawn_boss(_data.get("boss", "b_director"))
		return
	if type == "inn" or type == "start":
		return
	# 普通/精英房：刷怪（重进即刷新）
	for spec in _data.get("enemies", []):
		var eid: String = spec[0]; var cnt: int = int(spec[1])
		for k in cnt:
			var pos := _rand_pos()
			_spawn_enemy(eid, pos)
			# 精英怪分身
			var ed: Dictionary = Enemies.get_enemy(eid)
			if ed != null and ed.get("clone_count", 0) > 0:
				for c in int(ed["clone_count"]):
					_spawn_enemy(eid, _rand_pos())


func _spawn_enemy(eid: String, pos: Vector2) -> void:
	var e := ENEMY.instantiate() as Node2D
	e.call("setup", eid)
	e.global_position = pos
	e.z_index = int(pos.y)
	# 加进本房间节点：切换房间时 _room.queue_free() 会一并销毁，避免跨房叠加
	add_child(e)


func _spawn_boss(bid: String) -> void:
	var b := load(BOSS_PATH).instantiate() as Node2D
	b.call("setup", bid)
	b.global_position = Vector2(0, -60)
	b.z_index = int(b.global_position.y)
	# 加进本房间节点：随房间销毁
	add_child(b)


func _rand_pos() -> Vector2:
	return Vector2(randf_range(-W / 2 + 60, W / 2 - 60), randf_range(-H / 2 + 60, H / 2 - 60))
