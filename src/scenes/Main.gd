# 《梦境逐影》主菜单（Control 根，项目入口场景）
# 场景化 UI：标题循环.ogv 背景 + 像素风标题（梦境逐影 / DREAM CHASER）
# 流程：按任意键 → 「按任意键继续」消失 → 菜单淡入（新游戏/继续游戏/设置/退出游戏）
# 设置：主音量滑块 → AudioServer master 总线 + ProjectSettings 持久化（game/master_volume）
# 新游戏 -> 选武器；继续 -> 读档；退出。
extends Control

@onready var _press_any: Label = $PressAny
@onready var _menu_root: CenterContainer = $MenuRoot
@onready var _settings_wrap: CenterContainer = $SettingsWrap
@onready var _save_wrap: CenterContainer = $SaveWrap
@onready var _continue_btn: Button = $MenuRoot/MenuPanel/ContinueBtn
@onready var _vol_slider: HSlider = $SettingsWrap/SettingsPanel/SettingsBox/VolRow/VolSlider
@onready var _vol_value: Label = $SettingsWrap/SettingsPanel/SettingsBox/VolRow/VolValue
@onready var _f12_toggle: CheckButton = $SettingsWrap/SettingsPanel/SettingsBox/F12MapToggle
@onready var _f11_toggle: CheckButton = $SettingsWrap/SettingsPanel/SettingsBox/F11KillToggle
@onready var _god_toggle: CheckButton = $SettingsWrap/SettingsPanel/SettingsBox/GodModeToggle
@onready var _blink: Timer = $BlinkTimer
@onready var _slot_btns: Array = [$SaveWrap/SavePanel/SaveBox/Slot1Btn, $SaveWrap/SavePanel/SaveBox/Slot2Btn, $SaveWrap/SavePanel/SaveBox/Slot3Btn]

var _menu_shown := false


func _ready() -> void:
	# 标题界面即开始播放全局 BGM（音乐从进入游戏就开始）。
	GameManager.play_bgm()
	# 重置视口相机变换：Game 每帧写 viewport.canvas_transform 做缩放跟随，返回标题后该变换残留，
	# 会导致标题 UI 整体被放大/偏移（change_scene 不会自动重置 canvas_transform）。
	get_viewport().set_canvas_transform(Transform2D.IDENTITY)
	# 防御性清理：无论从哪条路径返回标题（ESC/死亡/生日/通关），都还原全局状态，
	# 防止 GameManager 瞬态标志/暂停残留导致再进游戏错乱（input_locked 卡死等）。
	get_tree().paused = false
	GameManager.input_locked = false
	GameManager.cutscene_frozen = false
	GameManager.weak_window = false
	GameManager.game_completed = false
	GameManager.prologue_pending = false
	GameManager.prologue_dialog_active = false
	# 应用并显示持久化音量（默认 80%）
	var v: float = float(ProjectSettings.get_setting("game/master_volume", 80.0))
	_vol_slider.value = v
	_vol_value.text = "%d%%" % int(v)
	_apply_volume(v)
	_continue_btn.disabled = not SaveManager.has_save()
	_menu_root.visible = false
	_settings_wrap.visible = false
	_save_wrap.visible = false
	_vol_slider.value_changed.connect(_on_vol_changed)
	# 调试开关：F12 全开地图 / F11 秒杀敌人 / 无敌模式（默认关闭）
	_f12_toggle.button_pressed = GameManager.debug_full_map
	_f11_toggle.button_pressed = GameManager.debug_kill_all
	_god_toggle.button_pressed = GameManager.god_mode
	_f12_toggle.toggled.connect(func(on: bool) -> void: GameManager.debug_full_map = on)
	_f11_toggle.toggled.connect(func(on: bool) -> void: GameManager.debug_kill_all = on)
	_god_toggle.toggled.connect(func(on: bool) -> void: GameManager.god_mode = on)
	$MenuRoot/MenuPanel/NewBtn.pressed.connect(_new_game)
	$MenuRoot/MenuPanel/ContinueBtn.pressed.connect(_open_save_select)
	$MenuRoot/MenuPanel/SettingsBtn.pressed.connect(_open_settings)
	$MenuRoot/MenuPanel/QuitBtn.pressed.connect(_quit)
	$SettingsWrap/SettingsPanel/SettingsBox/CloseBtn.pressed.connect(_close_settings)
	$SaveWrap/SavePanel/SaveBox/SaveCloseBtn.pressed.connect(_close_save_select)
	for i in _slot_btns.size():
		(_slot_btns[i] as Button).pressed.connect(_continue_slot.bind(i + 1))
	_blink.timeout.connect(func() -> void:
		_press_any.visible = not _press_any.visible)


## 任意键/任意点击 → 显示主菜单（首次）
func _input(event: InputEvent) -> void:
	if _menu_shown:
		return
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		_show_menu()


func _show_menu() -> void:
	_menu_shown = true
	_press_any.visible = false
	_blink.stop()
	_menu_root.visible = true
	_menu_root.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_menu_root, "modulate:a", 1.0, 0.4)


func _new_game() -> void:
	# 新游戏 -> 先播开头动画，播完/跳过后进入主玩法场景。
	# 置 prologue_pending：进入 Game 后会强制先播「醒来」开场序列，结束才摆出武器。
	GameManager.prologue_pending = true
	get_tree().change_scene_to_file("res://src/scenes/Intro.tscn")


func _continue_slot(slot: int) -> void:
	var data := SaveManager.load_game(slot)
	if data.is_empty():
		return
	SaveManager.apply_to_state(data)
	get_tree().change_scene_to_file("res://src/scenes/Game.tscn")


func _open_save_select() -> void:
	# 刷新 3 个存档槽的显示（有档：层+时间；空槽禁用）
	for i in _slot_btns.size():
		var b := _slot_btns[i] as Button
		var desc: String = SaveManager.slot_desc(i + 1)
		if desc == "":
			b.text = "存档 %d · 空" % (i + 1)
			b.disabled = true
		else:
			b.text = "存档 %d · %s" % [i + 1, desc]
			b.disabled = false
	_save_wrap.visible = true


func _close_save_select() -> void:
	_save_wrap.visible = false


func _open_settings() -> void:
	_settings_wrap.visible = true


func _close_settings() -> void:
	_settings_wrap.visible = false


func _on_vol_changed(value: float) -> void:
	_apply_volume(value)
	_vol_value.text = "%d%%" % int(value)
	ProjectSettings.set_setting("game/master_volume", value)
	ProjectSettings.save()


func _apply_volume(v: float) -> void:
	# master 总线音量（0~100 → -80dB~0dB），滑到 0 静音
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001) / 100.0))
	AudioServer.set_bus_mute(0, v <= 0.0)


func _quit() -> void:
	get_tree().quit()
