# 房间 + RoomManager：地板/墙/门/驿站 + 按数据刷怪（离开重进即「魂式」刷新）
@tool
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
var _layout: RoomLayout


func setup(rid: String, data: Dictionary, layer: int, entities: Node, game: Node) -> void:
	_rid = rid
	_data = data
	_layer = layer
	_entities = entities
	_game = game
	_layout = _load_layout()
	_build_floor()
	_build_walls()
	_build_doors()
	_build_blocked()
	if _data.get("type", "") == "inn":
		_build_inn()
	_spawn_content()


func _load_layout() -> RoomLayout:
	# 按 层+rid 读取该房的布局 .tres；不存在则退回空布局（全用默认/随机）。
	var path := "res://src/rooms/layouts/%d_%s.tres" % [_layer, _rid]
	if FileAccess.file_exists(path):
		return load(path) as RoomLayout
	return RoomLayout.new()


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
	# 背景偏移/缩放（来自 RoomLayout，用于对齐美术整图；缺省 0/1 等同原行为）
	_floor.position += _layout.bg_offset
	_floor.scale = Vector2(_layout.bg_scale, _layout.bg_scale)
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
	var door_map := {}
	for d in _layout.doors:
		door_map[d.target] = d.position
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
		d.position = door_map.get(nid, edges[i])
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

## 返回本房中「指向 target_rid 的那扇门」的房间局部坐标；找不到时返回 ZERO（调用方回退默认出生点）。
## 用于让玩家从某扇门进入新房间时，出生在该房「指回旧房」的那扇门位置（从门走出角色的效果）。
func entry_door_position(target_rid: String) -> Vector2:
	var edges: Array[Vector2] = [
		Vector2(0.0, -H / 2.0 + 26.0),
		Vector2(0.0, H / 2.0 - 26.0),
		Vector2(-W / 2.0 + 26.0, 0.0),
		Vector2(W / 2.0 - 26.0, 0.0)
	]
	var door_map: Dictionary = {}
	for d in _layout.doors:
		door_map[d.target] = d.position
	var neigh: Array = _data.get("neighbors", [])
	for i in mini(neigh.size(), edges.size()):
		if String(neigh[i]) == target_rid:
			return door_map.get(target_rid, edges[i])
	return Vector2.ZERO


## 返回本房在 RoomLayout 中设置的角色出生点（房间局部坐标）；未设置(默认 ZERO)时返回 ZERO。
## 用于让玩家在编辑器里自定义初始位置（Game._swap 首进/无来源房间时使用）。
func spawn_point_position() -> Vector2:
	if _layout != null:
		return _layout.spawn_point
	return Vector2.ZERO

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
			_start_boss_intro()
		return
	if type == "inn" or type == "start":
		return
	# 拖入式敌人放置：按 RoomLayout.enemy_placements 实例化（取代原 LevelData.enemies 数据驱动刷怪）。
	# 普通/精英房重进即刷新——玩家在编辑器里摆放的敌人每次进房都会重新出现。
	for def in _layout.enemy_placements:
		var eid: String = def.enemy_id
		if eid == "" or eid in Enemies.BOSS:
			continue
		var pos: Vector2 = def.pos
		_spawn_enemy(eid, pos)
		# 精英怪分身（按数据 clone_count）
		var ed: Dictionary = Enemies.get_enemy(eid)
		if ed != null and ed.get("clone_count", 0) > 0:
			for c in int(ed["clone_count"]):
				_spawn_enemy(eid, pos + Vector2(randf_range(-90.0, 90.0), randf_range(-90.0, 90.0)))


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

# Boss 房入场：先显示「入场图」(boss_intro_img，如 S_003_7)，播放入场动画（计时 boss_intro_time 秒），
# 动画结束再切换为正式地图 (scene_img，如 S_003_7_1) 并开始 boss 战。
# 仅当房间带 boss_intro_img 且未清空时生效；普通 boss 房（无该字段）intro 为空则直接出 boss。
func _start_boss_intro() -> void:
	var bid: String = _data.get("boss", "b_director")
	var intro: String = _data.get("boss_intro_img", "")
	var real: String = _data.get("scene_img", "")
	var intro_time: float = float(_data.get("boss_intro_time", 0.0))
	# 编辑器预览：直接出 boss，避免 @tool 下计时器行为异常
	if Engine.is_editor_hint():
		_spawn_boss(bid)
		return
	# 进入时先显示入场图（如 S_003_7）
	if intro != "" and _floor != null:
		_floor.texture = load(intro) as Texture2D
	if intro_time <= 0.0:
		_spawn_boss(bid)
		return
	var timer := get_tree().create_timer(intro_time)
	timer.timeout.connect(func():
		if is_instance_valid(_floor) and real != "":
			_floor.texture = load(real) as Texture2D
		_spawn_boss(bid)
	)


# 禁区/不可走区域：在 RoomLayout.blocked 中定义，生成无形碰撞墙 + 半透明红色可视。
func _build_blocked() -> void:
	for i in _layout.blocked.size():
		var rd: RectDef = _layout.blocked[i]
		var sb := StaticBody2D.new()
		sb.name = "Blocked_%d" % i
		sb.collision_layer = 16
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = rd.size
		cs.shape = sh
		cs.position = rd.center
		sb.add_child(cs)
		add_child(sb)
		var cr := ColorRect.new()
		cr.color = Color(0.8, 0.2, 0.2, 0.35)
		cr.size = rd.size
		cr.position = rd.center - rd.size / 2.0
		cr.z_index = -5
		add_child(cr)


# 编辑器预览：独立打开 Room.tscn 时构建一个示例战斗房（墙/门/敌人可见）。
# 当本节点被 Game 在编辑器里实例化并主动 setup() 时（parent 非 null），由 Game 驱动，不自动 build，避免重复生成。
func _ready() -> void:
	if Engine.is_editor_hint() and _rid == "" and get_parent() == null:
		var data := {"type": "combat", "neighbors": ["r2", "r3"], "enemies": [["overtime_ghost", 1]]}
		setup("preview", data, 1, get_parent(), get_tree().current_scene)
