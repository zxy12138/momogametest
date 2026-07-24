# -*- coding: utf-8 -*-
# 《梦境逐影》v3 资产改名迁移脚本
# 把代码里引用的 v2.0 占位文件名（老英文/拼写/缩写）统一改写成 v3.0 清单的 snake_case 英文名。
# 只改「文件名桩」（如 "M-001_overtime_ghost_walk"），不动前缀(SPR+/E1+/PROJ+)与后缀(.png)。
# 幂等：已迁移（老桩不存在）的文件再跑是 no-op。
import os, io

ROOT = r"E:\Godot\Godot_Project\momogametest"

# 老桩 -> 新桩（与 tools/v3_assets.py CODE_EN 对齐）
OLD_NEW = {
    # 玩家（mihui -> miai; attack/dead/true 改名）
    "A-001_mihui_idle": "A-001_miai_idle",
    "A-002_mihui_walk": "A-002_miai_walk",
    "A-003_mihui_run": "A-003_miai_run",
    "A-004_mihui_jump": "A-004_miai_jump",
    "A-005_mihui_hurt": "A-005_miai_hurt",
    "A-007_mihui_attack": "A-007_miai_attack_windup",
    "A-006_mihui_dead": "A-006_miai_death",
    "A-008_mihui_ult": "A-008_miai_ultimate_skill",
    "A-009_mihui_true_idle": "A-009_miai_true_form_idle",

    # 第一层怪物
    "M-003_kpi_float": "M-003_kpi_monster_float",
    "M-004_kpi_burst": "M-004_kpi_monster_explode",
    "M-005_printer_walk": "M-005_jammed_printer_walk",
    "M-006_printer_spray": "M-006_jammed_printer_spray",
    "M-007_meeting_ppt": "M-007_meeting_ghost_float",
    "M-008_phone_wave": "M-008_phone_nightmare_wave",

    # 第二层怪物
    "M-014_commuter_walk": "M-014_commuter_ghost_walk",
    "M-015_escalator_move": "M-015_reverse_escalator_move",
    "M-016_rider_dash": "M-016_delivery_rider_dash",
    "M-017_revolving_spin": "M-017_revolving_door_spin",
    "M-018_package_walk": "M-018_parcel_box_walk",
    "M-019_package_slam": "M-019_parcel_box_slam",

    # 第三层怪物
    "M-026_message_barrage": "M-026_unread_messages_swarm",
    "M-027_overdue_chase": "M-027_overdue_task_board_chase",
    "M-028_rejected_fly": "M-028_rejected_proposal_flutter",
    "M-029_heartbeat_pulse": "M-029_anxiety_heartbeat_pulse",
    "M-030_elite_996_rush": "M-030_elite_996_entity_dash",

    # Boss
    "M-009_director_idle": "M-009_director_boss_idle",
    "M-010_director_coffee": "M-010_director_boss_coffee_sweep",
    "M-020_train_idle": "M-020_commute_demon_train_idle",
    "M-021_train_bite": "M-021_commute_demon_door_bite",
    "M-031_fear_human1": "M-031_nameless_fear_phase1",
    "M-032_fear_twist2": "M-032_nameless_fear_phase2",

    # 武器图标
    "W-001_staff": "W-001_dream_staff_icon",
    "W-002_star_sword": "W-002_starlight_sword_icon",
    "W-003_nightmare_scythe": "W-003_nightmare_scythe_icon",
    "W-004_moon_shuriken": "W-004_moon_wheel_dart_icon",
    "W-005_dream_bubble": "W-005_dream_bubble_orb_icon",
    "W-006_star_lance": "W-006_star_piercer_spear_icon",
    "W-007_nightmare_bone_hammer": "W-007_nightmare_bone_hammer_icon",
    "W-008_phantom_blades": "W-008_phantom_dual_blades_icon",
    "W-009_dream_bow": "W-009_dream_bow_icon",
    "W-010_staff_adv": "W-010_starsea_staff_icon_upgraded",
    "W-011_sword_adv": "W-011_aurora_holy_sword_icon_upgraded",
    "W-012_scythe_adv": "W-012_abyss_great_scythe_icon_upgraded",

    # 弹射物
    "W-020_p_staff": "W-020_dream_light_bolt",
    "W-021_p_tribolt": "W-021_trident_star_bolt_upgraded",
    "W-022_p_moon": "W-022_moon_wheel_dart_projectile",
    "W-023_p_bubble": "W-023_dream_bubble_bomb",
    "W-024_p_arrow": "W-024_arrow_normal",
    "W-025_p_arrow_charge": "W-025_arrow_full_charge",

    # 特效 FX
    "FX-001_crit_burst": "FX-001_crit_trigger_orange_flash",
    "FX-010_staff_hit": "FX-010_staff_attack_explosion",
    "FX-015_hammer_shock": "FX-015_hammer_slam_shockwave",
    "FX-021_xp_orb": "FX-021_exp_orb",
    "FX-022_dream_crystal": "FX-022_dream_crystal_currency",
    "FX-023_kill_fade": "FX-023_kill_dissolve_effect",
    "FX-024_level_up": "FX-024_level_up_effect",

    # UI / CG
    "UI-020_title_logo": "UI-020_main_menu_title_logo",
    "CG-001_cg_death_a": "CG-001_death_cg_layer1_frame",
    "CG-004_cg_birthday": "CG-004_ending_birthday_cg",
}

SKIP_DIRS = {'.git', '.workbuddy', 'assets', 'tools', '__pycache__', 'DevelopmentRequirements'}
SCAN_EXTS = ('.gd', '.tscn', '.cfg', '.tres', '.cs', '.json')

def main():
    total_files = 0
    total_repl = 0
    changed = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        # 剪枝
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.lower().endswith(SCAN_EXTS):
                continue
            full = os.path.join(dirpath, fn)
            try:
                with io.open(full, 'r', encoding='utf-8') as f:
                    text = f.read()
            except Exception:
                continue
            newtext = text
            cnt = 0
            for old, new in OLD_NEW.items():
                if old in newtext:
                    newtext = newtext.replace(old, new)
                    cnt += 1
            if cnt:
                with io.open(full, 'w', encoding='utf-8') as f:
                    f.write(newtext)
                total_files += 1
                total_repl += cnt
                changed.append((os.path.relpath(full, ROOT), cnt))
    print("migrate_code: %d 文件被修改, 共 %d 处替换" % (total_files, total_repl))
    for p, c in changed:
        print("  %s  (+%d)" % (p, c))

if __name__ == '__main__':
    main()
