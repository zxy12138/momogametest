# 《梦境逐影》场景内的地面武器。
# 玩家走过去按 F 即可拾取；若已持有武器，则旧武器掉到地上（由 Game 负责生成掉落物）。
# 本节点只负责自身表现与数据；邻近检测与拾取逻辑在 Game.gd 中统一处理。
class_name WeaponPickup
extends Node2D

## 导出：这把地面武器对应的武器 id（见 Weapons.DATA）。
@export var weapon_id: String = ""

## 地面武器显示大小（默认 0.22；场景里 WeaponHandle.display_scale 可自定义）。
@export var display_scale: float = 0.22

const IMMUNE_TIME := 0.6   ## 刚被丢到地上时的不可拾取免疫窗口（秒），避免交换瞬间又换回来

var _spr: Sprite2D
var _immune: float = 0.0


func _ready() -> void:
	add_to_group("weapon_pickup")
	_spr = Sprite2D.new()
	var w: Dictionary = Weapons.get_weapon(weapon_id)
	var tex := GameManager.load_tex(Weapons.get_icon_path(weapon_id)) if w != null else null
	if tex != null:
		_spr.texture = tex
	else:
		# 兜底：洋红块，保证不崩
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 0, 1, 1))
		_spr.texture = ImageTexture.create_from_image(img)
	_spr.z_index = int(global_position.y)
	_spr.scale = Vector2(display_scale, display_scale)   # 大小可被 WeaponHandle.display_scale 自定义
	add_child(_spr)
	# 脚下椭圆阴影（视觉点缀，增强"在地面"的立体感）
	var sh := HandleUtil.shadow_polygon(Vector2(0.9, 0.4))
	sh.position = Vector2(0, 10)
	sh.z_index = _spr.z_index - 1
	add_child(sh)
	# 轻微上下浮动，提示这是可交互物。
	# 必须用节点方法 create_tween()（绑定本节点，随节点销毁自动 kill）：
	# 若用 get_tree().create_tween()（独立 tween），节点被切房清理后 tween 仍存活，
	# 目标 _spr 已失效 → 每帧步骤立即完成 + set_loops(-1) 无限重启 → "Infinite loop detected"（3 把武器=3 次报错）。
	var tw := create_tween()
	tw.set_loops(-1)
	tw.tween_property(_spr, "position:y", -4.0, 0.7)
	tw.chain().tween_property(_spr, "position:y", 4.0, 0.7)


func _process(delta: float) -> void:
	if _immune > 0.0:
		_immune -= delta
	z_index = int(global_position.y)


## 刚被丢到地上时调用：给它一个短暂免疫窗口，防止立刻又被同一玩家拾取。
func just_dropped() -> void:
	_immune = IMMUNE_TIME


## 当前是否可被拾取（免疫期内不可）。
func can_interact() -> bool:
	return _immune <= 0.0


## 玩家靠近时显示的提示文本。
func prompt_text() -> String:
	var w: Dictionary = Weapons.get_weapon(weapon_id)
	if w == null:
		return "拾取未知武器"
	return "拾取 " + w["name"]
