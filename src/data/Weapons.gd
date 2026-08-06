# 《梦境逐影》武器数据（8 把基础武器，无升阶）。
# 由 Weapons.gd 数据驱动全部武器。每把武器带 atk 行为标签，供新「悬浮三武器」系统区分攻击形态。
# 行为标签 atk：
#   ranged_bolt  法杖：远程发射光弹
#   melee_arc    剑：近战挥砍 + 剑气
#   melee_ring   镰刀：近战 360° 环斩
#   ranged_arrow 弓：远程发射箭矢（同法杖远程逻辑）
#   melee_slam   锤：近战前方砸地 AOE
#   melee_fan    鞭：近战扇形 AOE（范围比剑远）
#   melee_line   枪：近战直线突刺（范围比鞭短、窄）
#   ranged_spin  斧：远程飞旋斧（攻速慢、判定范围比弓大）
class_name Weapons

const ICON = "res://assets/weapons/icons/"
const FX = "res://assets/weapons/fx/"

# 通用字段：
#  kind: "ranged" | "melee"（兼容旧单武器逻辑)
#  atk:  行为标签（见上方）
#  dmg / cooldown(sec) / crit_bonus(float)
#  ranged: proj(fx 贴图), proj_speed, pierce, bounce, aoe(半径,0=无), spin(bool)
#  melee:  arc(deg, 360=全周), reach(px), dash(bool), aoe(半径,0=无)
#  knockback / effect(str) / effect_time
const DATA = {
	"staff":  {name="梦幻法杖", kind="ranged", atk="ranged_bolt", dmg=12, cooldown=0.30, crit_bonus=0.0,  proj=FX+"weapon_fx_staff.png",  proj_speed=420, pierce=2, bounce=0, aoe=0,  icon=ICON+"weapon_staff.png",  upg=""},
	"sword":  {name="星芒短剑", kind="melee",  atk="melee_arc",   dmg=15, cooldown=0.30, crit_bonus=0.03, arc=95,  reach=46, combo=3, dash=false, icon=ICON+"weapon_sword.png",  upg=""},
	"scythe": {name="噩梦镰刀", kind="melee",  atk="melee_ring",  dmg=11, cooldown=0.55, crit_bonus=0.01, arc=360, reach=54, combo=1, dash=false, slow=1.0, icon=ICON+"weapon_scythe.png", upg=""},

	"bow":    {name="梦境弓",   kind="ranged", atk="ranged_arrow", dmg=16, cooldown=0.55, crit_bonus=0.03, proj=FX+"weapon_fx_bow.png",   proj_speed=560, pierce=1, bounce=0, aoe=0,  icon=ICON+"weapon_bow.png",    upg=""},
	"hammer": {name="噩梦骨锤", kind="melee",  atk="melee_slam",  dmg=24, cooldown=0.85, crit_bonus=0.0,  arc=110, reach=50, combo=1, dash=false, knockback=80, aoe=60, icon=ICON+"weapon_hammer.png", upg=""},
	"whip":   {name="暗影长鞭", kind="melee",  atk="melee_fan",    dmg=13, cooldown=0.45, crit_bonus=0.02, arc=70,  reach=80, combo=1, dash=false, aoe=0,  icon=ICON+"weapon_whip.png",   upg=""},
	"spear":  {name="星穿长枪", kind="melee",  atk="melee_line",   dmg=18, cooldown=0.40, crit_bonus=0.02, arc=30,  reach=66, combo=1, dash=true,  icon=ICON+"weapon_spear.png",  upg=""},
	"axe":    {name="旋风飞斧", kind="ranged", atk="ranged_spin",  dmg=20, cooldown=0.70, crit_bonus=0.01, proj=FX+"weapon_fx_axe.png",   proj_speed=300, pierce=3, bounce=0, aoe=36, spin=true, icon=ICON+"weapon_axe.png",    upg=""},
}

# 兼容旧引用：起始三选一、场景内替换池。
const STARTERS = ["staff", "sword", "scythe"]
const SWAP_POOL = ["bow", "hammer", "whip", "spear", "axe"]

# 全部 8 把（新「悬浮三武器」系统从这池里随机抽 3 把）。
const POOL = ["staff", "sword", "scythe", "bow", "hammer", "whip", "spear", "axe"]


static func get_weapon(id: String) -> Dictionary:
	return DATA.get(id, {})


static func get_icon_path(id: String) -> String:
	if DATA.has(id):
		return DATA[id]["icon"]
	return ""


static func get_fx_path(id: String) -> String:
	if DATA.has(id):
		return DATA[id].get("proj", DATA[id].get("fx", ""))
	return ""


static func can_upgrade(id: String) -> bool:
	return DATA.has(id) and DATA[id].get("upg", "") != ""


# 从全部 8 把里随机抽 count 把（默认 3），不重复。
static func pick_three(count: int = 3) -> Array[String]:
	var pool := POOL.duplicate()
	var out: Array[String] = []
	while out.size() < count and pool.size() > 0:
		var i := randi() % pool.size()
		out.append(pool[i])
		pool.remove_at(i)
	return out
