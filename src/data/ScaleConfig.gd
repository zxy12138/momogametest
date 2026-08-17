# 《梦境逐影》全局类型级体型/碰撞缩放配置（2026-08-17）
# 用途：在编辑器插件面板里，按「类型」统一调整所有同类型小怪/Boss 的体型、碰撞范围、
#       碰撞形状（矩形/三角/圆/多边形）与碰撞中心偏移，而不是逐实例调整单个手柄。
#       例：把 alarm_clock 的体型调到 1.5，场景里所有闹钟怪都变大；把蜘蛛怪改成三角形碰撞。
# 数据：res://src/data/enemy_scale.json
#   { "enemies": { "<id>": {"scale":1.0, "collision":1.0, "shape":0, "w":50, "h":50, "ox":0, "oy":4, "poly":[[x,y],...]}, ... },
#     "bosses":  { "<id>": { ... 同结构 ... }, ... } }
# 运行时（导出游戏）只读；编辑时插件可写（本地 res:// 文件系统）。
# class_name 全局类：编辑器插件（@tool）与运行期 RoomManager 都能直接访问，无需 autoload。
class_name ScaleConfig

const PATH := "res://src/data/enemy_scale.json"

const GROUP_ENEMY := "enemies"
const GROUP_BOSS := "bosses"

## 碰撞形状：0=矩形 / 1=三角形（等腰，顶点朝上）/ 2=圆形 / 3=自定义多边形。
const SHAPE_RECT := 0
const SHAPE_TRI := 1
const SHAPE_CIRCLE := 2
const SHAPE_POLY := 3


## 读整个配置（无缓存，每次读文件，编辑器实时改动即时生效）。
static func _load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	if txt.strip_edges() == "":
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}


## 写整个配置（编辑器插件调用；本地 res:// 可写）。
static func _save(data: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("[ScaleConfig] 无法写入 %s" % PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


## 读取某组某类型的「任意类型」值（缺省返回 default）。
## 用于 w/h/ox/oy（缺省回落 CB 基础值）与 poly（数组）等非 float 字段。
static func _get_any(group: String, id: String, key: String, default: Variant) -> Variant:
	var d := _load()
	var g: Dictionary = d.get(group, {})
	var e: Dictionary = g.get(id, {})
	if e.has(key):
		return e[key]
	return default


## 写入某组某类型的「任意类型」值（float/int/Array 皆可）并保存。
static func _set_val_any(group: String, id: String, key: String, v: Variant) -> void:
	var d := _load()
	var g: Dictionary = d.get(group, {})
	if not (g is Dictionary):
		g = {}
	var e: Dictionary = g.get(id, {})
	if not (e is Dictionary):
		e = {}
	e[key] = v
	g[id] = e
	d[group] = g
	_save(d)


## 读取某组（enemies/bosses）某类型某键的缩放值（缺省 1.0）。
static func _get_val(group: String, id: String, key: String) -> float:
	return float(_get_any(group, id, key, 1.0))


## 写入某组某类型某键的缩放值并保存。
static func _set_val(group: String, id: String, key: String, v: float) -> void:
	_set_val_any(group, id, key, v)


## —— 形状 / 尺寸 / 中心点 / 多边形（与 CB 基础值协同；缺省回落 CB）——
## w/h/ox/oy 的缺省由调用方传入 CB 基础值（ScaleConfig 不持有 CB，保持解耦）。

static func get_enemy_shape(id: String, default: int = SHAPE_RECT) -> int:
	return int(_get_any(GROUP_ENEMY, id, "shape", default))

static func get_enemy_w(id: String, default: float) -> float:
	return float(_get_any(GROUP_ENEMY, id, "w", default))

static func get_enemy_h(id: String, default: float) -> float:
	return float(_get_any(GROUP_ENEMY, id, "h", default))

static func get_enemy_ox(id: String, default: float) -> float:
	return float(_get_any(GROUP_ENEMY, id, "ox", default))

static func get_enemy_oy(id: String, default: float) -> float:
	return float(_get_any(GROUP_ENEMY, id, "oy", default))

## 读取多边形顶点（世界单位，局部坐标，中心在原点）；缺省空数组（无顶点）。
static func get_enemy_poly(id: String) -> PackedVector2Array:
	var raw: Variant = _get_any(GROUP_ENEMY, id, "poly", [])
	var out := PackedVector2Array()
	if raw is Array:
		for v in raw:
			if v is Vector2:
				out.append(v)
			elif v is Array and v.size() >= 2:
				out.append(Vector2(float(v[0]), float(v[1])))
	return out


static func set_enemy_shape(id: String, v: int) -> void:
	_set_val_any(GROUP_ENEMY, id, "shape", v)

static func set_enemy_w(id: String, v: float) -> void:
	_set_val_any(GROUP_ENEMY, id, "w", v)

static func set_enemy_h(id: String, v: float) -> void:
	_set_val_any(GROUP_ENEMY, id, "h", v)

static func set_enemy_ox(id: String, v: float) -> void:
	_set_val_any(GROUP_ENEMY, id, "ox", v)

static func set_enemy_oy(id: String, v: float) -> void:
	_set_val_any(GROUP_ENEMY, id, "oy", v)

## 写入多边形顶点（局部坐标，中心在原点）。
static func set_enemy_poly(id: String, pts: PackedVector2Array) -> void:
	var arr: Array = []
	for v in pts:
		arr.append([v.x, v.y])
	_set_val_any(GROUP_ENEMY, id, "poly", arr)


## —— Boss 同结构 ——

static func get_boss_shape(id: String, default: int = SHAPE_RECT) -> int:
	return int(_get_any(GROUP_BOSS, id, "shape", default))

static func get_boss_w(id: String, default: float) -> float:
	return float(_get_any(GROUP_BOSS, id, "w", default))

static func get_boss_h(id: String, default: float) -> float:
	return float(_get_any(GROUP_BOSS, id, "h", default))

static func get_boss_ox(id: String, default: float) -> float:
	return float(_get_any(GROUP_BOSS, id, "ox", default))

static func get_boss_oy(id: String, default: float) -> float:
	return float(_get_any(GROUP_BOSS, id, "oy", default))

static func get_boss_poly(id: String) -> PackedVector2Array:
	var raw: Variant = _get_any(GROUP_BOSS, id, "poly", [])
	var out := PackedVector2Array()
	if raw is Array:
		for v in raw:
			if v is Vector2:
				out.append(v)
			elif v is Array and v.size() >= 2:
				out.append(Vector2(float(v[0]), float(v[1])))
	return out


static func set_boss_shape(id: String, v: int) -> void:
	_set_val_any(GROUP_BOSS, id, "shape", v)

static func set_boss_w(id: String, v: float) -> void:
	_set_val_any(GROUP_BOSS, id, "w", v)

static func set_boss_h(id: String, v: float) -> void:
	_set_val_any(GROUP_BOSS, id, "h", v)

static func set_boss_ox(id: String, v: float) -> void:
	_set_val_any(GROUP_BOSS, id, "ox", v)

static func set_boss_oy(id: String, v: float) -> void:
	_set_val_any(GROUP_BOSS, id, "oy", v)

static func set_boss_poly(id: String, pts: PackedVector2Array) -> void:
	var arr: Array = []
	for v in pts:
		arr.append([v.x, v.y])
	_set_val_any(GROUP_BOSS, id, "poly", arr)


## —— 小怪 体型/碰撞倍率（保留原接口）——
static func get_enemy_scale(id: String) -> float:
	return _get_val(GROUP_ENEMY, id, "scale")

static func get_enemy_collision(id: String) -> float:
	return _get_val(GROUP_ENEMY, id, "collision")

static func set_enemy_scale(id: String, v: float) -> void:
	_set_val(GROUP_ENEMY, id, "scale", v)

static func set_enemy_collision(id: String, v: float) -> void:
	_set_val(GROUP_ENEMY, id, "collision", v)


## —— Boss 体型/碰撞倍率（保留原接口）——
static func get_boss_scale(id: String) -> float:
	return _get_val(GROUP_BOSS, id, "scale")

static func get_boss_collision(id: String) -> float:
	return _get_val(GROUP_BOSS, id, "collision")

static func set_boss_scale(id: String, v: float) -> void:
	_set_val(GROUP_BOSS, id, "scale", v)

static func set_boss_collision(id: String, v: float) -> void:
	_set_val(GROUP_BOSS, id, "collision", v)
