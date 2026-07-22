# 《梦境逐影》敌人与 Boss 数据
# behavior: "chase" 追击近身 / "shooter" 远程弹幕 / "charger" 冲锋 / "aoe" 范围脉冲
# Boss: phases = 触发下一阶段的血量比例数组；phase_patterns 决定每阶段攻击模式。
class_name Enemies

const E1 = "res://assets/sprites/enemies/layer1/"
const E2 = "res://assets/sprites/enemies/layer2/"
const E3 = "res://assets/sprites/enemies/layer3/"
const B = "res://assets/sprites/bosses/"

const DATA = {
	# ---------- 第一层：午夜办公室 ----------
	"overtime_ghost": {name="加班幽灵", layer=1, behavior="shooter", hp=35, xp=10, speed=60, contact_dmg=12,
		idle=E1+"e_overtime_ghost_idle.png", attack=E1+"e_overtime_ghost_attack.png", fw=28, fh=32, fi=4, fa=3,
		atk_cd=1.6, atk_range=240, proj_dmg=8, proj_speed=210, proj="res://assets/weapons/projectiles/p_staff.png", bullet=1},
	"kpi": {name="KPI怪", layer=1, behavior="shooter", hp=25, xp=8, speed=45, contact_dmg=8,
		idle=E1+"e_kpi_idle.png", attack=E1+"e_kpi_attack.png", fw=24, fh=24, fi=3, fa=3,
		atk_cd=2.0, atk_range=300, proj_dmg=10, proj_speed=150, proj="res://assets/weapons/projectiles/p_bubble.png", bullet=1, homing=true},
	"printer": {name="卡纸打印机", layer=1, behavior="chase", hp=50, xp=14, speed=72, contact_dmg=14,
		idle=E1+"e_printer_idle.png", attack=E1+"e_printer_attack.png", fw=40, fh=32, fi=4, fa=3},
	"meeting": {name="会议幽魂", layer=1, behavior="shooter", hp=30, xp=10, speed=40, contact_dmg=10,
		idle=E1+"e_meeting_idle.png", attack=E1+"e_meeting_attack.png", fw=32, fh=40, fi=3, fa=3,
		atk_cd=1.2, atk_range=320, proj_dmg=6, proj_speed=340, proj="res://assets/weapons/projectiles/p_staff.png", bullet=1},
	"phone": {name="电话噩梦", layer=1, behavior="aoe", hp=40, xp=12, speed=30, contact_dmg=10,
		idle=E1+"e_phone_idle.png", attack=E1+"e_phone_attack.png", fw=24, fh=32, fi=4, fa=3,
		atk_cd=2.2, aoe_radius=72, proj_dmg=10, knockback=40},

	# ---------- 第二层：无尽通勤路 ----------
	"commuter": {name="通勤幽灵", layer=2, behavior="charger", hp=55, xp=16, speed=95, contact_dmg=16,
		idle=E2+"e_commuter_idle.png", attack=E2+"e_commuter_attack.png", fw=28, fh=32, fi=4, fa=3},
	"escalator": {name="逆行扶梯", layer=2, behavior="charger", hp=80, xp=20, speed=38, contact_dmg=18,
		idle=E2+"e_escalator_idle.png", attack=E2+"e_escalator_attack.png", fw=48, fh=24, fi=3, fa=3, knockback=50},
	"rider": {name="堵路外卖员", layer=2, behavior="charger", hp=45, xp=15, speed=125, contact_dmg=15,
		idle=E2+"e_rider_idle.png", attack=E2+"e_rider_attack.png", fw=32, fh=28, fi=4, fa=3},
	"revolving": {name="旋转门陷阱", layer=2, behavior="aoe", hp=70, xp=18, speed=28, contact_dmg=12,
		idle=E2+"e_revolving_idle.png", attack=E2+"e_revolving_attack.png", fw=40, fh=40, fi=4, fa=3,
		atk_cd=2.4, aoe_radius=60, proj_dmg=14, knockback=20},
	"package": {name="无法签收的快递", layer=2, behavior="charger", hp=60, xp=16, speed=75, contact_dmg=16,
		idle=E2+"e_package_idle.png", attack=E2+"e_package_attack.png", fw=32, fh=32, fi=4, fa=3, aoe_on_hit=42, aoe_dmg=12},

	# ---------- 第三层：深夜崩溃核心 ----------
	"message": {name="未读消息群", layer=3, behavior="shooter", hp=30, xp=8, speed=60, contact_dmg=6,
		idle=E3+"e_message_idle.png", attack=E3+"e_message_attack.png", fw=16, fh=16, fi=2, fa=2,
		atk_cd=0.9, atk_range=320, proj_dmg=5, proj_speed=210, proj="res://assets/weapons/projectiles/p_staff.png", bullet=3, spread=0.4},
	"overdue": {name="逾期任务板", layer=3, behavior="chase", hp=150, xp=40, speed=50, contact_dmg=22,
		idle=E3+"e_overdue_idle.png", attack=E3+"e_overdue_attack.png", fw=48, fh=56, fi=3, fa=3},
	"rejected": {name="被否定方案", layer=3, behavior="shooter", hp=60, xp=18, speed=55, contact_dmg=10,
		idle=E3+"e_rejected_idle.png", attack=E3+"e_rejected_attack.png", fw=24, fh=24, fi=3, fa=3,
		atk_cd=1.4, atk_range=320, proj_dmg=10, proj_speed=240, proj="res://assets/weapons/projectiles/p_staff.png", bullet=1},
	"heart_beat": {name="焦虑心跳", layer=3, behavior="aoe", hp=100, xp=28, speed=20, contact_dmg=12,
		idle=E3+"e_heart_beat_idle.png", attack=E3+"e_heart_beat_attack.png", fw=32, fh=32, fi=4, fa=3,
		atk_cd=2.6, aoe_radius=82, proj_dmg=16, knockback=30},
	"elite_996": {name="精英·996实体", layer=3, behavior="charger", hp=400, xp=90, speed=140, contact_dmg=24, is_elite=true,
		idle=E3+"e_996_idle.png", attack=E3+"e_996_attack.png", fw=40, fh=48, fi=6, fa=4, clone_count=1, atk_cd=1.0},
}

# Boss：phases = 进入下一阶段的血量比例（从高到低）；final=true 时每次换阶段露出「疲惫之眼」弱点窗口
const BOSS = {
	"b_director": {name="项目总监·无影手", layer=1, hp=400, sprite_idle=B+"b_director_idle.png", sprite_attack=B+"b_director_attack.png", fw=80, fh=64, fi=4, fa=4,
		phases=[0.60, 0.30], phase_patterns=["summon","cards","spin"], final=false},
	"b_train": {name="通勤魔王·永不到站", layer=2, hp=700, sprite_idle=B+"b_train_idle.png", sprite_attack=B+"b_train_attack.png", fw=128, fh=48, fi=4, fa=5,
		phases=[0.50, 0.25], phase_patterns=["charge","slam","spin"], final=false},
	"b_fear": {name="无名恐惧·职场深渊", layer=3, hp=1800, sprite_idle=B+"b_fear_idle.png", sprite_attack=B+"b_fear_attack.png", fw=48, fh=64, fi=4, fa=4,
		phases=[0.75, 0.50, 0.25], phase_patterns=["summon","ddl","crash","frenzy"], final=true},
}

static func get_enemy(id):
	return DATA.get(id, null)

static func get_boss(id):
	return BOSS.get(id, null)

static func enemies_of_layer(layer):
	var out = []
	for id in DATA.keys():
		if DATA[id]["layer"] == layer:
			out.append(id)
	return out
