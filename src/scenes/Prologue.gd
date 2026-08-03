# 《梦境逐影》开篇剧情场景（第一章：醒来）
# 流程：Main -> Intro(视频) -> Prologue(剧情) -> Game(开场序列+武器拾取)
# 任意键（Space/Enter）或鼠标点击推进；ESC 跳过（同样推进）。
extends Control

## 完成后前往的场景。
const NEXT_SCENE := "res://src/scenes/Game.tscn"

@onready var _hint: Label = $Hint
var _finished := false

func _ready() -> void:
	# 提示稍后浮现，避免与画面同时出现造成视觉拥挤
	_hint.modulate.a = 0.0
	var t := get_tree().create_tween()
	t.tween_property(_hint, "modulate:a", 1.0, 0.6).set_delay(0.3)


# 用 _input 而非 _unhandled_input：与 Intro 一致，
# Control 根节点会消费 GUI 事件，导致 _unhandled_input 收不到部分输入。
func _input(event: InputEvent) -> void:
	if _finished:
		return
	# ESC / 空格 / 回车 / 鼠标按下：任一按下即推进
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
