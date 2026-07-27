# 修改日志 · 2026-07-27（武器选择改为场景内拾取 + 开场序列）

## 需求
开头动画结束后直接进入第一场景（不再走 WeaponSelect），场景里散落 3 把武器，按 F 交互拾取；
已持武器时选另一把会把旧武器掉地上，走过去按 F 可换回；靠近时有 `[F] 拾取` 提示框；
选择武器前强制播放一段「醒来」序列（头顶对话框「我醒来了，这是在哪……」+ 镜头拉近），序列可 ESC 跳过。

## 改动文件
- `src/autoload/GameManager.gd`
  - 新增 `var prologue_pending := false`（新游戏开场序列触发开关）。
  - `get_weapon() -> Dictionary` 改为无武器(`weapon_id=""`)时返回空 `{}`，避免返回 null 触发运行时报错。
- `src/weapons/WeaponPickup.gd`（新增）
  - 场景内地面武器节点：`weapon_id` 导出；运行时用图标建 Sprite2D + 上下浮动动画；
    `just_dropped()`(0.6s 拾取免疫)、`can_interact()`、`prompt_text()`。
- `src/scenes/Game.gd`
  - `_ready`：新增 `_build_pickup_prompt()`；若 `prologue_pending` 则 `reset_run("")` 并 `_play_prologue()`。
  - 开场序列：`_play_prologue` / `_show_prologue_dialogue` / `_end_prologue` / `_player_camera`；
    相机临时居中(`anchor_mode=0`)+ zoom 2→3.4 拉近，头顶 Control 对话框，3.4s 或 **ESC 跳过**后回归(`zoom=2`、anchor 还原 1) 并生成 3 把起始武器。
  - `_input`：开场中消费 `ui_cancel`(ESC 跳过序列)，避免误开暂停。
  - `_unhandled_input`：开场中不响应；`interact`(F) 优先拾取附近武器，否则开驿站。
  - `_physics_process`：邻近检测（玩家 64px 内最近可交互武器）→ 屏幕底部 `[F] 拾取 XX` 提示框。
  - 武器生成/拾取：`_spawn_starter_weapons` / `_make_weapon_pickup` / `_pick_up_weapon`（已持武器则旧武器掉脚下并免疫 0.6s）。
  - `_swap` 清理 `_pickups` 数组。
  - 注：因 headless 不复扫全局类缓存，`Game.gd` 用 `preload("WeaponPickup.gd")` 创建实例，类型按 `Node2D`，成员走 `call/get/set`。
- `src/scenes/Intro.gd`：`NEXT_SCENE` 改为 `Game.tscn`（不再进 WeaponSelect）。
- `src/scenes/Main.gd`：`_new_game` 置 `GameManager.prologue_pending = true`。
- `src/weapons/Weapon.gd`：`get_weapon()` 返回空 `{}` 时以 `w.is_empty()` 判无武器提前 return。
- `src/ui/HUD.gd`：无武器显示「武器：未装备」；操作提示追加「· F 拾取/交互」。

## 说明
- `F`=`interact` 动作早已绑定（physical_keycode 70），直接复用。
- `WeaponSelect.tscn` / `WeaponSelect.gd` 现已无人引用（死代码），保留未删；如需清理可移除。
- 武器交换后旧武器落地的 0.6s 免疫是防「拾起即掉、掉了又捡」死循环的关键。
- 无头校验（`--run-prologue-test`，临时 `_chk.gd` autoload）通过：序列激活→ESC 跳过→生成 3 把→拾取 staff→交换 sword→走回换回 scythe，全 OK（EXIT=0）。测试脚本与临时配置已还原。
