# 《梦境逐影》存档管理器（多槽位：user://save_1.json ~ save_3.json）
# 自动存档点：击败每层 Boss 后（默认槽 1）。手动存档：ESC 菜单/标题界面可选槽 1/2/3。
# 记录等级 / 武器 / 地图解锁进度 + 存档时间戳。
extends Node

const SLOTS := 3

func _path(slot: int) -> String:
	return "user://save_%d.json" % clampi(slot, 1, SLOTS)


func save_game(slot: int = 1) -> void:
	var gm := GameManager
	var data := {
		"level": gm.level,
		"xp": gm.xp,
		"xp_needed": gm.xp_needed,
		"weapon_id": gm.weapon_id,
		"weapon_swap_used": gm.weapon_swap_used,
		"upgraded_done": gm.upgraded_done,
		"dream_crystals": gm.dream_crystals,
		"affixes": gm.affixes,
		"layer_index": gm.layer_index,
		"boss_cleared": gm.boss_cleared,
		"visited": gm.visited,
		"birthday": gm.birthday,
		"saved_at": Time.get_datetime_string_from_system(false, true),
	}
	var json := JSON.stringify(data)
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f != null:
		f.store_string(json)
		f.close()


func has_save(slot: int = 1) -> bool:
	return FileAccess.file_exists(_path(slot))


func load_game(slot: int = 1) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		return {}
	return parsed as Dictionary


## 存档槽描述（标题存档选择界面显示用）：如「第 2 层 · 2026-08-16 21:45」；空槽返回 ""。
func slot_desc(slot: int) -> String:
	if not has_save(slot):
		return ""
	var d := load_game(slot)
	var layer: int = int(d.get("layer_index", 1))
	var time_str: String = str(d.get("saved_at", ""))
	var lname: String = "第一层"
	if layer == 2:
		lname = "第二层"
	elif layer == 3:
		lname = "第三层"
	if time_str != "" and time_str.length() >= 16:
		time_str = time_str.substr(5, 11)   # MM-DD HH:MM
	return "%s · %s" % [lname, time_str]


func apply_to_state(dict: Dictionary) -> void:
	var gm := GameManager
	gm.level = int(dict.get("level", 1))
	gm.xp = int(dict.get("xp", 0))
	gm.xp_needed = int(dict.get("xp_needed", gm.xp_for_level(gm.level)))
	gm.weapon_id = str(dict.get("weapon_id", "staff"))
	gm.weapon_swap_used = bool(dict.get("weapon_swap_used", false))
	gm.upgraded_done = bool(dict.get("upgraded_done", false))
	gm.dream_crystals = int(dict.get("dream_crystals", 0))
	gm.affixes = dict.get("affixes", {}) if dict.has("affixes") else {}
	gm.layer_index = int(dict.get("layer_index", 1))
	gm.boss_cleared = dict.get("boss_cleared", {}) if dict.has("boss_cleared") else {}
	gm.visited = dict.get("visited", {}) if dict.has("visited") else {}
	gm.birthday = bool(dict.get("birthday", false))
	gm.weak_window = false
	gm.compute_stats()
	gm.hp = gm.max_hp
	gm.emit_signal("stats_changed")


func clear_save(slot: int = 1) -> void:
	var p := _path(slot)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
