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
var _sel_enemy: EnemyHandle = null
var _sel_weapon: WeaponHandle = null
var _sel_boss: BossHandle = null
var _sel_blocked: BlockedHandle = null   ## 选中禁区手柄时显示顶点操作按钮
var _blocked_ops: HBoxContainer = null
var _dir_edit: LineEdit   ## 黑白图导入默认文件夹（文件选择器打开时定位到这里）
var _plugin: EditorPlugin = null   ## 插件引用（取撤销管理器等插件级能力）
var _hide_blocked: CheckBox   ## 隐藏禁区可视化（测试用）

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
	hint.text = "打开房间场景（src/rooms/scenes/f{层}_{房}.tscn）后点下方按钮添加手柄：\n· 直接拖动手柄定位\n· 选中手柄在 Inspector 改属性（敌人类型/武器/大小/门目标/禁区形状/下一层）\n· Ctrl+S 保存进场景\n· 运行期手柄自动隐藏，由 RoomManager 生成真实内容"
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
	row2.add_child(_btn("+ 装饰", _add_decoration))
	row2.add_child(_btn("+ 下一层门", _add_next_door))
	add_child(row2)
	# 隐藏禁区可视化（测试用）：一键隐藏当前场景所有禁区手柄的编辑器显示
	_hide_blocked = CheckBox.new()
	_hide_blocked.text = "隐藏禁区可视化（测试）"
	_hide_blocked.toggled.connect(_on_hide_blocked)
	add_child(_hide_blocked)
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


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_info()
		_sync_selection()


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
	var n_spawn := 0
	var n_weapon := 0
	var n_deco := 0
	var n_next := 0
	for c in root.get_children():
		if c is DoorHandle:
			n_door += 1
		elif c is EnemyHandle:
			n_enemy += 1
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
	_count.text = "门 %d · 敌人 %d · 禁区 %d · 出生点 %d · 武器 %d · 装饰 %d · 门%d" % [n_door, n_enemy, n_blocked, n_spawn, n_weapon, n_deco, n_next]


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


## 隐藏/显示禁区可视化（测试用）：设置 BlockedHandle 类级静态标志 + 刷新当前场景所有禁区。
## 不直接改 visible（否则 Ctrl+S 会把 visible=false 存进 .tscn，导致该房间禁区永久隐藏）。
func _on_hide_blocked(hide: bool) -> void:
	BlockedHandle.s_hidden_all = hide
	var root := _current_root()
	if root == null:
		return
	for b in _collect_blocked(root):
		b.call("_redraw")


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
