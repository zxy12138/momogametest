# 改动清单 · 房间叠加 / 驿站锁死 / ESC 暂停 / 开发者模式

> 全部经无头（`--headless`）真实运行验证：进战斗房刷怪、跨房无叠加、驿站提示、ESC 暂停冻结、开发者模式全图+跳层，日志零 `SCRIPT ERROR`、退出码 0。

## 1. 房间怪物叠加（每层怪不同，之前跨房累积）
**根因**：`RoomManager` 把敌人/Boss 加进 `_entities`（即 `$World`），而房间切换只 `_room.queue_free()` 销毁房间节点本身——敌人留在 `$World` 跨房累积。
**修复**：
- `src/rooms/RoomManager.gd`：`_spawn_enemy` / `_spawn_boss` 改为 `add_child(e)`（加进 RoomManager 自身），随房间销毁一并清除。
- `src/scenes/Game.gd`：`spawn_enemy`（Boss 召唤小怪用）改为加进 `_room`。
- `Game._swap`：切换时额外清理上一房残留的 `projectile` / `pickup` 分组节点（这两类加在场景根，不随房间销毁）。
**验证**：r2=4 敌 → r3=5 敌（未变成 9）；敌人均为房间节点子节点。

## 2. 驿站锁死、无提示
**根因**：驿站垫 `body_entered` 直接 `open_inn()` 上锁，而玩家恰好出生在垫子中心 → 一进驿站就被锁，像卡死；且无任何引导。
**修复**（`RoomManager.gd` + `Game.gd`）：
- 驿站垫回调改为通知 `_on_inn_enter` / `_on_inn_exit`。
- 踏入垫子：显示「按 F 开启驿站」提示（`_inn_prompt`），**不再自动上锁**。
- 按 **F**（`interact` 动作）才弹出驿站面板；离开垫子隐藏提示。
- 面板逻辑（升级/换武器/梦晶/离开）原样保留。

## 3. ESC 暂停菜单
**新增**（`Game.gd`）：监听 `ui_cancel`（即 ESC），优先级：驿站开→关驿站；暂停开→关暂停；否则开暂停。
- 暂停菜单：`继续` / `重新开始` / `返回主菜单`。
- 暂停时**冻结世界**（对 `enemy` / `projectile` 分组 `set_physics_process(false)` + 锁输入），但**不暂停整棵树**，保证菜单按钮可交互。
- `返回主菜单` 切到 `Main.tscn`，`重新开始` 调 `GameManager.reset_run` 后重载 `Game.tscn`。

## 4. 开发者模式（看全图 + 任意跳关）
**新增**：
- `GameManager.dev_mode`（默认关），**F2**（`dev` 动作）切换；屏幕底部显示「开发者模式 ON · F2 切换 · M 看全图 · 地图内选层跳关」。
- 开启时 `MapData.load_layer` 把当前层所有房间置 `VISITED`（地图全显示、所有房间可传送）；新增 `MapData.reveal_all()`。
- `MapUI.gd`：地图内增加 `L1/L2/L3` 选层按钮（dev 模式显示），点击切层并刷新地图。
- `Game.dev_goto_layer(l)`：切到第 l 层并即时传送 r1。
- 操作流：F2 开 dev → 按 **M** 看全图（所有房间亮起、可点）→ 点房间任意跳关，或点 `L2/L3` 切层看另一张图。

## 配置文件
- `project.godot`：新增输入动作 `interact`（F 键，`physical_keycode=70`）、`dev`（F2，`keycode=4194320`）。ESC 复用内置 `ui_cancel`，无需改动。

## 临时文件
诊断脚本与日志（`_diag.gd` / `_diag.log` / `_boot.log`）已清理；`project.godot` 入口复原 `Main.tscn`、autoload 仅 3 个正式单例。
