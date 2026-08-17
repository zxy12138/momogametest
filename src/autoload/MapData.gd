# 《梦境逐影》网状地图数据（Autoload 单例）
# 房间状态：LOCKED（隐藏类型）/ REVEALED（显示类型，不可传送）/ VISITED（可传送）/ CURRENT / BOSS_CLEARED
extends Node

const LAYER = {
	1: "第一层·午夜办公室",
	2: "第二层·无尽通勤路",
	3: "第三层·深夜崩溃核心",
}

var layer_idx := 1
var rooms := {}      # room_id -> {type, pos, neighbors, enemies, boss}
var states := {}    # room_id -> 状态字符串
var perception := false   # Lv.21+ 梦境感知：锁定房间也显示类型轮廓
var merged := {}    # 合并地图："f{层}-{rid}" -> {floor, rid, type, gx, gy, state, links}
var full_map_override := false  # 地图界面按 F12 临时全开（只影响显示/可传送，不改 states，可反复开关）

## 地图布局模式：true = 手动（build_merged 直接用 LevelData.pos 映射，改 pos 即所见即所得）；
## false = 自动（层内拉伸铺满 + 三层错落 + MapUI 波浪抖动）。
## 手动模式下优先读 MapLayoutEditor 生成的地图布局资源（map_layout.tres），未配置的房间回退 LevelData.pos。
const USE_MANUAL_POS := true

var _manual_layout: MapLayoutData = null   # 可视化地图布局（MapLayoutEditor 写回），懒加载缓存


func load_layer(idx: int) -> void:
	layer_idx = idx
	var L: Dictionary = LevelData.get_layer(idx)
	if L == null:
		rooms = {}
		states = {}
		return
	rooms = L["rooms"].duplicate(true)
	# 注入 S_00 系列美术整图背景：各房间 scene_img 由 LevelData.TILES 统一驱动（取代逐房硬编码）。
	for rid in rooms.keys():
		var tp: String = LevelData.tile_path(idx, rid)
		if tp != "":
			rooms[rid]["scene_img"] = tp
	states = {}
	var start: String = LevelData.start_room(idx)
	for rid in rooms.keys():
		states[rid] = "LOCKED"
	states[start] = "CURRENT"
	# 起始房相邻直接揭示
	_reveal_neighbors(start)
	perception = GameManager.level >= 21
	# 合并地图：构建三层合一的全量视图（所有房间可见可点）
	build_merged()


func room(rid: String) -> Dictionary:
	if rooms.has(rid):
		return rooms[rid]
	return {}


func neighbors(rid: String) -> Array:
	if rooms.has(rid):
		return rooms[rid]["neighbors"]
	return []


func state(rid: String) -> String:
	if states.has(rid):
		return states[rid]
	return "LOCKED"


func is_teleportable(rid: String) -> bool:
	var s := state(rid)
	return s in ["VISITED", "CURRENT", "BOSS_CLEARED"]


func enter_room(rid: String) -> void:
	if not states.has(rid):
		return
	# 旧 CURRENT -> VISITED
	for k in states.keys():
		if states[k] == "CURRENT":
			states[k] = "VISITED"
	states[rid] = "CURRENT"
	_reveal_neighbors(rid)
	perception = GameManager.level >= 21
	# 合并地图：同步当前房间高亮（CURRENT 跟随玩家所在层/房）
	sync_merged_current_with(rid)


func mark_boss_cleared(rid: String) -> void:
	if states.has(rid):
		states[rid] = "BOSS_CLEARED"


func _reveal_neighbors(rid: String) -> void:
	if not rooms.has(rid):
		return
	for n in rooms[rid]["neighbors"]:
		if states.has(n) and states[n] == "LOCKED":
			states[n] = "REVEALED"

# ============ 合并地图（三层合一的全量全局视图） ============
# 键方案："f{层}-{rid}"（如 "f1-r1"）。gx/gy 归一化 [0,1]；
# 每层占地图宽度 1/3（左/中/右三栏），层内房间按各自 pos 映射到所在栏。
func build_merged() -> void:
	merged.clear()
	var keys: Array = LevelData.LAYERS.keys()
	keys.sort()
	var n: int = keys.size()

	# 趟 0：先收集每层的 pos 范围，用于把层内房间「归一化铺满」所在栏（避免 7 房挤在一起按钮重叠）
	var range_of: Dictionary = {}   # floor_i -> {minx,maxx,miny,maxy}
	for fi in range(n):
		var floor_i: int = keys[fi] as int
		var layer: Dictionary = LevelData.get_layer(floor_i)
		if layer == null:
			continue
		var minx := 1e9; var maxx := -1e9; var miny := 1e9; var maxy := -1e9
		for rid in (layer.get("rooms", {}) as Dictionary).keys():
			var pos: Array = (layer["rooms"][rid] as Dictionary).get("pos", [0.0, 0.0])
			var px: float = pos[0] if pos.size() > 0 else 0.0
			var py: float = pos[1] if pos.size() > 1 else 0.0
			minx = mini(minx, px); maxx = maxi(maxx, px)
			miny = mini(miny, py); maxy = maxi(maxy, py)
		if maxx > minx + 0.0001 and maxy > miny + 0.0001:
			range_of[floor_i] = {"minx": minx, "maxx": maxx, "miny": miny, "maxy": maxy}

	# 趟 1：建立所有层的所有节点，并记录每层 boss 房 rid
	var boss_of: Dictionary = {}   # floor_i -> boss rid
	# 手动模式开关：true = gx/gy 直接用 LevelData.pos 映射（用户改 pos 即所见即所得，自己排布）；
	# false = 自动拉伸铺满 + 三层错落（原逻辑，交给程序排）。
	# 地图分三栏：第一层占左 1/3、第二层中、第三层右；层内 x=0 左边界、x=1 右边界；y=0 顶部、y=1 底部。
	var col_start: float = 0.0
	var col_w: float = 1.0 / float(n)
	# 自动模式用：三层错落布局参数（每层中心 x 参差 + 层宽略收 + 层 y 偏移）
	var layer_cx: Array[float] = [0.165, 0.50, 0.835]
	var layer_w: float = 0.34
	var layer_yoff: Array[float] = [0.0, 0.055, -0.04]
	for fi in range(n):
		var floor_i: int = keys[fi] as int
		var layer: Dictionary = LevelData.get_layer(floor_i)
		if layer == null:
			continue
		var rooms_l: Dictionary = layer.get("rooms", {}) as Dictionary
		col_start = float(fi) / float(n)
		var cx: float = layer_cx[fi] if fi < layer_cx.size() else 0.5
		var yoff: float = layer_yoff[fi] if fi < layer_yoff.size() else 0.0
		# 自动模式用：层内归一化拉伸
		var rg: Dictionary = range_of.get(floor_i, {})
		var span_x: float = float(rg.get("maxx", 1.0) - rg.get("minx", 0.0))
		var span_y: float = float(rg.get("maxy", 1.0) - rg.get("miny", 0.0))
		for rid in rooms_l.keys():
			var d: Dictionary = rooms_l[rid] as Dictionary
			var pos: Array = d.get("pos", [0.0, 0.0])
			var px: float = pos[0] if pos.size() > 0 else 0.0
			var py: float = pos[1] if pos.size() > 1 else 0.0
			var gx_val: float
			var gy_val: float
			if USE_MANUAL_POS:
				# 手动模式：优先用可视化编辑器(map_layout.tres)位置，未配置回退 LevelData.pos
				var mp: Variant = _manual_pos(floor_i, rid)
				var ppos: Vector2 = (mp as Vector2) if mp is Vector2 else Vector2(px, py)
				gx_val = clampf(col_start + ppos.x * col_w, 0.01, 0.99)
				gy_val = clampf(ppos.y, 0.03, 0.97)
			else:
				var nx: float = 0.5 if span_x <= 0.0001 else (px - float(rg.get("minx", 0.0))) / span_x
				var ny: float = 0.5 if span_y <= 0.0001 else (py - float(rg.get("miny", 0.0))) / span_y
				gx_val = clampf(cx - layer_w / 2.0 + (0.03 + 0.94 * nx) * layer_w, 0.005, 0.995)
				gy_val = clampf(0.05 + 0.90 * ny + yoff, 0.02, 0.98)
			var node: Dictionary = {
				"floor": floor_i,
				"rid": rid,
				"type": d.get("type", ""),
				"gx": gx_val,
				"gy": gy_val,
				# 初始状态按真实进度：当前层用 states，其他层按通关判定；MapUI 显示时仍走 show_state_for 实时取。
				"state": show_state_for(floor_i, rid),
				"links": [],
			}
			merged["f%d-%s" % [floor_i, rid]] = node
			if node["type"] == "boss":
				boss_of[floor_i] = rid

	# 趟 2：层内连线（所有节点已建好，_merged_add_link 内部仍做防御性 has 校验）
	for fi in range(n):
		var floor_i: int = keys[fi] as int
		var layer: Dictionary = LevelData.get_layer(floor_i)
		if layer == null:
			continue
		var rooms_l: Dictionary = layer.get("rooms", {}) as Dictionary
		for rid in rooms_l.keys():
			var d: Dictionary = rooms_l[rid] as Dictionary
			var from_key: String = "f%d-%s" % [floor_i, rid]
			for nb in d.get("neighbors", []):
				var nb_key: String = "f%d-%s" % [floor_i, nb]
				_merged_add_link(from_key, nb_key)

	# 趟 3：跨层连线（boss(f) -> start(f+1)=r1）。所有节点已建好，目标 key 必存在，连线必能加上
	for fi in range(n - 1):
		var floor_i: int = keys[fi] as int
		var next_floor: int = keys[fi + 1] as int
		if boss_of.has(floor_i):
			var boss_rid: String = boss_of.get(floor_i, "") as String
			var boss_key: String = "f%d-%s" % [floor_i, boss_rid]
			var target_key: String = "f%d-%s" % [next_floor, LevelData.start_room(next_floor)]
			_merged_add_link(boss_key, target_key)


func _merged_add_link(from_key: String, to_key: String) -> void:
	if not merged.has(from_key) or not merged.has(to_key):
		return
	var node: Dictionary = merged[from_key]
	var links: Array = node.get("links", [])
	if not links.has(to_key):
		links.append(to_key)
		node["links"] = links
		merged[from_key] = node


func merged_teleportable(key: String) -> bool:
	if not merged.has(key):
		return false
	var node: Dictionary = merged[key]
	var st: String = show_state_for(node.get("floor", 1), String(node.get("rid", "")))
	return st in ["VISITED", "CURRENT", "BOSS_CLEARED"] or full_map_override


## 合并地图里某房间的「显示状态」：F12 全开时除「当前所在房间」保持 CURRENT 外一律 VISITED；
## 当前层用 states 实时进度；其他层按是否通关（boss_cleared）判定，否则 LOCKED。
## MapUI 画图与可传送判断都走这里，避免 merged 快照状态过期。
func show_state_for(floor_i: int, rid: String) -> String:
	if full_map_override:
		if floor_i == layer_idx and rid == GameManager.current_room:
			return "CURRENT"
		return "VISITED"
	if floor_i == layer_idx:
		return state(rid)
	if GameManager.boss_cleared.get(floor_i, false):
		return "VISITED"
	return "LOCKED"


## 节点是否要在地图上「画出来」：F12 全开全可见；当前层除 LOCKED 外都画（含 REVEALED 邻居问号）；
## 其他层只在通关（boss_cleared）后画整层。
## 「下一个能看到才显示」语义：未探明 LOCKED 完全隐藏节点和引线。
func is_visible(floor_i: int, rid: String) -> bool:
	if full_map_override:
		return true
	if floor_i == layer_idx:
		return state(rid) != "LOCKED"
	return GameManager.boss_cleared.get(floor_i, false)


## 取可视化布局（map_layout.tres）中某房间的归一化位置；文件不存在或未配置该房返回 null。
func _manual_pos(floor_i: int, rid: String) -> Variant:
	if _manual_layout == null:
		var p := "res://src/data/map_layout.tres"
		# 用 ResourceLoader.exists 而非 FileAccess.file_exists——后者对打包后 pck 里的资源返回 false，
		# 会导致自定义地图布局（map_layout.tres）在导出后失效、回退默认布局。
		_manual_layout = (load(p) as MapLayoutData) if ResourceLoader.exists(p) else MapLayoutData.new()
	return _manual_layout.positions.get("f%d-%s" % [floor_i, rid], null)


func current_composite() -> String:
	return "f%d-%s" % [GameManager.layer_index, GameManager.current_room]


# 把指定房间在合并地图中标为 CURRENT，旧的 CURRENT 退回 VISITED。
func sync_merged_current_with(rid: String) -> void:
	if merged.is_empty():
		build_merged()
	var cur: String = "f%d-%s" % [GameManager.layer_index, rid]
	for k in merged.keys():
		var node: Dictionary = merged[k]
		if node.get("state", "") == "CURRENT":
			node["state"] = "VISITED"
			merged[k] = node
	if merged.has(cur):
		var node2: Dictionary = merged[cur]
		node2["state"] = "CURRENT"
		merged[cur] = node2
