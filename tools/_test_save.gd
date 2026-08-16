extends SceneTree

func _init() -> void:
	# 手动挂 GameManager + SaveManager（模拟 autoload）
	var gm_s := load("res://src/autoload/GameManager.gd") as GDScript
	var gm: Node = gm_s.new()
	gm.name = "GameManager"
	root.add_child(gm)
	var sm_s := load("res://src/autoload/SaveManager.gd") as GDScript
	var sm: Node = sm_s.new()
	sm.name = "SaveManager"
	root.add_child(sm)
	# 清空 3 槽
	for i in 3:
		sm.call("clear_save", i + 1)
	print("初始 has_save(1..3) =", sm.call("has_save", 1), sm.call("has_save", 2), sm.call("has_save", 3))
	# 写槽 2
	gm.set("level", 7)
	gm.set("layer_index", 2)
	gm.set("weapon_id", "sword")
	sm.call("save_game", 2)
	print("写槽2后 has_save(2) =", sm.call("has_save", 2))
	print("slot_desc(2) =", str(sm.call("slot_desc", 2)))
	# 读回
	var d: Dictionary = sm.call("load_game", 2)
	print("读回 level=", d.get("level"), " layer=", d.get("layer_index"), " weapon=", d.get("weapon_id"), " saved_at=", d.get("saved_at"))
	# 默认槽 1 写入（兼容旧调用）
	gm.set("level", 3)
	sm.call("save_game")
	print("默认槽1写后 has_save(1)=", sm.call("has_save", 1), " 槽3仍空=", not sm.call("has_save", 3))
	# 清理
	for i in 3:
		sm.call("clear_save", i + 1)
	print("清理后全空 =", not sm.call("has_save", 1) and not sm.call("has_save", 2) and not sm.call("has_save", 3))
	print("SAVE TEST DONE")
	quit()
