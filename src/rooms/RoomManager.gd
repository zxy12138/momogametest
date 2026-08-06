# 房间 + RoomManager：地板/墙/门/驿站 + 按数据刷怪（离开重进即「魂式」刷新）
@tool
extends Node2D
class_name RoomManager

const ENEMY = preload("res://src/enemies/Enemy.tscn")
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
var _layout: RoomLayout
var _setup_done := false  # 防重复构建：房间场景 _ready 自建后，Game 再调 setup 直接返回


func setup(rid: String, data: Dictionary, floor_idx: int, entities: Node, game: Node) -> void:
	if _setup_done:
		return
	_setup_done = true
	_rid = rid
	_data = data
	_layer = floor_idx
	_entities = entities
	_game = game
	_layout = _load_layout()
	_build_floor()
	_build_walls()
	_build_doors()
	_build_blocked()
	if _data.get("type", "") == "inn":
		_build_inn()
	# 编辑器预览只构建静态骨架（地板/墙/门/禁区/驿站）：避免刷怪把动态节点写进场景文件，
	# 也避免 @tool 下 GameManager(placeholder) 被调用崩溃。运行期(F5/F6)才刷怪/装饰。
	if not Engine.is_editor_hint():
		_spawn_content()
		_spawn_decorations()


func _load_layout() -> RoomLayout:
	# 按 层+rid 读取该房的布局 .tres；不存在则退回空布局（全用默认/随机）。
	var path := "res://src/rooms/layouts/%d_%s.tres" % [_layer, _rid]
	if FileAccess.file_exists(path):
		return load(path) as RoomLayout
	return RoomLayout.new()


func _build_floor() -> void:
	_floor = get_node_or_null("Floor") as TextureRect
	if _floor == null:
		# 防御：场景缺少 Floor 子节点时自建（生成的房间场景缺 Floor 会崩；此处兜底）
		_floor = TextureRect.new()
		_floor.name = "Floor"
		add_child(_floor)
	var img: String = _data.get("scene_img", "")
	# 背景基准变换（来自 RoomLayout 的 bg_offset/bg_scale 用于对齐美术整图；缺省 0/1 等同原行为）。
	# 视频与图片两套背景套用同一变换，确保编辑器摆放与运行期渲染完全一致。
	var base_pos := Vector2(-W / 2, -H / 2) + _layout.bg_offset
	var base_scale := Vector2(_layout.bg_scale, _layout.bg_scale)
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
	# 起点房(start)现在也从 enemy_placements 刷怪（满足「起始场景也能刷怪」需求）；
	# 驿站(inn)仍不刷，保持为安全休整区。
	if type == "inn":
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


## 装饰性动态素材：所有房间类型（含 inn/boss）都实例化，独立于 _spawn_content 的刷怪逻辑。
## 数据来自 RoomLayout.decorations（编辑器里从序列帧插件拖入生成）；随房间销毁，不跨房叠加。
func _spawn_decorations() -> void:
	for def in _layout.decorations:
		if def.scene_path == "" or not ResourceLoader.exists(def.scene_path):
			continue
		var ps := load(def.scene_path) as PackedScene
		if ps == null:
			push_error("RoomManager: 装饰场景加载失败 %s" % def.scene_path)
			continue
		var inst := ps.instantiate() as Node2D
		if inst == null:
			continue
		inst.position = def.pos   # 房间局部坐标（房间实例挂在锚点下，全局由锚点变换）
		inst.z_index = int(def.pos.y)
		# 还原编辑器里的视觉调整：缩放/旋转/翻转，保证运行期与编辑器预览一致。
		# Node2D 只有 rotation(弧度)，用 deg_to_rad 把数据里的 rotation_deg 转回。
		inst.scale = def.scale_xy
		inst.rotation = deg_to_rad(def.rotation_deg)
		inst.flip_h = def.flip_h
		inst.flip_v = def.flip_v
		add_child(inst)


func _spawn_enemy(eid: String, pos: Vector2) -> void:
	var e := ENEMY.instantiate() as Node2D
	e.call("setup", eid)
	e.position = pos   # 房间局部坐标（房间挂锚点下）
	e.z_index = int(pos.y)
	# 加进本房间节点：切换房间时 _room.queue_free() 会一并销毁，避免跨房叠加
	add_child(e)


func _spawn_boss(bid: String) -> void:
	var b := load(BOSS_PATH).instantiate() as Node2D
	b.call("setup", bid)
	b.position = Vector2(0, -60)   # 房间局部坐标（房间挂锚点下）
	b.z_index = int(b.position.y)
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
# 支持矩形(shape_type=0)与多边形(shape_type=1)；rotation_deg 让形状任意旋转对齐倾斜障碍。
func _build_blocked() -> void:
	for i in _layout.blocked.size():
		var rd: RectDef = _layout.blocked[i]
		var is_poly: bool = (rd.shape_type == 1 and rd.points.size() >= 3)
		var sb := StaticBody2D.new()
		sb.name = "Blocked_%d" % i
		sb.collision_layer = 16
		if is_poly:
			# 多边形碰撞：用 CollisionPolygon2D 节点直接吃局部顶点（比 PolygonShape2D 更稳，且不依赖 Shape 子类解析）。
			var cp := CollisionPolygon2D.new()
			cp.polygon = rd.points          # 多边形顶点为相对 center 的局部坐标
			cp.position = rd.center
			cp.rotation = deg_to_rad(rd.rotation_deg)
			sb.add_child(cp)
		else:
			var cs := CollisionShape2D.new()
			var rsh: RectangleShape2D = RectangleShape2D.new()
			rsh.size = rd.size
			cs.shape = rsh
			cs.position = rd.center
			cs.rotation = deg_to_rad(rd.rotation_deg)
			sb.add_child(cs)
		add_child(sb)
		# 半透明红色可视：与碰撞形状套用同一变换(center+rotation)，所见即所得。
		var pts: PackedVector2Array
		if is_poly:
			pts = rd.points
		else:
			var hw: float = rd.size.x / 2.0
			var hh: float = rd.size.y / 2.0
			pts = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.color = Color(0.8, 0.2, 0.2, 0.35)
		poly.position = rd.center
		poly.rotation = deg_to_rad(rd.rotation_deg)
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
		return
	# 旧版示例预览：Room.tscn 无导出配置时的兜底
	if Engine.is_editor_hint() and _rid == "" and get_parent() == null:
		var data2 := {"type": "combat", "neighbors": ["r2", "r3"], "enemies": [["overtime_ghost", 1]]}
		setup("preview", data2, 1, get_parent(), get_tree().current_scene)
