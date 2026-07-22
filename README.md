# 梦境逐影 · Dream Chaser

> 为虚拟主播 **弥绘** 庆生定制的像素风 Roguelite 动作射击 Demo。
> 引擎：**Godot 4.7.1**｜视角：俯视 8 向移动｜占位美术：程序生成的「方块人形」PNG。

---

## 1. 运行方式

1. 用 **Godot 4.7.1** 打开本项目根目录（`project.godot` 所在文件夹）。
2. 入口场景已在 `project.godot` 中设为 `res://src/scenes/Main.tscn`。
3. 按 **F5** 直接运行，或 F5 配置后「Select Current Scene」即可。
4. 首次进入为 **主菜单**：新游戏 → 选武器 → 进入梦境。

> 无需任何外部资源：104 张占位 PNG 与全部脚本均已随仓库生成。

---

## 2. 操作说明

| 操作 | 按键 |
|------|------|
| 移动（8 向） | `W` `A` `S` `D` |
| 瞄准 | 鼠标 |
| 攻击 | 鼠标左键 |
| 终极技能·噩梦吞噬（每房间一次） | `E` |
| 打开 / 关闭 梦境地图 | `M` |

- **地图**：已探明（VISITED）/ 当前（CURRENT）/ 已净化（BOSS_CLEARED）房间可点击直接传送。
- **驿站**（房间内暖光地块）：Lv.8 武器升阶、Lv.4 换武器、梦晶临时强化。
- **升级**：每次升级弹出三选一词条（致命感知 / 梦境锐化 / 破绽猎手 / 连锁暴击 / 梦食强化 / 全力一击）。
- **死亡**：演出后可选「重试本层」（保留等级/经验/武器/已解锁传送点，重置词条/梦晶/升阶）或回主菜单。
- **通关**：净化第三层最终 Boss 后触发 **生日彩蛋**。

---

## 3. 美术一键替换指南（核心需求）

当前所有美术均为**同名占位 PNG**，路径严格对应 `assets/` 结构。后期替换只需：

> **用同名、同尺寸（建议单帧 32×32 或按数据表规格）的 PNG 覆盖对应文件**，Godot 会在下次打开/重新导入时自动刷新，无需改动任何脚本。

### 目录结构（`assets/`）

```
assets/
├─ sprites/
│  ├─ player/            # A-001~A-009：idle/walk/run/jump/hurt/dead/attack/ult/true（横向精灵表）
│  ├─ enemies/
│  │  ├─ layer1/ layer2/ layer3/   # 每层 5 种小怪，各 idle + attack 两表
│  └─ bosses/           # 3 个 Boss 精灵表
├─ weapons/
│  ├─ icons/            # 武器图标 w_*.png（选武器/换武器界面用）
│  └─ projectiles/      # 弹道贴图 p_*.png
├─ fx/                  # 暴击/冲击波/击杀消散/升级等特效横向表
├─ ui/                  # 标题、按钮、暴击图标、死亡 CG(abc)、生日 CG
├─ tiles/               # 预留地砖
└─ audio/
   ├─ bgm/             # 预留背景乐（按层切换，暂未接入播放）
   └─ sfx/             # 预留音效（暂未接入）
```

- **精灵表规格**：横向排列，单帧宽高见数据（`Player.gd` 的 `spec`、`Enemies.gd` 的 `fw/fh`、`fx` 的 `make_frames` 调用）。替换时务必保持**帧数一致**（否则循环错位）。
- **完整清单**：`assets/GENERATED_PLACEHOLDERS.json` 记录了所有 104 个生成文件的相对路径，可作为美术交付验收表。

---

## 4. 数据驱动设计（改数值不用碰代码逻辑）

| 模块 | 文件 | 说明 |
|------|------|------|
| 武器 | `src/data/Weapons.gd` | 9 基础 + 9 升阶，字段含 dmg/cooldown/暴击/弹道/控制 |
| 敌人 | `src/data/Enemies.gd` | 3 层 ×5 小怪 + 3 Boss（多阶段） |
| 关卡 | `src/data/LevelData.gd` | 网状房间布局、邻接、敌人配置 |
| 全局状态 | `src/autoload/GameManager.gd` | 等级/经验/暴击/属性成长/存档/占位切片 |
| 地图数据 | `src/autoload/MapData.gd` | 房间状态机（LOCKED→REVEALED→VISITED→BOSS_CLEARED） |
| 存档 | `src/autoload/SaveManager.gd` | `user://save.json`，击败每层 Boss 自动存档 |

---

## 5. 已知限制 / 后续 TODO

- **占位美术**：方块人形，仅用于验证完整玩法循环；正式美术按第 3 节覆盖即可。
- **音频**：`audio/bgm` 与 `audio/sfx` 目录已预留，路径尚未接入播放节点（避免悬空引用导致报错，目前为静音）。接入时在 `GameManager`/`RoomManager` 增 `AudioStreamPlayer` 即可。
- **开发文档**：原始需求在 `DevelopmentRequirements/`（`.docx`/`.xlsx`），本实现已据此落地核心玩法。

---

## 6. 重新生成占位素材（可选）

如需重做占位图（例如调整尺寸/配色），运行：

```bash
python tools/gen_placeholders.py
```

会重新生成 `assets/` 下全部 PNG 并刷新 `GENERATED_PLACEHOLDERS.json`。
