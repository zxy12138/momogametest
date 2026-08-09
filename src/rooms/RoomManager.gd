# 房间 + RoomManager：地板/墙/门/驿站 + 按数据刷怪（离开重进即「魂式」刷新）
@tool
extends Node2D
class_name RoomManager

const ENEMY = preload("res://src/enemies/Enemy.tscn")
# WeaponPickup 用 preload 拿脚本引用来 new()（避免解析期依赖全局 class_name 缓存，类型按 Node2D 处理）
const WeaponPickupScript := preload("res://src/weapons/WeaponPickup.gd")
# Boss 继承 Enemy，若用 preload 会在 RoomManager 解析期就加载 Boss.gd，
# 此时 class_name Enemy 可能尚未注册，导致 "Could not find base class Enemy"。
# 改为运行期 load()：进入 Boss 房时 Enemy 早已注册，可安全解析。
const BOSS_PATH := "res://src/enemies/Boss.tscn"

## 场景自描述（世界场景里的房间场景 f{层}_{房}.tscn 导出）：编辑器里直接看到该节点属于哪层哪房，
## 也用于独立运行(F6)/编辑器打开时 _ready 自动构建该真实房间。
@export var layer: int = 1
@export var room_id: String = ""

var W := 880.0
var H := 500.0
var _rid := ""
var _data := {}
var _layer := 1
var _entities: Node = null
var _game: Node = null
var _floor: TextureRect
var _prefab := false  # 是否使用美术预制整图作背景（v4.0 试用）
var _setup_done := false  # 防重复构建：房间场景 _ready 自建后，Game 再调 setup 直接返回

# 场景手柄收集（房间场景 f{层}_{房}.tscn 里直接摆放的 @tool 手柄节点）：
# 房间内容（门/禁区/敌人/出生点/武器/装饰）全部由手柄定义，不再读 layouts/*.tres（旧 RoomLayoutEditor 已移除）。
var _door_handles: Array[DoorHandle] = []
var _enemy_handles: Array[EnemyHandle] = []
var _blocked_handles: Array[BlockedHandle] = []
var _spawn_handles: Array[SpawnPointHandle] = []
var _weapon_handles: Array[WeaponHandle] = []
var _decoration_handles: Array[DecorationHandle] = []
var _next_door_handles: Array[NextDoorHandle] = []
var _boss_handles: Array[BossHandle] = []   ## Boss 房手柄（取代旧「运行时自动生成 boss」）
var _next_doors: Array[Area2D] = []   ## 生成的下一层传送门（Boss 击败后 enable_next_door 启用）


func setup(rid: String, data: Dictionary, floor_idx: int, entities: Node, game: Node) -> void:
	if _setup_done:
		return
	_setup_done = true
	_rid = rid
	_data = data
	_layer = floor_idx
	_entities = entities
	_game = game
	_collect_handles()
	_build_floor()
	_build_walls()
	# 编辑器预览（F6 / 在编辑器里打开房间场景）：只构建地板/墙（房间骨架）。
	# 门 / 禁区 / 驿站 / 敌人 / 装饰 / 武器 / 下一层门 全部由场景里的「手柄」可视化（Handles @tool 已自带可视化）；
	# 运行期才生成真实碰撞 / Area2D / 实例。这样用户在编辑器里看到的「战斗」门/敌人/武器都是可拖动的场景节点，
	# 而不是 RoomManager 程序生成、无法编辑的运行时节点。
	if not Engine.is_editor_hint():
		_build_doors()
		_build_blocked()
		_spawn_content()
		_spawn_decorations()
		_spawn_weapons()
		_build_next_door()


## 收集房间场景里的手柄节点（门/敌人/禁区/出生点/武器），供后续构建优先读取。
func _collect_handles() -> void:
	_door_handles.clear()
	_enemy_handles.clear()
	_blocked_handles.clear()
	_spawn_handles.clear()
	_weapon_handles.clear()
	_decoration_handles.clear()
	_next_door_handles.clear()
	_boss_handles.clear()
	for c in get_children():
		if c is DoorHandle:
			_door_handles.append(c)
		elif c is EnemyHandle:
			_enemy_handles.append(c)
		elif c is BlockedHandle:
			_blocked_handles.append(c)
		elif c is SpawnPointHandle:
			_spawn_handles.append(c)
		elif c is WeaponHandle:
			_weapon_handles.append(c)
		elif c is DecorationHandle:
			_decoration_handles.append(c)
		elif c is NextDoorHandle:
			_next_door_handles.append(c)
		elif c is BossHandle:
			_boss_handles.append(c)


func _build_floor() -> void:
	_floor = get_node_or_null("Floor") as TextureRect
	if _floor == null:
		# 防御：场景缺少 Floor 子节点时自建（生成的房间场景缺 Floor 会崩；此处兜底）
		_floor = TextureRect.new()
		_floor.name = "Floor"
		add_child(_floor)
	var img: String = _data.get("scene_img", "")
	# 背景基准变换（背景整图与房间 880×500 对齐；视频与图片两套背景套用同一变换）
	var base_pos := Vector2(-W / 2, -H / 2)
	var base_scale := Vector2.ONE
	if img != "":
		# 预制整图方案（v4.0 试用）：直接用美术预制的一图一房背景，墙体烘焙在图内；
		# 碰撞仍由 _build_walls 的无形墙负责，这里只做背景显示。
		_prefab = true
		var res := load(img)
		if res is VideoStream:
			# 动态地图（.ogv Theora）：用 VideoStreamPlayer 播放，原 TextureRect 隐藏。
			_floor.visible = false
			_add_video_floor(res as VideoStream, base_pos, base_scale)
			return
		_floor.texture = res as Texture2D
		_floor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_floor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_floor.size = Vector2(W, H)
		_floor.position = base_pos
		_floor.scale = base_scale
		_floor.modulate = Color(1, 1, 1)
	else:
		_floor.texture = load("res://assets/tiles/T-000_base_dream_floor_tile_1.png") as Texture2D
		_floor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_floor.stretch_mode = TextureRect.STRETCH_TILE
		_floor.size = Vector2(W, H)
		_floor.position = base_pos
		_floor.scale = base_scale
		# 按层轻微染色，强化每层主题（克制，近 1.0 乘法）
		var tints := {1: Color(0.92, 0.96, 1.08), 2: Color(1.0, 1.0, 1.0), 3: Color(1.08, 0.92, 0.94)}
		_floor.modulate = tints.get(_layer, Color(1, 1, 1))
	# 地板永远在最底层：实体用 z_index=int(y) 做 Y 排序，上移时 y<0→z<0，
	# 若地板 z=0 会把上移的角色/敌人/弹道盖住而「消失」。
	_floor.z_index = -4000


## 动态地图视频背景：以 VideoStreamPlayer 覆盖 880×500 房间世界区域，
## 与图片背景套用相同变换（base_pos/base_scale），保证编辑器摆放和运行期渲染一致。
## 音频静音（audio_track=-1），背景音效交给 BGM；10s 片段循环播放（loop=true）。
func _add_video_floor(stream: VideoStream, base_pos: Vector2, base_scale: Vector2) -> void:
	var vp := VideoStreamPlayer.new()
	vp.name = "FloorVideo"
	vp.stream = stream
	vp.expand = true            # 视频缩放铺满 880×500 房间区域（视频 1280×720 与房间 1.76:1 几乎同比例，拉伸失真可忽略）
	vp.loop = true             # 片段播完自动循环（动态地图背景）
	vp.audio_track = -1        # 背景地图静音，避免与 BGM 叠加
	vp.set_anchors_preset(Control.PRESET_TOP_LEFT)  # 让 position/size 直接生效（Control 不被父 Node2D 的 rect 影响）
	vp.size = Vector2(W, H)
	vp.position = base_pos
	vp.scale = base_scale
	vp.z_index = -4000
	# play() 必须在节点进入场景树后调用（VideoStreamPlayer 要求 is_inside_tree()）。
	# 用 tree_entered 信号保证时序，但【必须在 add_child 之前 connect】——
	# tree_entered 在 add_child 时同步发出，connect 写在 add_child 之后会错过信号，play() 永不执行 → 背景黑屏。
	vp.tree_entered.connect(func() -> void:
		if is_instance_valid(vp):
			vp.play()
	)
	add_child(vp)


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
	# 门位置：场景 DoorHandle（target=邻居 id）优先，否则用四边默认位置
	var neigh: Array = _data.get("neighbors", [])
	for i in mini(neigh.size(), edges.size()):
		var nid: String = neigh[i]
		var dpos: Vector2 = edges[i]
		for h in _door_handles:
			if h.target == nid:
				dpos = h.position
				break
		var d := Area2D.new()
		d.name = "Door_" + nid
		d.collision_layer = 8
		d.collision_mask = 1
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(44, 44)
		cs.shape = sh
		d.add_child(cs)
		d.position = dpos
		var cb := func(b: Node):
			if b.is_in_group("player"):
				if _game != null and _game.has_method("transition_to"):
					_game.call("transition_to", nid)
		d.connect("body_entered", cb)
		add_child(d)
		# 运行时门框贴图（玩家视觉）："↑ 战斗"等方向+类型标签由场景 DoorHandle 编辑器显示，
		# 运行期不重复生成 Label（避免叠加）。
		var door_tex := load("res://assets/tiles/T-003_door_frame_open_anim.png") as Texture2D
		if door_tex != null:
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

func _room_label(rid: String) -> String:
	# 从 LevelData 全局类直接取房间类型（编辑器预览期 MapData 单例可能是 placeholder，
	# 调用其方法会崩；LevelData 为 class_name 全局类，编辑器/运行期均可安全访问）。
	var t: String = ""
	var layer: Dictionary = LevelData.get_layer(_layer)
	var rooms_d: Dictionary = layer.get("rooms", {}) as Dictionary
	if rooms_d.has(rid):
		t = (rooms_d[rid] as Dictionary).get("type", "")
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
	# 门位置：优先场景 DoorHandle，否则四边默认
	var door_pos: Vector2 = Vector2.ZERO
	for h in _door_handles:
		if h.target == target_rid:
			door_pos = h.position
			break
	var neigh: Array = _data.get("neighbors", [])
	for i in mini(neigh.size(), edges.size()):
		if str(neigh[i]) == target_rid:
			return door_pos if door_pos != Vector2.ZERO else edges[i]
	return Vector2.ZERO


## 返回本房的角色出生点（房间局部坐标）；未设置(默认 ZERO)时返回 ZERO。
## 优先读场景 SpawnPointHandle（新编辑方式），其次旧 "Spawn" 命名节点。
func spawn_point_position() -> Vector2:
	if _spawn_handles.size() > 0:
		return _spawn_handles[0].position
	var sp := get_node_or_null("Spawn") as Node2D
	if sp != null:
		return sp.position
	return Vector2.ZERO


## 玩家碰撞体半径（Player.tscn CircleShape2D radius=11）+ 5px 余量。
## 出生点安全性检测必须用碰撞体级（采样中心+8 方向），否则点级"安全"的窄缝里玩家放不下。
const _PLAYER_RADIUS := 16.0


## 无门（跨层进入下一大关起点 / 地图跳转 / 首进 / 找不到来源门）时的【安全出生点】（房间局部坐标）。
## 由 Game._swap 在「没有指回旧房的门」时调用——保证角色绝不会出生在禁区里卡死：
##   ① 优先插件 SpawnPointHandle（/ 旧 "Spawn" 节点）配置的位置（碰撞体级安全才用）；
##   ② 任意一扇门的位置（门口通常是安全通道，地图跳转到有门的房间时出生在门口最合理）；
##   ③ 预置安全区：房间底部中间 (0, H/2-60)——迷宫类铺满禁区的房间通常底部有空地；
##   ④ 以候选点为中心螺旋搜索（16px 步长、8 方向）最近的【碰撞体级】安全点；
##   ⑤ 全房间网格扫描（16px 步长）——螺旋只测 45°×8 方向，缝隙不在其上会漏，扫描必有答案。
func safe_spawn_position() -> Vector2:
	var candidate: Vector2 = spawn_point_position()
	if candidate != Vector2.ZERO and _is_spawn_safe(candidate):
		return candidate
	var door_pos := fallback_door_position()
	if door_pos != Vector2.ZERO and _is_spawn_safe(door_pos):
		return door_pos
	var fallback := Vector2(W * 0.3, H * 0.5 - 60.0)   # 房间右下偏中（明显不在中心，避免"看起来在中心"误解）
	if _is_spawn_safe(fallback):
		return fallback
	if candidate == Vector2.ZERO:
		candidate = fallback
	var max_r: int = int(max(W, H))
	for radius in range(16, max_r, 16):
		for k in 8:
			var ang := deg_to_rad(45.0 * float(k))
			var p := candidate + Vector2(cos(ang), sin(ang)) * float(radius)
			if _is_spawn_safe(p):
				return p
	var gy_max: int = int(H * 0.5 - _PLAYER_RADIUS)
	var gx_max: int = int(W * 0.5 - _PLAYER_RADIUS)
	for gy in range(-gy_max, gy_max + 1, 16):
		for gx in range(-gx_max, gx_max + 1, 16):
			var gp := Vector2(float(gx), float(gy))
			if _is_spawn_safe(gp):
				return gp
	return fallback


## 返回本房任意一扇门的位置（第一个 DoorHandle；无手柄时回退第一个邻居的默认边位置）。
## 门口通常是安全通道——地图跳转/无来源门时出生在门口比随机兜底更符合直觉。
func fallback_door_position() -> Vector2:
	if _door_handles.size() > 0:
		return _door_handles[0].position
	var neigh: Array = _data.get("neighbors", [])
	if neigh.size() > 0:
		return entry_door_position(str(neigh[0]))
	return Vector2.ZERO


## 出生点安全性校验（碰撞体级）：整个玩家圆形碰撞体（半径 _PLAYER_RADIUS）必须落在
## 房间边界内，且中心 + 8 个方向采样点全部不在任何禁区内部——保证玩家真的站得下。
func _is_spawn_safe(pos: Vector2) -> bool:
	if pos.x < -W * 0.5 + _PLAYER_RADIUS or pos.x > W * 0.5 - _PLAYER_RADIUS \
			or pos.y < -H * 0.5 + _PLAYER_RADIUS or pos.y > H * 0.5 - _PLAYER_RADIUS:
		return false
	var offs: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(_PLAYER_RADIUS, 0.0),
		Vector2(-_PLAYER_RADIUS, 0.0),
		Vector2(0.0, _PLAYER_RADIUS),
		Vector2(0.0, -_PLAYER_RADIUS),
		Vector2(_PLAYER_RADIUS * 0.7, _PLAYER_RADIUS * 0.7),
		Vector2(-_PLAYER_RADIUS * 0.7, _PLAYER_RADIUS * 0.7),
		Vector2(_PLAYER_RADIUS * 0.7, -_PLAYER_RADIUS * 0.7),
		Vector2(-_PLAYER_RADIUS * 0.7, -_PLAYER_RADIUS * 0.7),
	]
	for s in offs:
		var sp := pos + s
		for h in _blocked_handles:
			if _point_in_blocked(sp, h):
				return false
	return true


## 点是否落在单个禁区内部：把点变换到禁区局部坐标系（逆旋转）后做包含测试。
func _point_in_blocked(p: Vector2, h: BlockedHandle) -> bool:
	var local := p - h.position
	var rot := -deg_to_rad(h.rotation_deg)
	local = Vector2(
		local.x * cos(rot) - local.y * sin(rot),
		local.x * sin(rot) + local.y * cos(rot)
	)
	if h.shape_type == 0:
		# 矩形模式：AABB 包含测试
		var hw: float = h.rect_size.x * 0.5
		var hh: float = h.rect_size.y * 0.5
		return absf(local.x) <= hw and absf(local.y) <= hh
	# 多边形模式：优先读子 PolygonPointHandle，子点缺失时回退 points 备份
	var pts := h.collect_polygon_points()
	if pts.size() < 3 and h.points.size() >= 3:
		pts = h.points
	if pts.size() < 3:
		return false
	return _point_in_polygon(local, pts)


## 射线法：点是否在多边形内部（顶点为相对中心的局部坐标）。
func _point_in_polygon(p: Vector2, pts: PackedVector2Array) -> bool:
	var inside := false
	var n: int = pts.size()
	var j := n - 1
	for i in n:
		var a := pts[i]
		var b := pts[j]
		if (a.y > p.y) != (b.y > p.y):
			var x_int: float = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
			if p.x < x_int:
				inside = not inside
		j = i
	return inside


## 场景 WeaponHandle → 地面武器：位置/数量/大小取自手柄，但【武器种类进游戏随机】——
## 手柄在编辑器里显示一种武器样子作为"掉落位"预览；运行期从 8 把武器池随机抽（不重复优先），
## 保证每次进房掉落的武器组合不同。大小取手柄 display_scale，位置=手柄位置。
func _spawn_weapons() -> void:
	if _weapon_handles.size() == 0:
		return
	var pool: Array = Weapons.POOL.duplicate()
	for h in _weapon_handles:
		if pool.is_empty():
			pool = Weapons.POOL.duplicate()
		var wid: String = str(pool[randi() % pool.size()])
		pool.erase(wid)
		var pk: Node2D = WeaponPickupScript.new()
		pk.set("weapon_id", wid)
		pk.set("display_scale", h.display_scale)
		pk.position = h.position
		add_child(pk)
		if _game != null and _game.has_method("register_pickup"):
			_game.call("register_pickup", pk)


## 场景 NextDoorHandle → 下一层传送门（初始隐藏+禁用；Boss 击败后 Game 调 enable_next_door 启用）。
func _build_next_door() -> void:
	_next_doors.clear()
	for h in _next_door_handles:
		var next: int = h.next_layer if h.next_layer > 0 else _layer + 1
		var d := Area2D.new()
		d.name = "NextDoor"
		d.collision_layer = 8
		d.collision_mask = 1
		d.position = h.position
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(48, 48)
		cs.shape = sh
		d.add_child(cs)
		var cb := func(b: Node):
			if b.is_in_group("player") and _game != null and _game.has_method("_go_next_layer"):
				_game.call("_go_next_layer", next)
		d.connect("body_entered", cb)
		d.monitoring = false
		d.visible = false
		add_child(d)
		_next_doors.append(d)
		# 可见门框 + 标签（挂在传送门下，随 d 一起显示/隐藏）
		var door_tex := load("res://assets/tiles/T-003_door_frame_open_anim.png") as Texture2D
		if door_tex != null:
			var ds := door_tex.get_size()
			var dh := 96.0
			var fw := ds.x / 4.0
			var dw := dh * fw / ds.y
			var spr := Sprite2D.new()
			spr.texture = door_tex
			spr.hframes = 4
			spr.frame = 0
			spr.scale = Vector2(dw / fw, dh / ds.y)
			spr.z_index = 4
			d.add_child(spr)
		var lab := Label.new()
		lab.text = "↑ 下一层"
		lab.position = Vector2(-34, -14)
		lab.add_theme_font_size_override("font_size", 22)
		lab.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
		lab.z_index = 6
		d.add_child(lab)


## Boss 击败后启用本房所有下一层传送门（由 Game.on_boss_defeated 调用）。
func enable_next_door() -> void:
	for d in _next_doors:
		if is_instance_valid(d):
			d.monitoring = true
			d.visible = true


func _spawn_content() -> void:
	var type: String = _data.get("type", "combat")
	if type == "boss":
		var cleared: bool = GameManager.boss_cleared.get(_layer, false)
		if not cleared:
			# Boss 不再自动生成：由场景 BossHandle 决定（插件摆放，3 种可选）。
			# 每个手柄生成一个 Boss（位置=手柄位置），保留入场图/计时逻辑（数据驱动）。
			for h in _boss_handles:
				_start_boss_intro(h.boss_id(), h.position)
		return
	# 起点房(start)现在也从 enemy_placements 刷怪（满足「起始场景也能刷怪」需求）；
	# 驿站(inn)仍不刷，保持为安全休整区。
	if type == "inn":
		return
	# 拖入式敌人放置：全部由场景 EnemyHandle 定义（旧 .tres 数据体系已移除）。
	# 普通/精英房重进即刷新——玩家在房间场景里摆放的敌人每次进房都会重新出现。
	for h in _enemy_handles:
		var eid: String = h.enemy_id()
		if eid == "" or eid in Enemies.BOSS:
			continue
		var hpos: Vector2 = h.position
		_spawn_enemy(eid, hpos)
		var hed: Dictionary = Enemies.get_enemy(eid)
		if hed != null and hed.get("clone_count", 0) > 0:
			for c in int(hed["clone_count"]):
				_spawn_enemy(eid, hpos + Vector2(randf_range(-90.0, 90.0), randf_range(-90.0, 90.0)))


## 装饰性动态素材：所有房间类型（含 inn/boss）都实例化，独立于 _spawn_content 的刷怪逻辑。
## 由场景 DecorationHandle 定义；随房间销毁，不跨房叠加。
func _spawn_decorations() -> void:
	for h in _decoration_handles:
		_spawn_decoration(h.scene_path, h.position, h.scale_xy, h.rotation_deg, h.flip_h, h.flip_v)


func _spawn_decoration(path: String, pos: Vector2, scale_xy: Vector2, rot_deg: float, flip_h: bool, flip_v: bool) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("RoomManager: 装饰场景加载失败 %s" % path)
		return
	var inst := ps.instantiate() as Node2D
	if inst == null:
		return
	inst.position = pos   # 房间局部坐标（房间实例挂在锚点下，全局由锚点变换）
	inst.z_index = int(pos.y)
	# 还原编辑器里的视觉调整：缩放/旋转/翻转，保证运行期与编辑器预览一致。
	# Node2D 只有 rotation(弧度)，用 deg_to_rad 把数据里的 rotation_deg 转回。
	inst.scale = scale_xy
	inst.rotation = deg_to_rad(rot_deg)
	inst.flip_h = flip_h
	inst.flip_v = flip_v
	add_child(inst)


func _spawn_enemy(eid: String, pos: Vector2) -> void:
	var e := ENEMY.instantiate() as Node2D
	e.call("setup", eid)
	e.position = pos   # 房间局部坐标（房间挂锚点下）
	e.z_index = int(pos.y)
	# 加进本房间节点：切换房间时 _room.queue_free() 会一并销毁，避免跨房叠加
	add_child(e)


func _spawn_boss(bid: String, pos: Vector2) -> void:
	var b := load(BOSS_PATH).instantiate() as Node2D
	b.call("setup", bid)
	b.position = pos   # 房间局部坐标（房间挂锚点下；位置由场景 BossHandle 决定）
	b.z_index = int(b.position.y)
	# 加进本房间节点：随房间销毁
	add_child(b)

# Boss 房入场：先显示「入场图」(boss_intro_img，如 S_003_7)，播放入场动画（计时 boss_intro_time 秒），
# 动画结束再切换为正式地图 (scene_img，如 S_003_7_1) 并开始 boss 战。
# 仅当房间带 boss_intro_img 且未清空时生效；普通 boss 房（无该字段）intro 为空则直接出 boss。
func _start_boss_intro(bid: String, pos: Vector2) -> void:
	var intro: String = _data.get("boss_intro_img", "")
	var real: String = _data.get("scene_img", "")
	var intro_time: float = float(_data.get("boss_intro_time", 0.0))
	# 进入时先显示入场图（如 S_003_7）
	if intro != "" and _floor != null:
		_floor.texture = load(intro) as Texture2D
	if intro_time <= 0.0:
		_spawn_boss(bid, pos)
		return
	var timer := get_tree().create_timer(intro_time)
	timer.timeout.connect(func():
		if is_instance_valid(_floor) and real != "":
			_floor.texture = load(real) as Texture2D
		_spawn_boss(bid, pos)
	)


# 禁区/不可走区域：生成无形碰撞墙 + 半透明红色可视。
# 由场景 BlockedHandle 定义（支持矩形 shape_type=0 与多边形 shape_type=1；rotation_deg 任意旋转）。
func _build_blocked() -> void:
	var centers: Array[Vector2] = []
	var sizes: Array[Vector2] = []
	var pts_list: Array[PackedVector2Array] = []
	var rots: Array[float] = []
	var is_polys: Array[bool] = []
	for h in _blocked_handles:
		var hp: bool = h.shape_type == 1
		if hp:
			# 多边形模式：优先读子 PolygonPointHandle 节点位置（PS 风格拖点），回退旧 points
			var pts_from_children: PackedVector2Array = h.collect_polygon_points()
			if pts_from_children.size() >= 3:
				hp = true
				pts_list.append(pts_from_children)
			else:
				hp = h.points.size() >= 3
				pts_list.append(h.points)
		else:
			pts_list.append(PackedVector2Array())
		centers.append(h.position)
		sizes.append(h.rect_size)
		rots.append(h.rotation_deg)
		is_polys.append(hp)
	for i in centers.size():
		var center: Vector2 = centers[i]
		var size: Vector2 = sizes[i]
		var pts: PackedVector2Array = pts_list[i]
		var rot_deg: float = rots[i]
		var is_poly: bool = is_polys[i]
		var sb := StaticBody2D.new()
		sb.name = "Blocked_%d" % i
		sb.collision_layer = 16
		if is_poly:
			# 多边形碰撞：用 CollisionPolygon2D 节点直接吃局部顶点（比 PolygonShape2D 更稳，且不依赖 Shape 子类解析）。
			var cp := CollisionPolygon2D.new()
			cp.polygon = pts          # 多边形顶点为相对 center 的局部坐标
			cp.position = center
			cp.rotation = deg_to_rad(rot_deg)
			sb.add_child(cp)
		else:
			var cs := CollisionShape2D.new()
			var rsh: RectangleShape2D = RectangleShape2D.new()
			rsh.size = size
			cs.shape = rsh
			cs.position = center
			cs.rotation = deg_to_rad(rot_deg)
			sb.add_child(cs)
		add_child(sb)
		# 半透明红色可视：与碰撞形状套用同一变换(center+rotation)，所见即所得。
		var vis_pts: PackedVector2Array
		if is_poly:
			vis_pts = pts
		else:
			var hw: float = size.x / 2.0
			var hh: float = size.y / 2.0
			vis_pts = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
		var poly := Polygon2D.new()
		poly.polygon = vis_pts
		poly.color = Color(0.8, 0.2, 0.2, 0.35)
		poly.position = center
		poly.rotation = deg_to_rad(rot_deg)
		poly.z_index = -5
		add_child(poly)


# 独立运行(F6)/编辑器打开房间场景：按场景导出属性(layer/room_id)构建该真实房间（地板/墙/门/禁区/驿站/敌人）。
# 数据从 LevelData(class_name 全局类，编辑器/运行期均可安全访问)取，scene_img 由 tile_path 注入。
# 被 Game 在运行时实例化并主动 setup() 时，setup 的 _setup_done 守卫保证不重复构建。
func _ready() -> void:
	if _rid == "" and room_id != "":
		var L: Dictionary = LevelData.get_layer(layer)
		var rooms_d: Dictionary = L.get("rooms", {}) as Dictionary
		var data: Dictionary = (rooms_d.get(room_id, {}) as Dictionary).duplicate(true)
		var tp: String = LevelData.tile_path(layer, room_id)
		if tp != "":
			data["scene_img"] = tp
		setup(room_id, data, layer, get_parent(), get_tree().current_scene)
