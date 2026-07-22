# 《梦境逐影》报错修复与运行验证报告

> 日期：2026-07-21 · 引擎：Godot 4.7.1 · 验证方式：`--headless --path` 真实运行

## 背景
项目此前已实现完整玩法（占位美术），但开启「警告当错误」严格模式后存在大量解析/运行阻断，游戏无法启动。本次目标是修复报错并**真实运行测试**确认可启动。

## 根因与修复清单

### 1. 严格模式根因——Variant 推断当硬错误（7 处）
脚本内 `var x := variant_returning_call()` 被判定为「变量类型从 Variant 推断」而报错，导致脚本整体解析失败、其 `class_name` 不注册，进而拖垮下游所有类型查找。

| 文件 | 行 | 修复 |
|------|----|------|
| `Enemy.gd` | 136 | `var kb: int = _data.get("knockback", 0)` |
| `Weapon.gd` | 18 | `var cd: float = w["cooldown"] * ...` |
| `Weapon.gd` | 39 | `var is_crit: bool = GameManager.roll_crit() or ...` |
| `RoomManager.gd` | 63 | `var neigh: Array = _data.get("neighbors", [])` |
| `RoomManager.gd` | 109 | `var cleared: bool = GameManager.boss_cleared.get(_layer, false)` |
| `RoomManager.gd` | 122 | `var ed: Dictionary = Enemies.get_enemy(eid)` |
| `Boss.gd` | 16 | `var b: Dictionary = Enemies.get_boss(bid)` |

### 2. 循环 `class_name` 强转（40 个 Could-not-find-type → 降为 0）
`Player↔Weapon↔Enemy↔Projectile`、`Boss→Enemy` 间的 `as Player/Enemy/Boss/Weapon/Projectile/Pickup/RoomManager` 制造循环依赖，使循环内**所有类型**解析期都找不到。

**解法**：跨类引用一律改为引擎基类强转 + 动态调用，打破循环：
- `as Player/Enemy/Weapon/Boss/RoomManager` → `as Node2D`
- `as Projectile/Pickup` → `as Area2D`
- 自定义方法：`obj.call("method", args)`；自定义属性：`obj.set("prop", val)`
- 仅保留单向合法继承 `Boss extends Enemy`

### 3. `Boss.gd:2 extends Enemy` 无头模式找不到基类
`class_name` 全局注册表在无头模式下不登记 "Enemy"，按类名继承失败。**改为按脚本路径继承**：
```
extends "res://src/enemies/Enemy.gd"
```
同时把 `RoomManager.gd` 的 `const BOSS = preload(...)` 改为运行期 `load()`，解除启动期加载链。

### 4. Boss 严格模式 3 处
- `create_timer()` 返回 `SceneTreeTimer`（RefCounted，非 Node）不能 `add_child` → 改用 `get_tree().create_timer(2.5).timeout.connect(cb)`。
- `Enemies.enemies_of_layer(...)` / `pool[...]` 返回 Variant，显式标注 `: Array` / `: String`。

### 5. 运行期真 bug（此前因 Boss 脚本未加载而一直藏着）
`Enemy._tick_status` 每帧 `float(_data["speed"])`，但 Boss 数据 `b_director` 无 `speed` 键 → 改为 `float(_data.get("speed", speed))` 防御性取值。

### 6. 测试脚手架修正
- `_test_auto.gd` 用 `Engine.get_singleton("GameManager")` 取不到 autoload → 改为直接写全局名 `GameManager`。
- `Game.gd:90` 的 `$Player` 取 null（Player 在 `World` 子树下）→ 改为 `$World/Player`。

## 验证结果
- **玩法链路无头测试**：`reset_run("staff")` → 战斗房刷 4 敌 → 进 Boss 房（实体 5，Boss 每帧 `_tick_status` 无报错）→ MapUI 开关 → `ult_ready()` → 打印 `RT_OK`，退出码 0。**零 SCRIPT ERROR**。
- **真实入口 Main 启动测试**：主菜单干净启动，零报错，`BOOT_OK scene=Main`。
- **交付配置最终启动**：入口 `Main.tscn`、autoload 仅 `GameManager/SaveManager/MapData`，无悬挂引用，启动零报错。

## 交付态
- `project.godot`：入口复原 `Main.tscn`；autoload 仅 3 个正式单例。
- 临时文件已全部删除：`_test_auto.gd`、`_rt.log`、`_boot.gd`、`_boot.log`、`_final.log`、`_runtime_test.gd`。
- 全项目**无残留循环 `as` 引用、无 `get_singleton` 误用**。

## 剩余非阻断事项
- 正式美术按 `README` 第 3 节同名 PNG 覆盖替换（占位清单 `assets/GENERATED_PLACEHOLDERS.json`）。
- 音频节点接入（`audio/bgm`、`audio/sfx` 路径已预留，目前静音）。
