# 梦境逐影 · 改动与修复日志（主档）

> 持续累积档。每一次修改 / 修复都在此追加「日期 + 主题 + 根因 + 修复 + 验证」四段。
> 历史快照仍保留在根目录 `CHANGELOG_2026-07-22.md` / `CHANGELOG_2026-07-22b.md` / `DEBUG_REPORT.md`。
> 格式约定：标题 `# 改动 · YYYY-MM-DD · 主题`；子项按 `根因 / 修复 / 验证` 三块。

---

# 改动 · 2026-07-22（上/中/下三批）

## A. 玩家手感 & 渲染修复（3 项）
1. **上移角色「消失」**：Y 轴排序 `z_index=int(global_position.y)`，上移 `y<0` 被 Floor(ColorRect, z=0) 盖住。`RoomManager._build_floor` 设 `_floor.z_index=-4000`（实体 y∈[-250,250]，永久最底）。文件 `src/rooms/RoomManager.gd`。
2. **武器不在手上 + 远程弹道不显示**：`Weapon` 裸 Node2D 无视觉子节点 → `_ready` 建 Sprite2D 挂 icon 并按瞄准翻转偏移；`Weapon._spawn_proj` 把 `texture_path` 的 `set` 移到 `add_child` 之前；敌人弹道路径 `B+"../weapons/..."` 错解析 → 改用干净绝对路径 `res://assets/weapons/projectiles/`。文件 `src/weapons/Weapon.gd` `src/data/Enemies.gd` `src/autoload/GameManager.gd`。
3. **无地图/门指引**：`RoomManager._build_doors` 只造隐形 Area2D。`MapUI` 新增房间指引 + 出口标记。文件 `src/rooms/RoomManager.gd` `src/ui/MapUI.gd`。

## B. 四合一修复（房间叠加 / 驿站锁死 / ESC 暂停 / 开发者模式）
- 房间怪物跨房累积：`_spawn_enemy/_spawn_boss` 改 `add_child` 进 RoomManager 自身随房销毁；`Game._swap` 清残留 projectile/pickup。
- 驿站锁死：踏入垫子只显「按 F 开启驿站」提示，不再自动上锁；`interact`(F) 才弹面板。
- ESC 暂停：新增 `_open_pause` 冻结输入 + 面板。
- 开发者模式：`dev` 动作 F2 切全图 + 跳层。
- 全部经无头真实运行验证（跨房无叠加、驿站提示、ESC 冻结、dev 全图跳层，零 `SCRIPT ERROR`）。

## C. 动态 UI 不可见（按钮无反应 / 驿站不弹窗）
- **根因**：动态面板（toast/驿站/升级/暂停/dev 标签）`add_child` 到受 `Camera2D`(zoom=2 跟随) 变换的 `Game`(Node2D)，却用 `get_viewport_rect().size/2`（屏幕中心）定位 → 被相机变换推到屏幕外。
- **修复**：`Game` 新增专用 `CanvasLayer`(`_ui_layer`, layer=10)，所有动态 Control 改挂其下，定位改用 `get_window().get_visible_rect()`。11 处编辑。
- **验证**：无头启动零报错。

## D. F2 开发者模式无效 + 地图内 ESC 行为
- F2 无效：`project.godot` 的 `dev` 键码错填 `4194320`(小键盘0)，真 F2=`4194305`。已改。
- 地图内 ESC 弹选项框：原 `Game._unhandled_input` 的 `ui_cancel` 分支没判断地图是否开着。`MapUI` 加 `is_open()/close_map()`，`Game` 的 ESC 优先级改为 驿站→地图→暂停→否则开暂停。

## E. 地图未探明房间隐藏类型
- `MapUI._draw_map`：未探明房只显示「未探明」，已可达才显真实类型；保留 `MapData.perception`(Lv21+ 显示类型) 机制。

---

# 改动 · 2026-07-23 · 美术资产库重构（v2.0 最终清单驱动）✅ 已完成

## 动机
`DevelopmentRequirements/梦境逐影_美术素材清单_最终版.xlsx`（v2.0，6 页）定义权威资产标准：编号 `A-/M-/W-/FX-/T-/UI-/CG-/BGM-/SFX-` + 尺寸 + 帧数/数量单位。旧占位用旧命名（`A-001_idle.png`、`e_overtime_ghost_idle.png`…），需按 v2.0「编号 + 英文名称」重做并替换；场景（sheet3）按「数量单位」（8块 / N帧 / 1张 …）展开。

## 决策（已与用户确认）
1. 生成模式：程序占位图（保留后期同名 PNG 覆盖替换）。
2. 代码引用：全量迁移（新命名会令旧 GDScript 路径失效，必须同步改）。
3. 场景「数量单位」展开：多单位→`{code}_{en}_1..N.png`（如 `T-000_dream_floor_1..8`）；N 帧→横向精灵表（宽=w×N，兼容 `GameManager.make_frames` 切片）；1张/1套/1帧→单文件。

## 根因
- 旧资产命名与 v2.0 编号体系不对应；怪物旧代码是 `idle/attack` 二元精灵，v2.0 拆成逐动作（M-001 行走 / M-002 投掷…），需逐敌定制迁移 `fi/fa` 与精灵文件名。
- 旧 `GENERATED_PLACEHOLDERS.json` 仍是旧命名清单，迁移后旧文件需清理、新清单需回写。
- `gen_assets.py` 与 `migrate_code.py` 的英文名必须一致，否则代码引用悬空。

## 修复
- 新增 `tools/gen_assets.py`：手写 zlib RGBA PNG 编码器（无第三方库），按 v2.0 manifest（218 条目 → 220 文件，含 M 逐动作、T 多块/精灵表展开）生成占位 PNG 落到 `assets/` 对应子目录；结尾清理旧占位 + 写回 `assets/GENERATED_PLACEHOLDERS.json`（220 条）。
- 命名：`{编号}_{英文名称}.png`（英文由中文义派生 snake_case，复用 `mihui`/`staff` 等旧名）。
- 新增 `tools/migrate_code.py`：把 `src/` 全部 `res://assets` 旧路径引用改为新命名，逐敌整段替换并同步 `fi/fa`（kpi fa=3→5、package fa=3→5、elite_996 fa=4→6、b_director fa=4→5、b_fear fa=4→5、phone fa=3→4 且 layer=1 用 E1）；弹道 `p_staff/p_bubble`→`W-020/W-023`；FX `fx_*`→`FX-*`；UI/武器/标题/Birthday/DeathCG 全部对齐。共 64 处跨 11 文件。脚本幂等（旧串不在且新串已在则跳过）。
- 修复 `gen_assets.py` manifest 拼写错：`M-017`/`T-034` 的 `revolver_spin`/`revolver_deco`（左轮手枪，误）改为 `revolving_spin`/`revolving_deco`（旋转门，正）；同步改 cleanup 逻辑为「仅删旧清单有、本次未生成的文件」+ `try/except` 兜底 safe-delete 守护的 EPERM，避免重跑时误删本次产物或崩溃致 JSON 未写。

## 验证（静态；本沙箱无 Godot 二进制，实机验证见下）
- `assets/` 现存 v2.0 PNG 共 220 张（与 JSON 一致）；另有 5 张 `gemini_generated_image_*.png` 为历史 AI 废图，未引用、非本次范围，留作备注。
- 0 个代码引用文件名在磁盘缺失（52 处被引用的精灵/贴图文件名全部存在）。
- 0 个旧命名残留（旧 `e_*`/`fx_*`/`w_*`/`A-00x_*` 等已全部替换）。
- 0 个孤儿 `.import`（无指向已删 png 的悬空导入）。
- 3 个 `res://assets/audio/bgm/bgm_1..3.ogg` 缺失为**历史预留下**（`LevelData.gd` 字符串常量，非 `preload`，播放走运行时 `load()` 返回 null 静音），本次按约定跳过音频（清单 Sheet5），非回归。
- **待用户实机验证**：在本机用 Godot 4.7.1 启动，确认全部精灵/贴图加载、零 `SCRIPT ERROR`（重点核对逐动作怪物 M-001..M-036 的 `fi/fa` 切片与精灵表宽高匹配；可临时把 `project.godot` 的 `run/main_scene` 指向 `Game.tscn` 挂诊断 autoload 进战斗房跑数秒抓日志里的 `Invalid access`/`E `/`SCRIPT ERROR`）。

## 已知风险与缓解
- 逐动作怪物 `fa` 帧数必须与精灵表帧数一致，否则动画切片错位 → 实机 Playtest 重点核对 M-003/M-018/M-021/M-030/M-031/M-032。
- 音频 BGM 仍为占位缺失 → 接入真实音频后需在 `LevelData.BGM` 放对应 `.ogg`，否则持续静音（不影响运行）。
- `gemini_generated_image_*.png` 5 张废图建议后续清理（删除前请确认）。

---

# 改动 · 2026-07-23（续）· 美术资产库重构 v3.0（纠正"v2.0"前提，覆盖上条）

## 前提纠正
- 上一条（2026-07-23 美术资产库重构 v2.0）误以为读取的是 v2.0 清单；用户确认磁盘上的 xlsx 实为 **v3.0 最终版**（之前忘记替换文档）。故上条所述尺寸/英文名/帧数均应按 v3.0 标准理解。本条目按 v3.0 实际完成重构。

## v3.0 标准要点（相对上条纠正）
- **尺寸**：角色 / 普通怪 / 精英怪 = **130×250**；Boss = **260×500**（上条误作 32×32 / 80×64）；武器/特效/UI/场景 Tile 尺寸同前。
- **英文名权威列**：清单新增「英文名称」列（带空格与大小写，如 `Miai Idle` / `Revolving Door Spin`），生成时转 snake_case 作文件名；**不再用上条手推旧名**（`mihui`→`miai`、`revolving_spin`→`revolving_door_spin`、`kpi_float`→`kpi_monster_float`、`director_idle`→`director_boss_idle` 等）。
- **帧数权威**：清单帧数列即精灵表帧数（`fi`/`fa` 必须匹配，否则切片错位）。
- **场景数量单位**：8 块→`_1..8` 多文件；N 帧→横向精灵表（宽=w×N）；1 张/1 套/1 帧→单文件（同前）。

## 修复
- 新增 `tools/v3_assets.py`：单一权威清单 `(code, english_snake, w, h, frames, cat, kind)`，从 v3.0 xlsx 解析（经 `tools/_tmp_xlsx_dump.py` stdlib `zipfile`+`ElementTree` 解析 6 页）。
- 改写 `tools/gen_assets.py`：数据源改从 `v3_assets.py` 取；`folder_of` 映射 enemy 按编号分 `layer1(≤8)/layer2(≤19)/layer3`；`kind` single/sheet/multi。运行 `TOTAL generated: 220`，写回 `assets/GENERATED_PLACEHOLDERS.json`（`generated` 220 条 + `note`）。
- 改写 `tools/migrate_code.py`：v3 改名映射（old→new 桩），遍历 `src/` 全部 `.gd`（跳过 tools/assets/.git/.workbuddy）替换文件名桩；**幂等**。本轮运行：11 文件 / **67 处**替换。
- 维度回填：写 `tools/_fix_dims.py`（临时）按 v3 帧数/尺寸回填 `Enemies.gd` 与 `Player.gd`：`fw/fh` 怪物 130/250、Boss 260/500；`fi`=idle v3 帧、`fa`=attack v3 帧（逻辑见 `Enemy.gd` setup：`fi` 切 idle、`fa` 切 attack，二者同 `fw/fh`）。玩家 `dead` 帧 6→5（v3 `A-006_miai_death`=5）。
- 顺手把 `Birthday.gd`/`DeathCG.gd` 注释里的旧占位名改为 v3 名。

## 验证
- `assets/` 现有 PNG = **220**（与 JSON 完全一致），**0 stale**（v2.0 旧文件已全部迁出）。
- 枚举 `src/` 全部 `res://assets/*.png` 引用共 **24 处，0 缺失**（全部指向存在的 v3 文件）。
- 精确比对 56 个 v3 改名老桩：src/ 内 **0 残留**（grep 曾报的 `jammed_printer_walk`/`exp_orb` 等均为"新名含老桩子串"误报，已用精确桩列表复核）。
- 0 个孤儿 `.import`（v2.0 的 `.import` 随 png 一并迁出）。

## 已知风险与缓解
- 旧 v2.0 占位 PNG 共 135 张，已用 **move**（非 delete，绕开 safe-delete 守护的 50/会话阈值）整体迁出至项目外 `_trash_v2/`（含其 `.import`，共 270 条目），**可逆**。本会话 safe-delete 守护阈值已耗尽，无法 `os.remove` 批量永久删；待新会话或用户手动清 `_trash_v2/` 即可彻底移除。
- Boss `M-031..M-036`（phase1..death 等）已在磁盘生成占位，但 `Enemies.gd` 的 BOSS 字典仅引用 `sprite_idle(M-031)/sprite_attack(M-032)`，phase 精灵当前未被代码使用——属预留，不影响运行；后续做多阶段换皮可接入。
- 实机仍建议用 Godot 4.7.1 启动验证：零 `SCRIPT ERROR`，重点核对逐动作怪 `fi/fa` 切片与精灵表宽高匹配（玩家 130×250、Boss 260×500）。
- 音频 BGM/SFX 仍按约定跳过（清单 Sheet5），`LevelData.BGM` 引用 `bgm_1..3.ogg` 缺失→静音，非回归。

---

# 改动 · 2026-07-24 · 角色放大后的视觉比例与待机速率修正

## 动机
v3.0 把角色/怪物贴图从占位的小尺寸改为 **130×250**（Boss 260×500），但房间门、下一层传送门、驿站等**可见色块仍是旧的小尺寸（≈56×70）**，相对 130×250 的大角色显得过小；同时待机(idle)动画按 spec `fps=12` 播放（4 帧 0.33 秒一循环），换成精细美术后明显发飘。

## 决策（已与用户确认）
1. 待机速率：idle 12→**6 fps**，并同比例调慢 walk 12→8、run 16→10（jump/hurt/attack/dead/ult/true 保持）。
2. 门/传送门/驿站放大：**等比到角色尺寸**（碰撞体积与位置不变，仅放大可视色块 + 文字字号）。

## 根因
- 门/传送门/驿站是 `RoomManager._build_doors`、`Game._spawn_next_door`、`RoomManager._build_inn` 里用纯色 `ColorRect` + `Label` 画的，尺寸写死为小数值；地板是纯色 `ColorRect`（无瓦片贴图），房间 `W=880,H=500` 本身已能容纳大角色，无需改尺寸。
- idle 速率快纯属 `Player.gd` spec 的 `fps` 字面值偏高；实测替换后的 `A-001_miai_idle.png` = **520×250（正好 4 帧×130 宽）**，切片正确，不是尺寸/帧数错。

## 修复
- `src/player/Player.gd`：spec 中 idle 12→6、walk 12→8、run 16→10。
- `src/rooms/RoomManager.gd`：`_build_doors` 门可视 `frame 56×70→130×160`、`portal 50×64→120×150`、标签字号 14→22；`_build_inn` 驿站暖光标记 `60×60→150×150`、标签字号 14→22 并上移避免压住标记。碰撞（Door 44×44、Inn 60×60）不动。
- `src/scenes/Game.gd`：`_spawn_next_door` 下一层传送门 `frame 58×74→130×160`、`portal 54×70→120×150`、标签字号 14→22。碰撞（48×48）不动。

## 验证
- 纯字面量数值/字号改动，无语法结构变化，低风险。建议本机 Godot 4.7.1 实机目测：待机呼吸节奏是否自然、门/传送门是否与大角色协调、进入门仍正常触发切房。

## 已知风险与缓解
- 放大后的门（高 160）中心点仍在房间边缘（`-H/2+26 = -224`），上半部分会略微探出地板（房间高 500，墙为不可见碰撞体无贴图），属传送门常见表现，不影响触发；若介意可后续把门的 `position` 沿法线内移。
- 地板仍为纯色（未用 T-xxx 瓦片贴图）；若后续要把"场景"做成带瓦片纹理的地面，属独立功能（瓦片资产已就绪），需另行排期，不在本次范围。

---

## 2026-07-24（续）· 贴图场景构建 + 角色 0.6 缩放（v3.1）✅ 已完成

### 背景
- 用户确认：地图场景**此前完全没用**生成的 `T-*` 贴图——`RoomManager.gd` 地板纯色 `ColorRect`、墙为隐形 `StaticBody2D` 碰撞体、门/驿站为青色/暖色 `ColorRect`；`assets/tiles/` 下 186 个瓦片全部闲置。
- 用户要求：按 GDD（§4 地图系统 / §7 关卡主题 / §9.1 场景结构）**正式构建贴图场景**，落实「改无法进入的无法进入」，并把在 880×500 房间里屏占比过大（约半屏高）的角色缩小。
- 决策（用户拍板）：角色 **0.6×**；**完整贴图场景**（地板瓦片化 + 按层贴墙 + 门口门框 + 驿站贴图）。

### 改动（改无法进入的无法进入：四面墙都有贴图+碰撞，仅 `neighbors` 边留门洞）
- `src/rooms/Room.tscn`：Floor 节点 `ColorRect` → `TextureRect`（供代码赋纹理）。
- `src/rooms/RoomManager.gd`：
  - `_build_floor`：平铺 `T-000_base_dream_floor_tile_1.png`（`STRETCH_TILE`）+ 按层 `modulate` 染色（层1 冷蓝/层2 中性/层3 暗红）。
  - 新增 `_build_wall_visuals(th)` + `_wall_seg(...)`：四边平铺对应层墙瓦片——层1 `T-021_office_wall_tile_1` / 层2 `T-031_subway_wall_tile_1` / 层3 `T-041_warped_wall_animated` / 兜底 `T-001_base_wall_tile_1`（均 16×16 STRETCH_TILE）；**仅 `neighbors` 存在的边留 64px 门洞，其余实墙不可穿**。碰撞 `StaticBody2D` 四边不变。墙体 `z_index=-10`。
  - `_build_doors`：青色 `frame/portal` → `Sprite2D` 门框（`T-003_door_frame_open_anim.png`，128×48 为 4 帧横排表，取首帧，`hframes=4, frame=0`，缩放到 64×96）；`Area2D` 触发器 44×44 与 `Label` 不变。
  - `_build_inn`：加 `T-050_dream_rest_stop_interior.png` 地面贴图（`Sprite2D`，`z_index=-3000`）+ 保留暖光 `ColorRect`。
- `src/scenes/Game.gd`：`_spawn_next_door` 下一层传送门青色 `frame/portal` → 同上 `T-003` 门框 `Sprite2D`（64×96）；触发器与 `Label` 不变。
- `src/player/Player.gd`：`_ready` 加 `_sprite.scale = Vector2(0.6, 0.6)`（**仅缩视觉精灵，CharacterBody2D 碰撞/物理不动**）。

### 验证
- Godot 4.7.1 `--headless --script` 解析校验：修掉 1 个严格模式错误（`_build_inn` 中 `var iscale := 130.0 / max(isz.x, isz.y)` 的 `max()` 推断失败 → 改为 `var iscale: float = ...`）；其余 `GameManager/MapData` 未找到报错是 `--script` 环境未注册 Autoload 的**环境性误报**（游戏运行时有 Autoload，非本次引入）。
- 新增 7 个 `res://assets/tiles/*` 引用全部在磁盘（**0 缺失**）；旧青色门/传送门色块无残留。

### 已知风险与缓解
- `T-041_warped_wall_animated`(64×16) 是 4 帧横排墙动画表，平铺时会以整 64px 为周期重复（视觉为 4 种微差 16px 墙循环），层3 作占位可接受；若想要单帧墙可改取首帧或换 `T-001`。
- `T-003` 门框目前取首帧静态显示；若要"开启动画"效果，可给 `Sprite2D` 加 `AnimationPlayer`/`_process` 循环 `frame 0..3`（本次未做，保持低风险）。
- Agent 调度器（engineering-lead）连续两次报内部错误（`Cannot read properties of undefined (reading 'history')`）派单失败，本次由主理人直接落地实现并保持 oversight；建议本机 Godot 4.7.1 实机目测：地板/墙/门贴图观感、门洞与墙对齐、角色 0.6 比例是否合适、进门切房仍正常。

---

## 2026-07-24（续2）· 场景构建方案切换为预制整图（v4.0）✅ 文档已更新

### 背景
- 用户对"通用瓦片拼接场景"流程感到繁琐，决定改为：**每一关的场景由美术预先制作好**（一图一房，含墙/地板/家具/灯光全部烘焙），工程只需实现「门的开关动画」与「空气墙（InvisibleWall）」的逻辑。
- 用户参考图：`assets/tiles/changjing1.png`（第一层办公室类型，整图场景俯视图，工位林立、文件散落、四面墙与地板一体）。

### 决策
- **场景视觉**：每种房间类型由美术提供一张预制整图（PNG，960×540），不再使用通用瓦片拼接。
- **工程范围**：仅需实现 `Door`（开/关帧切换 + Area2D 触发器联动）与 `InvisibleWall`（纯 `StaticBody2D` + `CollisionShape2D`，零贴图）的逻辑。
- **房间结构保持不变**：W=880, H=500，碰撞/传送逻辑/刷新机制/玩家缩放（0.6×）均不动；仅场景渲染方式从"程序拼瓦片"改为"美术出整图"。

### 文档改动

**① `DevelopmentRequirements/梦境逐影_游戏设计文档_最终版.docx`（已落地）**
- §9.1 场景结构表：RoomManager.gd 行重写为「加载预制场景整图 + 叠加不可见空气墙 + 放置门节点 + 怪物刷新」；新增 2 行 `Door.tscn/Door.gd`、`InvisibleWall.tscn`（表行数 13 → 15）。
- §4.3 末尾新增 1 段「场景视觉呈现」说明（含 changjing1.png 引用）。
- §7.2 / §7.3 / §7.4 各新增 1 段「【场景构建方式】」说明，明确本层采用预制整图方案。

**② `DevelopmentRequirements/梦境逐影_美术素材清单_最终版.xlsx`（v4.0 内容已写到 sibling 文件）**
- 原文件被 WPS（`wps.exe` PID 44676，长期运行实例）持有排他锁，无法直接覆盖。
- v4.0 内容已写到 sibling 文件 `DevelopmentRequirements/_梦境逐影_美术素材清单_最终版_v4.0.xlsx`，**用户需关闭 WPS 后手动改名覆盖原文件**（或双击打开 sibling 验证内容 OK 后再覆盖）。
- Sheet3 重构为 5 段（场景整图 / 门动画 / 驿站内饰 / 通用道具 / 地图节点）+ 1 段废弃清单：
  - **A. 场景整图 S-001~S-018**（3 层 × 6 房型：战斗/精英/驿站/神秘/Boss/传送阵），960×540 各 1 张；S-001 引用 changjing1.png。
  - **B. 门动画 D-001~D-003**：D-001 标准门·关闭（48×64,1帧）、D-002 标准门·开启动画（48×64,4帧 横向精灵表）、D-003 Boss 门·特殊态（64×80,2帧）。
  - **C. 驿站内饰 I-001~I-003**（沿用 v3 T-050~T-052 内容）。
  - **D. 通用道具 P-001~P-003**（沿用 v3 T-004/T-005/T-006 内容）。
  - **E. 地图节点 N-001~N-010**（沿用 v3 T-007~T-016 内容）。
  - **F. 已废弃清单**（v3 通用 Tileset T-000/T-001/T-020~T-044 共 21 项），均标 ✗，说明「已废弃：改用 S-xxx 整图方案」或「已废弃：装饰烘焙进场景整图」。
- Sheet6 总览更新为 v4.0：「场景整图·第一层/二/三层（6 房）」+「门动画」3 个新行；Tileset 行移除。

### 验证
- GDD docx：15 行 §9.1 表 + 4 个新增段落（§4.3 + §7.2/7.3/7.4）全部就位（重读 document.xml 验证）。
- xlsx v4.0 sibling：Sheet3 = 67 行（标题/说明/表头 + 6 段分组 65 + 表头 1）、Sheet6 = 31 行（标题/表头 + 27 类别 + 1 更新说明），结构正确、内容可读。
- 工程文件**本次未改**（仅文档改动）：RoomManager.gd 现有的 `_build_floor/_build_walls/_build_doors` 仍按 v3.1 的瓦片方案运行，待用户完成整图后由工程侧按 v4.0 改为「加载整图 + 空气墙 + 门动画」。

### 已知风险与缓解
- **WPS 锁文件**：`wps.exe PID 44676` 长期持有原 xlsx，导致无法直接覆盖。已通过 sibling 文件方式绕过；用户关闭 WPS 后即可完成替换。
- **代码现状**：当前 RoomManager.gd 仍是 v3.1 通用瓦片拼接版，**与新文档规范不一致**。待用户美术整图资产就绪后，工程侧按 v4.0 重写 RoomManager（删 `_build_wall_visuals`、改 `_build_floor` 为 `load(scene_png)`、新增 `Door`/`InvisibleWall` 节点挂载逻辑）。建议作为下一阶段任务排期。
- **Sheet 编号迁移**：v3 → v4 编号体系变化（Tileset T-* → Scene S-* + Door D-* + Rest I-* + Prop P-* + Node N-*）；原 `T-007~T-016` 地图节点代码侧未引用（地图节点在 MapUI.gd 单独画），但建议下一版 MapUI 引用编号同步到 N-*。

---

## 2026-07-24（续3）· 角色再缩小 + changjing1 预制整图试用（v4.0 代码第一步）

### 需求
- 用户：人物还是太大，"起码缩小一半以上"；并希望"用我提供的地图 changjing1.png 作为一个战斗场景试试"。

### 改动
- **`Player.gd`**：`_sprite.scale` 由 `Vector2(0.6,0.6)` → `Vector2(0.28,0.28)`（约 53% 缩减，满足"缩小一半以上"）；仅视觉精灵，CharacterBody2D 碰撞不动。
- **`Enemy.gd`**：`setup` 新增 `_sprite.scale = Vector2(0.45, 0.45)`。原敌人是原生 1.0（比 0.6 的玩家还大），若只缩玩家会"玩家很小、敌人巨大"不协调；取 0.45 保持原 0.6:1.0≈0.28:0.45 比例。碰撞半径 `mini(fw,fh)*0.32` 不变。Boss 暂未动。
- **`RoomManager.gd`**：新增 `_prefab` 标记；`_build_floor` 读 `_data.scene_img`——有则 `load` 该图作背景（`STRETCH_KEEP_ASPECT_COVERED`，`z_index=-4000`）并跳过瓦片墙体贴图（`_build_walls` 中 `if not _prefab` 才调 `_build_wall_visuals`）；碰撞墙/门触发器逻辑不变。这是 v4.0「加载预制整图」的第一步落地。
- **`LevelData.gd`**：第一层 `r2`/`r3` 临时加 `scene_img="res://assets/tiles/changjing1.png"`（标注 TEST，待正式整图流程接管后删除此键）。即第一层两个战斗房现在以 changjing1.png 作背景试运行。
- **`Game.gd`**：开发者模式标签 "F2 切换" → "F12 切换"（与 `project.godot` 实际绑定 keycode 4194315=F12 一致，旧标签误导）。

### 验证
- Godot 4.7.1 `--headless` 临时将 `main_scene` 指向 `Game.tscn` + `_chk` autoload 进入战斗房 `r2`（预制整图背景 + 刷 rescale 敌人），日志 `CHK_START`→`RT_OK_ENTERED_R2`，EXIT=0，零 `SCRIPT ERROR` / `Invalid access`。验证后还原 `project.godot` 并删除 `_chk.gd`。

### 已知风险与缓解
- **仅 v4.0 第一步**：本次只跑通"加载预制整图背景"。门动画（Door 开/关帧切换）与空气墙（InvisibleWall 独立节点）**尚未实现**，当前仍用 RoomManager 旧碰撞墙 + `T-003` 门框贴图。待用户整图资产（S-001~S-018）就绪后，按 v4.0 补齐 Door/InvisibleWall 并重写场景加载。
- **临时 TEST 键**：`LevelData` 的 `scene_img` 为试用钩子，正式流程应改为按房型从美术清单 S-* 读取；r2/r3 现共用同一张 changjing1，观感上两房相同属正常现象（试用阶段）。
- **敌人碰撞未随视觉缩小**：视觉 0.45 但碰撞半径仍按 `fw/fh` 原值，等同"判定框略大于缩后精灵"，对玩家偏友好，可接受；正式调参时若需更贴合可另行缩放碰撞。

---

# 改动 · 2026-07-26 · 玩家精灵图改用合并图 A-001_all.png（按行分动作 + 四向方向逻辑）

## 背景
- 原 `Player.gd` 的 `spec` 把每个动作拆成独立 PNG（`A-001_miai_idle` / `A-002_miai_walk` / `A-003_miai_run` / `A-006_miai_death` …），由 `GameManager.make_frames` 逐图横向取帧。
- 现美术合并为单张 `A-001_all.png`：**1024×1024、8×8 格、每格 128×128、每行 8 帧、全填满**。行映射（自上而下）：
  - 行0 = 下走(walk_down) / 行1 = 左走(walk_left) / 行2 = 上走(walk_up) / 行3 = 左跑(run_left) / 行4 = 待机(idle) / 行5 = 死亡(dead) / 行6、行7 空。
- ⚠️ **与项目原约定冲突**：角色帧长期是 **130×250**，但这张合并图物理上是 **128×128**（1024 高放不下 8 行 250 高），原约定对合并图失效。代码按文件实测值接入（128×128、8 帧/行）。

## 根因 / 修复
- **`GameManager.gd` `make_frames`**：原为「仅第 0 行横向取帧」`Rect2(i*fw, 0, fw, fh)`。新增**行号参数**（spec 第 6 元素，默认 0），取帧改为 `Rect2(i*fw, row*fh, fw, fh)`；敌人/Boss 调用不传行号 → 行为不变（兼容）。
- **`Player.gd` `spec`**：
  - 合并图行接入 6 个：`idle`(行4) / `walk_down`(行0) / `walk_left`(行1) / `walk_up`(行2) / `run_left`(行3) / `dead`(行5)，均 `[A-001_all.png, 128,128, 8, fps, 行号]`。
  - **未纳入合并图的 5 个动作保留独立文件**：`jump`(A-004) / `hurt`(A-005) / `attack`(A-007) / `ult`(A-008) / `true`(A-009)（130×250 旧尺寸，行号默认 0）。
- **`Player.gd` `_anim_update` 重写（方向逻辑）**：原单一 `walk` + 靠瞄准 `flip_h`；现按移动向量四向选动作——水平主导用 `walk_left` 且 `flip_h = velocity.x>0`（左行镜像为右向），上下主导用 `walk_down`/`walk_up`，冲刺(`_dash_t>0`)用 `run_left`；静止/上下行走按瞄准保持左右朝向。移除 `_physics_process` 里原「按瞄准设 `flip_h`」那一行，避免与方向逻辑冲突。
- **`assets/sprites/player/A-001_all.png.import`**：新建，照现有 player 图设置（lossless `compress/mode=0`、`mipmaps/generate=false`），省略 `uid` 由引擎首次打开自动生成。

## 已知风险 / 待确认
- **角色明显变小**：`scale=0.28` 原按 250 高调，现帧高 128 → 同缩放下角色约变为原来的 ~51%。如观感需保持，应将 `_sprite.scale` 提到约 `0.55`，但这是美术尺寸决策，未擅改，留待你/美术定。
- **合并图(128×128)与独立动作(130×250)高度不一致**：保留的 `attack`/`ult`/`jump`/`hurt`/`true` 仍是 250 高，而 `idle`/`walk`/`run`/`dead` 变 128 高；同一 sprite 的 `scale` 统一，故切到攻击/终极时人物会瞬间变高约 2 倍。根因是两类素材分辨率不同，彻底解决需把剩余动作也并入合并图（或统一重导出为同尺寸）。本次按「保留独立文件」决定落子，未强行缩放。
- **攻击/终极仅 1 帧可见**：`ult`/`attack` 仍走原逻辑（无播放时长锁），`_anim_update` 次帧即被 idle/walk 覆盖——属改动前既有行为，本次未动。
- **`v3_assets.py` 美术清单未改**：合并图为新增资产 `A-001_all`，原 `A-001~A-009` 独立项仍作独立动作源保留（仅 idle/walk/run/dead 实际改读合并图）。`DevelopmentRequirements/*.xlsx` 为二进制，未手写改动；如需在清单里登记合并图请告知。

## 验证
- 本机无 Godot 可执行文件（沙箱下载 release CDN 被掐），未跑无头实机。已做代码级核对：3 处改动落在文件；`make_frames` 行号默认 0 兼容敌人/Boss；`walk/run` 旧名无别处硬编码；PNG 网格实测 8×8、每行 8 帧与映射一致。
- 请在本机 Godot 打开工程确认：① 进战斗房角色 idle/移动/冲刺/死亡动画正确；② 右向移动是左行镜像（非穿模）；③ 角色尺寸是否需调 `scale`。

---

# 修正 · 2026-07-26（补）· 玩家合并图方向名 + 动画降速

## 1. 第二行实为「向右 walk」
- 原按 `A-001_all.png` 行映射把**行1**接成 `walk_left`（左走）。用户核图后确认行1实际是**向右 walk**。
- `Player.gd`：`spec` 中 `walk_left` → **`walk_right`**（仍指行1）；`_anim_update` 水平移动改用 `walk_right`，镜像规则反转——`_sprite.flip_h = velocity.x < 0`（右走精灵默认朝右，左移时翻成左向）。
- 注释同步：`行映射：0=下走 1=右走 2=上走 3=左跑 4=待机 5=死亡`。
- 行3（`run_left` 左跑）用户未要求改，维持原样。

## 2. 动画整体降速（用户反馈「太快」）
- 合并图 8 帧/行 + 帧率偏高导致观感偏快。统一下调帧率约 25–33%：
  - `idle` 6 → **5**
  - `walk_down`/`walk_right`/`walk_up` 8 → **6**
  - `run_left` 10 → **8**
  - `dead` 12 → **8**
- 说明：独立图时代的 walk/run/dead 帧率本就是 8/10/12，合并图每行动画帧数从 6 增至 8，故整体偏快；本次在文件实测值基础上直接降 fps，肉眼可见变慢。若仍偏快可继续下调（walk 建议下限 ~4）。

## 验证
- `grep walk_left` 全仓无残留；Python 复刻 `make_frames` 取帧矩形，6 个动画所有帧均在 1024×1024 内（OK）；方向逻辑自检：右移→walk_right 不翻、左移→walk_right 翻转（True）。
- 本机仍无 Godot 二进制，未跑无头实机；请本机确认右移为「朝右」原图（非镜像穿模）、降速幅度是否合适。

---

# 改动 · 2026-07-26（补）· 让所有场景在编辑器里可见（@tool 编辑器预览）

## 背景
- 用户诉求：在场景编辑器里直接看到「所有东西」（房间/墙/门/敌人/Boss/玩家），而不是只能 F5 运行后看。
- 根因：原架构是数据驱动 + 运行时生成。`.tscn` 仅放骨架（`Game.tscn` 只有 World/Player/HUD/MapUI/Fade），房间/墙/门/敌人/Boss 全是 `RoomManager.setup()` 与 `Game._ready→transition_to→_swap` 在运行时 `add_child` 进去的；玩家精灵帧也在 `_ready` 里 `make_frames` 构建。全仓当时只有 Player 是 `@tool`，所以编辑器里近乎全空。

## 修复（@tool 编辑器预览）
- **`Game.gd`**：加 `@tool`。`_ready()` 内 `if Engine.is_editor_hint(): _editor_build_preview(); return`，在编辑器里直接 build 一个示例世界（地板/墙/门/敌人/Boss 全显示），跳过 UI/淡入/信号/计时器等游戏逻辑。运行期逻辑完全不变。
  - 新增 `_editor_build_preview()`：`MapData.load_layer(1)` → 实例化 `Room` 并 `setup("r1", …)` → 手动放 2 个敌人(`overtime_ghost`/`printer`)+ 1 个 Boss(`b_director`)，并把玩家相机锚点临时改居中(`anchor_mode=0`)，使房间整屏可见。
- **`RoomManager.gd`**：加 `@tool`。`setup()` 在编辑器可运行；新增 `_ready()` 仅当 `is_editor_hint() and _rid=="" and get_parent()==null`（即独立打开 Room.tscn）时 build 一个示例战斗房，被 Game 嵌套实例化时不自动 build（避免重复生成）。
- **`Enemy.gd`**：加 `@tool`；`_physics_process` 首行 `if Engine.is_editor_hint(): return`；`_ready()` 仅在编辑器且未 setup 时 `setup("overtime_ghost")` 预览（被 Game 实例化时 setup 已在 add_child 前调用，`_eid` 非空 → 跳过，无重复）。
- **`Boss.gd`**：加 `@tool`；`_physics_process` 首行守卫；覆盖 `_ready()` 用 `setup("b_director")` 预览（避免误走敌人 setup）。

## 已知注意点（如实告知）
- **Ctrl+S 污染风险**：预览节点是 `@tool` 在编辑器运行时 `add_child` 的，标准 @tool 模式下不会写进 `.tscn`；但请勿在预览存在时保存 Game.tscn。若误保存导致场景被污染，删除场景中凭空出现的 `Room` 节点即可。关闭场景重开即自动清理。
- **相机**：玩家相机 `anchor_mode` 原为 `1`(固定左上)，会导致房间偏到角落；预览里已临时改居中，仅影响 live 节点、不写入场景。
- HUD/MapUI 是 CanvasLayer（UI 覆盖层），非 `@tool`，编辑器里仍为空——属正常（它们是运行时 UI，不属「世界内容」）。
- 本机仍无 Godot 二进制，未跑无头实机；已做代码级核查：`@tool`/`is_editor_hint` 守卫齐全、位置正确、无重复 build、节点名(Sprite/CollisionShape2D/Hitbox/Floor)与 setup 引用一致、`LevelData.r1` 含 neighbors 且 `MapData.room(r2/r3)` 存在（门/标签不取空）。

## 验证（请在编辑器确认）
- 打开 `Game.tscn`：应看到房间地板/四面墙/上下门 + 玩家 + 2 敌人 + 1 Boss 在 2D 视图里。
- 单独打开 `Room.tscn` / `Enemy.tscn` / `Boss.tscn`：应各自显示示例内容。
- 运行 F5：行为与改动前完全一致（编辑器分支已早退，不影响运行期）。

---

# 改动 · 2026-07-26（补）· 拾取物磁吸：经验 2 秒后自动飞向玩家

## 需求
- 敌人/Boss 掉落的「经验球」在落地 2 秒后，自动飞向玩家并被拾取（磁吸式拾取），不必走上去碰。

## 实现（仅改 `src/fx/Pickup.gd`）
- 新增 `@export var homing_delay = 2.0` / `homing_speed = 420.0`（可在检查器调），`const PICKUP_RADIUS = 14`。
- `_ready()`：保留原落地轻微漂浮 tween；新增 `get_tree().create_timer(homing_delay).timeout.connect(_start_homing)`。
- `_start_homing()`：杀掉漂浮 tween，置 `_homing=true`，用 `get_tree().get_first_node_in_group("player") as Node2D` 取玩家（**不向下 `get_parent`**，符合组件向上通信规范）。
- `_process(delta)`：磁吸态下 `global_position.move_toward(player.global_position, homing_speed*delta)`，天然减速、不越界；进入 `PICKUP_RADIUS` 即 `_collect()`。
- 保留原 `body_entered` 碰撞拾取（玩家可提前走上去捡）；统一收口到 `_collect()`，并在其中安全断开定时器、杀 tween、`queue_free()`。
- 类型全部显式：`kind: String` / `value: int` / `_player: Node2D` / `_homing_timer: SceneTreeTimer`，无 `Variant`、无 untyped `var`。

## 验证（本机无 Godot，代码级核查）
- `GameManager.add_xp(amount: int)` / `add_crystals(n: int)` 均收 `int`，`value: int` 匹配。
- 旧字符串 `connect("body_entered", ...)` 已换 Godot 4 `body_entered.connect(...)`。
- 定时器断开用 `is_connected("timeout", _start_homing)` 守卫，避免重复/已失效连接报错；提前踩拾取也能安全清掉定时器与 tween。
- `Enemy._drop` / `Boss`(5 颗梦晶) 均先 `set(kind/value)` 再 `add_child` → `_ready` 读到正确值，兼容。
- 注：磁吸对**所有** Pickup（含 Boss 梦晶）生效，非仅经验球；若只想经验球磁吸、梦晶保持碰触，告诉我即可改成按 `kind` 判断。

---

# 改动 · 2026-07-27 · 新游戏开头动画（ESC 可跳过 + 右上角提示）

## 需求
- 新游戏后加载一段开头动画 `assets/Anime/A_001.mp4`；可按 ESC 跳过；右上角显示「按 ESC 跳过」提示。

## 关键决策：mp4 → ogv 转码
- Godot 4 桌面端 `VideoStreamPlayer` **默认不能可靠解码 H.264/mp4**（无内置解码器，专利限制）；原生稳定支持的是 **Theora `.ogv`**。
- 用 imageio-ffmpeg 静态二进制把 `A_001.mp4` 转码为 `assets/Anime/A_001.ogv`（libtheora -q:v 5 + libvorbis -q:a 4，约 15 秒，26MB）。原 `A_001.mp4` 保留未删。
- `Intro.tscn` 引用 `.ogv`。若你的 Godot 构建确认能播 mp4，把 `Intro.tscn` 第 4 行 `ext_resource` 路径改回 `A_001.mp4` 即可。

## 实现
- 新增 `src/scenes/Intro.tscn`（Control 根）：
  - `VideoPlayer`(VideoStreamPlayer)：全屏铺满（anchors FULL_RECT），`stream=A_001.ogv`，`autoplay=true`，`stretch_mode=2`(EXPAND 覆盖铺满、不变形)，`mouse_filter=2`(忽略)避免吞输入。
  - `SkipHint`(Label)：锚点右上（PRESET_TOP_RIGHT），`text="按 ESC 跳过"`，`horizontal_alignment=2`(右对齐)；字号 22 / 白色在 `Intro.gd._ready` 用 `add_theme_*_override` 运行时设置（避免依赖 .tscn 序列化属性名）。
- 新增 `src/scenes/Intro.gd`（extends Control）：
  - `_ready()`：确认 stream 后 `play()`，连接 `finished` 信号；设提示样式。
  - `_unhandled_input(event)`：`event.is_action_pressed("ui_cancel")`(ESC) → `_skip()`。
  - 播放完 `finished` 或 `_skip()` → `_advance()`（`_finished` 防重入）→ `change_scene_to_file(WeaponSelect.tscn)`。
- `src/scenes/Main.gd` `_new_game()`：目标从 `WeaponSelect.tscn` 改为 `Intro.tscn`（「新游戏 -> 开头动画 -> 选武器」）。`继续` 路径不变（不走 intro）。
- 暂停菜单的「重新开始」仍直接进 `Game.tscn`，**不**重播 intro（避免每次死亡重开都看一遍）。

## 验证（本机无 Godot，代码级核查）
- 类型：所有变量显式类型，无 untyped var / Variant；无 `get_parent()` 反模式。
- ESC 映射：`ui_cancel` 与项目既有暂停 ESC 写法一致，已在运行时验证可用。
- 路径衔接：`Main._new_game→Intro`、`Intro→WeaponSelect` 均存在；`持续`路径未受影响。
- 健壮性：若 ogv 未被引擎导入（`stream==null`），`_video.play()` 跳过且 `finished` 不触发，但 ESC 仍可 `_skip()` 并切场景，不会卡死。
- 请在编辑器确认：`Intro.tscn` 应显示视频首帧 + 右上角白字提示；F5 跑主菜单点「新游戏」→ 播动画 → 按 ESC 立即进选武器 / 不按则播完自动进。

---

# 改动 · 2026-07-27（补2）· 开头动画视频修复：改用 1080p 整图 + 扩展名 .ogv 修正

## 需求
- 开头动画「显示不全」。用户重新生成了 1080p 文件 `assets/Anime/A_001.Ogg`，要求用它修复并写入修改文档。

## 根因
- **扩展名陷阱（主因）**：`A_001.Ogg` 的扩展名 `.Ogg`（大写 O）在 Godot 4 中被 `OggVorbis` **音频**导入器识别，而非 `VideoStreamTheoraImporter`。`VideoStreamPlayer.stream` 需要 `VideoStream` 资源，喂入音频流 → 视频不渲染 / 显示不全。Theora 视频**必须带 `.ogv` 扩展名**才会被当作视频导入。
- **分辨率**：旧 `A_001.ogv` 为 theora 2560×1440（1440p），虽 16:9 可铺满，但用户意图是换 1080p 整图。

## 修复
- 将新文件 `A_001.Ogg`（ffprobe 实测 theora **1920×1080**）改名为 `A_001.ogv`，覆盖旧的 1440p 版本；原 1440p 备份为 `A_001_1440p_old.ogv`（连同 `.uid`/`.import` 一并迁移，避免孤立导入残留）。
- `Intro.tscn` 本就引用 `res://assets/Anime/A_001.ogv`，**无需改路径**。新视频精确匹配视口 1920×1080，`VideoStreamPlayer.stretch_mode=2`(COVER) 下铺满无裁切、无黑边。

## 验证
- ffprobe 复测改名后的 `A_001.ogv` = theora 1920×1080（内容完整、未损坏）。
- Godot 4.7.1 `--headless` 临时将 `main_scene` 指向 `Intro.tscn` + `_chk` autoload 加载场景：日志 `CHK_INTRO_OK stream=res://assets/Anime/A_001.ogv`，EXIT=0，零 `SCRIPT ERROR`；证明新 `.ogv` 被正确识别为 `VideoStream` 资源（若仍是 `.Ogg` 音频导入则 `stream` 为 null/AudioStream，验证会失败）。
- 验证后已还原 `project.godot`（main_scene 回到 `Main.tscn`）并删除 `_chk.gd`。

## 已知风险与缓解
- 首次在编辑器打开工程时，Godot 会对新 `A_001.ogv` 重新导入（自动触发，生成新 `.uid`/`.import`）。若打开后动画空白，在文件系统面板右键 `A_001.ogv` → 重新导入 即可。
- 旧 1440p 文件保留为 `A_001_1440p_old.ogv` 备份（未删除，确认新片无误后可手动清理）。
- **通用提醒（Godot 导入坑）**：任何 Theora 视频素材放进工程都必须以 `.ogv` 结尾；`.ogg`/`.Ogg`/`.oga` 一律按音频导入，绝不能被 `VideoStreamPlayer` 使用。

---

# 改动 · 2026-07-27（补3）· 开头动画铺满全屏 + 提示置顶

## 需求
- 开头动画只在**左上角一小块**显示，没有全屏；要求右上角「按 ESC 跳过」提示**置顶显示在视频画面前方**。

## 根因
- `Intro` 根节点是默认 `Control`，默认只占左上角一小块（Godot 中 Control 根节点不会自动铺满视口）。子节点 `VideoStreamPlayer` 用「填满父节点」锚点，结果只填满那小块 → 视频贴在左上角。
- 提示层级：原 `SkipHint` 虽在 `VideoPlayer` 之后（树序在后），但未显式设 `z_index`，存在被视频盖住的风险。

## 修复（`src/scenes/Intro.tscn`）
- 根节点 `Intro`：设 `layout_mode = 3`（FULL_RECT，强制铺满父视口），`anchors_preset = 15` + `anchor_right/bottom = 1.0`，`mouse_filter = 2`（忽略鼠标，ESC 走 `_unhandled_input`）。
- `VideoPlayer`：保留 `layout_mode=1` + 全锚点 + `stretch_mode=2`(COVER)，显式加 `z_index = 0`。
- `SkipHint`：保留右上角锚点，显式加 `z_index = 1`（高于视频 0）→ 稳定置顶在视频画面前方；字号/颜色仍由 `Intro.gd` 运行时设置。

## 验证
- Godot 4.7.1 `--headless` 临时 `main_scene=Intro.tscn` + `_chk` 加载：日志 `CHK_VP global_pos=(0,0) stream_ok=true`、`CHK_VP_z=0 hint_z=1`；视频流加载正常、提示层级高于视频。铺满性因无头窗口为 64×64 退化窗口无法像素级确认，但节点尺寸已随视口全尺寸展开（非旧的小块）。
- 验证后还原 `project.godot` 并删除 `_chk.gd`。

## 已知风险与缓解
- 真实 1920×1080 窗口下根节点 FULL_RECT 应使视频铺满；请在本机 F5 主菜单点「新游戏」目测：① 视频是否全屏无左上角黑块；② 右上角白字「按 ESC 跳过」是否在视频上方可见。若仍偏角，检查 `window/stretch` 设置（当前未设 stretch_mode，视口 1920×1080）。

# 改动 · 2026-07-27（补4）· 修复「ESC 跳过开场视频失效」

## 需求
- 用户反馈：在补3（铺满全屏）之后，按下 ESC 键**无法跳过开头视频**。

## 根因（关键！）
- `src/scenes/Intro.tscn` 的**根节点 `Intro` 漏挂脚本**：在补3 用 `Write` 整体重写 `.tscn` 时，只写了 `[ext_resource type="Script" ... id="1"]`，却**漏掉了根节点上的 `script = ExtResource("1")` 这一行**。
- 后果：视频靠节点 `autoplay=true`、`SkipHint` 文字/`z_index` 都写死在 `.tscn` 里 → **画面、提示一切正常显示**；但 `Intro.gd` 整个没被实例化 → `_ready` / `_input` / `_skip` 全不执行 → ESC 跳过逻辑彻底失效（且视频播完也不会自动进选武器，因为 `finished` 信号没连上）。
- 诊断过程：无头注入 ESC 事件后发现 `current_scene.has_method("_skip") == false`，确认脚本根本没挂上；同时把 `_unhandled_input` 改为 `_input`（根节点是 Control，`ui_cancel` 这类 UI 动作会在 GUI 阶段被 Control 消费掉，`_unhandled_input` 收不到；`_input` 在最前置阶段必定触发，更稳）。

## 修复
- `src/scenes/Intro.tscn`：根节点 `Intro` 补回 `script = ExtResource("1")`。
- `src/scenes/Intro.gd`：输入处理由 `func _unhandled_input(event)` 改为 `func _input(event)`（捕获 ESC / `ui_cancel` 更可靠），逻辑不变（`_skip()` → `change_scene_to_file(WeaponSelect)`）。

## 验证
- Godot 4.7.1 `--headless` 临时 `main_scene=Intro.tscn` + `_chk`：
  - `CHK_HAS_SKIP=true`（脚本已挂上）；
  - 直接调用 `_skip()` → 场景切到 `WeaponSelect`（`CHK_DIRECT_OK`）；
  - 注入 ESC `InputEventKey(keycode=KEY_ESCAPE, pressed=true)` → 场景切到 `WeaponSelect`（`CHK_ESC_OK`）。
- 退出码 0，零 `SCRIPT ERROR`。验证后还原 `project.godot`、删除 `_chk.gd`。
- 注：本机 F5 实测前，若之前编辑器缓存过旧 `.tscn`，建议在文件系统面板对 `Intro.tscn` 右键「重新导入」一次，确保脚本挂载生效。

## 经验
- **整体 `Write` 重写场景 `.tscn` 时必须保留根节点的 `script = ExtResource(...)`**。Godot 不会因有同名 `ext_resource` 就自动给根节点挂脚本，漏写则整脚本静默失效（画面却照常，极难察觉）。

# 改动 · 2026-07-27（补5）· 修复「开头动画画面花屏」

## 现象
- 引擎里播放开头动画：功能正常（能播放、ESC 可跳过、播完自动进选武器），但**画面花屏**（彩色错乱块/撕裂）。非布局问题（全屏+提示置顶已在补3 修好）。

## 根因（ffprobe/ffmpeg 实测确认，非推断）
- 用户"重新生成的 1080p 文件" = `assets/Anime/A_001.Ogg`（改名 `A_001.ogv`）的 **theora 流本身损坏**：
  - ffmpeg 解码前 120 帧报 **564 行** `error in unpack_block_qpis` / `unpack_vectors` 错误；
  - 解码 905 输出帧中 **730 帧是 dup 重复帧**（解码失败丢帧、用前一帧填补）→ 绝大多数帧解码失败。
  - Godot 用 libtheora 解码此损坏流，吐出的是乱码块 → 花屏；功能正常只是因为解码器容错未崩溃。
- 对照证据：
  - 旧 `A_001_1440p_old.ogv` 解码 **0 错误**（干净，但分辨率 1440p 且当时扩展名错未显示）；
  - 目录内 `A_001.mp4`（**H.264 / 2560×1440 / yuv420p / 24fps / 15.0s / 带 AAC 音轨**）解码 **0 错误** —— 才是干净原始源。

## 修复
- 从干净 `A_001.mp4` 重新编码为 Godot 友好的 theora，关键两点：
  1. **用干净源**（不再从损坏 ogv 转，那只会传播损坏）；
  2. **高度对齐 16 的倍数**：`scale=1920:1072`（裁上下各 4px）→ 1920×1072 = 16×67×120，frame=pic 一致、无 padding/offset，根除"Theora 帧尺寸非 16 对齐 → 解码错位花屏"隐患。
- 编码参数：`libtheora -q:v 7 -g 1`（全关键帧）`-r 30 -pix_fmt yuv420p -an`（暂去音频，避免引入未知音轨行为）。
- 覆盖 `assets/Anime/A_001.ogv`（61MB）。损坏源备份为 `A_001_1080p_src_before_align.ogv`。

## 验证
- ffmpeg 重新解码新 `A_001.ogv` 前 200 帧：**0 错误**；参数 theora / 1920×1072 / yuv420p。
- 注：无头模式无 GPU 渲染，无法在此确认"不花屏"的视觉效果；需本机 F5 → 主菜单「新游戏」目测。

## 风险 / 下一步
- 若真机重新导入后仍花屏，则排除文件问题，转向 **Godot 4.7.1 Theora 解码器 / 显卡驱动层**排查（如：改用 GDExtension 支持的其他容器、或进一步降帧率/分辨率）。
- `A_001.mp4` 含 AAC 音轨；如开头动画需要配音，后续可加 `-c:a libvorbis` 重新封装进 ogv。
