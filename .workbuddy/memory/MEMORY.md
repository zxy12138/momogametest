# 项目长期记忆 · 《梦境逐影》Godot 4.7.1

## 架构
- 入口：`project.godot` → `Main.tscn` → `WeaponSelect.tscn` → `Game.tscn`（主玩法）。
- Autoload：`GameManager`（全局状态/成长/暴击/存档）、`SaveManager`（`user://save.json`，每层 Boss 自动存）、`MapData`（房间状态机）。
- 数据驱动：`src/data/` 下 `Weapons/Enemies/LevelData.gd` 全静态，通用 `Enemy`/`Boss`/`Weapon` 读取。
- 玩家（大鹏/dapeng）：Godot 4 做食梦貘主题 2.5D 8 向动作射击，给虚拟主播「弥绘」庆生。当前阶段=占位素材验证完整玩法，美术后期替换。

## Godot 4.x 关键坑（已踩，务必遵守）
- **严格模式把"变量类型从 Variant 推断"当硬错误**：`var x := variant_call()` 必须显式标类型（`:int/:float/:bool/:Array/:Dictionary`），否则整脚本解析失败、`class_name` 不注册，拖垮下游 `Could not find type X`。
- **循环 `class_name` 强转连锁崩溃**：跨类引用一律用引擎基类 `as Node2D/Area2D/Node` + `.call()/.set()` 打破循环；仅保留 `Boss extends Enemy`。
- **无头模式 `extends Enemy`（按类名）找不到基类**：改用 `extends "res://src/enemies/Enemy.gd"`；并把 `const BOSS = preload(...)` 改运行期 `load()` 解除启动期加载链。
- **Autoload 不能用 `Engine.get_singleton("Name")` 取**：直接写全局名 `GameManager`。
- **`CanvasLayer` 非 CanvasItem**：子节点取屏幕尺寸用 `get_window().get_visible_rect().size`，别用 `get_viewport_rect()`。**任何动态 UI/遮罩必须挂 CanvasLayer（屏幕空间）**，否则被相机 zoom+跟随推到屏幕外（现象：面板看不见、按钮没反应、淡入淡出只在角落露黑块）。
- `snappedf` 已合并进 `snapped(value, step)`。
- `create_timer()` 返回 `SceneTreeTimer`（RefCounted），不能 `add_child`，用 `get_tree().create_timer(2.5).timeout.connect(cb)`。
- 字典缺键运行期崩：用 `.get("key", default)` 防御取值（Boss 数据缺 `speed` 键尤其注意）。
- **`AnimatedSprite2D.frames` → `sprite_frames`**（3→4 改名）；`Sprite2D` 无 `play()`/`sprite_frames`，动画节点须 `AnimatedSprite2D`。
- **`Camera2D.zoom` 是 `Vector2`**：设 `Vector2(2,2)`，非 `2.0`。
- **1080p 窗口标准做法**：`viewport_width/height=1920/1080` + `Camera2D.zoom=Vector2(2,2)`，使可见世界仍为 960×540。只拉视口不调相机→画面缩 2 倍。
- **`Camera2D.z_index` 范围 `[-4096,4096]`**；Y 轴排序地板/背景须设 -4000（在实体 y∈[-250,250] 之下），否则实体被地板盖住「上移消失」。
- 子节点贴图须在 `add_child` 之前 `set` 好（否则 `_ready` 读空→隐形）。
- `load_tex` 用 `load()` 而非 `ResourceLoader.exists()+load()`（`exists` 不规范化 `..` 路径）。
- 敌人弹道贴图统一用 `res://assets/weapons/projectiles/`（勿用 `../weapons/...` 相对 Boss 目录，会多退一级）。
- 输入键码：`ui_cancel`=ESC 内置；`dev` 动作绑定 **F12=`4194315`**（非 F2）。字母键用 `physical_keycode`。
- 编辑重复定义函数坑：替换前先 Read 确认目标函数唯一，避免整段塞入造成 `Parse Error: Function X ...`。
- **编辑器看不到场景/精灵 = 运行时生成 + 非 @tool**：本作场景（房间/墙/门/敌/Boss）全在代码 `_ready`/`_build_floor` 里 `add_child`，`.tscn` 仅骨架；且全仓原无 `@tool` 脚本，故 `_ready` 不跑、精灵帧为空→编辑器空白。要让某节点在编辑器可见：给其脚本加 `@tool`，并**所有游戏逻辑用 `Engine.is_editor_hint()` 挡在编辑器外**（否则编辑器里会刷怪/发射/读运行期状态）。已对 `Player.gd` 加 `@tool`（仅 `_ready` 构建 sprite_frames + 播 idle；`_physics_process` 顶部 `if Engine.is_editor_hint(): return`）。代价：世界/房间仍只在运行时生成，需 `@tool` RoomManager/Enemy 才能编辑器预览（更侵入，按需再做）。
- **`GameManager.input_locked` 是输入总闸**（`Player._physics_process` 一见到 true 就 `velocity=0; return`，不能动也不能打）。凡是把它设 true 的路径（ESC 暂停 `_open_pause`、死亡 `on_player_died`、生日 `_birthday`、驿站、地图、词条）回到可玩 `Game` 场景时都必须归位。**最稳的修法在 `Game._ready` 开头 `GameManager.input_locked = false`**（覆盖 ESC→重开 / 死亡→重试 / 死亡→回菜单→新游戏 / 生日→回游戏）；`reset_run` 也要归位。切勿只在某条路径补，否则兄弟路径照样卡死。

## 无头测试注意
- headless 下 `E` 级错误非致命（只中断当前方法），只看退出码 0 会**漏检** bug。正确验证：进战斗房跑动画逻辑后 grep 日志 `Invalid access`/`SCRIPT ERROR`。
- 临时进玩法：把 `project.godot` 的 `run/main_scene` 临时指 `Game.tscn`，挂 `_chk.gd`（reset_run→transition_to→等→quit），跑完还原。

## 合并地图（三层合一）
- 一张大图显示全 3 层（18 房间），并排左/中/右三栏，跨层连线 boss(r6)→下一层 r1；全部房间初始可见可点。
- `MapData.merged`（`"f{层}-{rid}"`→`{floor,rid,type,gx,gy,state,links}`）；`build_merged()` 三趟：建节点→层内连线→跨层连线（须所有节点建好后再加，否则丢连线）。
- `Game.transition_to` 解析含 `"-"` 键→拆层数→`_switch_floor`→走原逐层逻辑；`_go_next_layer` 不动。
- `MapUI._draw_map` 遍历 `merged`，连线遍历 `links`，点击 `transition_to(合并键)`。

## 美术资产管线（v3.0 清单驱动）
- 权威清单：`DevelopmentRequirements/梦境逐影_美术素材清单_最终版.xlsx`（v3.0，Sheet5 音频按约定跳过）。关键尺寸：角色/普通怪/精英怪=**130×250**；Boss=**260×500**。
- 命名铁律：`{编号}_{英文snake_case}.png`（如 `A-001_miai_idle.png`）。权威数据源 `tools/v3_assets.py`；生成器 `tools/gen_assets.py`（手写 zlib，无第三方库）生成 220 占位并写 `assets/GENERATED_PLACEHOLDERS.json`；迁移 `tools/migrate_code.py`（幂等）。
- 维度回填：`Enemy/Player` 的 `fw/fh` 须=精灵表帧尺寸（怪 130/250、Boss 260/500），`fi`=idle/`fa`=attack 帧。
- 替换：同名同尺寸 PNG 覆盖占位（帧数须一致）。
- **场景构建=v4.0 预制整图**：每关美术预制整图（一房一图，含墙/地板/家具/灯光烘焙）+ 空气墙 `InvisibleWall`（`StaticBody2D`+`CollisionShape2D` 零贴图）+ 门 `Door`（开/关帧切 + Area2D 触发）。`RoomManager._build_floor` 读 `_data.scene_img` 作背景（`z_index=-4000`）并跳过通用瓦片墙；`LevelData` 第一层 `r2/r3` 已临时挂 `scene_img`（TEST，待正式流程接管）。`Game.gd` dev 标签 F2→F12。
- 角色缩放：玩家 `_sprite.scale`=**0.28**，敌人=**0.45**（仅视觉，碰撞不变）。
- 旧 v2.0 占位 135 张已迁至项目外 `_trash_v2/`（可逆），safe-delete 阈值耗尽未永久删。
- `audio/bgm`/`audio/sfx` 预留，`LevelData.BGM` 引 `bgm_1..3.ogg` 缺失→静音。

## 本会话已修 BUG（2026-07-26）
- **切场景右下角黑屏**：`Game.tscn` 的 `Fade` 原是 `Game`(Node2D) 下的 `ColorRect`（世界空间），被相机 zoom=2 推到屏幕外，只在右下角露出一块黑（淡入淡出时可见）。改法：把 `Fade` 改为 `CanvasLayer`(layer=20) 内含全屏 `ColorRect`，`Game.gd` 用 `@onready _fade_rect:=$Fade/Rect` 并设 `size=get_window().get_visible_rect().size`。见下方 2026-07-26 日志。

## 编辑器可见性（@tool 预览，2026-07-26 加）
- 本游戏是「数据驱动 + 运行时生成」：`.tscn` 只放骨架，房间/墙/门/敌人/Boss 由 `RoomManager.setup()` 与 `Game._ready→transition_to→_swap` 在运行时 `add_child`。故默认编辑器里近乎全空。
- 让编辑器可见的套路：给 `Game`/`RoomManager`/`Enemy`/`Boss` 加 `@tool`，在 `_ready` 用 `Engine.is_editor_hint()` 走「预览 build」分支（只建视觉、跳过输入/物理/计时器/信号），运行期逻辑不变。
- 防重复 build 的关键：`Game._ready` 编辑器分支 `return` 早退；`RoomManager._ready` 仅当 `is_editor_hint() and _rid=="" and get_parent()==null`（独立打开 Room.tscn）才自动 build，被 Game 嵌套时不自动 build；`Enemy/Boss` 因 `setup()` 在 `add_child` 前调用、`_eid` 已非空，`_ready` 预览靠 `_eid==""` 跳过。
- `Enemy/Boss` 的 `_physics_process` 首行必须 `if Engine.is_editor_hint(): return`，否则 `@tool` 下编辑器里会跑 AI/弹幕。
- 玩家相机 `Camera2D.anchor_mode=1`(固定左上)会让房间偏角；预览里临时改 `0`(居中)仅改 live 节点、不写场景。
- 注意：预览节点是 `@tool` 运行时 `add_child`，标准模式下不写进 `.tscn`；但提醒用户**不要在预览存在时 Ctrl+S 保存 Game.tscn**，误保存则删掉凭空出现的 `Room` 节点即可。
