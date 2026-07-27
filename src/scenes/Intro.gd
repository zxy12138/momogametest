# 《梦境逐影》开头动画场景。
# 新游戏后播放：全屏视频 + 右上角「按 ESC 跳过」提示。
# 播放完毕或按 ESC 跳过 -> 直接进入第一个场景（Game），
# 由 Game 在开场序列（醒来独白 + 镜头拉近）结束后摆出 3 把初始武器供选择。
extends Control

## 视频播放完毕 / 跳过后前往的场景：直接进主玩法场景（武器选择改为场景内完成）。
const NEXT_SCENE := "res://src/scenes/Game.tscn"

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

func _input(event: InputEvent) -> void:
	if _finished:
		return
	# ESC 默认映射到 ui_cancel；按 ESC 即跳过开头动画。
	# 用 _input 而非 _unhandled_input：Intro 根节点是 Control，
	# ui_cancel 这类 UI 动作会在 GUI 阶段被 Control 消费，
	# 导致 _unhandled_input 收不到；_input 在 GUI 派发前必定触发，最稳。
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
