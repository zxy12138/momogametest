@tool
extends Node2D
class_name WeaponHandle

## 武器手柄：房间场景里直接摆放（武器图标缩略 + 阴影 + 名字，可拖）。
## weapon_type 用 int + @export_enum（最可靠的下拉）；display_scale 定义地面武器显示大小。
## 运行期 RoomManager 据此生成地面武器（WeaponPickup）并可被 F 拾取。

const WIDS := ["staff", "sword", "scythe", "bow", "hammer", "whip", "spear", "axe"]

@export_enum("staff", "sword", "scythe", "bow", "hammer", "whip", "spear", "axe")
var weapon_type: int = 0

## 地面武器显示大小（运行期 WeaponPickup.display_scale）
@export var display_scale: float = 0.22

var _last_type := -1


func _ready() -> void:
	if Engine.is_editor_hint():
		_last_type = weapon_type
		_redraw()
	else:
		visible = false


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _last_type != weapon_type:
		_last_type = weapon_type
		_redraw()


## 当前选中的武器 id（供 RoomManager 生成地面武器）。
func weapon_id() -> String:
	return WIDS[clampi(weapon_type, 0, WIDS.size() - 1)]


func _redraw() -> void:
	for c in get_children():
		c.queue_free()
	var wid: String = weapon_id()
	var sh := HandleUtil.shadow_polygon(Vector2(1.6, 0.8))
	sh.position = Vector2(0, 16)
	sh.z_index = 79
	add_child(sh)
	var sp := Sprite2D.new()
	# 直接用 load() 加载：Weapons 是 class_name 全局类，编辑器预览期可安全访问。
	# 之前用 GameManager.load_tex()（autoload）在 @tool 预览期是 placeholder，调用崩/返回 null → 武器不显示样子。
	var tex := load(Weapons.get_icon_path(wid)) as Texture2D
	if tex != null:
		sp.texture = tex
	sp.scale = Vector2(display_scale, display_scale)
	sp.z_index = 80
	add_child(sp)
	var w: Dictionary = Weapons.get_weapon(wid)
	var nm := str(w.get("name", wid)) if not w.is_empty() else wid
	var lab := Label.new()
	lab.text = nm
	lab.position = Vector2(-26, 20)
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	lab.z_index = 81
	add_child(lab)
