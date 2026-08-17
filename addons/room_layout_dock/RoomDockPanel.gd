@tool
extends VBoxContainer

## 房间布局编辑器面板：检测当前编辑场景是否为房间场景（有 layer/room_id 导出），
## 一键添加 门/敌人/禁区/出生点/武器 手柄；手柄是房间场景里的普通节点，直接拖放定位，
## 选中后在 Inspector 编辑属性（敌人类型/武器类型/武器大小/门目标等），Ctrl+S 保存进场景。
## 运行期手柄自动隐藏，由 RoomManager._collect_handles 读取并生成真实内容。

var _info: Label
var _count: Label
var _enemy_drop: OptionButton   ## 敌人类型下拉（+ 敌人 时用当前选中值；选中场景 EnemyHandle 时双向同步）
var _weapon_drop: OptionButton  ## 武器类型下拉（+ 武器 时用当前选中值；选中场景 WeaponHandle 时双向同步）
var _boss_drop: OptionButton    ## Boss 类型下拉（+ Boss 时用当前选中值；选中场景 BossHandle 时双向同步）
var _adj_kind: OptionButton     ## 全局调节目标：小怪 / Boss
var _adj_type: OptionButton     ## 全局调节具体类型（按 _adj_kind 填充敌人/Boss 列表）
var _adj_scale_slider: HSlider  ## 全局体型倍率（应用到所有同类型，写 ScaleConfig）
var _adj_scale_label: Label
var _adj_coll_slider: HSlider   ## 全局碰撞倍率（应用到所有同类型，写 ScaleConfig）
var _adj_coll_label: Label
var _adj_shape_drop: OptionButton  ## 碰撞形状：矩形/三角/圆/多边形
var _adj_w_slider: HSlider         ## 碰撞宽（世界单位，缺省回落 CB 基础宽）
var _adj_w_label: Label
var _adj_h_slider: HSlider         ## 碰撞高（世界单位）
var _adj_h_label: Label
var _adj_ox_slider: HSlider        ## 碰撞中心 X 偏移（相对 sprite 中心）
var _adj_ox_label: Label
var _adj_oy_slider: HSlider        ## 碰撞中心 Y 偏移
var _adj_oy_label: Label
var _poly_box: VBoxContainer       ## 多边形顶点编辑器（仅形状=多边形时显示）
var _poly_list: VBoxContainer      ## 顶点行容器
var _poly_count_label: Label
var _poly_syncing := false         ## 防止多边形顶点编辑时反向写回
var _sel_enemy: EnemyHandle = null
var _sel_weapon: WeaponHandle = null
var _sel_boss: BossHandle = null
var _sel_blocked: BlockedHandle = null   ## 选中禁区手柄时显示顶点操作按钮
var _blocked_ops: HBoxContainer = null
var _dir_edit: LineEdit   ## 黑白图导入默认文件夹（文件选择器打开时定位到这里）
var _plugin: EditorPlugin = null   ## 插件引用（取撤销管理器等插件级能力）
var _hide_blocked: CheckBox   ## 隐藏禁区可视化（测试用）
var _hide_door_visual: CheckBox   ## 隐藏门判定框（测试用）
var _adj_syncing := false   ## 防止滑块值在同步时反向触发写回

## 房间世界尺寸（与 RoomManager.W/H 一致，用于黑白图→房间坐标映射）
const ROOM_W := 880.0
const ROOM_H := 500.0
## 黑白图采样网格边长（世界单位 px）：8px 一格，兼顾形状精度与矩形数量
const GRID := 8.0


func _ready() -> void:
	custom_minimum_size = Vector2(250, 0)
	var title := Label.new()
	title.text = "房间布局编辑器"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(0, 36)
	add_child(_info)
	var hint := Label.new()
	hint.text = "打开房间场景（src/rooms/scenes/f{层}_{房}.tscn）后点下方按钮添加手柄：\n· 直接拖动手柄定位\n· 选中手柄在 Inspector 改属性（敌人类型/武器/门目标/禁区形状等）\n· Ctrl+S 保存进场景\n· 下方「全局体型/碰撞」按类型统一调所有同类型怪（小怪+Boss 都可调体型与碰撞）"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.65)
	add_child(hint)
	# 敌人类型选择（用户核心诉求：面板里直接选怪物种类）
	var erow := HBoxContainer.new()
	erow.add_child(_label("敌人类型:"))
	_enemy_drop = OptionButton.new()
	_enemy_drop.custom_minimum_size = Vector2(170, 0)
	_enemy_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in EnemyHandle.IDS:
		var ed: Dictionary = {}
		var raw: Variant = Enemies.get_enemy(id)
		if raw is Dictionary:
			ed = raw
		_enemy_drop.add_item("%s · %s" % [str(ed.get("name", id)), id])
	_enemy_drop.selected = 0
	_enemy_drop.item_selected.connect(_on_enemy_drop)
	erow.add_child(_enemy_drop)
	add_child(erow)
	# 武器类型选择
	var wrow := HBoxContainer.new()
	wrow.add_child(_label("武器类型:"))
	_weapon_drop = OptionButton.new()
	_weapon_drop.custom_minimum_size = Vector2(170, 0)
	_weapon_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in WeaponHandle.WIDS:
		var w: Dictionary = Weapons.get_weapon(id)
		_weapon_drop.add_item("%s · %s" % [str(w.get("name", id)), id])
	_weapon_drop.selected = 0
	_weapon_drop.item_selected.connect(_on_weapon_drop)
	wrow.add_child(_weapon_drop)
	add_child(wrow)
	# Boss 类型选择（3 种：b_director / b_train / b_fear）
	var brow := HBoxContainer.new()
	brow.add_child(_label("Boss 类型:"))
	_boss_drop = OptionButton.new()
	_boss_drop.custom_minimum_size = Vector2(170, 0)
	_boss_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in BossHandle.BIDS:
		var bd: Dictionary = {}
		var braw: Variant = Enemies.get_boss(id)
		if braw is Dictionary:
			bd = braw
		_boss_drop.add_item("%s · %s" % [str(bd.get("name", id)), id])
	_boss_drop.selected = 0
	_boss_drop.item_selected.connect(_on_boss_drop)
	brow.add_child(_boss_drop)
	add_child(brow)
	# 两行按钮（8 种手柄），避免一行挤不下
	var row1 := HBoxContainer.new()
	row1.add_child(_btn("+ 门", _add_door))
	row1.add_child(_btn("+ 敌人", _add_enemy))
	row1.add_child(_btn("+ Boss", _add_boss))
	row1.add_child(_btn("+ 禁区", _add_blocked))
	add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_child(_btn("+ 出生点", _add_spawn))
	row2.add_child(_btn("+ 武器", _add_weapon))
	row2.add_child(_btn("+ 驿站", _add_inn))
	row2.add_child(_btn("+ 装饰", _add_decoration))
	row2.add_child(_btn("+ 下一层门", _add_next_door))
	add_child(row2)
	# 隐藏禁区可视化（测试用）：一键隐藏当前场景所有禁区手柄的编辑器显示
	_hide_blocked = CheckBox.new()
	_hide_blocked.text = "隐藏禁区可视化（测试）"
	# 与持久化设置同步：重启后勾选框状态对齐 project.godot 里的值，避免"框没勾但游戏里仍隐藏"的困惑
	_hide_blocked.button_pressed = BlockedHandle.is_visual_hidden()
	_hide_blocked.toggled.connect(_on_hide_blocked)
	add_child(_hide_blocked)
	# 隐藏门判定框（测试用）：勾选后进游戏不显示门的 44×44 判定框可视化（project.godot 持久化）
	_hide_door_visual = CheckBox.new()
	_hide_door_visual.text = "隐藏门判定框（测试）"
	_hide_door_visual.button_pressed = BlockedHandle.is_door_visual_hidden()
	_hide_door_visual.toggled.connect(_on_hide_door_visual)
	add_child(_hide_door_visual)
	# 黑白图导入生成禁区（黑=禁区 / 白=可行走）+ 默认文件夹
	var dir_row := HBoxContainer.new()
	dir_row.add_child(_label("文件夹:"))
	_dir_edit = LineEdit.new()
	_dir_edit.text = "res://assets/tiles/"
	_dir_edit.placeholder_text = "输入文件夹路径（res:// 或绝对路径）"
	_dir_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir_row.add_child(_dir_edit)
	dir_row.add_child(_btn("…", _browse_import_dir))
	add_child(dir_row)
	var row3 := HBoxContainer.new()
	row3.add_child(_btn("导入禁区图（黑白）", _import_blocked_image))
	add_child(row3)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 11)
	add_child(_count)
	# 选中禁区（多边形）时显示顶点操作：+ 顶点 / - 顶点（PS 风格拖点编辑）
	var blocked_info := Label.new()
	blocked_info.name = "BlockedInfo"
	blocked_info.text = "选中禁区手柄后可编辑顶点"
	blocked_info.add_theme_font_size_override("font_size", 11)
	blocked_info.modulate = Color(1, 0.7, 0.7, 0.85)
	add_child(blocked_info)
	_blocked_ops = HBoxContainer.new()
	_blocked_ops.add_child(_btn("+ 顶点", _add_point))
	_blocked_ops.add_child(_btn("- 顶点", _remove_point))
	_blocked_ops.add_child(_btn("居中到中心", _center_blocked))
	_blocked_ops.add_child(_btn("切换矩形/多边形", _toggle_blocked_shape))
	_blocked_ops.visible = false
	add_child(_blocked_ops)
	# 全局类型级调节组：按类型统一调整所有同类型小怪/Boss 的体型与碰撞范围（写 ScaleConfig JSON）
	var adj_sep := HSeparator.new()
	adj_sep.add_theme_constant_override("separation", 8)
	add_child(adj_sep)
	var adj_title := Label.new()
	adj_title.text = "全局体型 / 碰撞（应用到同类型所有怪）"
	adj_title.add_theme_font_size_override("font_size", 12)
	adj_title.modulate = Color(1, 1, 0.8, 0.9)
	add_child(adj_title)
	# 目标切换：小怪 / Boss
	var kind_row := HBoxContainer.new()
	kind_row.add_child(_label("目标:"))
	_adj_kind = OptionButton.new()
	_adj_kind.add_item("小怪", 0)
	_adj_kind.add_item("Boss", 1)
	_adj_kind.selected = 0
	_adj_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_adj_kind.item_selected.connect(_on_adj_kind)
	kind_row.add_child(_adj_kind)
	add_child(kind_row)
	# 具体类型下拉（按目标填充敌人/Boss 列表）
	var type_row := HBoxContainer.new()
	type_row.add_child(_label("类型:"))
	_adj_type = OptionButton.new()
	_adj_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_adj_type.item_selected.connect(_on_adj_type)
	type_row.add_child(_adj_type)
	add_child(type_row)
	# 体型滑块
	var scale_row := HBoxContainer.new()
	scale_row.add_child(_label("体型:"))
	_adj_scale_slider = HSlider.new()
	_adj_scale_slider.min_value = 0.1
	_adj_scale_slider.max_value = 3.0
	_adj_scale_slider.step = 0.05
	_adj_scale_slider.value = 1.0
	_adj_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(_adj_scale_slider)
	_adj_scale_label = Label.new()
	_adj_scale_label.custom_minimum_size = Vector2(48, 0)
	_adj_scale_label.text = "%.2f" % _adj_scale_slider.value
	scale_row.add_child(_adj_scale_label)
	add_child(scale_row)
	_adj_scale_slider.value_changed.connect(_on_adj_scale_changed)
	# 碰撞滑块
	var coll_row := HBoxContainer.new()
	coll_row.add_child(_label("碰撞:"))
	_adj_coll_slider = HSlider.new()
	_adj_coll_slider.min_value = 0.1
	_adj_coll_slider.max_value = 3.0
	_adj_coll_slider.step = 0.05
	_adj_coll_slider.value = 1.0
	_adj_coll_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coll_row.add_child(_adj_coll_slider)
	_adj_coll_label = Label.new()
	_adj_coll_label.custom_minimum_size = Vector2(48, 0)
	_adj_coll_label.text = "%.2f" % _adj_coll_slider.value
	coll_row.add_child(_adj_coll_label)
	add_child(coll_row)
	_adj_coll_slider.value_changed.connect(_on_adj_coll_changed)
	# —— 碰撞形状 / 尺寸 / 中心点 / 多边形（按类型全局控制，写 ScaleConfig）——
	var shape_sep := HSeparator.new()
	shape_sep.add_theme_constant_override("separation", 6)
	add_child(shape_sep)
	# 形状下拉
	var shape_row := HBoxContainer.new()
	shape_row.add_child(_label("形状:"))
	_adj_shape_drop = OptionButton.new()
	_adj_shape_drop.add_item("矩形", ScaleConfig.SHAPE_RECT)
	_adj_shape_drop.add_item("三角形", ScaleConfig.SHAPE_TRI)
	_adj_shape_drop.add_item("圆形", ScaleConfig.SHAPE_CIRCLE)
	_adj_shape_drop.add_item("多边形", ScaleConfig.SHAPE_POLY)
	_adj_shape_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_adj_shape_drop.item_selected.connect(_on_adj_shape_changed)
	shape_row.add_child(_adj_shape_drop)
	add_child(shape_row)
	# 宽 / 高
	var w_row := HBoxContainer.new()
	w_row.add_child(_label("宽:"))
	_adj_w_slider = HSlider.new()
	_adj_w_slider.min_value = 4.0
	_adj_w_slider.max_value = 320.0
	_adj_w_slider.step = 1.0
	_adj_w_slider.value = 40.0
	_adj_w_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w_row.add_child(_adj_w_slider)
	_adj_w_label = Label.new()
	_adj_w_label.custom_minimum_size = Vector2(48, 0)
	_adj_w_label.text = "%.0f" % _adj_w_slider.value
	w_row.add_child(_adj_w_label)
	add_child(w_row)
	_adj_w_slider.value_changed.connect(_on_adj_w_changed)
	var h_row := HBoxContainer.new()
	h_row.add_child(_label("高:"))
	_adj_h_slider = HSlider.new()
	_adj_h_slider.min_value = 4.0
	_adj_h_slider.max_value = 320.0
	_adj_h_slider.step = 1.0
	_adj_h_slider.value = 40.0
	_adj_h_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_row.add_child(_adj_h_slider)
	_adj_h_label = Label.new()
	_adj_h_label.custom_minimum_size = Vector2(48, 0)
	_adj_h_label.text = "%.0f" % _adj_h_slider.value
	h_row.add_child(_adj_h_label)
	add_child(h_row)
	_adj_h_slider.value_changed.connect(_on_adj_h_changed)
	# 中心点 X / Y 偏移
	var ox_row := HBoxContainer.new()
	ox_row.add_child(_label("中心X:"))
	_adj_ox_slider = HSlider.new()
	_adj_ox_slider.min_value = -160.0
	_adj_ox_slider.max_value = 160.0
	_adj_ox_slider.step = 1.0
	_adj_ox_slider.value = 0.0
	_adj_ox_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ox_row.add_child(_adj_ox_slider)
	_adj_ox_label = Label.new()
	_adj_ox_label.custom_minimum_size = Vector2(48, 0)
	_adj_ox_label.text = "%.0f" % _adj_ox_slider.value
	ox_row.add_child(_adj_ox_label)
	add_child(ox_row)
	_adj_ox_slider.value_changed.connect(_on_adj_ox_changed)
	var oy_row := HBoxContainer.new()
	oy_row.add_child(_label("中心Y:"))
	_adj_oy_slider = HSlider.new()
	_adj_oy_slider.min_value = -160.0
	_adj_oy_slider.max_value = 160.0
	_adj_oy_slider.step = 1.0
	_adj_oy_slider.value = 0.0
	_adj_oy_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oy_row.add_child(_adj_oy_slider)
	_adj_oy_label = Label.new()
	_adj_oy_label.custom_minimum_size = Vector2(48, 0)
	_adj_oy_label.text = "%.0f" % _adj_oy_slider.value
	oy_row.add_child(_adj_oy_label)
	add_child(oy_row)
	_adj_oy_slider.value_changed.connect(_on_adj_oy_changed)
	# 多边形顶点编辑器（仅形状=多边形时显示）
	_poly_box = VBoxContainer.new()
	var poly_info := Label.new()
	poly_info.text = "多边形顶点（局部坐标，中心在原点）"
	poly_info.add_theme_font_size_override("font_size", 10)
	poly_info.modulate = Color(1, 1, 1, 0.7)
	_poly_box.add_child(poly_info)
	var poly_ops := HBoxContainer.new()
	poly_ops.add_child(_btn("+ 顶点", _on_poly_add))
	poly_ops.add_child(_btn("- 顶点", _on_poly_remove))
	poly_ops.add_child(_btn("重置为矩形", _on_poly_reset))
	_poly_box.add_child(poly_ops)
	_poly_count_label = Label.new()
	_poly_count_label.add_theme_font_size_override("font_size", 10)
	_poly_count_label.modulate = Color(1, 1, 1, 0.7)
	_poly_box.add_child(_poly_count_label)
	_poly_list = VBoxContainer.new()
	_poly_box.add_child(_poly_list)
	_poly_box.visible = false
	add_child(_poly_box)
	# 初始化类型列表
	_fill_adj_types()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_info()
		_sync_selection()


## 按当前目标（小怪/Boss）填充类型下拉。
func _fill_adj_types() -> void:
	if _adj_type == null or _adj_kind == null:
		return
	_adj_type.clear()
	if _adj_kind.selected == 0:
		for id in EnemyHandle.IDS:
			var ed: Dictionary = {}
			var raw: Variant = Enemies.get_enemy(id)
			if raw is Dictionary:
				ed = raw
			_adj_type.add_item("%s · %s" % [str(ed.get("name", id)), id])
	else:
		for id in BossHandle.BIDS:
			var bd: Dictionary = {}
			var braw: Variant = Enemies.get_boss(id)
			if braw is Dictionary:
				bd = braw
			_adj_type.add_item("%s · %s" % [str(bd.get("name", id)), id])
	_adj_type.select(0)
	_refresh_adj_sliders()


## 当前选中的调节类型 id。
func _adj_type_id() -> String:
	if _adj_kind.selected == 0:
		return EnemyHandle.IDS[clampi(_adj_type.selected, 0, EnemyHandle.IDS.size() - 1)]
	return BossHandle.BIDS[clampi(_adj_type.selected, 0, BossHandle.BIDS.size() - 1)]


## 滑块改全局 ScaleConfig 后：对当前编辑场景里「同类型」的所有 EnemyHandle / BossHandle 触发 _redraw，
## 让编辑器场景里的怪物预览实时反映大小/碰撞变化（之前只写 JSON，手柄预览不刷新）。递归查找，
## 兼容手柄被嵌套在子节点下的场景结构。
func _redraw_handles_of_type(id: String, is_boss: bool) -> void:
	var root := _current_root()
	if root == null:
		return
	_collect_redraw(root, id, is_boss)


func _collect_redraw(node: Node, id: String, is_boss: bool) -> void:
	for c in node.get_children():
		var match_id := ""
		if is_boss and c is BossHandle:
			match_id = (c as BossHandle).boss_id()
		elif not is_boss and c is EnemyHandle:
			match_id = (c as EnemyHandle).enemy_id()
		if match_id == id and c.has_method("_redraw"):
			c.call("_redraw")
		_collect_redraw(c, id, is_boss)


## 当前选中类型的 CB 基础值（用于 w/h/ox/oy 缺省回落）。
func _cb_defaults(id: String, is_boss: bool) -> Vector4:
	if is_boss:
		var b: Variant = Enemies.get_boss(id)
		if b is Dictionary:
			var fd: Dictionary = (b as Dictionary).get("form1", {})
			return (fd as Dictionary).get("cb", Vector4(80, 90, 0, 4))
		return Vector4(80, 90, 0, 4)
	return Enemy.CB.get(id, Vector4(32, 32, 0, 0))


## 把滑块同步到当前选中类型的全局值（切换类型/目标时调用）。
func _refresh_adj_sliders() -> void:
	if _adj_scale_slider == null:
		return
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	var cb := _cb_defaults(id, is_boss)
	_adj_syncing = true
	if is_boss:
		_adj_scale_slider.value = ScaleConfig.get_boss_scale(id)
		_adj_coll_slider.value = ScaleConfig.get_boss_collision(id)
		_adj_shape_drop.selected = ScaleConfig.get_boss_shape(id, ScaleConfig.SHAPE_RECT)
		_adj_w_slider.value = ScaleConfig.get_boss_w(id, cb.x)
		_adj_h_slider.value = ScaleConfig.get_boss_h(id, cb.y)
		_adj_ox_slider.value = ScaleConfig.get_boss_ox(id, cb.z)
		_adj_oy_slider.value = ScaleConfig.get_boss_oy(id, cb.w)
	else:
		_adj_scale_slider.value = ScaleConfig.get_enemy_scale(id)
		_adj_coll_slider.value = ScaleConfig.get_enemy_collision(id)
		_adj_shape_drop.selected = ScaleConfig.get_enemy_shape(id, ScaleConfig.SHAPE_RECT)
		_adj_w_slider.value = ScaleConfig.get_enemy_w(id, cb.x)
		_adj_h_slider.value = ScaleConfig.get_enemy_h(id, cb.y)
		_adj_ox_slider.value = ScaleConfig.get_enemy_ox(id, cb.z)
		_adj_oy_slider.value = ScaleConfig.get_enemy_oy(id, cb.w)
	_adj_scale_label.text = "%.2f" % _adj_scale_slider.value
	_adj_coll_label.text = "%.2f" % _adj_coll_slider.value
	_adj_w_label.text = "%.0f" % _adj_w_slider.value
	_adj_h_label.text = "%.0f" % _adj_h_slider.value
	_adj_ox_label.text = "%.0f" % _adj_ox_slider.value
	_adj_oy_label.text = "%.0f" % _adj_oy_slider.value
	_adj_syncing = false
	# 形状=多边形时显示顶点编辑器并重建
	_poly_box.visible = (_adj_shape_drop.selected == ScaleConfig.SHAPE_POLY)
	if _poly_box.visible:
		_build_poly_ui()


## 目标切换（小怪/Boss）→ 重填类型下拉。
func _on_adj_kind(_idx: int) -> void:
	_fill_adj_types()


## 类型切换 → 滑块同步到该类型全局值。
func _on_adj_type(_idx: int) -> void:
	_refresh_adj_sliders()


## 体型滑块 → 写回全局类型缩放（应用到所有同类型怪）。
func _on_adj_scale_changed(v: float) -> void:
	_adj_scale_label.text = "%.2f" % v
	if _adj_syncing:
		return
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	if is_boss:
		ScaleConfig.set_boss_scale(id, v)
	else:
		ScaleConfig.set_enemy_scale(id, v)
	_redraw_handles_of_type(id, is_boss)


## 碰撞滑块 → 写回全局类型碰撞（应用到所有同类型怪）。
func _on_adj_coll_changed(v: float) -> void:
	_adj_coll_label.text = "%.2f" % v
	if _adj_syncing:
		return
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	if is_boss:
		ScaleConfig.set_boss_collision(id, v)
	else:
		ScaleConfig.set_enemy_collision(id, v)
	_redraw_handles_of_type(id, is_boss)


## 形状下拉 → 写回全局类型形状（矩形/三角/圆/多边形）。
func _on_adj_shape_changed(v: int) -> void:
	if _adj_syncing:
		return
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	if is_boss:
		ScaleConfig.set_boss_shape(id, v)
	else:
		ScaleConfig.set_enemy_shape(id, v)
	_poly_box.visible = (v == ScaleConfig.SHAPE_POLY)
	if _poly_box.visible:
		_build_poly_ui()
	_redraw_handles_of_type(id, is_boss)


## 宽滑块 → 写回全局类型碰撞宽（世界单位，缺省回落 CB）。
func _on_adj_w_changed(v: float) -> void:
	_adj_w_label.text = "%.0f" % v
	if _adj_syncing:
		return
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	if is_boss:
		ScaleConfig.set_boss_w(id, v)
	else:
		ScaleConfig.set_enemy_w(id, v)
	_redraw_handles_of_type(id, is_boss)


## 高滑块 → 写回全局类型碰撞高。
func _on_adj_h_changed(v: float) -> void:
	_adj_h_label.text = "%.0f" % v
	if _adj_syncing:
		return
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	if is_boss:
		ScaleConfig.set_boss_h(id, v)
	else:
		ScaleConfig.set_enemy_h(id, v)
	_redraw_handles_of_type(id, is_boss)


## 中心 X 偏移滑块 → 写回全局类型碰撞中心 X。
func _on_adj_ox_changed(v: float) -> void:
	_adj_ox_label.text = "%.0f" % v
	if _adj_syncing:
		return
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	if is_boss:
		ScaleConfig.set_boss_ox(id, v)
	else:
		ScaleConfig.set_enemy_ox(id, v)
	_redraw_handles_of_type(id, is_boss)


## 中心 Y 偏移滑块 → 写回全局类型碰撞中心 Y。
func _on_adj_oy_changed(v: float) -> void:
	_adj_oy_label.text = "%.0f" % v
	if _adj_syncing:
		return
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	if is_boss:
		ScaleConfig.set_boss_oy(id, v)
	else:
		ScaleConfig.set_enemy_oy(id, v)
	_redraw_handles_of_type(id, is_boss)


## 重建多边形顶点编辑列表（切换类型/形状/顶点数时调用）。
func _build_poly_ui() -> void:
	if _poly_list == null:
		return
	for c in _poly_list.get_children():
		c.queue_free()
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	var poly := ScaleConfig.get_enemy_poly(id) if not is_boss else ScaleConfig.get_boss_poly(id)
	if poly.size() < 3:
		var hint := Label.new()
		hint.text = "尚未创建顶点：点「重置为矩形」或「+ 顶点」（至少 3 个）"
		hint.add_theme_font_size_override("font_size", 10)
		hint.modulate = Color(1, 0.8, 0.6, 0.9)
		_poly_list.add_child(hint)
		_poly_count_label.text = "顶点数: %d" % poly.size()
		return
	_poly_syncing = true
	for i in poly.size():
		var row := HBoxContainer.new()
		row.add_child(_label("顶点%d" % i))
		var sx := SpinBox.new()
		sx.min_value = -400.0
		sx.max_value = 400.0
		sx.step = 1.0
		sx.value = poly[i].x
		sx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sx.value_changed.connect(_on_poly_vertex_changed.bind(i, 0))
		row.add_child(sx)
		var sy := SpinBox.new()
		sy.min_value = -400.0
		sy.max_value = 400.0
		sy.step = 1.0
		sy.value = poly[i].y
		sy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sy.value_changed.connect(_on_poly_vertex_changed.bind(i, 1))
		row.add_child(sy)
		_poly_list.add_child(row)
	_poly_syncing = false
	_poly_count_label.text = "顶点数: %d（至少 3 个）" % poly.size()


## 多边形顶点 x/y 改变 → 写回顶点数组（value, idx, axis 顺序由 bind 决定）。
func _on_poly_vertex_changed(v: float, idx: int, axis: int) -> void:
	if _poly_syncing:
		return
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	var poly := ScaleConfig.get_enemy_poly(id) if not is_boss else ScaleConfig.get_boss_poly(id)
	if idx < 0 or idx >= poly.size():
		return
	var p := poly[idx]
	if axis == 0:
		p.x = v
	else:
		p.y = v
	poly[idx] = p
	if is_boss:
		ScaleConfig.set_boss_poly(id, poly)
	else:
		ScaleConfig.set_enemy_poly(id, poly)
	_redraw_handles_of_type(id, is_boss)


## 多边形 + 顶点（新顶点放在末尾顶点附近偏移 16）。
func _on_poly_add() -> void:
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	var poly := ScaleConfig.get_enemy_poly(id) if not is_boss else ScaleConfig.get_boss_poly(id)
	var nv := Vector2(16.0, 16.0)
	if poly.size() > 0:
		nv = poly[poly.size() - 1] + Vector2(16.0, 16.0)
	poly.append(nv)
	if is_boss:
		ScaleConfig.set_boss_poly(id, poly)
	else:
		ScaleConfig.set_enemy_poly(id, poly)
	_build_poly_ui()
	_redraw_handles_of_type(id, is_boss)


## 多边形 - 顶点（至少保留 3 个）。
func _on_poly_remove() -> void:
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	var poly := ScaleConfig.get_enemy_poly(id) if not is_boss else ScaleConfig.get_boss_poly(id)
	if poly.size() <= 3:
		return
	poly.remove_at(poly.size() - 1)
	if is_boss:
		ScaleConfig.set_boss_poly(id, poly)
	else:
		ScaleConfig.set_enemy_poly(id, poly)
	_build_poly_ui()
	_redraw_handles_of_type(id, is_boss)


## 多边形重置为当前 w/h 的矩形四顶点。
func _on_poly_reset() -> void:
	var id := _adj_type_id()
	var is_boss := _adj_kind.selected == 1
	var w := _adj_w_slider.value
	var h := _adj_h_slider.value
	var poly := PackedVector2Array([Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5), Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5)])
	if is_boss:
		ScaleConfig.set_boss_poly(id, poly)
	else:
		ScaleConfig.set_enemy_poly(id, poly)
	_build_poly_ui()
	_redraw_handles_of_type(id, is_boss)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _btn(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 30)
	b.pressed.connect(fn)
	return b


func _current_root() -> Node:
	if get_tree() == null:
		return null
	return get_tree().edited_scene_root


func _update_info() -> void:
	var root := _current_root()
	if root == null:
		_info.text = "未打开场景"
		_count.text = ""
		return
	var is_room: bool = ("layer" in root) and ("room_id" in root)
	if not is_room:
		_info.text = "当前场景不是房间场景\n请打开 src/rooms/scenes/f{层}_{房}.tscn"
		_count.text = ""
		return
	# 用 str() 而非 String()：root.get() 返回 Variant，String(Variant) 会报 "Nonexistent 'String' constructor"
	_info.text = "当前房间：f%s_%s.tscn" % [str(root.get("layer")), str(root.get("room_id"))]
	var n_door := 0
	var n_enemy := 0
	var n_blocked := 0
	var n_inn := 0
	var n_spawn := 0
	var n_weapon := 0
	var n_deco := 0
	var n_next := 0
	for c in root.get_children():
		if c is DoorHandle:
			n_door += 1
		elif c is EnemyHandle:
			n_enemy += 1
		elif c is InnHandle:
			n_inn += 1   # 驿站继承禁区：先判断子类
		elif c is BlockedHandle:
			n_blocked += 1
		elif c is SpawnPointHandle:
			n_spawn += 1
		elif c is WeaponHandle:
			n_weapon += 1
		elif c is DecorationHandle:
			n_deco += 1
		elif c is NextDoorHandle:
			n_next += 1
	_count.text = "门 %d · 敌人 %d · 禁区 %d · 驿站 %d · 出生点 %d · 武器 %d · 装饰 %d · 门%d" % [n_door, n_enemy, n_blocked, n_inn, n_spawn, n_weapon, n_deco, n_next]


func _add_handle(h: Node2D) -> void:
	var root := _current_root()
	if root == null:
		return
	# 合理命名：按手柄类型生成可读名称（Enemy_1 / Door_r2 / Weapon_staff / Blocked_1 / Spawn / Decoration_1 / NextDoor）
	var base: String
	if h is DoorHandle:
		base = "Door"
	elif h is EnemyHandle:
		base = "Enemy"
	elif h is InnHandle:
		base = "Inn"   # 驿站继承禁区：先判断子类
	elif h is BlockedHandle:
		base = "Blocked"
	elif h is SpawnPointHandle:
		base = "Spawn"
	elif h is WeaponHandle:
		base = "Weapon_" + (h as WeaponHandle).weapon_id()
	elif h is DecorationHandle:
		base = "Decoration"
	elif h is NextDoorHandle:
		base = "NextDoor"
	else:
		base = "Handle"
	var i := 1
	while root.get_node_or_null(base if i == 1 else "%s_%d" % [base, i]) != null:
		i += 1
	h.name = base if i == 1 else "%s_%d" % [base, i]
	root.add_child(h)
	h.owner = root
	# 默认位置：房间中心附近随机偏移，避免全部叠在原点
	h.position = Vector2(randf_range(-160.0, 160.0), randf_range(-110.0, 110.0))


func _add_door() -> void:
	_add_handle(DoorHandle.new())


func _add_enemy() -> void:
	var h := EnemyHandle.new()
	h.enemy_type = clampi(_enemy_drop.selected, 0, EnemyHandle.IDS.size() - 1)
	_add_handle(h)


func _add_blocked() -> void:
	_add_handle(BlockedHandle.new())


func _add_inn() -> void:
	_add_handle(InnHandle.new())


func _add_spawn() -> void:
	# 出生点系统：每个房间至多一个 SpawnPointHandle（Game 无门时用它决定出生位置）。
	# 已有则直接选中它（避免重复创建；位置可拖），没有才新建到房间中心附近。
	var root := _current_root()
	if root == null:
		return
	for c in root.get_children():
		if c is SpawnPointHandle:
			var sel := EditorInterface.get_selection()
			if sel != null:
				sel.clear()
				sel.add_node(c)
			if _info != null:
				_info.text = "该房间已有出生点，已选中（拖动可调整位置）"
			return
	_add_handle(SpawnPointHandle.new())


func _add_weapon() -> void:
	var h := WeaponHandle.new()
	h.weapon_type = clampi(_weapon_drop.selected, 0, WeaponHandle.WIDS.size() - 1)
	_add_handle(h)


func _add_boss() -> void:
	var h := BossHandle.new()
	h.boss_type = clampi(_boss_drop.selected, 0, BossHandle.BIDS.size() - 1)
	_add_handle(h)


func _add_decoration() -> void:
	_add_handle(DecorationHandle.new())


func _add_next_door() -> void:
	_add_handle(NextDoorHandle.new())


## 选中场景里的 EnemyHandle / WeaponHandle 时，把下拉框同步到其当前类型；
## 用户改下拉直接写回手柄（触发其 _redraw 实时刷新样子）。
func _sync_selection() -> void:
	var sel := EditorInterface.get_selection()
	if sel == null:
		return
	var nodes: Array[Node] = sel.get_selected_nodes()
	var enemy: EnemyHandle = null
	var weapon: WeaponHandle = null
	var blocked: BlockedHandle = null
	var boss: BossHandle = null
	for n in nodes:
		if enemy == null and n is EnemyHandle:
			enemy = n
		elif weapon == null and n is WeaponHandle:
			weapon = n
		elif blocked == null and n is BlockedHandle:
			blocked = n
		elif boss == null and n is BossHandle:
			boss = n
	if enemy != null:
		if enemy != _sel_enemy:
			_sel_enemy = enemy
			_enemy_drop.select(clampi(enemy.enemy_type, 0, EnemyHandle.IDS.size() - 1))
	elif _sel_enemy != null:
		_sel_enemy = null
	if weapon != null:
		if weapon != _sel_weapon:
			_sel_weapon = weapon
			_weapon_drop.select(clampi(weapon.weapon_type, 0, WeaponHandle.WIDS.size() - 1))
	elif _sel_weapon != null:
		_sel_weapon = null
	# 禁区手柄：选中时显示顶点操作（+ / - 顶点 + 切换矩形/多边形）
	_sel_blocked = blocked
	_blocked_ops.visible = blocked != null
	# Boss 手柄：选中时同步下拉
	_sel_boss = boss
	if boss != null and _boss_drop != null:
		_boss_drop.select(clampi(boss.boss_type, 0, BossHandle.BIDS.size() - 1))


func _on_enemy_drop(idx: int) -> void:
	if _sel_enemy != null and is_instance_valid(_sel_enemy):
		_sel_enemy.enemy_type = idx


func _on_weapon_drop(idx: int) -> void:
	if _sel_weapon != null and is_instance_valid(_sel_weapon):
		_sel_weapon.weapon_type = idx


func _on_boss_drop(idx: int) -> void:
	if _sel_boss != null and is_instance_valid(_sel_boss):
		_sel_boss.boss_type = idx


## 隐藏/显示禁区可视化（测试用）：设置 BlockedHandle 类级静态标志 + 刷新当前场景所有禁区，
## 并持久化到 project.godot，让运行期（F5/F6 新进程）进游戏后同样不显示红色禁区。
## 不直接改 visible（否则 Ctrl+S 会把 visible=false 存进 .tscn，导致该房间禁区永久隐藏）。
func _on_hide_blocked(hide: bool) -> void:
	BlockedHandle.s_hidden_all = hide
	BlockedHandle.set_visual_hidden(hide)
	var root := _current_root()
	if root == null:
		return
	for b in _collect_blocked(root):
		b.call("_redraw")


## 隐藏/显示门判定框：持久化到 project.godot，让运行期进游戏后同样不显示门的判定框可视化；
## 并重绘当前场景所有 DoorHandle，让编辑器里勾选/取消即时生效（不勾=显示，勾=隐藏）。
func _on_hide_door_visual(hide: bool) -> void:
	BlockedHandle.set_door_visual_hidden(hide)
	var root := _current_root()
	if root == null:
		return
	for d in _collect_door(root):
		d.call("_redraw")


func _collect_door(node: Node) -> Array[DoorHandle]:
	var out: Array[DoorHandle] = []
	for c in node.get_children():
		if c is DoorHandle:
			out.append(c)
		out.append_array(_collect_door(c))
	return out


func _collect_blocked(node: Node) -> Array[BlockedHandle]:
	var out: Array[BlockedHandle] = []
	for c in node.get_children():
		if c is BlockedHandle:
			out.append(c)
		out.append_array(_collect_blocked(c))
	return out


## 禁区编辑：+ 顶点（PS 风格多边形拖点）
func _add_point() -> void:
	if _sel_blocked != null and is_instance_valid(_sel_blocked):
		_sel_blocked.add_polygon_point()


## 禁区编辑：- 顶点（至少留 3 个）
func _remove_point() -> void:
	if _sel_blocked != null and is_instance_valid(_sel_blocked):
		_sel_blocked.remove_last_polygon_point()


## 禁区编辑：把中心手柄移动到多边形顶点的几何中心（图形不跳）
func _center_blocked() -> void:
	if _sel_blocked != null and is_instance_valid(_sel_blocked):
		_sel_blocked.center_to_polygon_center()


## 禁区编辑：矩形 ↔ 多边形切换
func _toggle_blocked_shape() -> void:
	if _sel_blocked != null and is_instance_valid(_sel_blocked):
		_sel_blocked.shape_type = 1 if _sel_blocked.shape_type == 0 else 0
		_sel_blocked._ensure_polygon_points()


## 黑白图导入生成禁区：弹文件选择器（默认定位到「文件夹」输入框的路径），选 PNG（黑=禁区 / 白=可行走）。
func _import_blocked_image() -> void:
	var fd := EditorFileDialog.new()
	fd.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	fd.access = EditorFileDialog.ACCESS_FILESYSTEM
	fd.add_filter("*.png,*.jpg,*.jpeg,*.webp ; 黑白图（黑=禁区）")
	var dir_text: String = _dir_edit.text.strip_edges()
	if dir_text != "" and DirAccess.dir_exists_absolute(dir_text):
		fd.current_dir = dir_text
	fd.file_selected.connect(_parse_blocked_image)
	EditorInterface.get_base_control().add_child(fd)
	fd.popup_centered_ratio(0.6)


## 浏览文件夹：选中的目录写回「文件夹」输入框，下次导入默认定位到这里。
func _browse_import_dir() -> void:
	var fd := EditorFileDialog.new()
	fd.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	fd.access = EditorFileDialog.ACCESS_FILESYSTEM
	var dir_text: String = _dir_edit.text.strip_edges()
	if dir_text != "" and DirAccess.dir_exists_absolute(dir_text):
		fd.current_dir = dir_text
	fd.dir_selected.connect(func(d: String) -> void: _dir_edit.text = d)
	EditorInterface.get_base_control().add_child(fd)
	fd.popup_centered_ratio(0.6)


## 解析黑白图：图片任意尺寸，自动拉伸铺满 880×500 房间。
## 算法：缩放采样（GRID 8px 一格）→ 行扫描黑色段 → 垂直合并相邻同 x 段 → 每矩形生成 BlockedHandle(矩形模式)。
func _parse_blocked_image(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		push_error("[梦境编辑器] 禁区图加载失败: " + path)
		return
	var root := _current_root()
	if root == null:
		return
	if not (("layer" in root) and ("room_id" in root)):
		push_error("[梦境编辑器] 请先打开房间场景（f{层}_{房}.tscn）再导入禁区图")
		return
	var cols := int(ceil(ROOM_W / GRID))
	var rows := int(ceil(ROOM_H / GRID))
	img.resize(cols, rows, Image.INTERPOLATE_NEAREST)
	# 采样网格 grid[y][x]：true=禁区（亮度 < 0.5）
	var grid: Array[Array] = []
	for y in rows:
		var line: Array[bool] = []
		for x in cols:
			var c := img.get_pixel(x, y)
			line.append((c.r + c.g + c.b) / 3.0 < 0.5)
		grid.append(line)
	# 行扫描：每行连续黑色段 → Rect2i(x, y, w, 1)
	var segs: Array[Rect2i] = []
	for y in rows:
		var x := 0
		while x < cols:
			if grid[y][x]:
				var x1 := x
				while x1 < cols and grid[y][x1]:
					x1 += 1
				segs.append(Rect2i(x, y, x1 - x, 1))
				x = x1
			else:
				x += 1
	# 垂直合并：同 x 范围且 y 紧邻的段合并成高矩形
	var merged: Array[Rect2i] = []
	for s in segs:
		var done := false
		for i in merged.size():
			var m: Rect2i = merged[i]
			if m.position.x == s.position.x and m.size.x == s.size.x \
					and (m.end.y == s.position.y or s.end.y == m.position.y):
				var y0 := mini(m.position.y, s.position.y)
				var y1 := maxi(m.end.y, s.end.y)
				merged[i] = Rect2i(m.position.x, y0, m.size.x, y1 - y0)
				done = true
				break
		if not done:
			merged.append(s)
	# 生成 BlockedHandle（**多边形模式**，4 个角 = 4 个可拖顶点），坐标映射：网格 → 房间中心原点坐标。
	# 用多边形模式让黑白图生成的禁区同样支持「+ 顶点 / - 顶点 / 居中到中心 / 拖点」编辑。
	# 节点先 new 出来但**不挂树**，最后用 UndoRedo 包裹挂载/摘除 → 导入错了可 Ctrl+Z 撤销。
	var nodes: Array[Node] = []
	for r in merged:
		if r.size.x < 1 or r.size.y < 1:
			continue
		var h := BlockedHandle.new()
		h.shape_type = 1
		# 关键：禁用 _ready 自动补默认点（否则 add_child 触发 _ready 生成 4 个默认点 +
		# 下面再手动加 4 个角点 = 8 点叠加，形状错乱）
		h.auto_seed_points = false
		var i := 1
		while root.get_node_or_null("Blocked" if i == 1 else "Blocked_%d" % i) != null:
			i += 1
		h.name = "Blocked" if i == 1 else "Blocked_%d" % i
		var hw: float = r.size.x * GRID * 0.5
		var hh: float = r.size.y * GRID * 0.5
		h.position = Vector2(
			(r.position.x + r.size.x * 0.5) * GRID - ROOM_W * 0.5,
			(r.position.y + r.size.y * 0.5) * GRID - ROOM_H * 0.5)
		var corners: Array[Vector2] = [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]
		for j in corners.size():
			var p := PolygonPointHandle.new()
			p.idx = j
			h.add_child(p)   # h 未挂树，子点直接挂 h 下（owner 在 attach 时统一设置）
			p.position = corners[j]
		nodes.append(h)
	# 挂载/摘除包进撤销栈 → 编辑器 Ctrl+Z / Ctrl+Y 可撤销/重做本次导入。
	# Godot 4.7 正确取法：EditorPlugin.get_undo_redo() 返回 EditorUndoRedoManager 实例；
	# EditorUndoRedoManager.add_do_method(object, method, ...) 用 object+方法名（不是 Callable）。
	if _plugin == null:
		# 兜底：无插件引用时直接挂载（仍可用，只是不能撤销）
		for n in nodes:
			root.add_child(n)
			n.owner = root
			n.call("_redraw")
		print("[梦境编辑器] 禁区图解析完成：%d 个多边形禁区（%s），选中后可加/减顶点" % [nodes.size(), path.get_file()])
		return
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action("导入禁区图（%d 个）" % nodes.size())
	ur.add_do_method(self, "_attach_imported_nodes", nodes)
	ur.add_undo_method(self, "_detach_imported_nodes", nodes)
	ur.commit_action()
	print("[梦境编辑器] 禁区图解析完成：%d 个多边形禁区（%s），Ctrl+Z 可撤销" % [nodes.size(), path.get_file()])


## UndoRedo do：把导入生成的节点挂到场景根并设置 owner（**含子顶点 owner——否则 Ctrl+S 保存时子顶点丢失**）。
func _attach_imported_nodes(nodes: Array) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	for n in nodes:
		if not is_instance_valid(n):
			continue
		if n.get_parent() == null:
			root.add_child(n)
		n.owner = root
		# 关键：子顶点（PolygonPointHandle）也要设 owner，否则保存场景时顶点丢失，
		# 重新打开 collect 不到点 → 不绘制红框（f1_r5/f2_r1 等房间已踩坑）
		for c in n.get_children():
			c.owner = root
		if n.has_method("_redraw"):
			n.call("_redraw")


## UndoRedo undo：把导入生成的节点从场景摘除（保留引用，redo 可再挂回）。
func _detach_imported_nodes(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n) and n.get_parent() != null:
			n.get_parent().remove_child(n)


## EditorPlugin 注入：用于取 EditorUndoRedoManager（撤销导入）等插件级能力。
func set_plugin(p: EditorPlugin) -> void:
	_plugin = p
