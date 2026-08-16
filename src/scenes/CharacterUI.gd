# 角色 UI 面板（参考图 11.png 样式）：左上圆头像（蒙版）+ HP/MP/EXP 三条 + 信息 + 右下梦晶 + 底部操作提示。
# 挂在 Game 的 HUD CanvasLayer 下（不受相机 canvas_transform 影响）。数值每帧读 GameManager 刷新。
extends Control

@onready var _hp_bar: ProgressBar = $BarsBox/HPBar
@onready var _mp_bar: ProgressBar = $BarsBox/MPBar
@onready var _xp_bar: ProgressBar = $BarsBox/EXPBar
@onready var _lvl: Label = $InfoBox/LvLabel
@onready var _crit: Label = $InfoBox/CritLabel
@onready var _wep: Label = $InfoBox/WepLabel
@onready var _ult: Label = $InfoBox/UltLabel
@onready var _gv: Label = $GVRow/GVLabel
@onready var _hint: Label = $Hint
@onready var _toggle_hint: Label = $ToggleHint


func _unhandled_input(event: InputEvent) -> void:
	# H 键切换底部操作提示的显示/隐藏
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_hint.visible = not _hint.visible
		_toggle_hint.text = "按 H 显示" if not _hint.visible else "按 H 隐藏"


func _process(_d: float) -> void:
	var g := GameManager
	if g == null:
		return
	_hp_bar.value = 100.0 * clampf(float(g.hp) / float(maxf(1, g.max_hp)), 0.0, 1.0)
	_mp_bar.value = 100.0 * g.mana_pct()
	_xp_bar.value = 100.0 * clampf(float(g.xp) / float(maxf(1, g.xp_needed)), 0.0, 1.0)
	_lvl.text = "Lv." + str(g.level)
	_crit.text = "暴击 " + str(int(g.crit_rate * 100)) + "%"
	_gv.text = "GV " + str(g.dream_crystals)
	var w: Dictionary = g.get_weapon()
	if w != null and not w.is_empty():
		_wep.text = "武器：" + w["name"] + ("（已升阶）" if g.upgraded_done else "")
	else:
		_wep.text = "武器：未装备"
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and p.has_method("skill_ready"):
		var ready: bool = p.call("skill_ready")
		var w2: Dictionary = g.get_weapon()
		var sname: String = "武器技能"
		if w2 != null and not w2.is_empty() and w2.has("skill"):
			sname = w2["skill"]["name"]
		_ult.text = sname + "：" + ("就绪 [E]" if ready else "回蓝中 %d%%" % int(g.mana_pct() * 100))
		_ult.modulate = Color(1, 1, 1) if ready else Color(0.6, 0.6, 0.6)
