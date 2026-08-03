# 《梦境逐影》关卡（网状房间地图）数据
# 每层 = 一张房间网。房间类型：start / combat / elite / inn / boss
# pos = 归一化坐标 [x,y]（0..1），MapData 会缩放到地图画布。
# inn（梦境驿站）：进入可 Lv.4 换武器、Lv.8 升阶。
# 单层 7 房（按流程图 r1→r2→r3/r4→r5→r6→r7 线性排列）：
#   r1 起点 → r2 战斗1 → r3 战斗2 / r4 战斗3（平行分支，都汇入 r5）
#                     → r5 精英 → r6 驿站 → r7 BOSS
class_name LevelData

const BGM = {
	1: "res://assets/audio/bgm/bgm_1.ogg",
	2: "res://assets/audio/bgm/bgm_2.ogg",
	3: "res://assets/audio/bgm/bgm_3.ogg",
}

const LAYERS = {
	1: {
		name = "第一层·午夜办公室",
		bgm = 1,
		rooms = {
			"r1": {type="start", pos=[0.05,0.50], neighbors=["r2"], enemies=[]},
			"r2": {type="combat", pos=[0.20,0.50], neighbors=["r1","r3","r4"], enemies=[["overtime_ghost",3],["printer",1]]},
			"r3": {type="combat", pos=[0.38,0.25], neighbors=["r2","r5"], enemies=[["kpi",2],["meeting",2],["phone",1]]},
			"r4": {type="combat", pos=[0.38,0.75], neighbors=["r2","r5"], enemies=[["overtime_ghost",2],["kpi",2],["phone",2]]},
			"r5": {type="elite", pos=[0.58,0.50], neighbors=["r3","r4","r6"], enemies=[["overtime_ghost",3],["printer",2],["meeting",3]]},
			"r6": {type="inn", pos=[0.78,0.50], neighbors=["r5","r7"], enemies=[]},
			"r7": {type="boss", pos=[0.95,0.55], neighbors=["r6"], enemies=[], boss="b_director"},
		}
	},
	2: {
		name = "第二层·无尽通勤路",
		bgm = 2,
		rooms = {
			"r1": {type="start", pos=[0.05,0.50], neighbors=["r2"], enemies=[]},
			"r2": {type="combat", pos=[0.20,0.50], neighbors=["r1","r3","r4"], enemies=[["commuter",3],["rider",1]]},
			"r3": {type="combat", pos=[0.38,0.25], neighbors=["r2","r5"], enemies=[["revolving",2],["escalator",1],["package",1]]},
			"r4": {type="combat", pos=[0.38,0.75], neighbors=["r2","r5"], enemies=[["commuter",2],["revolving",2],["package",2]]},
			"r5": {type="elite", pos=[0.58,0.50], neighbors=["r3","r4","r6"], enemies=[["commuter",3],["rider",2],["revolving",2]]},
			"r6": {type="inn", pos=[0.78,0.50], neighbors=["r5","r7"], enemies=[]},
			"r7": {type="boss", pos=[0.95,0.55], neighbors=["r6"], enemies=[], boss="b_train"},
		}
	},
	3: {
		name = "第三层·深夜崩溃核心",
		bgm = 3,
		rooms = {
			"r0": {type="start", pos=[0.0,0.50], neighbors=["r1"], enemies=[]},
			"r1": {type="combat", pos=[0.12,0.50], neighbors=["r0","r2"], enemies=[]},
			"r2": {type="combat", pos=[0.20,0.50], neighbors=["r1","r3","r4"], enemies=[["message",3],["rejected",2],["heart_beat",1]]},
			"r3": {type="combat", pos=[0.38,0.25], neighbors=["r2","r5"], enemies=[["overdue",1],["rejected",2],["message",2]]},
			"r4": {type="combat", pos=[0.38,0.75], neighbors=["r2","r5"], enemies=[["message",2],["overdue",2],["rejected",2]]},
			"r5": {type="elite", pos=[0.58,0.50], neighbors=["r3","r4","r6"], enemies=[["elite_996",1],["heart_beat",2],["overdue",2]]},
			"r6": {type="inn", pos=[0.78,0.50], neighbors=["r5","r7"], enemies=[]},
			"r7": {type="boss", pos=[0.95,0.55], neighbors=["r6"], enemies=[], boss="b_fear", boss_intro_img="res://assets/tiles/S_003_7.png", boss_intro_time=2.5},
		}
	}
}

# S_00 系列美术整图背景：键规则 "S_00{层}_{房}"。
# 房="3or4"/"3ro4" 表示 r3 与 r4 平行分支共用一张图（第三关文件名写作 3or4，第二关为 3ro4——以实际文件为准）。
# 该表为各房间背景的唯一来源；MapData.load_layer 会据此写入 room 的 scene_img，RoomManager 直接取用。
const TILES = {
	1: {"r1":"S_001_1", "r2":"S_001_2", "r3":"S_001_3or4", "r4":"S_001_3or4", "r5":"S_001_5", "r6":"S_001_6", "r7":"S_001_7"},
	2: {"r1":"S_002_1", "r2":"S_002_2", "r3":"S_002_3ro4", "r4":"S_002_3ro4", "r5":"S_002_5", "r6":"S_002_6", "r7":"S_002_7"},
	3: {"r0":"S_003_0", "r1":"S_003_1", "r2":"S_003_2", "r3":"S_003_3or4", "r4":"S_003_3or4", "r5":"S_003_5", "r6":"S_003_6", "r7":"S_003_7_1"},
}

static func tile_path(floor_idx, rid) -> String:
	var layer_tiles: Dictionary = TILES.get(floor_idx, {})
	var name: String = layer_tiles.get(rid, "")
	if name == "":
		return ""
	return "res://assets/tiles/" + name + ".png"

## 返回某层的「起点房」rid（type=="start"）。第三层起点为 r0（新增），第一/二层仍为 r1。
## Game 的跨层跳转与 starter 武器生成依赖此函数，避免硬编码 r1。
static func start_room(idx) -> String:
	var L: Dictionary = get_layer(idx)
	if L == null:
		return "r1"
	for rid in L["rooms"].keys():
		if L["rooms"][rid].get("type", "") == "start":
			return rid
	return "r1"

static func get_layer(idx):
	return LAYERS.get(idx, null)

static func room_count(idx):
	var L: Dictionary = get_layer(idx)
	if L == null: return 0
	return L["rooms"].size()