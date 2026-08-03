# 《梦境逐影》结局剧情场景（终章：黎明）
# 流程：第3层Boss击败 -> Epilogue(剧情) -> Game(通关状态+ESC回主菜单)
# 任意键/ESC 推进 -> 回到 Game 场景（带 game_completed 标志）
extends Control

## 完成后前往的场景：回到主玩法场景，由 GameManager.game_completed 标志判定为「通关」状态。
const NEXT_SCENE := "res://src/scenes/Game.tscn"

@onready var _hint: Label = $Hint
var _finished := false

func _ready() -> void:
	_hint.modulate.a = 0.0
	var t := get_tree().create_tween()
	t.tween_property(_hint, "modulate:a", 1.0, 0.6).set_delay(0.3)


func _input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventKey:
		if event.pressed and not event.echo:
			_advance()
	elif event is InputEventMouseButton:
		if event.pressed:
			_advance()


func _advance() -> void:
	if _finished:
		return
	_finished = true
	get_tree().change_scene_to_file(NEXT_SCENE)
