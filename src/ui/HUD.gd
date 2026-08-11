# 战斗 HUD（CanvasLayer）：血条 / 蓝条 / 经验条 / 等级 / 暴击率 / 梦晶 / 武器 / 操作提示
extends CanvasLayer

var _hp_fill: ColorRect
var _mana_fill: ColorRect
var _xp_fill: ColorRect
var _lvl: Label
var _crit: Label
var _crys: Label
var _wep: Label
var _ult: Label
var _hint: Label
const BAR_W := 220.0


func _ready() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_bar_bg(root, Vector2(16, 14), Vector2(BAR_W, 16), Color(0.25, 0.08, 0.12))
	_hp_fill = _bar_fill(root, Vector2(16, 14), Vector2(BAR_W, 16), Color(0.95, 0.25, 0.35))
	# 蓝条（技能法力）：血条正下方，蓝色
	_bar_bg(root, Vector2(16, 32), Vector2(BAR_W, 10), Color(0.06, 0.15, 0.30))
	_mana_fill = _bar_fill(root, Vector2(16, 32), Vector2(BAR_W, 10), Color(0.25, 0.55, 1.0))
	# 经验条（下移到蓝条下方）
	_bar_bg(root, Vector2(16, 46), Vector2(BAR_W, 8), Color(0.18, 0.12, 0.30))
	_xp_fill = _bar_fill(root, Vector2(16, 46), Vector2(BAR_W, 8), Color(0.65, 0.45, 0.95))

	_lvl = _text(root, "Lv.1", Vector2(BAR_W + 26, 10), 18)
	_crit = _text(root, "暴击 5%", Vector2(16, 58), 14)
	_crit.add_theme_color_override("font_color", Color(1, 0.6, 0.1))
	_crys = _text(root, "◆ 0", Vector2(16, 78), 14)
	_crys.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	_wep = _text(root, "武器：未装备", Vector2(16, 98), 13)
	_wep.add_theme_color_override("font_color", Color(0.8, 0.7, 1.0))
	_ult = _text(root, "", Vector2(16, 116), 13)
	_ult.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_hint = _text(root, "WASD 移动 · 鼠标瞄准 · 左键攻击 · E 武器技能 · F 拾取/交互 · M 地图", Vector2(16, 520), 12)
	_hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))


func _process(_d: float) -> void:
	var g := GameManager
	if g == null: return
	_hp_fill.size.x = BAR_W * clampf(float(g.hp) / float(maxf(1, g.max_hp)), 0, 1)
	_mana_fill.size.x = BAR_W * g.mana_pct()
	_xp_fill.size.x = BAR_W * clampf(float(g.xp) / float(maxf(1, g.xp_needed)), 0, 1)
	_lvl.text = "Lv." + str(g.level)
	_crit.text = "暴击 " + str(int(g.crit_rate * 100)) + "%"
	_crys.text = "◆ " + str(g.dream_crystals)
	var w: Dictionary = g.get_weapon()
	if w != null and not w.is_empty():
		_wep.text = "武器：" + w["name"] + ("（已升阶）" if g.upgraded_done else "")
	else:
		_wep.text = "武器：未装备"
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and p.has_method("skill_ready"):
		var ready: bool = p.call("skill_ready")
		# 显示当前武器技能名（如"武器技能·星尘陨落"）
		var w2: Dictionary = g.get_weapon()
		var sname: String = "武器技能"
		if w2 != null and not w2.is_empty() and w2.has("skill"):
			sname = w2["skill"]["name"]
		_ult.text = sname + "：" + ("就绪 [E]" if ready else "回蓝中 %d%%" % int(g.mana_pct() * 100))
		_ult.modulate = Color(1, 1, 1) if ready else Color(0.6, 0.6, 0.6)


func _bar_bg(parent: Control, pos: Vector2, size: Vector2, col: Color) -> void:
	var r := ColorRect.new()
	r.position = pos; r.size = size; r.color = col; r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)


func _bar_fill(parent: Control, pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos; r.size = size; r.color = col; r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _text(parent: Control, t: String, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = t; l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
