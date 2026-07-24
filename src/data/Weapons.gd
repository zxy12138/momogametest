# 《梦境逐影》武器数据
# 9 把基础武器（3 初始 + 6 更换池） + 9 把升阶版
# 字段说明见下方注释。Weapon.gd 读取此处数据驱动所有武器。
class_name Weapons

const ICON = "res://assets/weapons/icons/"
const PROJ = "res://assets/weapons/projectiles/"

# 通用字段：
#  kind: "ranged" | "melee"
#  dmg / cooldown(sec) / crit_bonus(float)
#  ranged: proj, proj_speed, pierce, bounce, aoe(radius,0=无)
#  melee:  arc(deg), reach(px), combo, dash(bool)
#  slow / freeze / knockback / effect(str) / effect_time
#  upg: 升阶后的武器 id（基础武器才有）
const DATA = {
	"staff":      {name="梦幻法杖", kind="ranged", dmg=12, cooldown=0.32, crit_bonus=0.0, proj=PROJ+"W-020_dream_light_bolt.png", proj_speed=360, pierce=2, bounce=0, aoe=0, icon=ICON+"W-001_dream_staff_icon.png", upg="staff_adv"},
	"sword":      {name="星芒短剑", kind="melee", dmg=14, cooldown=0.28, crit_bonus=0.03, arc=100, reach=38, combo=3, dash=false, icon=ICON+"W-002_starlight_sword_icon.png", upg="sword_adv"},
	"scythe":     {name="噩梦镰刀", kind="melee", dmg=11, cooldown=0.5, crit_bonus=0.01, arc=160, reach=50, combo=1, dash=false, slow=1.0, icon=ICON+"W-003_nightmare_scythe_icon.png", upg="scythe_adv"},

	"moon":       {name="月轮飞镖", kind="ranged", dmg=10, cooldown=0.4, crit_bonus=0.02, proj=PROJ+"W-022_moon_wheel_dart_projectile.png", proj_speed=320, pierce=0, bounce=3, aoe=0, icon=ICON+"W-004_moon_wheel_dart_icon.png", upg="moon_adv"},
	"bubble":     {name="梦泡法球", kind="ranged", dmg=8, cooldown=0.7, crit_bonus=0.0, proj=PROJ+"W-023_dream_bubble_bomb.png", proj_speed=170, pierce=0, bounce=0, aoe=42, icon=ICON+"W-005_dream_bubble_orb_icon.png", upg="bubble_adv"},
	"spear":      {name="星穿长枪", kind="melee", dmg=16, cooldown=0.45, crit_bonus=0.02, arc=55, reach=66, combo=1, dash=true, icon=ICON+"W-006_star_piercer_spear_icon.png", upg="spear_adv"},
	"hammer":     {name="噩梦骨锤", kind="melee", dmg=22, cooldown=0.8, crit_bonus=0.0, arc=120, reach=46, combo=1, dash=false, knockback=70, icon=ICON+"W-007_nightmare_bone_hammer_icon.png", upg="hammer_adv"},
	"dual":       {name="幻影双刃", kind="melee", dmg=9, cooldown=0.16, crit_bonus=0.04, arc=80, reach=34, combo=4, dash=false, icon=ICON+"W-008_phantom_dual_blades_icon.png", upg="dual_adv"},
	"bow":        {name="梦境弓", kind="ranged", dmg=14, cooldown=0.6, crit_bonus=0.03, proj=PROJ+"W-024_arrow_normal.png", proj_speed=520, pierce=1, bounce=0, aoe=0, charge=true, icon=ICON+"W-009_dream_bow_icon.png", upg="bow_adv"},

	# ---- 升阶版 ----
	"staff_adv":  {name="星海法杖", kind="ranged", dmg=16, cooldown=0.3, crit_bonus=0.0, proj=PROJ+"W-021_trident_star_bolt_upgraded.png", proj_speed=380, pierce=3, bounce=0, aoe=0, effect="burn", effect_time=2.0, icon=ICON+"W-010_starsea_staff_icon_upgraded.png", upg=""},
	"sword_adv":  {name="极光圣剑", kind="melee", dmg=18, cooldown=0.26, crit_bonus=0.05, arc=110, reach=42, combo=5, dash=false, icon=ICON+"W-011_aurora_holy_sword_icon_upgraded.png", upg=""},
	"scythe_adv": {name="深渊大镰", kind="melee", dmg=14, cooldown=0.48, crit_bonus=0.01, arc=175, reach=58, combo=1, dash=false, freeze=1.0, icon=ICON+"W-012_abyss_great_scythe_icon_upgraded.png", upg=""},
	"moon_adv":   {name="月神轮", kind="ranged", dmg=12, cooldown=0.38, crit_bonus=0.02, proj=PROJ+"W-022_moon_wheel_dart_projectile.png", proj_speed=330, pierce=0, bounce=6, bounce_bonus=0.15, aoe=0, icon=ICON+"W-004_moon_wheel_dart_icon.png", upg=""},
	"bubble_adv": {name="深梦法球", kind="ranged", dmg=11, cooldown=0.66, crit_bonus=0.0, proj=PROJ+"W-023_dream_bubble_bomb.png", proj_speed=180, pierce=0, bounce=0, aoe=58, effect="dot", effect_time=2.5, icon=ICON+"W-005_dream_bubble_orb_icon.png", upg=""},
	"spear_adv":  {name="雷霆枪", kind="melee", dmg=20, cooldown=0.42, crit_bonus=0.02, arc=55, reach=70, combo=1, dash=true, effect="paralyze", effect_time=0.5, icon=ICON+"W-006_star_piercer_spear_icon.png", upg=""},
	"hammer_adv": {name="混沌重锤", kind="melee", dmg=28, cooldown=0.8, crit_bonus=0.0, arc=140, reach=50, combo=1, dash=false, knockback=70, always_crit=true, effect="shock", effect_time=0.0, icon=ICON+"W-007_nightmare_bone_hammer_icon.png", upg=""},
	"dual_adv":   {name="梦境双刃", kind="melee", dmg=12, cooldown=0.15, crit_bonus=0.04, arc=85, reach=36, combo=4, dash=false, phantom=2, icon=ICON+"W-008_phantom_dual_blades_icon.png", upg=""},
	"bow_adv":    {name="星陨弓", kind="ranged", dmg=18, cooldown=0.58, crit_bonus=0.05, proj=PROJ+"W-025_arrow_full_charge.png", proj_speed=560, pierce=1, bounce=0, aoe=20, charge=true, effect="burn", effect_time=2.0, icon=ICON+"W-009_dream_bow_icon.png", upg=""},
}

const STARTERS = ["staff", "sword", "scythe"]
const SWAP_POOL = ["moon", "bubble", "spear", "hammer", "dual", "bow"]

static func get_weapon(id):
	return DATA.get(id, null)

static func get_icon_path(id):
	if DATA.has(id):
		return DATA[id]["icon"]
	return ""

static func can_upgrade(id):
	return DATA.has(id) and DATA[id].get("upg", "") != ""
