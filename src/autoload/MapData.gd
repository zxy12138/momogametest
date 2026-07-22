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


func load_layer(idx: int) -> void:
	layer_idx = idx
	var L: Dictionary = LevelData.get_layer(idx)
	if L == null:
		rooms = {}
		states = {}
		return
	rooms = L["rooms"].duplicate(true)
	states = {}
	for rid in rooms.keys():
		states[rid] = "LOCKED"
	states["r1"] = "CURRENT"
	# 起始房相邻直接揭示
	_reveal_neighbors("r1")
	perception = GameManager.level >= 21
	# 开发者模式：揭示当前层所有房间（地图全显示、可任意传送）
	if GameManager.dev_mode:
		for rid in rooms.keys():
			states[rid] = "VISITED"
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

# 开发者模式：把当前层所有房间置为可传送（地图全显示）
func reveal_all() -> void:
	for rid in rooms.keys():
		states[rid] = "VISITED"


# ============ 合并地图（三层合一的全量全局视图） ============
# 键方案："f{层}-{rid}"（如 "f1-r1"）。gx/gy 归一化 [0,1]；
# 每层占地图宽度 1/3（左/中/右三栏），层内房间按各自 pos 映射到所在栏。
func build_merged() -> void:
	merged.clear()
	var keys: Array = LevelData.LAYERS.keys()
	keys.sort()
	var n: int = keys.size()

	# 趟 1：建立所有层的所有节点（初始全 VISITED：可见且可点），并记录每层 boss 房 rid
	var boss_of: Dictionary = {}   # floor_i -> boss rid
	for fi in range(n):
		var floor_i: int = keys[fi] as int
		var col_start: float = float(fi) / float(n)
		var col_w: float = 1.0 / float(n)
		var layer: Dictionary = LevelData.get_layer(floor_i)
		if layer == null:
			continue
		var rooms_l: Dictionary = layer.get("rooms", {}) as Dictionary
		for rid in rooms_l.keys():
			var d: Dictionary = rooms_l[rid] as Dictionary
			var pos: Array = d.get("pos", [0.0, 0.0])
			var px: float = pos[0] if pos.size() > 0 else 0.0
			var py: float = pos[1] if pos.size() > 1 else 0.0
			var node: Dictionary = {
				"floor": floor_i,
				"rid": rid,
				"type": d.get("type", ""),
				"gx": col_start + px * col_w,
				"gy": py,
				"state": "VISITED",
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
			var target_key: String = "f%d-r1" % next_floor
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
	return merged.has(key)


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
