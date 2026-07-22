# 《梦境逐影》存档管理器（user://save.json）
# 自动存档点：击败每层 Boss 后。记录等级 / 武器 / 地图解锁进度。
extends Node

const SAVE_PATH := "user://save.json"

func save_game() -> void:
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
	}
	var json := JSON.stringify(data)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(json)
		f.close()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		return {}
	return parsed as Dictionary


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


func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
