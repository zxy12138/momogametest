# 《梦境逐影》敌人与 Boss 数据（2026-08-15 v5.0：攻击/死亡双向 + 混合攻击 + 全自定义弹道）
# 精灵素材源：assets/sprites/enemies/{layer}/F{x}_N_{NNN}.png（1024×1024 多行动画表）
# 行序说明：C:/Users/17930_ueiiii0/Desktop/怪物说明.txt（2026-08-15 完整版）
# 动画键 -> 帧数字段（每怪可独立指定；缺省 8）：
#   idle->fi / walk_down->fwd / walk_right->fwr / walk_up->fwu / walk_left->fwl
#   attack->fa / dead->fd / melee->fa（近战）
#   *_left 为镜像（attack_left/dead_left/melee_left 帧数与对应主键一致）
# behavior: "chase" / "shooter" 远程 / "charger" / "aoe" / "patrol" 锁定追击近战
#           "hybrid" 近战+远程混合（远距 shooter、近身 melee）
class_name Enemies

const E1 = "res://assets/sprites/enemies/layer1/"
const E2 = "res://assets/sprites/enemies/layer2/"
const E3 = "res://assets/sprites/enemies/layer3/"
const B1 = "res://assets/sprites/bosses/layer1/"
const B2 = "res://assets/sprites/bosses/layer2/"
const B3 = "res://assets/sprites/bosses/layer3/"

const DATA = {
	# ---------- 第一层：午夜办公室 ----------
	"alarm_clock": {name="闹钟怪物", layer=1, behavior="patrol", hp=45, xp=12, speed=55, contact_dmg=14,
		walk_down=E1+"F1_N_001_walk_down.png", walk_right=E1+"F1_N_001_walk_right.png", walk_up=E1+"F1_N_001_walk_up.png", walk_left=E1+"F1_N_001_walk_left.png",
		attack=E1+"F1_N_001_attack.png", attack_left=E1+"F1_N_001_attack_left.png", dead=E1+"F1_N_001_dead.png", dead_left=E1+"F1_N_001_dead_left.png",
		fw=128, fh=128, atk_range=40, atk_cd=2.0},

	"lamp": {name="路灯怪", layer=1, behavior="patrol", hp=40, xp=11, speed=50, contact_dmg=12,
		walk_down=E1+"F1_N_002_walk_down.png", walk_right=E1+"F1_N_002_walk_right.png", walk_up=E1+"F1_N_002_walk_up.png", walk_left=E1+"F1_N_002_walk_left.png",
		attack=E1+"F1_N_002_attack.png", attack_left=E1+"F1_N_002_attack_left.png", dead=E1+"F1_N_002_dead.png", dead_left=E1+"F1_N_002_dead_left.png",
		idle=E1+"F1_N_002_idle.png", fw=128, fh=128, fwd=10, fwr=10, fwu=10, fwl=10, atk_range=80, atk_cd=2.0},

	"dog": {name="小狗怪", layer=1, behavior="patrol", hp=35, xp=10, speed=60, contact_dmg=10,
		walk_down=E1+"F1_N_003_walk_down.png", walk_right=E1+"F1_N_003_walk_right.png", walk_up=E1+"F1_N_003_walk_up.png", walk_left=E1+"F1_N_003_walk_left.png",
		attack=E1+"F1_N_003_attack.png", attack_left=E1+"F1_N_003_attack_left.png", dead=E1+"F1_N_003_dead.png", dead_left=E1+"F1_N_003_dead_left.png",
		fw=128, fh=128, atk_range=80, atk_cd=2.0},

	"mower": {name="除草工人", layer=1, behavior="shooter", hp=40, xp=14, speed=48, contact_dmg=10,
		walk_down=E1+"F1_N_004_walk_down.png", walk_right=E1+"F1_N_004_walk_right.png", walk_up=E1+"F1_N_004_walk_up.png", walk_left=E1+"F1_N_004_walk_left.png",
		attack=E1+"F1_N_004_attack.png", attack_left=E1+"F1_N_004_attack_left.png", dead=E1+"F1_N_004_dead.png", dead_left=E1+"F1_N_004_dead_left.png",
		fw=128, fh=128, atk_range=280, atk_cd=3.0, proj_dmg=10, proj_speed=220, proj=E1+"F1_N_004_proj.png", bullet=1},

	"road_daredevil": {name="马路撒手", layer=1, behavior="patrol", hp=120, xp=40, speed=90, contact_dmg=20, is_elite=true,
		walk_down=E1+"F1_N_005_walk_down.png", walk_up=E1+"F1_N_005_walk_up.png", walk_right=E1+"F1_N_005_walk_right.png", walk_left=E1+"F1_N_005_walk_left.png",
		attack=E1+"F1_N_005_attack.png", attack_left=E1+"F1_N_005_attack_left.png", dead=E1+"F1_N_005_dead.png", dead_left=E1+"F1_N_005_dead_left.png",
		idle=E1+"F1_N_005_idle.png", fw=128, fh=128, fd=7, atk_range=80, atk_cd=2.4},

	# ---------- 第二层：无尽通勤路 ----------
	"office_ghost": {name="透明上班族", layer=2, behavior="shooter", hp=50, xp=14, speed=60, contact_dmg=14,
		walk_down=E2+"F2_N_001_walk_down.png", walk_right=E2+"F2_N_001_walk_right.png", walk_up=E2+"F2_N_001_walk_up.png", walk_left=E2+"F2_N_001_walk_left.png",
		attack=E2+"F2_N_001_attack.png", attack_left=E2+"F2_N_001_attack_left.png", dead=E2+"F2_N_001_dead.png", dead_left=E2+"F2_N_001_dead_left.png",
		idle=E2+"F2_N_001_idle.png", fw=128, fh=128, fa=3, atk_range=280, atk_cd=2.8, proj_dmg=12, proj_speed=230, proj=E2+"F2_N_001_proj.png", bullet=1},

	"spider": {name="蜘蛛怪", layer=2, behavior="hybrid", hp=42, xp=12, speed=70, contact_dmg=12,
		walk_up=E2+"F2_N_002_walk_up.png", walk_down=E2+"F2_N_002_walk_down.png", walk_right=E2+"F2_N_002_walk_right.png", walk_left=E2+"F2_N_002_walk_left.png",
		attack=E2+"F2_N_002_attack.png", attack_left=E2+"F2_N_002_attack_left.png",
		melee=E2+"F2_N_002_melee.png", melee_left=E2+"F2_N_002_melee_left.png",
		dead=E2+"F2_N_002_dead.png", dead_left=E2+"F2_N_002_dead_left.png", idle=E2+"F2_N_002_idle.png",
		fw=128, fh=128, fa=6, atk_range=280, atk_cd=2.6, proj_dmg=11, proj_speed=240, proj=E2+"F2_N_002_proj.png", bullet=1,
		hybrid_range=220, melee_range=80, melee_cd=2.0},

	"hypno_tv": {name="催眠电视", layer=2, behavior="shooter", hp=40, xp=12, speed=30, contact_dmg=10,
		walk_down=E2+"F2_N_003_walk_down.png", walk_right=E2+"F2_N_003_walk_right.png", walk_left=E2+"F2_N_003_walk_left.png",
		attack=E2+"F2_N_003_attack.png", attack_left=E2+"F2_N_003_attack_left.png", dead=E2+"F2_N_003_dead.png", dead_left=E2+"F2_N_003_dead_left.png",
		fw=128, fh=128, fa=8, atk_range=300, atk_cd=3.0, proj_dmg=12, proj_speed=200, proj=E2+"F2_N_003_proj.png", bullet=1},

	"centipede": {name="蜈蚣怪", layer=2, behavior="hybrid", hp=140, xp=42, speed=80, contact_dmg=18, is_elite=true,
		idle=E2+"F2_N_004_idle.png",
		attack=E2+"F2_N_004_attack.png", attack_left=E2+"F2_N_004_attack_left.png",
		melee=E2+"F2_N_004_melee.png", melee_left=E2+"F2_N_004_melee_left.png",
		dead=E2+"F2_N_004_dead.png", dead_left=E2+"F2_N_004_dead_left.png",
		fw=128, fh=128, fi=4, fa=6, fme=4, fd=6, atk_range=320, atk_cd=2.8, proj_dmg=16, proj_speed=260, proj=E2+"F2_N_002_proj.png", bullet=1,
		hybrid_range=260, melee_range=90, melee_cd=2.4},

	"zombie": {name="僵尸上班族", layer=2, behavior="patrol", hp=65, xp=18, speed=45, contact_dmg=16,
		walk_down=E2+"F2_N_005_walk_down.png", walk_up=E2+"F2_N_005_walk_up.png", walk_right=E2+"F2_N_005_walk_right.png", walk_left=E2+"F2_N_005_walk_left.png",
		attack=E2+"F2_N_005_attack.png", attack_left=E2+"F2_N_005_attack_left.png", dead=E2+"F2_N_005_dead.png", dead_left=E2+"F2_N_005_dead_left.png",
		fw=128, fh=128, fwd=6, fwu=6, fwr=3, fwl=3, fa=6, fd=5, atk_range=80, atk_cd=2.2},

	# ---------- 第三层：深夜崩溃核心 ----------
	"overtime1": {name="加班工作者1", layer=3, behavior="patrol", hp=80, xp=22, speed=55, contact_dmg=18,
		walk_down=E3+"F3_N_001_walk_down.png", walk_up=E3+"F3_N_001_walk_up.png", walk_right=E3+"F3_N_001_walk_right.png", walk_left=E3+"F3_N_001_walk_left.png",
		attack=E3+"F3_N_001_attack.png", attack_left=E3+"F3_N_001_attack_left.png", dead=E3+"F3_N_001_dead.png", dead_left=E3+"F3_N_001_dead_left.png",
		fw=128, fh=128, fwd=6, fwu=7, fwr=7, fwl=7, atk_range=80, atk_cd=2.2},

	"kpi_group": {name="kpi团", layer=3, behavior="shooter", hp=70, xp=20, speed=40, contact_dmg=12,
		walk_up=E3+"F3_N_002_walk_up.png", walk_down=E3+"F3_N_002_walk_down.png", walk_right=E3+"F3_N_002_walk_right.png", walk_left=E3+"F3_N_002_walk_left.png",
		attack=E3+"F3_N_002_attack.png", attack_left=E3+"F3_N_002_attack_left.png", dead=E3+"F3_N_002_dead.png", dead_left=E3+"F3_N_002_dead_left.png",
		fw=128, fh=128, fa=3, atk_range=320, atk_cd=2.8, proj_dmg=14, proj_speed=240, proj=E3+"F3_N_002_proj.png", proj_frames=3, bullet=3, spread=0.4},

	"hardware_core": {name="硬件核心", layer=3, behavior="shooter", hp=300, xp=80, speed=60, contact_dmg=24, is_elite=true,
		walk_down=E3+"F3_N_003_walk_down.png", walk_right=E3+"F3_N_003_walk_right.png", walk_up=E3+"F3_N_003_walk_up.png", walk_left=E3+"F3_N_003_walk_left.png",
		attack=E3+"F3_N_003_attack.png", attack_left=E3+"F3_N_003_attack_left.png", dead=E3+"F3_N_003_dead.png", dead_left=E3+"F3_N_003_dead_left.png",
		fw=128, fh=128, fa=3, fd=6, atk_range=340, atk_cd=2.6, proj_dmg=20, proj_speed=280, proj=E3+"F3_N_003_proj.png", proj_frames=1, bullet=1},

	"printer2": {name="打印机怪", layer=3, behavior="patrol", hp=100, xp=28, speed=50, contact_dmg=18,
		idle=E3+"F3_N_004_idle.png", walk_down=E3+"F3_N_004_walk_down.png", walk_up=E3+"F3_N_004_walk_up.png",
		walk_right=E3+"F3_N_004_walk_right.png", walk_left=E3+"F3_N_004_walk_left.png",
		attack=E3+"F3_N_004_attack.png", attack_left=E3+"F3_N_004_attack_left.png", dead=E3+"F3_N_004_dead.png", dead_left=E3+"F3_N_004_dead_left.png",
		fw=128, fh=128, atk_range=80, atk_cd=2.2},

	"overtime2": {name="加班工作者2", layer=3, behavior="patrol", hp=85, xp=24, speed=55, contact_dmg=18,
		walk_down=E3+"F3_N_005_walk_down.png", walk_up=E3+"F3_N_005_walk_up.png", walk_right=E3+"F3_N_005_walk_right.png", walk_left=E3+"F3_N_005_walk_left.png",
		attack=E3+"F3_N_005_attack.png", attack_left=E3+"F3_N_005_attack_left.png", dead=E3+"F3_N_005_dead.png", dead_left=E3+"F3_N_005_dead_left.png",
		idle=E3+"F3_N_005_idle.png", fw=128, fh=128, fa=7, fd=7, atk_range=80, atk_cd=2.2},

	"overtime3": {name="加班工作者3", layer=3, behavior="shooter", hp=90, xp=26, speed=55, contact_dmg=18,
		walk_down=E3+"F3_N_006_walk_down.png", walk_right=E3+"F3_N_006_walk_right.png", walk_up=E3+"F3_N_006_walk_up.png", walk_left=E3+"F3_N_006_walk_left.png",
		attack=E3+"F3_N_006_attack.png", attack_left=E3+"F3_N_006_attack_left.png", dead=E3+"F3_N_006_dead.png", dead_left=E3+"F3_N_006_dead_left.png",
		idle=E3+"F3_N_006_idle.png", fw=128, fh=128, fa=8, atk_range=300, atk_cd=2.9, proj_dmg=16, proj_speed=250, proj=E3+"F3_N_006_proj.png", bullet=1},
}

# Boss：每个 Boss 两个形态（form1 打空血 → 变身动画 → form2 满血 → 打死通关）。
# 素材源：assets/sprites/bosses/{layer}/F{x}_B_{NNN}.png（多行动画表，2026-08-16 切片）
# 数据字段：
#   hp1/hp2      形态1/形态2 血量（形态1打空即变身，形态2满血接管）
#   form1/form2  各形态动画表（键=动画名，值=横向精灵条路径）+ 帧数字段（fwd/fwr/fwu/fwl/fi/fa/fd/fme/fch）
#   transform    Boss 本体变身动画（Anime 大图切帧缩放的横向精灵条）
#   transform_frames/fps  变身动画帧数与播放速度
#   proj         弹道贴图（远程攻击）
#   behavior     行为：chase 追击 / hybrid 近远混合 / patrol 锁定追击近战 / charger 冲锋
#   cb           碰撞框 Vector4(宽,高,偏移x,偏移y)（按形态分开配置）
const BOSS = {
	# ---------- 第一层 Boss：梦魇公车（公交 → 机器人） ----------
	"b_bus": {name="梦魇公车", layer=1, xp=200, contact_dmg=18, speed=55,
		hp1=250, hp2=400,
		transform=B1+"F1_B_001_transform.png", transform_frames=120, transform_fps=30,
		form1={   # 公交形态：移动 + 触手近战 + 冲撞（charge 8帧），无 idle 无 death（打空直接变身）
			idle=B1+"F1_B_001_walk_down.png", walk_down=B1+"F1_B_001_walk_down.png",
			walk_right=B1+"F1_B_001_walk_right.png", walk_left=B1+"F1_B_001_walk_left.png",
			walk_up=B1+"F1_B_001_walk_up.png",
			attack=B1+"F1_B_001_attack.png", attack_left=B1+"F1_B_001_attack_left.png",
			charge=B1+"F1_B_001_charge.png",
			fw=192, fh=192, fwd=6, fwr=5, fwu=6, fi=6, fa=2, fch=8,
			behavior="charger", atk_range=70, atk_cd=2.8, charge_cd=3.2,
			scale=1.2, cb=Vector4(168, 104, 0, 8)},
		form2={   # 机器人形态：移动 + 远程铁块 + 近战下砸 + 死亡
			idle=B1+"F1_B_002_idle.png", walk_down=B1+"F1_B_002_walk_down.png",
			walk_right=B1+"F1_B_002_walk_right.png", walk_left=B1+"F1_B_002_walk_left.png",
			walk_up=B1+"F1_B_002_walk_up.png",
			attack=B1+"F1_B_002_attack.png", attack_left=B1+"F1_B_002_attack_left.png",
			melee=B1+"F1_B_002_melee.png", melee_left=B1+"F1_B_002_melee_left.png",
			dead=B1+"F1_B_002_dead.png", dead_left=B1+"F1_B_002_dead_left.png",
			proj=B1+"F1_B_002_proj.png", proj_frames=2, proj_random=true,
			fw=192, fh=192, fi=8, fwd=8, fwr=8, fwu=8, fa=8, fme=8, fd=8,
			behavior="hybrid", speed=60, atk_range=300, melee_range=90, atk_cd=3.0, melee_cd=2.4,
			proj_dmg=14, proj_speed=260, hybrid_range=240,
			scale=1.1, cb=Vector4(110, 132, 0, 4)},
	},

	# ---------- 第二层 Boss：昆虫僵尸（僵尸 → 完全昆虫） ----------
	"b_bug": {name="昆虫僵尸", layer=2, xp=200, contact_dmg=20, speed=60,
		hp1=300, hp2=500,
		transform=B2+"F2_B_001_transform.png", transform_frames=114, transform_fps=30,
		form1={   # 昆虫僵尸形态：移动 + 近战抓人 + 远程毒液 + 待机
			idle=B2+"F2_B_001_idle.png", walk_down=B2+"F2_B_001_walk_down.png",
			walk_right=B2+"F2_B_001_walk_right.png", walk_left=B2+"F2_B_001_walk_left.png",
			walk_up=B2+"F2_B_001_walk_up.png",
			melee=B2+"F2_B_001_melee.png", melee_left=B2+"F2_B_001_melee_left.png",
			attack=B2+"F2_B_001_attack.png", attack_left=B2+"F2_B_001_attack_left.png",
			proj=B2+"F2_B_001_proj.png", proj_frames=1, proj_random=false,
			fw=192, fh=192, fi=8, fwd=8, fwr=8, fwu=8, fa=8, fme=8,
			behavior="hybrid", atk_range=280, melee_range=80, atk_cd=2.9, melee_cd=2.2,
			proj_dmg=12, proj_speed=250, hybrid_range=230,
			scale=1.05, cb=Vector4(82, 118, 0, 6)},
		form2={   # 完全昆虫形态：待机 + 移动 + 近战踢人 + 远程光束 + 死亡
			idle=B2+"F2_B_002_idle.png", walk_down=B2+"F2_B_002_walk_down.png",
			walk_right=B2+"F2_B_002_walk_right.png", walk_left=B2+"F2_B_002_walk_left.png",
			walk_up=B2+"F2_B_002_walk_up.png",
			melee=B2+"F2_B_002_melee.png", melee_left=B2+"F2_B_002_melee_left.png",
			attack=B2+"F2_B_002_attack.png", attack_left=B2+"F2_B_002_attack_left.png",
			dead=B2+"F2_B_002_dead.png", dead_left=B2+"F2_B_002_dead_left.png",
			proj=B2+"F2_B_002_proj.png", proj_frames=1, proj_random=false,
			fw=192, fh=192, fi=8, fwd=8, fwr=8, fwu=8, fa=7, fme=8, fd=8,
			behavior="hybrid", speed=65, atk_range=300, melee_range=95, atk_cd=3.0, melee_cd=2.2,
			proj_dmg=15, proj_speed=280, hybrid_range=250,
			scale=1.15, cb=Vector4(104, 116, 0, 4)},
	},

	# ---------- 第三层 Boss：加班电脑老板（人形 → 电脑机器） ----------
	"b_pc": {name="加班电脑老板", layer=3, xp=200, contact_dmg=22, speed=55,
		hp1=500, hp2=900,
		transform=B3+"F3_B_001_transform.png", transform_frames=146, transform_fps=30,
		form1={   # 人形态：移动 + 近战拍巴掌 + 待机（无远程无死亡，打空直接变身）
			idle=B3+"F3_B_001_idle.png", walk_down=B3+"F3_B_001_walk_down.png",
			walk_right=B3+"F3_B_001_walk_right.png", walk_left=B3+"F3_B_001_walk_left.png",
			walk_up=B3+"F3_B_001_walk_up.png",
			melee=B3+"F3_B_001_melee.png", melee_left=B3+"F3_B_001_melee_left.png",
			fw=192, fh=192, fi=10, fwd=12, fwr=12, fwu=12, fme=10,
			behavior="patrol", atk_range=80, atk_cd=2.6,
			scale=1.0, cb=Vector4(70, 128, 0, 6)},
		form2={   # 电脑机器形态：待机 + 移动 + 近战砸地 + 远程光弹 + 死亡
			idle=B3+"F3_B_002_idle.png", walk_down=B3+"F3_B_002_walk_down.png",
			walk_right=B3+"F3_B_002_walk_right.png", walk_left=B3+"F3_B_002_walk_left.png",
			walk_up=B3+"F3_B_002_walk_up.png",
			melee=B3+"F3_B_002_melee.png", melee_left=B3+"F3_B_002_melee_left.png",
			attack=B3+"F3_B_002_attack.png", attack_left=B3+"F3_B_002_attack_left.png",
			dead=B3+"F3_B_002_dead.png", dead_left=B3+"F3_B_002_dead_left.png",
			proj=B3+"F3_B_002_proj.png", proj_frames=3, proj_random=true,
			fw=192, fh=192, fi=10, fwd=10, fwr=10, fwu=10, fa=6, fme=10, fd=10,
			behavior="hybrid", speed=60, atk_range=320, melee_range=100, atk_cd=3.2, melee_cd=2.4,
			proj_dmg=18, proj_speed=300, hybrid_range=260,
			scale=1.25, cb=Vector4(116, 128, 0, 4)},
	},
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