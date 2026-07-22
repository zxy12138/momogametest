# 改动清单 · 2026-07-22

修复 3 项玩家反馈（均经 `--headless` 真实运行诊断 + 验证）。

## 1. 上移角色「消失」→ 已修复
- **根因**：不是相机（诊断证实相机正常跟随，`cam.y` 始终 = `player.y`）。
  真正原因是 Y 轴排序：玩家/敌人/弹道都用 `z_index = int(global_position.y)`，
  上移时 `y<0 → z<0`，被 `Room.tscn` 的 `Floor`（ColorRect，默认 `z=0`）盖住 → 隐形；
  下移 `z>0` → 回到地板前 → 重现。
- **修法**：`RoomManager._build_floor` 把 `_floor.z_index = -4000`
  （Godot z_index 合法范围 `[-4096,4096]`，-4000 仍在所有实体 y∈[-250,250] 之下，永久最底层）。
- **文件**：`src/rooms/RoomManager.gd`

## 2. 武器不在手上 + 远程弹道不显示 → 已修复
- **武器在手**：`Weapon` 节点原本是裸 `Node2D`，无任何视觉子节点。
  现 `Weapon.gd` 在 `_ready` 阶段建一个 `Sprite2D` 子节点，载入当前武器的 `icon` 贴图，
  每帧按瞄准方向翻转并偏移到手部位置；武器切换时自动重建。
- **弹道贴图（玩家法杖）**：`Weapon._spawn_proj` 原先把 `p.set("texture_path", ...)` 写在
  `_spawn(p,pos)`（内部 `add_child` 会立刻触发 `_ready` 加载贴图）**之后**，
  导致 `_ready` 时 `texture_path` 还是空串 → 贴图永远加载不上 → 弹道隐形。
  现把所有属性 `set` 移到 `_spawn` **之前**。
- **敌人弹道（连带修）**：`Enemies.gd` 的弹道路径写成 `B+"../weapons/projectiles/..."`
  （`B="res://assets/sprites/bosses/"`），解析成 `assets/sprites/weapons/...`（错的，应为 `assets/weapons/...`）。
  改成与玩家 `Weapons.gd` 一致的干净绝对路径 `res://assets/weapons/projectiles/`。
  同时 `GameManager.load_tex` 由 `ResourceLoader.exists()+load()` 改为直接 `load()`
  （`exists()` 不规范化 `..` 路径，会误判缺失）。
- **文件**：`src/weapons/Weapon.gd`、`src/data/Enemies.gd`、`src/autoload/GameManager.gd`

## 3. 无地图/门指引 → 已修复
- **根因**：`RoomManager._build_doors` 只造了隐形的 `Area2D` 门碰撞体，玩家看不到出口。
- **修法**：
  - 每道门加发光门框 + 传送光柱（青色 ColorRect，`z=4/5`）+ 方向箭头标签
    （`↑/↓/←/→` + 目标房类型：战斗/精英/BOSS/驿站/起点/房间）。
  - 击败 Boss 后的「下一层」传送门（`Game._spawn_next_door`）同样加可见指示。
  - 驿站加「驿站」标签。
- **文件**：`src/rooms/RoomManager.gd`、`src/scenes/Game.gd`

## 验证
- 临时诊断 autoload 进 `r1` 战斗房，模拟 `move_up/down` 1s + `attack` 0.6s，记录
  `player.y / z_index / camera.y` 与每发弹道 `from_player / tex_ok`：
  - 玩家弹道 `from_player=true tex_ok=true` ✓
  - 敌人弹道 `from_player=false tex_ok=true` ✓
  - 武器节点含 `Sprite2D` 子节点 ✓
  - 日志零 `SCRIPT ERROR`、零 Z 越界、零资源缺失 ✓
- 交付配置（入口 `Main`、1920×1080、相机 zoom 2）启动零报错。
- 临时诊断文件与日志均已清理，`project.godot` 入口复原 `Main.tscn`。
