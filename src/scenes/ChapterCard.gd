# 《梦境逐影》章节标题场景（第二章 / 第三章）。
# 流程：Game 切层 -> 本场景（黑屏 + 标题 + 旁白 + 按任意键继续）-> Game（进新层起始房）。
# 结构与 Prologue.tscn 一致：ChapterTitle + StoryText + Hint，任意键/点击推进，ESC 跳过。
extends Control

## 完成后回到主玩法场景，由 GameManager.layer_index 决定进入哪一层的起始房。
const NEXT_SCENE := "res://src/scenes/Game.tscn"

@onready var _hint: Label = $Hint
var _finished := false

func _ready() -> void:
	# 提示稍后浮现，避免与画面同时出现造成视觉拥挤
	_hint.modulate.a = 0.0
	var t := get_tree().create_tween()
	t.tween_property(_hint, "modulate:a", 1.0, 0.6).set_delay(0.3)


# 用 _input 而非 _unhandled_input：与 Prologue 一致（Control 根消费 GUI 事件）。
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
