extends SceneTree

func _init() -> void:
	# 强制解析本次改动涉及的脚本及其依赖链；任一有 Parse 错误会被 Godot 直接报出
	preload("res://src/rooms/RoomManager.gd")
	preload("res://src/scenes/Game.gd")
	preload("res://src/player/Player.gd")
	preload("res://src/rooms/Room.tscn")
	print("PARSE_OK_ALL")
	quit()
