@tool
extends Control
class_name GalgameDialog

## 《梦境逐影》Galgame 对话框组件（v4.0 演出规范 §5.0）：
##   · 底部半透明深色对话框 + 名字框 + 打字机正文（逐字出现）
##   · 左侧说话人立绘：说话人全亮、非说话人半透明置灰（弥绘/粉丝双槽）
##   · 交互：点击 / 回车(空格) = 打字中立即显示全文，打完后下一句；长按 = 快进；
##           ESC = 跳过整段（finished 信号照常发出）
## 用法：
##   var dlg := GalgameDialog.new()
##   _ui_layer.add_child(dlg)
##   dlg.play([
##       { "name": "弥绘", "text": "……这里是……梦？", "portrait": load(...) },
##   ], func(): _set_gm_locked(false))

signal finished   ## 整段结束（自然播完或 ESC 跳过）

const TYPING_CPS := 46.0      # 打字速度（字符/秒）
const FAST_CPS := 320.0       # 长按快进速度（字符/秒）
const PORTRAIT_MAX_H := 400.0 # 立绘最大高度（保持比例）

var _lines: Array[Dictionary] = []
var _idx := 0
var _chars := 0.0             # 已显示字符数（float 累积）
var _complete := false        # 当前句是否已完整显示
var _holding := false         # 长按快进中
var _prev_lmb := false        # 鼠标左键上升沿检测
var _on_finish: Callable = Callable()

var _portrait_left: TextureRect   # 弥绘槽
var _portrait_right: TextureRect  # 粉丝槽
var _name_label: Label
var _text_label: Label
var _hint_label: Label


func _init() -> void:
	name = "GalgameDialog"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	# UI 构建放 _ready：节点已进树、父 rect 可用，锚点预设才能正确计算。
	# （@tool 编辑器预览也会触发；运行期 add_child 后同步执行）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	# 全屏透明遮罩：吞掉点击，防止穿透到游戏世界
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.0)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	# 立绘左槽（弥绘）：左下角，底对齐，对话框上方。
	# 注意：必须给左右双边 offset（正宽度），单边 offset + BOTTOM_LEFT 锚点会算出负宽 → 控件不渲染。
	_portrait_left = TextureRect.new()
	_portrait_left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_portrait_left.offset_left = 40.0
	_portrait_left.offset_right = 270.0     # 宽 230
	_portrait_left.offset_top = -600.0      # 高 400
	_portrait_left.offset_bottom = -200.0
	_portrait_left.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_left)
	# 立绘右槽（粉丝）：右下角，底对齐
	_portrait_right = TextureRect.new()
	_portrait_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_portrait_right.offset_left = -270.0
	_portrait_right.offset_right = -40.0
	_portrait_right.offset_top = -600.0
	_portrait_right.offset_bottom = -200.0
	_portrait_right.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_right.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_right)
	# 底部对话框：半透明深色底
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.12, 0.94)
	bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bg.offset_top = -190.0
	bg.offset_bottom = -36.0
	bg.offset_left = 30.0
	bg.offset_right = -30.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	# 名字框：左下锚点 + 双边 offset（之前用绝对 position (56,-184) 在视口上方之外，看不见）
	_name_label = Label.new()
	_name_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_name_label.offset_left = 56.0
	_name_label.offset_right = 356.0
	_name_label.offset_top = -184.0
	_name_label.offset_bottom = -144.0
	_name_label.add_theme_font_size_override("font_size", 24)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)
	# 正文（打字机）
	_text_label = Label.new()
	_text_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_text_label.offset_top = -150.0
	_text_label.offset_bottom = -52.0
	_text_label.offset_left = 56.0
	_text_label.offset_right = -56.0
	_text_label.add_theme_font_size_override("font_size", 20)
	_text_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text_label)
	# 右下角操作提示
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint_label.offset_left = -260.0
	_hint_label.offset_right = -44.0
	_hint_label.offset_top = -30.0
	_hint_label.offset_bottom = -8.0
	_hint_label.text = "点击/回车 继续 · 长按 快进 · ESC 跳过"
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_label)


## 开始播放一段台词。lines 每项：{name, text, portrait(可选 Texture2D), role(可选 "momo"/"zhujue")}
func play(lines: Array[Dictionary], on_finish: Callable = Callable()) -> void:
	# 防御：UI 在 _ready 构建；若 _ready 未执行（父未进树等极端情况）则补构建，避免空指针
	if _text_label == null:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_build_ui()
	_lines = lines
	_idx = 0
	_chars = 0.0
	_complete = false
	_holding = false
	_prev_lmb = false
	_on_finish = on_finish
	_apply_line(0)
	visible = true


func _process(delta: float) -> void:
	if not visible or _lines.is_empty():
		return
	# 打字机：累积字符
	if not _complete:
		var cps: float = FAST_CPS if _holding else TYPING_CPS
		_chars += cps * delta
		var txt: String = str(_lines[_idx]["text"])
		var shown := mini(int(_chars), txt.length())
		_text_label.text = txt.substr(0, shown)
		if shown >= txt.length():
			_complete = true
			_chars = float(txt.length())
	# 交互：点击 / 回车推进
	var lmb: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var clicked: bool = lmb and not _prev_lmb
	_prev_lmb = lmb
	if clicked or Input.is_action_just_pressed("ui_accept"):
		_advance()
	if Input.is_action_just_pressed("ui_cancel"):
		_skip_all()
		return
	_holding = lmb or Input.is_action_pressed("ui_accept")


func _advance() -> void:
	if _complete:
		_next()
	else:
		_complete = true
		_chars = float(_lines[_idx]["text"].length())
		_text_label.text = str(_lines[_idx]["text"])


func _next() -> void:
	_idx += 1
	if _idx >= _lines.size():
		_finish()
		return
	_chars = 0.0
	_complete = false
	_apply_line(_idx)


func _skip_all() -> void:
	_finish()


func _finish() -> void:
	visible = false
	finished.emit()
	if _on_finish.is_valid():
		_on_finish.call()


func _apply_line(idx: int) -> void:
	var line: Dictionary = _lines[idx]
	var nm: String = str(line.get("name", ""))
	_name_label.text = nm
	# 旁白（narration=true）：只显示名字、不显示立绘——左右两个立绘槽全部隐藏
	var is_narration: bool = bool(line.get("narration", false))
	if is_narration:
		_portrait_left.visible = false
		_portrait_right.visible = false
		_name_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	else:
		# 普通对话：立绘槽恢复显示
		_portrait_left.visible = true
		_portrait_right.visible = true
		# 名字颜色：弥绘金色、粉丝/其他蓝色
		var speaker: String = str(line.get("role", nm))
		_name_label.add_theme_color_override("font_color",
			Color(1.0, 0.88, 0.5) if speaker == "momo" else Color(0.65, 0.88, 1.0))
		# 立绘：说话人全亮，另一方半透明置灰
		var left_tex := line.get("portrait_left", null) as Texture2D
		var right_tex := line.get("portrait_right", null) as Texture2D
		if left_tex != null:
			_portrait_left.texture = left_tex
		if right_tex != null:
			_portrait_right.texture = right_tex
		var speaking_left: bool = speaker == "momo"
		_portrait_left.modulate = Color(1, 1, 1, 1.0) if speaking_left else Color(1, 1, 1, 0.30)
		_portrait_right.modulate = Color(1, 1, 1, 1.0) if not speaking_left else Color(1, 1, 1, 0.30)
	_text_label.text = ""
	_chars = 0.0
	_complete = false
