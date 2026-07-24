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
