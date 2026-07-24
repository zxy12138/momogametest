# 《梦境逐影》关卡（网状房间地图）数据
# 每层 = 一张房间网。房间类型：start / combat / elite / inn / boss
# pos = 归一化坐标 [x,y]（0..1），MapData 会缩放到地图画布。
# inn（梦境驿站）：进入可 Lv.4 换武器、Lv.8 升阶。
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
			"r1": {type="start", pos=[0.15,0.50], neighbors=["r2","r3"], enemies=[]},
			# TEST: scene_img 为 v4.0 预制整图试用键，待美术整图就绪后由正式流程接管并删除此键
			"r2": {type="combat", pos=[0.40,0.25], neighbors=["r1","r4","r5"], enemies=[["overtime_ghost",3],["printer",1]], scene_img="res://assets/tiles/changjing1.png"},
			"r3": {type="combat", pos=[0.40,0.75], neighbors=["r1","r4"], enemies=[["kpi",2],["meeting",2],["phone",1]], scene_img="res://assets/tiles/changjing1.png"},
			"r4": {type="inn", pos=[0.62,0.50], neighbors=["r2","r3","r5"], enemies=[]},
			"r5": {type="elite", pos=[0.82,0.30], neighbors=["r2","r4","r6"], enemies=[["overtime_ghost",2],["printer",2],["meeting",2]]},
			"r6": {type="boss", pos=[0.90,0.62], neighbors=["r5"], enemies=[], boss="b_director"},
		}
	},
	2: {
		name = "第二层·无尽通勤路",
		bgm = 2,
		rooms = {
			"r1": {type="start", pos=[0.15,0.50], neighbors=["r2","r3"], enemies=[]},
			"r2": {type="combat", pos=[0.40,0.22], neighbors=["r1","r4","r5"], enemies=[["commuter",3],["rider",1]]},
			"r3": {type="combat", pos=[0.40,0.78], neighbors=["r1","r4"], enemies=[["revolving",2],["escalator",1],["package",1]]},
			"r4": {type="inn", pos=[0.62,0.50], neighbors=["r2","r3","r5"], enemies=[]},
			"r5": {type="elite", pos=[0.82,0.32], neighbors=["r2","r4","r6"], enemies=[["commuter",2],["rider",2],["revolving",1]]},
			"r6": {type="boss", pos=[0.90,0.60], neighbors=["r5"], enemies=[], boss="b_train"},
		}
	},
	3: {
		name = "第三层·深夜崩溃核心",
		bgm = 3,
		rooms = {
			"r1": {type="start", pos=[0.15,0.50], neighbors=["r2","r3"], enemies=[]},
			"r2": {type="combat", pos=[0.40,0.22], neighbors=["r1","r4","r5"], enemies=[["message",3],["rejected",2],["heart_beat",1]]},
			"r3": {type="combat", pos=[0.40,0.78], neighbors=["r1","r4"], enemies=[["overdue",1],["rejected",2],["message",2]]},
			"r4": {type="inn", pos=[0.62,0.50], neighbors=["r2","r3","r5"], enemies=[]},
			"r5": {type="elite", pos=[0.82,0.32], neighbors=["r2","r4","r6"], enemies=[["elite_996",1],["heart_beat",2],["overdue",1]]},
			"r6": {type="boss", pos=[0.90,0.60], neighbors=["r5"], enemies=[], boss="b_fear"},
		}
	}
}

static func get_layer(idx):
	return LAYERS.get(idx, null)

static func room_count(idx):
	var L: Dictionary = get_layer(idx)
	if L == null: return 0
	return L["rooms"].size()
