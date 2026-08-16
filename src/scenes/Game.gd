# 游戏主玩法场景：房间切换 / 传送 / 驿站 / 词条 / 死亡 / 生日彩蛋
@tool
extends Node2D

const WORLD_DIR := "res://src/rooms/worlds/"
const ROOM_DIR := "res://src/rooms/scenes/"
const ENEMY = preload("res://src/enemies/Enemy.tscn")
const DEATHCG = preload("res://src/ui/DeathCG.tscn")
const BIRTHDAY = preload("res://src/ui/Birthday.tscn")
const EPILOGUE = preload("res://src/scenes/Epilogue.tscn")
# 预加载地面武器脚本。注意：headless 下全局 class_name 缓存不会重新扫描，
# 因此这里用 preload 拿脚本引用来 new()，类型统一按 Node2D 处理（成员走 call/get/set），
# 避免解析期依赖全局类型「WeaponPickup」导致 Parse Error。
const WeaponPickupScript := preload("res://src/weapons/WeaponPickup.gd")
# Galgame 演出立绘（v4.0 §5.0）：弥绘 3 表情差分 + 粉丝剪影
const MOMO_HAPPY := preload("res://assets/Live2d/momo/momo_happy.png")
const MOMO_ANGER := preload("res://assets/Live2d/momo/momo_anger.png")
const MOMO_PITY := preload("res://assets/Live2d/momo/momo_pity.png")
const MOMO_MOVE := preload("res://assets/Live2d/momo/momo_move.png")   # 弥绘「感动/动容」表情
const ZHUJUE_PITY := preload("res://assets/Live2d/zhujue/zhujue_pity.png")
const ZHUJUE_HAPPY := preload("res://assets/Live2d/zhujue/zhujue_happy.png")   # 粉丝「清醒/开心」版（花海）

var _room: Node = null
var _crossed_layer := false   ## 跨层标志：_switch_floor/_go_next_layer 置 true；_swap 消费后置 false。跨层时 rid 撞名不能用 prev_rid 查门
var _world: Node2D = null   ## 当前层世界场景实例（Layer1/2/3.tscn，内含房间锚点+连线）
var _transitioning := false
var _layer_w := 880.0
var _layer_h := 500.0
var _toast: Label = null
var _pause_open := false
var _pause_overlay: Control = null
var _dev_label: Label = null
var _ui_layer: CanvasLayer = null

# 相机：本 Godot 版本 Camera2D.current / make_current() 均不可靠（不接管视口），
# 故改用确定性方案——Game.gd 每帧直接写 get_viewport().canvas_transform，数学上保证玩家居中。
# Camera2D 节点已设为 enabled=false，仅作占位（Player.shake 仍 tween 其 offset，但视觉由手动 transform 决定）。
var _cam_zoom: float = 0.0  # 0 = 自动适配整间房(固定视角，不跟随玩家)；>0 时沿用该固定倍率（手动放大）

# f1_r3/f1_r4 进入关卡演出（首次进入）：门开完 → 视角下移看怪（怪暂停）→ 视角回中 → momo 出现关卡开始。
# 相机用 _cam_focus_offset 相对房间中心偏移（_update_camera 里叠加），配合状态机逐段推进。
var _intro_active := false
var _intro_anim: AnimatedSprite2D = null   # f1_r3/r4 开门动画节点（RoomManager 提供）
var _intro_phase := 0   # 0=无演出 1=门动画播放 2=视角下移 3=停留展示 4=视角回中 5=完成
var _intro_t := 0.0
var _cam_focus_offset := Vector2.ZERO   # 演出相机偏移（相对房间中心）
var _enemy_center := Vector2.ZERO       # 怪群中心（房间局部坐标，视角下移目标）
const _INTRO_PAN_T := 0.8     # 视角平移时长（下移/回中各一段）
const _INTRO_HOLD_T := 0.7    # 视角停在怪群展示的时长

# 通关状态：从 Epilogue 返回时为 true。期间 ESC 直接返回主菜单，不弹暂停菜单。
var _completed_state_active := false
var _completion_overlay: Control = null

# ============ 开场序列 / 场景内武器拾取 ============
var _prologue_active := false
var _galgame_dialog: GalgameDialog = null   ## 当前 Galgame 对话框（Prologue / Boss 前演出）
var _galgame_active := false                ## Galgame 演出进行中（锁输入，ESC 不弹暂停）
var _near_pickup: Node2D = null
var _pickups: Array[Node2D] = []
var _pickup_panel: Panel = null
var _pickup_label: Label = null
const _PICKUP_RADIUS := 64.0

# Fade 必须挂在 CanvasLayer（屏幕空间）下，否则会被相机 zoom+跟随推到屏幕外，
# 只在角落露出黑块（之前每次切场景右下角的黑屏即此）。
@onready var _fade_rect: ColorRect = $Fade/Rect


func _ready() -> void:
	# 进入可玩场景的唯一切入点：无论如何都要解锁输入，
	# 否则任何把 input_locked 设成 true 的路径（ESC 暂停/死亡/生日）在回到 Game 时都会卡死玩家。
	_set_gm_locked(false)
	# 相机由 _update_camera() 每帧手动驱动 viewport.canvas_transform（见 _physics_process），
	# 不依赖 Camera2D.current/make_current()（本 Godot 版本不可靠）。
	# 编辑器预览：在场景编辑器里直接 build 一个示例世界（地板/墙/门/敌人/Boss 可见），
	# 不跑任何游戏逻辑（输入/淡入/信号/计时器）。运行期走下方真实逻辑。
	if Engine.is_editor_hint():
		_editor_build_preview()
		return
	GameManager.play_bgm()   # 进入玩法场景：播放全局 BGM（autoload 循环，切房不中断）
	# 通关状态：玩家刚从 Epilogue 场景返回。跳过 prologue_pending 与 r1 生成，
	# 直接进入第3层 r6（已清的 Boss 房）并显示通关覆盖层。消费完即清零。
	if GameManager.game_completed:
		GameManager.game_completed = false
		_enter_completed_state()
		return
	_fade_rect.size = get_window().get_visible_rect().size
	_fade_rect.modulate.a = 1.0
	var t := get_tree().create_tween()
	t.tween_property(_fade_rect, "modulate:a", 0.0, 0.6)
	MapData.load_layer(GameManager.layer_index)
	_restore_map_progress()
	GameManager.connect("leveled_up", _on_level_up)
	# 专用屏幕空间 UI 层：所有动态面板/提示都挂这里，避免被相机 zoom+跟随推到屏幕外
	var ui := CanvasLayer.new()
	ui.name = "UILayer"
	ui.layer = 10
	ui.process_mode = Node.PROCESS_MODE_ALWAYS   # ESC 全暂停时菜单/面板仍可交互
	add_child(ui)
	_ui_layer = ui
	_build_toast()
	_build_dev_label()
	_build_pickup_prompt()
	transition_to(LevelData.start_room(1), true)

	# 新游戏：先强制播放开场序列（醒来独白 + 镜头拉近），结束后才生成可选武器。
	# 「继续」/「死亡重开」不会置 prologue_pending，因此直接进正常玩法。
	if GameManager.prologue_pending:
		GameManager.prologue_pending = false
		GameManager.reset_run("")   # 新游戏开局：先无武器，拾取后才装备
		_play_prologue()


# 编辑器预览：在场景编辑器里 build 一个示例世界，方便直接看到房间/墙/门/敌人/Boss。
# 预览节点由 @tool 在编辑器运行时动态 add_child，请勿在预览存在时 Ctrl+S 保存 Game.tscn，
# 以免把预览节点写进场景文件；关闭场景重开即可自动清理。运行期不会走这里。
func _editor_build_preview() -> void:
	if get_node_or_null("World/Layer1") != null:
		return
	# 编辑器预览：实例化第 1 层世界场景（房间锚点+连线可见），并在每个锚点下实例化房间场景。
	# 数据从 LevelData（class_name 全局类，编辑器内可用）取，避免 @tool 下调用 autoload placeholder 崩溃；
	# scene_img 由 tile_path 手动注入，保证预览也能显示动态背景。
	# 预览节点由 @tool 动态 add_child，请勿在预览存在时 Ctrl+S 保存 Game.tscn（关闭场景重开即自动清理）。
	var ps := load(WORLD_DIR + "Layer1.tscn") as PackedScene
	if ps == null:
		return
	var world := ps.instantiate() as Node2D
	world.name = "Layer1"
	$World.add_child(world)
	_world = world
	var rooms_d: Dictionary = (LevelData.get_layer(1).get("rooms", {}) as Dictionary)
	var start: String = LevelData.start_room(1)
	for rid in rooms_d.keys():
		var anchor := world.get_node_or_null(str(rid)) as Node2D
		if anchor == null:
			continue
		var room := (load(ROOM_DIR + "f1_%s.tscn" % str(rid)) as PackedScene).instantiate() as Node2D
		anchor.add_child(room)
		var rd: Dictionary = (rooms_d[str(rid)] as Dictionary).duplicate(true)
		var tp: String = LevelData.tile_path(1, str(rid))
		if tp != "":
			rd["scene_img"] = tp
		room.call("setup", str(rid), rd, 1, anchor, self)
		if str(rid) == start:
			_room = room
	var p := get_node_or_null("World/Player")
	if p != null and _room != null:
		p.global_position = _room.global_position
		var cam := p.get_node_or_null("Camera") as Camera2D
		if is_instance_valid(cam):
			# 编辑器预览关闭相机自动渲染，改由 _focus_editor_viewport 手动聚焦。
			cam.enabled = false
			cam.anchor_mode = 0
		# 把 2D 视图对准起点房（房间中心），打开 Game.tscn 即可直接看到角色居中 + 整层拓扑。
		_focus_editor_viewport(_room.global_position)


# 编辑器专用：把 2D 视口直接对准指定世界坐标（居中显示）。
# 注意：不能用 get_node("/root/EditorInterface") 取编辑器接口——该路径在 Godot 4 下取不到，
# 会静默失效，导致预览始终停在左上角。改用 Engine.get_singleton("EditorInterface") 才能拿到。
# EditorInterface 不是 GDScript 通用已知类型，且严格模式下对 Object 直调其方法会报“方法不存在”，
# 因此统一走 ei.call("get_editor_viewport_2d") 动态调用，返回 Variant 再 as SubViewport。
func _focus_editor_viewport(focus: Vector2) -> void:
	var ei: Object = Engine.get_singleton("EditorInterface")
	if ei == null:
		return
	var vp: SubViewport = ei.call("get_editor_viewport_2d") as SubViewport
	if vp == null:
		return
	var z := 0.6
	var sz := Vector2(vp.size.x, vp.size.y)
	if sz.x <= 0.0:
		sz = Vector2(1280.0, 720.0)
	var center := sz * 0.5
	# 正确顺序：先平移到 center - focus*z（屏幕空间），再缩放 z。
	# 注意 .scaled().translated() 会把平移也乘上 z（错）；必须 .translated().scaled()。
	var ct := Transform2D().translated(center - focus * z).scaled(Vector2(z, z))
	vp.set_canvas_transform(ct)


# 相机逻辑全部交由 _update_camera() 每帧手动写 viewport.canvas_transform（玩家居中跟随）。
# 受击抖动由 Player.shake() tween 相机 offset（Camera2D 已 disabled，视觉微抖可忽略；如需抖动可改 _update_camera 加偏移）。

# 续关：把已探明/已通房间状态还原到 MapData（load_layer 会重置 states）
func _restore_map_progress() -> void:
	for rid in GameManager.visited.keys():
		if MapData.states.has(rid):
			MapData.states[rid] = "VISITED"
	if GameManager.boss_cleared.get(GameManager.layer_index, false):
		for rid in MapData.rooms.keys():
			if MapData.room(rid).get("type", "") == "boss":
				MapData.states[rid] = "BOSS_CLEARED"

func _build_toast() -> void:
	var vsize := get_window().get_visible_rect().size
	_toast = Label.new()
	_toast.position = Vector2(vsize.x - 580.0, 20.0)   # 右上角，右对齐
	_toast.size = Vector2(560.0, 28.0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast.modulate.a = 0.0
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	_toast.z_index = 100
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_toast)


func toast(text: String) -> void:
	if _toast == null: return
	_toast.text = text
	_toast.modulate.a = 1.0
	var t := get_tree().create_tween()
	t.tween_property(_toast, "modulate:a", 0.0, 1.2).set_delay(1.6)


# ============ 房间切换 ============
func transition_to(rid: String, instant: bool = false) -> void:
	if _transitioning and not instant:
		return
	# 合并地图键（含 "-"）：如 "f2-r3"。先解析跨层并切层，再走原逐层逻辑。
	if rid.contains("-"):
		var parts: PackedStringArray = rid.split("-")
		if parts.size() >= 2:
			var floor_str: String = parts[0]
			var bare: String = parts[1]
			if floor_str.begins_with("f"):
				var target_floor: int = int(floor_str.substr(1))
				if target_floor >= 1 and target_floor <= 3 and target_floor != GameManager.layer_index:
					_switch_floor(target_floor, bare)
				rid = bare
			else:
				rid = bare
	if not MapData.rooms.has(rid):
		return
	_transitioning = true
	if instant:
		_swap(rid)
		var t := get_tree().create_tween()
		t.tween_property(_fade_rect, "modulate:a", 0.0, 0.5)
		t.tween_callback(func(): _transitioning = false)
	else:
		var t := get_tree().create_tween()
		t.tween_property(_fade_rect, "modulate:a", 1.0, 0.25)
		t.tween_callback(func():
			_swap(rid)
			var t2 := get_tree().create_tween()
			t2.tween_property(_fade_rect, "modulate:a", 0.0, 0.35)
			t2.tween_callback(func(): _transitioning = false)
		)


func _swap(rid: String) -> void:
	var prev_rid: String = GameManager.current_room
	# 清理上一房间残留的弹道/拾取物（它们加在场景根，不随房间销毁）
	for n in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(n):
			n.queue_free()
	# 武器拾取物挂世界根（不再随房间销毁），切换房间时显式按组清理
	for n in get_tree().get_nodes_in_group("weapon_pickup"):
		if is_instance_valid(n):
			n.queue_free()
	if _room != null:
		_room.queue_free()
		_room = null
	# 房间切换时清空场景内武器拾取物（它们随房间销毁，数组引用需同步清掉）
	_pickups.clear()
	_near_pickup = null
	_update_pickup_prompt("")
	MapData.enter_room(rid)
	GameManager.current_room = rid
	# 场景化：在「当前层世界场景」的锚点（节点名=rid）下实例化该房间场景 f{层}_{rid}.tscn。
	_ensure_world()
	var anchor := _room_anchor(rid)
	if anchor == null:
		push_error("Game: 世界场景锚点缺失 rid=%s" % rid)
		return
	var room := (load(ROOM_DIR + "f%d_%s.tscn" % [GameManager.layer_index, rid]) as PackedScene).instantiate() as Node2D
	if room == null:
		push_error("Game: 房间场景加载失败 %s" % (ROOM_DIR + "f%d_%s.tscn" % [GameManager.layer_index, rid]))
		return
	_room = room
	anchor.add_child(room)
	room.call("setup", rid, MapData.room(rid), GameManager.layer_index, anchor, self)
	var p: Node2D = $World/Player
	var type: String = MapData.room(rid).get("type", "")
	# 角色从门走入：若来自另一房间，则出生在该房「指回旧房的那扇门」位置，并向房间中心偏移避免立即回弹；
	# 首进 / 无来源 / 找不到对应门时回退默认出生点。以下坐标均为房间局部坐标，最后转成世界坐标。
	var spawn_pos: Vector2 = Vector2.ZERO
	var from_door := false
	# 只有「同层过门」才查门；跨层跳转（地图/传送门）时 prev_rid 是其他层的房，
	# 而 rid 在各层重复（f1_r1 / f3_r1 都叫 r1）——prev_rid 会误匹配本层同名 target 的门，
	# 导致出生点落在错误的门上（例如从 f1_r1 跳 f3_r0 时误命中 f3_r0 的 Door_r1，出生在门位置而非出生点）。
	if prev_rid != "" and prev_rid != rid and not _crossed_layer:
		var dp: Variant = room.call("entry_door_position", prev_rid)
		if dp is Vector2 and dp != Vector2.ZERO:
			spawn_pos = dp
			from_door = true
	_crossed_layer = false   # 消费跨层标志
	if not from_door:
		# 无门（跨层进入下一大关起点 / 首进 / 找不到来源门）→ 用【安全出生点】：
		# RoomManager.safe_spawn_position 优先插件 SpawnPointHandle 配置的位置，
		# 并校验「房间边界内 + 不在禁区内部」，无效时自动螺旋搜索最近安全点，
		# 保证角色绝不会出生在禁区（dead zone）里卡死。
		var sp: Variant = room.call("safe_spawn_position")
		if sp is Vector2 and sp != Vector2.ZERO:
			spawn_pos = sp
		elif type == "boss":
			spawn_pos = Vector2(0, _layer_h / 2 - 60)
		else:
			spawn_pos = Vector2(0, _layer_h / 2 - 60)
	# 最终防线：clamp 到房间内（防任何数据异常把出生点推出房间；门位置的偏移量 70px 不受影响）
	spawn_pos.x = clampf(spawn_pos.x, -_layer_w * 0.5 + 24.0, _layer_w * 0.5 - 24.0)
	spawn_pos.y = clampf(spawn_pos.y, -_layer_h * 0.5 + 24.0, _layer_h * 0.5 - 24.0)
	if from_door and spawn_pos.length() > 1.0:
		spawn_pos += (Vector2.ZERO - spawn_pos).normalized() * 70.0
	p.global_position = anchor.global_position + spawn_pos
	# f1_r3/f1_r4 首次进入演出（门开 → 视角下移看怪 → 视角回 → momo 出现）；再次进入无演出
	_check_enter_intro()
	# 武器技能：蓝条自动恢复，无需每房重置（v5.0）
	# Boss 前演出（v4.0 §5.3）：进入未清的 Boss 房时触发。
	# f1_r7 = 完整演出（momo 走位 + 背景视频 4s + 对话）；f2/f3 = 进房直接播 Boss 前对话（锁输入+冻结）。
	if type == "boss" and not GameManager.boss_cleared.get(GameManager.layer_index, false):
		if GameManager.layer_index == 1:
			_check_boss_cutscene()
		else:
			_play_boss_intro_dialogue()
	# DEBUG：打印真实出生坐标 + 房间锚点 + 玩家最终位置，方便排查"在中心"问题
	print("[SPAWN DEBUG] rid=%s from_door=%s spawn_pos=%s anchor.global_position=%s player.global_position=%s focus=%s" % [rid, from_door, spawn_pos, anchor.global_position, p.global_position, _room.global_position if _room else Vector2.ZERO])
	# 武器掉落完全由房间场景里的 WeaponHandle 定义（RoomManager._spawn_weapons），程序不再随机生成。


## 确保当前层世界场景已实例化（名字按层）。切层时名字变化 → 自动销毁旧实例重建。
func _ensure_world() -> void:
	var need: String = "Layer%d" % GameManager.layer_index
	if _world != null and _world.name == need:
		return
	if _world != null:
		_world.queue_free()
		_world = null
	var ps := load(WORLD_DIR + need + ".tscn") as PackedScene
	if ps == null:
		push_error("Game: 世界场景加载失败 " + WORLD_DIR + need + ".tscn")
		return
	_world = ps.instantiate() as Node2D
	_world.name = need
	$World.add_child(_world)


## 返回当前层世界场景中名为 rid 的锚点；缺失时退回世界场景根（兜底，避免崩）。
func _room_anchor(rid: String) -> Node2D:
	if _world != null:
		var a := _world.get_node_or_null(rid) as Node2D
		if a != null:
			return a
	return _world


# 合并地图跨层跳转：直接加载目标层并把该房标为 CURRENT。
# 与 _go_next_layer（固定 +1、走门逻辑）区分，不破坏正常逐层玩法。
func _switch_floor(target: int, room: String) -> void:
	_crossed_layer = true   # 跨层标记：_swap 里不用 prev_rid 查门（rid 撞名会误匹配本层门）
	GameManager.layer_index = target
	MapData.load_layer(target)
	GameManager.emit_signal("stats_changed")
	MapData.sync_merged_current_with(room)
	# 切层后若地图仍开着，刷新合并地图高亮
	var mu := get_node_or_null("MapUI")
	if mu != null and mu.has_method("redraw") and mu.call("is_open"):
		mu.redraw()


# ============ Boss 击败 ============
func on_boss_defeated(layer: int, _boss: Node) -> void:
	MapData.mark_boss_cleared(GameManager.current_room)
	GameManager.boss_cleared[layer] = true
	SaveManager.save_game()
	toast("Boss 净化！梦境归于宁静")
	# f1_r7：boss 死后 Boss 战禁区（Blocked_2/3）消失 + 持久化（切房回来保持消失）
	if layer == 1 and _room != null and is_instance_valid(_room):
		GameManager.r7_blocks_gone[GameManager.current_room] = true
		if _room.has_method("set_boss_arena_blocks"):
			_room.call("set_boss_arena_blocks", false)
	# f1_r7：boss 死亡动画播完后，背景视频续播第二段（4~8s），播完固定末帧（RoomManager._process 检测）
	if layer == 1 and _room != null and is_instance_valid(_room) \
			and _room.has_method("resume_bg_segment2"):
		get_tree().create_timer(1.6).timeout.connect(func() -> void:
			if _room != null and is_instance_valid(_room):
				_room.call("resume_bg_segment2")
		)
	if layer < 3:
		# 击败过场对话（boss 死亡动画播完后 ~1.6s 触发），对话结束再开下一层传送门。
		get_tree().create_timer(1.6).timeout.connect(func() -> void:
			_play_boss_defeat_dialogue(layer)
		)
	else:
		# 第3层Boss：进入结局剧情场景（Epilogue · 花海三段式），
		# 剧情播完后再回到 Game 时会进入「通关状态」UI。
		GameManager.game_completed = true
		_goto_epilogue()


## Boss 击败过场对话（v4.0 §5.3）：f1/f2 击败后的弥绘台词，播完启用下一层传送门。
func _play_boss_defeat_dialogue(layer: int) -> void:
	_set_gm_locked(true)
	var lines: Array[Dictionary] = []
	if layer == 1:
		lines = [{ "name": "弥绘", "role": "momo", "text": "站牌碎了……这辆车，也终于到站了。", "portrait_left": MOMO_PITY }]
	else:
		lines = [{ "name": "弥绘", "role": "momo", "text": "车厢散成光了……隧道尽头，透出晨光。", "portrait_left": MOMO_PITY }]
	_create_galgame_dialog(lines, func() -> void:
		_set_gm_locked(false)
		if _room != null and is_instance_valid(_room) and _room.has_method("enable_next_door"):
			_room.call("enable_next_door")
		toast("通往下一层梦境的传送门已开启"))


func _goto_epilogue() -> void:
	_set_gm_locked(true)
	var t := get_tree().create_tween()
	t.tween_property(_fade_rect, "modulate:a", 1.0, 0.8)
	t.tween_callback(func():
		get_tree().change_scene_to_file(EPILOGUE.resource_path)
	)


# 通关状态：从 Epilogue 返回。跳到第3层 r7（已清的 Boss 房）+ 显示通关覆盖层。
func _enter_completed_state() -> void:
	_completed_state_active = true
	_crossed_layer = true   # 从 Epilogue 返回，非过门进入——不用 prev_rid 查门
	GameManager.layer_index = 3
	# 防御：boss_cleared[3] 可能因为「继续」/手动改存档而未置位，这里兜底置上，
	# 避免 RoomManager._spawn_content 又把 Boss 重新刷出来。
	if not GameManager.boss_cleared.get(3, false):
		GameManager.boss_cleared[3] = true
	_fade_rect.size = get_window().get_visible_rect().size
	_fade_rect.modulate.a = 1.0
	MapData.load_layer(3)
	# 屏幕空间 UI 层（沿用 _ready 中的规范）
	var ui := CanvasLayer.new()
	ui.name = "UILayer"
	ui.layer = 10
	add_child(ui)
	_ui_layer = ui
	_build_toast()
	_build_dev_label()
	_build_pickup_prompt()
	transition_to("r7", true)
	# 0.7s 后（fade-in 结束附近）显示通关覆盖层
	get_tree().create_timer(0.7).timeout.connect(_show_completion_overlay)


func _show_completion_overlay() -> void:
	if not _completed_state_active:
		return
	_set_gm_locked(true)
	var c := Control.new()
	c.name = "CompletionOverlay"
	c.mouse_filter = Control.MOUSE_FILTER_STOP   # STOP，吞掉点击避免穿透
	var vsize := get_window().get_visible_rect().size
	var w := 480.0
	var h := 260.0
	c.position = vsize / 2 - Vector2(w / 2.0, h / 2.0)
	c.size = Vector2(w, h)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.12, 0.96)
	bg.size = c.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(bg)
	var title := _label("✦ 恭喜通关 ✦", Vector2(0, 26), 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(w, 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65))
	c.add_child(title)
	var msg := _label("噩梦已被驱散", Vector2(0, 80), 18)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.size = Vector2(w, 28)
	msg.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	c.add_child(msg)
	# 两个选项：返回主菜单 / 继续游玩（留在这个世界自由探索）
	var bb := _button("返回主菜单", Vector2(80, 130), Vector2(140, 42))
	bb.connect("pressed", _return_menu)
	c.add_child(bb)
	var cb := _button("继续游玩", Vector2(260, 130), Vector2(140, 42))
	cb.connect("pressed", _continue_playing)
	c.add_child(cb)
	var hint := _label("继续游玩后可在梦境中自由探索", Vector2(0, 196), 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(w, 24)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	c.add_child(hint)
	_ui_layer.add_child(c)
	_completion_overlay = c


## 通关后「继续游玩」：关闭覆盖层 + 解锁输入，留在这个世界自由探索。
func _continue_playing() -> void:
	_completed_state_active = false
	_set_gm_locked(false)
	if is_instance_valid(_completion_overlay):
		_completion_overlay.queue_free()
	_completion_overlay = null


func _go_next_layer(next: int) -> void:
	_crossed_layer = true   # 跨层标记：_swap 里不用 prev_rid 查门（rid 撞名会误匹配本层门）
	GameManager.layer_index = next
	MapData.load_layer(next)
	GameManager.emit_signal("stats_changed")
	# 切层 → 章节标题场景（Chapter2/3.tscn，与 Prologue 同结构），播完按任意键回 Game 进新层起始房。
	_set_gm_locked(true)
	get_tree().change_scene_to_file("res://src/scenes/Chapter%d.tscn" % next)



func spawn_enemy(eid: String, pos: Vector2) -> void:
	var e := ENEMY.instantiate() as Node2D
	e.call("setup", eid)
	e.z_index = int(pos.y)
	# Boss 召唤的小怪也归当前房间，随房销毁（避免跨房叠加）。
	# 先挂载再设 global_position：Boss 传的是世界坐标（敌人在房间锚点下的 global 一致）。
	if _room != null:
		_room.add_child(e)
	else:
		$World.add_child(e)
	e.global_position = pos


func _build_dev_label() -> void:
	_dev_label = Label.new()
	_dev_label.text = "开发者模式 ON · 地图内选层跳关（F12 在地图界面临时全开）"
	_dev_label.position = Vector2(20, get_window().get_visible_rect().size.y - 40)
	_dev_label.add_theme_font_size_override("font_size", 13)
	_dev_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_dev_label.z_index = 100
	_dev_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dev_label.visible = false
	_ui_layer.add_child(_dev_label)


# ============ 词条（升级时三选一） ============
func _on_level_up(_lvl: int) -> void:
	_set_gm_locked(true)
	var c := Control.new()
	c.name = "AffixPanel"
	c.position = get_window().get_visible_rect().size / 2 - Vector2(170, 110)
	var bg := ColorRect.new()
	bg.size = Vector2(340, 220)
	bg.color = Color(0.14, 0.10, 0.22, 0.97)
	c.add_child(bg)
	c.add_child(_label("梦境馈赠 · 选择一项强化", Vector2(20, 10), 16))
	var pool := ["致命感知", "梦境锐化", "破绽猎手", "连锁暴击", "梦食强化", "全力一击"]
	var picks := []
	while picks.size() < 3 and not pool.is_empty():
		picks.append(pool.pop_at(randi_range(0, pool.size() - 1)))
	var desc := {"致命感知": "暴击率 +5%", "梦境锐化": "暴击额外伤害 +30", "破绽猎手": "对减速/冰冻敌人暴击率 +10%",
		"连锁暴击": "暴击后 1.5s 下次攻击暴击率 +15%", "梦食强化": "暴击击杀额外回复 8 HP",
		"全力一击": "攻速 -20%，伤害 +40% 暴击额外 +50"}
	var y := 44
	for afx in picks:
		var b := _button(afx + " — " + desc[afx], Vector2(20, y), Vector2(300, 26))
		b.connect("pressed", func():
			GameManager.add_affix(afx)
			_set_gm_locked(false)
			c.queue_free())
		c.add_child(b)
		y += 32
	var skip := _button("跳过", Vector2(20, y), Vector2(300, 24))
	skip.connect("pressed", func():
		_set_gm_locked(false)
		c.queue_free())
	c.add_child(skip)
	_ui_layer.add_child(c)


# ============ 死亡 / 生日 ============
func on_player_died() -> void:
	_set_gm_locked(true)
	var t := get_tree().create_tween()
	t.tween_property(_fade_rect, "modulate:a", 1.0, 0.6)
	t.tween_callback(func():
		get_tree().change_scene_to_file(DEATHCG.resource_path)
	)


func _birthday() -> void:
	GameManager.birthday = true
	SaveManager.save_game()
	_set_gm_locked(true)
	var t := get_tree().create_tween()
	t.tween_property(_fade_rect, "modulate:a", 1.0, 0.8)
	t.tween_callback(func():
		get_tree().change_scene_to_file(BIRTHDAY.resource_path)
	)


# ============ 输入 / 暂停 / 开发者模式 ============
# 开场序列进行中：ESC 在这里优先被 _input 拦截并消费（跳过序列），
# 因此 _unhandled_input 直接 return，避免误触发暂停菜单。
func _input(event: InputEvent) -> void:
	if _prologue_active and event.is_action_pressed("ui_cancel"):
		_end_prologue()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _prologue_active or _galgame_active:
		return
	# 通关状态：ESC 强制返回主菜单，不弹暂停菜单（玩家只剩这一条出路）
	if _completed_state_active and event.is_action_pressed("ui_cancel"):
		_return_menu()
		return
	if event.is_action_pressed("ui_cancel"):
		# 地图开着时，ESC 直接返回（关地图），而不是再弹暂停菜单
		var mu: Node = get_node_or_null("MapUI")
		if mu != null and mu.has_method("is_open") and mu.call("is_open"):
			mu.call("close_map")
		elif _pause_open:
			_close_pause()
		else:
			_open_pause()
	elif event.is_action_pressed("interact"):
		if _inn_nearby and not _is_gm_locked():
			_confirm_inn_heal()
		elif _portal_nearby and not _is_gm_locked():
			_jump_to_epilogue()
		elif _near_pickup != null and not _is_gm_locked():
			_pick_up_weapon(_near_pickup)
	elif event.is_action_pressed("dev"):
		_toggle_dev()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_F3:
		_toggle_god()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_F11:
		_kill_all_enemies()


func _toggle_god() -> void:
	GameManager.god_mode = not GameManager.god_mode
	if GameManager.god_mode:
		toast("无敌模式：开（血量为 0 也不死亡）")
		GameManager.hp = GameManager.max_hp
		GameManager.emit_signal("stats_changed")
	else:
		toast("无敌模式：关")


## 调试：F11 秒杀当前房间所有敌人（含 Boss——跳过变身动画直接死亡，触发通关流程）。
## 需在设置里开启「F11 秒杀敌人」（GameManager.debug_kill_all，默认关闭）。
func _kill_all_enemies() -> void:
	if not GameManager.debug_kill_all:
		return
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("kill_now"):
			e.call("kill_now")
			n += 1
	toast("秒杀 %d 个敌人" % n)

# 冻结/解冻世界：暂停时停掉敌人+弹道物理（保留以兼容演出期间冻结；ESC 全暂停用 get_tree().paused）
func _freeze_world(freeze: bool) -> void:
	for n in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(n):
			n.set_physics_process(!freeze)
	for n in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(n):
			n.set_physics_process(!freeze)


## ESC 暂停菜单：get_tree().paused 全树暂停（玩家/敌人/弹道/背景全停），菜单面板 PROCESS_MODE_ALWAYS 保持可交互。
## 菜单：继续 / 存档(3槽) / 设置(音量) / 重新开始本小关 / 返回主菜单。
func _open_pause() -> void:
	if _pause_open:
		return
	_pause_open = true
	_set_gm_locked(true)
	get_tree().paused = true
	var vs := get_window().get_visible_rect().size
	var panel := Control.new()
	panel.name = "PausePanel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS   # 全树暂停后仍可交互
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.position = vs / 2 - Vector2(200, 180)
	panel.size = Vector2(400, 360)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.12, 0.97)
	bg.size = panel.size
	panel.add_child(bg)
	panel.add_child(_label("已暂停", Vector2(24, 14), 22))
	# 主菜单按钮
	var opts := [
		["继续", _close_pause],
		["存档", _open_pause_save],
		["设置", _open_pause_settings],
		["重新开始本小关", _restart_room],
		["返回主菜单", _return_menu],
	]
	var y := 56
	for o in opts:
		var b := _button(o[0], Vector2(50, y), Vector2(300, 38))
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		b.connect("pressed", o[1])
		panel.add_child(b)
		y += 50
	# 存档子面板（初始隐藏）：3 槽 + 返回
	var save_sub := Control.new()
	save_sub.name = "SaveSub"
	save_sub.mouse_filter = Control.MOUSE_FILTER_PASS
	save_sub.position = Vector2.ZERO
	save_sub.size = panel.size
	var sbg := ColorRect.new()
	sbg.color = Color(0.08, 0.06, 0.15, 0.98)
	sbg.size = panel.size
	save_sub.add_child(sbg)
	save_sub.add_child(_label("存档", Vector2(24, 14), 22))
	var sy := 56
	for s in 3:
		var sb := _button("", Vector2(50, sy), Vector2(300, 40))
		sb.process_mode = Node.PROCESS_MODE_ALWAYS
		var desc: String = SaveManager.slot_desc(s + 1)
		if desc == "":
			sb.text = "存档 %d · 空" % (s + 1)
		else:
			sb.text = "存档 %d · %s" % [s + 1, desc]
		sb.connect("pressed", _do_save.bind(s + 1))
		save_sub.add_child(sb)
		sy += 52
	var sb_back := _button("返回", Vector2(50, sy + 6), Vector2(300, 38))
	sb_back.process_mode = Node.PROCESS_MODE_ALWAYS
	sb_back.connect("pressed", func():
		save_sub.visible = false)
	save_sub.add_child(sb_back)
	save_sub.visible = false
	panel.add_child(save_sub)
	# 设置子面板（初始隐藏）：主音量滑块 + 返回
	var set_sub := Control.new()
	set_sub.name = "SetSub"
	set_sub.mouse_filter = Control.MOUSE_FILTER_PASS
	set_sub.position = Vector2.ZERO
	set_sub.size = panel.size
	var sbg2 := ColorRect.new()
	sbg2.color = Color(0.08, 0.06, 0.15, 0.98)
	sbg2.size = panel.size
	set_sub.add_child(sbg2)
	set_sub.add_child(_label("设置", Vector2(24, 14), 22))
	var vlab := _label("主音量", Vector2(50, 62), 16)
	set_sub.add_child(vlab)
	var slider := HSlider.new()
	slider.name = "PauseVol"
	slider.process_mode = Node.PROCESS_MODE_ALWAYS
	slider.position = Vector2(130, 62)
	slider.size = Vector2(180, 24)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = float(ProjectSettings.get_setting("game/master_volume", 80.0))
	slider.value_changed.connect(_on_pause_vol)
	set_sub.add_child(slider)
	var vval := _label("%d%%" % int(slider.value), Vector2(330, 62), 16)
	vval.name = "PauseVolVal"
	set_sub.add_child(vval)
	# 调试开关：F12 全开地图 / F11 秒杀敌人（默认关闭）
	var f12_t := CheckButton.new()
	f12_t.name = "PauseF12"
	f12_t.process_mode = Node.PROCESS_MODE_ALWAYS
	f12_t.position = Vector2(50, 96)
	f12_t.text = "F12 全开地图"
	f12_t.button_pressed = GameManager.debug_full_map
	f12_t.toggled.connect(func(on: bool) -> void: GameManager.debug_full_map = on)
	set_sub.add_child(f12_t)
	var f11_t := CheckButton.new()
	f11_t.name = "PauseF11"
	f11_t.process_mode = Node.PROCESS_MODE_ALWAYS
	f11_t.position = Vector2(220, 96)
	f11_t.text = "F11 秒杀敌人"
	f11_t.button_pressed = GameManager.debug_kill_all
	f11_t.toggled.connect(func(on: bool) -> void: GameManager.debug_kill_all = on)
	set_sub.add_child(f11_t)
	var set_back := _button("返回", Vector2(50, 130), Vector2(300, 38))
	set_back.process_mode = Node.PROCESS_MODE_ALWAYS
	set_back.connect("pressed", func():
		set_sub.visible = false)
	set_sub.add_child(set_back)
	set_sub.visible = false
	panel.add_child(set_sub)
	_ui_layer.add_child(panel)
	_pause_overlay = panel


func _close_pause() -> void:
	if not _pause_open:
		return
	_pause_open = false
	get_tree().paused = false
	_freeze_world(false)
	if is_instance_valid(_pause_overlay):
		_pause_overlay.queue_free()
	_pause_overlay = null
	_set_gm_locked(false)


## 暂停菜单手动存档到指定槽（1/2/3），保存后回到菜单。
func _do_save(slot: int) -> void:
	SaveManager.save_game(slot)
	if is_instance_valid(_pause_overlay):
		var sub := _pause_overlay.get_node_or_null("SaveSub") as Control
		if sub != null:
			sub.visible = false
	toast("已保存到存档 %d" % slot)


## 暂停菜单打开存档子面板：刷新槽位显示。
func _open_pause_save() -> void:
	if not is_instance_valid(_pause_overlay):
		return
	var sub := _pause_overlay.get_node_or_null("SaveSub") as Control
	if sub == null:
		return
	var idx := 0
	for c in sub.get_children():
		if c is Button and c.text.begins_with("存档"):
			var desc: String = SaveManager.slot_desc(idx + 1)
			c.text = ("存档 %d · %s" % [idx + 1, desc]) if desc != "" else ("存档 %d · 空" % (idx + 1))
			idx += 1
	sub.visible = true


## 暂停菜单打开设置子面板。
func _open_pause_settings() -> void:
	if is_instance_valid(_pause_overlay):
		var sub := _pause_overlay.get_node_or_null("SetSub") as Control
		if sub != null:
			sub.visible = true


## 暂停菜单音量滑块：应用到 master 总线 + 持久化（与标题设置共用键）。
func _on_pause_vol(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.0001) / 100.0))
	AudioServer.set_bus_mute(0, value <= 0.0)
	ProjectSettings.set_setting("game/master_volume", value)
	ProjectSettings.save()
	if is_instance_valid(_pause_overlay):
		var sub := _pause_overlay.get_node_or_null("SetSub") as Control
		if sub != null:
			var vval := sub.get_node_or_null("PauseVolVal") as Label
			if vval != null:
				vval.text = "%d%%" % int(value)


## 重新开始本小关：回满血蓝 + 重载当前房间（普通房怪刷新；Boss 已清则无 Boss）。
func _restart_room() -> void:
	_pause_open = false
	get_tree().paused = false
	_freeze_world(false)
	if is_instance_valid(_pause_overlay):
		_pause_overlay.queue_free()
	_pause_overlay = null
	GameManager.hp = GameManager.max_hp
	GameManager.mana = GameManager.max_mana
	GameManager.emit_signal("stats_changed")
	_set_gm_locked(false)
	transition_to(GameManager.current_room, true)

func _return_menu() -> void:
	_pause_open = false
	get_tree().paused = false
	_freeze_world(false)
	if is_instance_valid(_pause_overlay):
		_pause_overlay.queue_free()
	_pause_overlay = null
	# 清理 GameManager 瞬态标志（防残留：返回标题后再进游戏状态错乱）
	GameManager.input_locked = false
	GameManager.cutscene_frozen = false
	GameManager.weak_window = false
	GameManager.game_completed = false
	GameManager.prologue_pending = false
	GameManager.prologue_dialog_active = false
	# 通关状态下走这里：清理通关标记与覆盖层引用
	_completed_state_active = false
	_set_gm_locked(false)   # 双保险：返回主菜单后也解锁输入
	get_tree().change_scene_to_file("res://src/scenes/Main.tscn")

func _toggle_dev() -> void:
	GameManager.dev_mode = not GameManager.dev_mode
	if _dev_label != null:
		_dev_label.visible = GameManager.dev_mode
	if GameManager.dev_mode:
		toast("开发者模式：开（地图内选层跳关）")
	else:
		toast("开发者模式：关")
	var mu := get_node_or_null("MapUI")
	if mu != null and mu.has_method("redraw"):
		mu.redraw()

func dev_goto_layer(l: int) -> void:
	if l < 1 or l > 3:
		return
	GameManager.layer_index = l
	MapData.load_layer(l)
	GameManager.emit_signal("stats_changed")
	transition_to(LevelData.start_room(l), true)
	toast("进入 " + MapData.LAYER[l])
	var mu := get_node_or_null("MapUI")
	if mu != null and mu.has_method("redraw"):
		mu.redraw()

# ============ 开场序列（醒来独白，居中跟随，无放大） ============
func _play_prologue() -> void:
	_prologue_active = true
	GameManager.prologue_dialog_active = true   # 对话中：地面武器延迟出现（§5.2 弥绘倒出武器）
	_set_gm_locked(true)
	print("[GALGAME] _play_prologue 触发")
	# v4.0 §5.2 苏醒对话（文档最新版）：Galgame 对话框 + 弥绘立绘 + 弥果卷立绘
	# （打字机逐句，点击/回车推进，ESC 跳过）。momo=弥绘左槽、zhujue=弥果卷右槽。
	# 最后两句是旁白（narration=true）：只显示名字、不显示立绘——两槽立绘全部隐藏。
	_create_galgame_dialog([
		{ "name": "弥绘", "role": "momo", "text": "……这里是……梦？怎么这么真实。等等——", "portrait_left": MOMO_HAPPY, "portrait_right": ZHUJUE_PITY },
		{ "name": "弥绘", "role": "momo", "text": "啊！你……你是今天的弥果卷！喂，醒醒——！", "portrait_left": MOMO_HAPPY, "portrait_right": ZHUJUE_PITY },
		{ "name": "弥果卷", "role": "zhujue", "text": "呜~我要上班，我要赚米给momo打钱。呜~", "portrait_left": MOMO_HAPPY, "portrait_right": ZHUJUE_PITY },
		{ "name": "弥绘", "role": "momo", "text": "（弥果卷没反应，只是发出梦呓）……糟糕，是‘魂被拖走了’的状态。", "portrait_left": MOMO_PITY, "portrait_right": ZHUJUE_PITY },
		{ "name": "弥绘", "role": "momo", "text": "身体还在，但灵魂不在。这是……噩梦核把灵魂锁在深处了。放着不管的话，你可能再也做不了美梦了。", "portrait_left": MOMO_PITY, "portrait_right": ZHUJUE_PITY },
		{ "name": "弥绘", "role": "momo", "text": "……没办法，谁让你是我的粉丝呢。我带你去把魂找回来——走，去把这场噩梦，一口吃掉！", "portrait_left": MOMO_ANGER, "portrait_right": ZHUJUE_PITY },
		{ "name": "弥绘", "role": "momo", "text": "是时候使用我的梦境武器了。", "portrait_left": MOMO_ANGER, "portrait_right": ZHUJUE_PITY },
		{ "name": "旁白", "narration": true, "text": "弥绘拿出了自己的口袋（梦境收纳袋），然后往外倒，3把武器掉落在了地上然后放大。" },
		{ "name": "旁白", "narration": true, "text": "弥绘把粉丝的本体收进自己的口袋（梦境收纳袋），拍了拍口袋，推开出租屋的门。门外不是走廊，而是一条延伸到黑暗里的公路。" },
	], _end_prologue)


## 新建并播放一段 Galgame 对话（挂屏幕空间 _ui_layer；finished 后自动释放）。
func _create_galgame_dialog(lines: Array[Dictionary], on_finish: Callable = Callable()) -> void:
	_galgame_active = true
	var dlg := GalgameDialog.new()
	_ui_layer.add_child(dlg)
	_galgame_dialog = dlg
	print("[GALGAME] 对话框已创建，句数=%d" % lines.size())
	# 包装回调：先清 active 标志（ESC 不再弹暂停），再执行调用方回调
	dlg.play(lines, func() -> void:
		_galgame_active = false
		_galgame_dialog = null
		if on_finish.is_valid():
			on_finish.call())


## 第一关 Boss 前演出（v4.0 §5.3 + v5.2 扩展）：进入未清的 f1_r7 时触发。
## 演出序列：momo 斜着走到地图中间 → 背景视频第一段(4s) → boss 出现（静止）→ 弥绘对话 → 对战开始。
## 状态机 _boss_cut_phase：1=momo 走 2=等视频暂停(4s) 3=对话中(结束即开战)
var _boss_cut_active := false
var _boss_cut_phase := 0

func _check_boss_cutscene() -> void:
	if _room == null or not _room.has_method("spawn_boss_now"):
		return
	var rid: String = GameManager.current_room
	if bool(GameManager.r7_video_done.get(rid, false)):
		return   # 视频已播完（boss 已清）：无演出
	# 锁输入 + 冻结敌人（momo 走位期间不受打扰）
	_set_gm_locked(true)
	GameManager.cutscene_frozen = true
	# momo 自动走到地图中间偏左上（斜着往上走；boss 在右上方对峙）
	var p: Node2D = $World/Player
	var target: Vector2 = _room.global_position + Vector2(-60, -30)
	p.call("auto_walk_to", target, 150.0)
	_boss_cut_active = true
	_boss_cut_phase = 1


func _tick_boss_cutscene(delta: float) -> void:
	if _room == null or not is_instance_valid(_room):
		return
	var p: Node2D = $World/Player
	match _boss_cut_phase:
		1:
			# momo 走到位 → 视频第一段开始播（boss 还未出现）
			if p == null or not bool(p.call("is_auto_walking")):
				_boss_cut_phase = 2
				_room.call("play_bg_segment1")
		2:
			# 视频播 4s 自动暂停后 → boss 出现 + Boss 战禁区启用（Blocked_2/3）+ 弥绘对话（boss 静止）
			if _room.has_method("is_bg_segment1_paused") and bool(_room.call("is_bg_segment1_paused")):
				_boss_cut_phase = 3
				_room.call("spawn_boss_now")
				if _room.has_method("set_boss_arena_blocks"):
					_room.call("set_boss_arena_blocks", true)
				_play_boss_intro_dialogue()
		3:
			pass   # 对话中，finished 回调里 _finish_boss_cutscene


func _finish_boss_cutscene() -> void:
	_boss_cut_active = false
	_boss_cut_phase = 0
	GameManager.cutscene_frozen = false
	_set_gm_locked(false)
	_freeze_world(false)


## Boss 前对话（v4.0 §5.3）：按层选台词。f1 由演出状态机触发、f2/f3 进房直接触发。
## 演出期间锁输入 + 冻结敌人（Boss 入场后打正在看对话的玩家）。
func _play_boss_intro_dialogue() -> void:
	_set_gm_locked(true)
	_freeze_world(true)
	var lines: Array[Dictionary] = []
	match GameManager.layer_index:
		2:
			lines = [
				{ "name": "弥绘", "role": "momo", "text": "好恶心的怪物啊，我可不想被它碰到", "portrait_left": MOMO_ANGER },
			]
		3:
			lines = [
				{ "name": "本体", "narration": true, "text": "……momo……momo……我喜欢你……" },
				{ "name": "弥绘", "role": "momo", "text": "……你一直有在认真看我的直播啊。那这场梦，我更得让你醒过来了——老板，开工了！", "portrait_left": MOMO_ANGER, "portrait_right": ZHUJUE_PITY },
			]
		_:
			lines = [
				{ "name": "弥绘", "role": "momo", "text": "末班车……？都这个点了还通车……不对，这感觉——是 Boss！", "portrait_left": MOMO_HAPPY },
			]
	_create_galgame_dialog(lines, func() -> void:
		_finish_boss_cutscene())


func _end_prologue() -> void:
	if not _prologue_active:
		return
	_prologue_active = false
	_galgame_active = false   # ESC 跳过路径：对话框被 queue_free，不触发 finished 回调，需手动清标志
	GameManager.prologue_dialog_active = false   # 对话结束 → 允许地面武器出现
	# 释放 Galgame 对话框（finished 已由组件触发，这里只做清理兜底）
	if is_instance_valid(_galgame_dialog):
		_galgame_dialog.queue_free()
		_galgame_dialog = null
	_set_gm_locked(false)
	# v4.0 §5.2：弥绘「倒出 3 把武器」——对话结束才生成地面武器（开局武器延迟出现）
	if _room != null and is_instance_valid(_room) and _room.has_method("spawn_weapons_now"):
		_room.call("spawn_weapons_now")


func _player_camera() -> Camera2D:
	var p: Node2D = $World/Player
	return p.get_node_or_null("Camera") as Camera2D


# 固定视角：把整间房(880x500)居中显示在视口，不随玩家移动（玩家在房间内自由走，画面不动）。
# canvas_transform 映射：screen = z * world + t。令房间中心(原点)落屏幕中心 → t = center。
# _cam_zoom<=0 时自动计算 fit 缩放让整房可见；>0 时沿用该固定倍率（手动放大）。
# 与 stretch_mode=canvas_items 兼容（Camera2D 内部也是这么写的）。
func _update_camera() -> void:
	if Engine.is_editor_hint():
		return
	var vp := get_viewport()
	var center := vp.get_visible_rect().size * 0.5
	var z: float = _cam_zoom
	if z <= 0.01:
		# 适配整房（留 2% 边距），保证 880x500 房间完整可见、固定不跟随。
		z = min(center.x * 2.0 / _layer_w, center.y * 2.0 / _layer_h) * 0.98
	# 聚焦当前房间实例的世界位置（房间挂在锚点下，global_position = 锚点世界坐标）：
	# 画面始终以当前房间中心为视觉中心，房间内走动画面不动（固定视角）。
	# _cam_focus_offset 为演出（f1_r3/r4 进入关卡演出）期间的相机偏移，正常为 ZERO。
	var focus := Vector2.ZERO
	if _room != null and is_instance_valid(_room):
		focus = _room.global_position + _cam_focus_offset
	# Transform2D(rotation, position) 的双参数构造会把第一个参数当成弧度旋转，
	# 不能把缩放值 z 直接传进去，否则 z=1.0 会让整个世界旋转 1 弧度。
	# 显式构造无旋转的缩放矩阵：screen = z * (world - focus) + center。
	var ct: Transform2D = Transform2D(
		Vector2(z, 0.0),
		Vector2(0.0, z),
		center - focus * z
	)
	vp.canvas_transform = ct


func _set_gm_locked(v: bool) -> void:
	# 防御：GameManager 运行期若未正常初始化（input_locked 不存在），写该属性会报错并中断当前函数。
	# 安全跳过写入；待缓存修复、GameManager 正常后此函数即正常落值。
	if GameManager != null and "input_locked" in GameManager:
		GameManager.input_locked = v


func _is_gm_locked() -> bool:
	# 防御：GameManager 运行期若未正常初始化（input_locked 不存在），直接读取会每帧刷屏。
	# 安全返回 false（不锁输入），保证游戏可运行、便于排查。
	if GameManager == null or not ("input_locked" in GameManager):
		return false
	return GameManager.input_locked


# ============ 场景内武器拾取 / 交换 ============
func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return   # ESC 全暂停：一切逻辑停摆（相机/演出/推进），世界由 World PAUSABLE 停，菜单 ALWAYS 可交互
	if not Engine.is_editor_hint():
		_update_camera()   # 每帧居中：即便开场/锁输入期间也保证玩家在屏幕正中
		if _intro_active:
			_tick_intro(_delta)   # 演出推进（f1_r3/r4 首次进入）：锁输入期间也要跑
		if _boss_cut_active:
			_tick_boss_cutscene(_delta)   # f1_r7 boss 演出推进（momo 走/等视频/对话）
	if _prologue_active or _is_gm_locked() or _room == null:
		if _near_pickup != null:
			_near_pickup = null
			_update_pickup_prompt("")
		return
	var p: Node2D = $World/Player
	var best: Node2D = null
	var best_d: float = INF
	for pk in _pickups:
		if not is_instance_valid(pk) or not bool(pk.call("can_interact")):
			continue
		var d: float = p.global_position.distance_to(pk.global_position)
		if d < _PICKUP_RADIUS and d < best_d:
			best_d = d
			best = pk
	_near_pickup = best
	if best != null:
		_update_pickup_prompt(str(best.call("prompt_text")))
	else:
		_update_pickup_prompt("")


func _build_pickup_prompt() -> void:
	_pickup_panel = Panel.new()
	_pickup_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := 220.0
	var h := 34.0
	var vsize := get_window().get_visible_rect().size
	_pickup_panel.position = Vector2(vsize.x - w - 24.0, 62.0)   # 右上角（toast 下方）
	_pickup_panel.size = Vector2(w, h)
	_pickup_label = Label.new()
	_pickup_label.position = Vector2(10, 6)
	_pickup_label.add_theme_font_size_override("font_size", 15)
	_pickup_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_pickup_panel.add_child(_pickup_label)
	_pickup_panel.visible = false
	_ui_layer.add_child(_pickup_panel)


func _update_pickup_prompt(text: String) -> void:
	if _pickup_panel == null:
		return
	if text == "":
		_pickup_panel.visible = false
	else:
		_pickup_label.text = "[F] " + text
		_pickup_panel.visible = true


func _make_weapon_pickup(wid: String, pos: Vector2) -> Node2D:
	var pk: Node2D = WeaponPickupScript.new()
	pk.set("weapon_id", wid)
	pk.global_position = pos
	return pk


## 房间场景里 WeaponHandle 生成的地面武器登记进可拾取列表（RoomManager 调用）。
func register_pickup(pk: Node2D) -> void:
	if is_instance_valid(pk) and not _pickups.has(pk):
		_pickups.append(pk)


# 玩家是否已持有武器（WeaponSystem loadout 非空）。供 RoomManager._spawn_weapons 判断：
# 已持有武器时不再生成开局地面武器（修复：拿走武器离开关卡回来又变 3 把）。
func player_has_weapon() -> bool:
	var p: Node2D = $World/Player
	var sys := p.get_node_or_null("Weapon")
	if sys != null and sys.has_method("get_active_id"):
		return str(sys.call("get_active_id")) != ""
	return false


# 显示/隐藏玩家（f1_r3/f1_r4 进入关卡演出用：首次进入先隐藏 momo，演出结束再显示）。
func set_player_visible(v: bool) -> void:
	var p := get_node_or_null("World/Player") as Node2D
	if p != null:
		p.visible = v


# ============ f1_r3/f1_r4 进入关卡演出 ============
# 首次进入 f1_r3/r4：播放开门动画 → 相机下移展示「暂停的怪」→ 相机回中 → momo 出现关卡开始。
# 再次进入（r34_opened 已记录）无演出，门保持最后一帧（RoomManager._find_enter_door_anim 处理）。
func _check_enter_intro() -> void:
	if _room == null or not _room.has_method("get_enter_door_anim"):
		return
	var anim: AnimatedSprite2D = _room.call("get_enter_door_anim") as AnimatedSprite2D
	if anim == null:
		return
	var rid: String = GameManager.current_room
	if bool(GameManager.r34_opened.get(rid, false)):
		return   # 已进过：无演出
	# 首次进入：开始演出
	GameManager.r34_opened[rid] = true
	_intro_anim = anim
	_intro_phase = 1
	_intro_t = 0.0
	_intro_active = true
	var ec: Variant = _room.call("get_enemy_center_local")
	_enemy_center = ec if ec is Vector2 else Vector2.ZERO
	_set_gm_locked(true)
	GameManager.cutscene_frozen = true
	set_player_visible(false)
	anim.play("default")


# 演出状态机推进（_physics_process 每帧调用，锁输入期间也运行）。
func _tick_intro(delta: float) -> void:
	_intro_t += delta
	var k: float
	match _intro_phase:
		1:
			# 门动画播放中：等它播完（非循环动画 is_playing 变 false）
			if _intro_anim == null or not is_instance_valid(_intro_anim) or not _intro_anim.is_playing():
				_intro_phase = 2
				_intro_t = 0.0
		2:
			# 视角下移到怪群（平滑）
			k = clampf(_intro_t / _INTRO_PAN_T, 0.0, 1.0)
			_cam_focus_offset = _enemy_center * smoothstep(0.0, 1.0, k)
			if _intro_t >= _INTRO_PAN_T:
				_intro_phase = 3
				_intro_t = 0.0
		3:
			# 停在怪群展示
			if _intro_t >= _INTRO_HOLD_T:
				_intro_phase = 4
				_intro_t = 0.0
		4:
			# 视角回中
			k = clampf(_intro_t / _INTRO_PAN_T, 0.0, 1.0)
			_cam_focus_offset = _enemy_center * (1.0 - smoothstep(0.0, 1.0, k))
			if _intro_t >= _INTRO_PAN_T:
				_finish_intro()


# 演出结束：敌人解冻 + 解锁输入 + momo 出现，关卡正式开始。
func _finish_intro() -> void:
	_intro_active = false
	_intro_phase = 0
	_intro_t = 0.0
	_cam_focus_offset = Vector2.ZERO
	_intro_anim = null
	GameManager.cutscene_frozen = false
	_set_gm_locked(false)
	set_player_visible(true)


# 驿站交互：玩家进入/离开驿站判定框（RoomManager 通知）。进入后按 F 弹确认回满血。
# 「按 F 回血」提示由 RoomManager 在驿站上方挂的 Label 显示（进框可见/离开隐藏），此处只维护状态。
var _inn_nearby := false
func set_inn_nearby(v: bool) -> void:
	_inn_nearby = v


# 测试传送门交互：靠近按 F 一键跳到结尾剧情（花海场景）。
var _portal_nearby := false
func set_portal_nearby(v: bool) -> void:
	_portal_nearby = v


## 测试用：一键跳到结尾剧情（花海）。置 game_completed 让花海播完回 Game 进通关态（两选项）。
func _jump_to_epilogue() -> void:
	GameManager.game_completed = true
	_set_gm_locked(true)
	get_tree().change_scene_to_file("res://src/scenes/Epilogue.tscn")


func _confirm_inn_heal() -> void:
	var d := ConfirmationDialog.new()
	d.dialog_text = "要回满血量吗？"
	d.get_ok_button().text = "回满血"
	d.confirmed.connect(_do_inn_heal)
	add_child(d)
	d.popup_centered()


func _do_inn_heal() -> void:
	GameManager.hp = GameManager.max_hp
	GameManager.emit_signal("stats_changed")
	toast("已回满血")


# 按 F 拾取/交换武器：若已持有武器，则旧武器掉到脚下（短暂免疫，避免瞬间又换回）。
func _pick_up_weapon(pk: Node2D) -> void:
	if not is_instance_valid(pk):
		return
	var wid: String = str(pk.get("weapon_id"))
	var p: Node2D = $World/Player
	var sys := p.get_node_or_null("Weapon")
	var old := ""   # 提到函数体层：下面 if 块内赋值，块外判断 old==""（首次拿到武器）触发开门
	if sys != null and sys.has_method("get_active_id"):
		old = str(sys.call("get_active_id"))
		if old == wid:
			return
		if old != "":
			var drop := _make_weapon_pickup(old, p.global_position + Vector2(0.0, 28.0))
			drop.call("just_dropped")
			$World.add_child(drop)
			_pickups.append(drop)
	sys.call("replace_active", wid)
	if old == "":
		# 首次拿到武器（开场房）：播放开门动画，播完门判定框生效（下一关入口开启）
		if _room != null and _room.has_method("play_open_door"):
			_room.call("play_open_door")
	GameManager.emit_signal("stats_changed")
	# 标记地面武器记录：当前房间的该武器已被拾取（置空，切房回来不再生成它）
	var key := "f%d-%s" % [GameManager.layer_index, GameManager.current_room]
	if GameManager.ground_weapons.has(key):
		var slots: Array = GameManager.ground_weapons[key]
		var idx: int = slots.find(wid)
		if idx >= 0:
			slots[idx] = ""
	var w: Dictionary = Weapons.get_weapon(wid)
	if not w.is_empty():
		toast("装备：" + w["name"])
	_pickups.erase(pk)
	pk.queue_free()


# ============ 小工具 ============
func _label(text: String, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	return b
