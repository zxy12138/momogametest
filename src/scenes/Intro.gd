# 《梦境逐影》开头动画场景。
# 新游戏后播放：全屏视频 + 右上角「按 ESC 跳过」提示。
# 播放完毕或按 ESC 跳过 -> 进入选武器场景。
extends Control

## 视频播放完毕 / 跳过后前往的场景（即原「新游戏」的下一站）。
const NEXT_SCENE := "res://src/scenes/WeaponSelect.tscn"

var _finished := false

@onready var _video: VideoStreamPlayer = $VideoPlayer
@onready var _hint: Label = $SkipHint

func _ready() -> void:
	# 视频流在 .tscn 里已通过 ext_resource 指定；这里仅确保播放并接信号。
	if _video.stream != null:
		_video.play()
	_video.finished.connect(_on_finished)
	# 右上角跳过提示样式（运行时设置，避免依赖 .tscn 序列化属性名）。
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 1))

func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	# ESC 默认映射到 ui_cancel；按 ESC 即跳过开头动画。
	if event.is_action_pressed("ui_cancel"):
		_skip()

func _on_finished() -> void:
	_advance()

func _skip() -> void:
	if _finished:
		return
	_video.stop()
	_advance()

func _advance() -> void:
	_finished = true
	get_tree().change_scene_to_file(NEXT_SCENE)
