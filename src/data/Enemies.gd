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
		idle=E1+"M-001_overtime_ghost_walk.png", attack=E1+"M-002_overtime_ghost_throw.png", fw=130, fh=250, fi=4, fa=3,
		atk_cd=1.6, atk_range=240, proj_dmg=8, proj_speed=210, proj="res://assets/weapons/projectiles/W-020_dream_light_bolt.png", bullet=1},
	"kpi": {name="KPI怪", layer=1, behavior="shooter", hp=25, xp=8, speed=45, contact_dmg=8,
		idle=E1+"M-003_kpi_monster_float.png", attack=E1+"M-004_kpi_monster_explode.png", fw=130, fh=250, fi=3, fa=5,
		atk_cd=2.0, atk_range=300, proj_dmg=10, proj_speed=150, proj="res://assets/weapons/projectiles/W-023_dream_bubble_bomb.png", bullet=1, homing=true},
	"printer": {name="卡纸打印机", layer=1, behavior="chase", hp=50, xp=14, speed=72, contact_dmg=14,
		idle=E1+"M-005_jammed_printer_walk.png", attack=E1+"M-006_jammed_printer_spray.png", fw=130, fh=250, fi=4, fa=3},
	"meeting": {name="会议幽魂", layer=1, behavior="shooter", hp=30, xp=10, speed=40, contact_dmg=10,
		idle=E1+"M-007_meeting_ghost_float.png", attack=E1+"M-007_meeting_ghost_float.png", fw=130, fh=250, fi=3, fa=3,
		atk_cd=1.2, atk_range=320, proj_dmg=6, proj_speed=340, proj="res://assets/weapons/projectiles/W-020_dream_light_bolt.png", bullet=1},
	"phone": {name="电话噩梦", layer=1, behavior="aoe", hp=40, xp=12, speed=30, contact_dmg=10,
		idle=E1+"M-008_phone_nightmare_wave.png", attack=E1+"M-008_phone_nightmare_wave.png", fw=130, fh=250, fi=4, fa=4,
		atk_cd=2.2, aoe_radius=72, proj_dmg=10, knockback=40},

	# ---------- 第二层：无尽通勤路 ----------
	"commuter": {name="通勤幽灵", layer=2, behavior="charger", hp=55, xp=16, speed=95, contact_dmg=16,
		idle=E2+"M-014_commuter_ghost_walk.png", attack=E2+"M-014_commuter_ghost_walk.png", fw=130, fh=250, fi=4, fa=4},
	"escalator": {name="逆行扶梯", layer=2, behavior="charger", hp=80, xp=20, speed=38, contact_dmg=18,
		idle=E2+"M-015_reverse_escalator_move.png", attack=E2+"M-015_reverse_escalator_move.png", fw=130, fh=250, fi=3, fa=3, knockback=50},
	"rider": {name="堵路外卖员", layer=2, behavior="charger", hp=45, xp=15, speed=125, contact_dmg=15,
		idle=E2+"M-016_delivery_rider_dash.png", attack=E2+"M-016_delivery_rider_dash.png", fw=130, fh=250, fi=4, fa=4},
	"revolving": {name="旋转门陷阱", layer=2, behavior="aoe", hp=70, xp=18, speed=28, contact_dmg=12,
		idle=E2+"M-017_revolving_door_spin.png", attack=E2+"M-017_revolving_door_spin.png", fw=130, fh=250, fi=4, fa=4,
		atk_cd=2.4, aoe_radius=60, proj_dmg=14, knockback=20},
	"package": {name="无法签收的快递", layer=2, behavior="charger", hp=60, xp=16, speed=75, contact_dmg=16,
		idle=E2+"M-018_parcel_box_walk.png", attack=E2+"M-019_parcel_box_slam.png", fw=130, fh=250, fi=4, fa=5, aoe_on_hit=42, aoe_dmg=12},

	# ---------- 第三层：深夜崩溃核心 ----------
	"message": {name="未读消息群", layer=3, behavior="shooter", hp=30, xp=8, speed=60, contact_dmg=6,
		idle=E3+"M-026_unread_messages_swarm.png", attack=E3+"M-026_unread_messages_swarm.png", fw=130, fh=250, fi=2, fa=2,
		atk_cd=0.9, atk_range=320, proj_dmg=5, proj_speed=210, proj="res://assets/weapons/projectiles/W-020_dream_light_bolt.png", bullet=3, spread=0.4},
	"overdue": {name="逾期任务板", layer=3, behavior="chase", hp=150, xp=40, speed=50, contact_dmg=22,
		idle=E3+"M-027_overdue_task_board_chase.png", attack=E3+"M-027_overdue_task_board_chase.png", fw=130, fh=250, fi=3, fa=3},
	"rejected": {name="被否定方案", layer=3, behavior="shooter", hp=60, xp=18, speed=55, contact_dmg=10,
		idle=E3+"M-028_rejected_proposal_flutter.png", attack=E3+"M-028_rejected_proposal_flutter.png", fw=130, fh=250, fi=3, fa=3,
		atk_cd=1.4, atk_range=320, proj_dmg=10, proj_speed=240, proj="res://assets/weapons/projectiles/W-020_dream_light_bolt.png", bullet=1},
	"heart_beat": {name="焦虑心跳", layer=3, behavior="aoe", hp=100, xp=28, speed=20, contact_dmg=12,
		idle=E3+"M-029_anxiety_heartbeat_pulse.png", attack=E3+"M-029_anxiety_heartbeat_pulse.png", fw=130, fh=250, fi=4, fa=4,
		atk_cd=2.6, aoe_radius=82, proj_dmg=16, knockback=30},
	"elite_996": {name="精英·996实体", layer=3, behavior="charger", hp=400, xp=90, speed=140, contact_dmg=24, is_elite=true,
		idle=E3+"M-030_elite_996_entity_dash.png", attack=E3+"M-030_elite_996_entity_dash.png", fw=130, fh=250, fi=6, fa=6, clone_count=1, atk_cd=1.0},
}

# Boss：phases = 进入下一阶段的血量比例（从高到低）；final=true 时每次换阶段露出「疲惫之眼」弱点窗口
const BOSS = {
	"b_director": {name="项目总监·无影手", layer=1, hp=400, sprite_idle=B+"M-009_director_boss_idle.png", sprite_attack=B+"M-010_director_boss_coffee_sweep.png", fw=260, fh=500, fi=4, fa=5,
		phases=[0.60, 0.30], phase_patterns=["summon","cards","spin"], final=false},
	"b_train": {name="通勤魔王·永不到站", layer=2, hp=700, sprite_idle=B+"M-020_commute_demon_train_idle.png", sprite_attack=B+"M-021_commute_demon_door_bite.png", fw=260, fh=500, fi=4, fa=5,
		phases=[0.50, 0.25], phase_patterns=["charge","slam","spin"], final=false},
	"b_fear": {name="无名恐惧·职场深渊", layer=3, hp=1800, sprite_idle=B+"M-031_nameless_fear_phase1.png", sprite_attack=B+"M-032_nameless_fear_phase2.png", fw=260, fh=500, fi=4, fa=5,
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
