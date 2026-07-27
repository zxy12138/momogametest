# 项目长期记忆 · 《梦境逐影》Godot 4.7.1

## 架构
- 入口：`Main.tscn`→`Intro.tscn`→`WeaponSelect.tscn`→`Game.tscn`。`Main._new_game` 置 `prologue_pending` 走 Intro→开场序列。
- Autoload：`GameManager`(全局状态/成长/暴击/存档)、`SaveManager`(user://save.json, 每层 Boss 自动存)、`MapData`(房间状态机)。
- 数据驱动：`src/data/` 下 Weapons/Enemies/LevelData.gd 全静态；通用 Enemy/Boss/Weapon 读取。
- 玩家=食梦貘主题 2.5D 8 向动作射击，给 Vtuber「弥绘」庆生；当前占位素材验证玩法。

## Godot 4.x 关键坑（务必遵守）
- 严格模式：变量从 Variant 推断会解析失败，必须显式标类型(:int/:float/:Array/:Dictionary)。
- 循环 class_name 强转崩溃：跨类用 `as Node2D/Area2D/Node` + `.call()/.set()`；仅留 `Boss extends Enemy`。
- 无头 `extends Enemy`(按类名)找不到基类→改 `extends "res://src/enemies/Enemy.gd"`；`const BOSS=preload` 改运行期 `load`。
- Theora 视频必须 `.ogv`（.ogg/.Ogg 被当音频导入→视频不显示）；帧高须16对齐(用 1072 非 1080)；AI 导出 ogv 必 `ffmpeg -v error -i x.ogv -f null -` 数解码错误行，别只看 ffprobe。
- Autoload 用全局名 `GameManager`，别用 `Engine.get_singleton("Name")`。
- 动态 UI/遮罩必须挂 CanvasLayer(屏幕空间)，否则被相机 zoom+跟随推到屏外（黑块/面板看不见）。取屏幕尺寸用 `get_window().get_visible_rect().size` 非 `get_viewport_rect()`。
- `create_timer()` 返回 SceneTreeTimer 不能 add_child；`snappedf`→`snapped`；`AnimatedSprite2D.frames`→`sprite_frames`；`Camera2D.zoom` 是 Vector2；`Camera2D.z_index`∈[-4096,4096]，地板/背景须 -4000。
- 字典缺键用 `.get(k,default)`；子节点贴图须在 add_child 前 set；`load_tex` 用 `load()`。
- `dev` 动作绑 F12=4194315(非 F2)；字母键用 physical_keycode。编辑重复定义函数前先 Read 确认唯一。
- **整体 Write 重写 .tscn 必须保留根节点 `script = ExtResource("1")`**，否则脚本静默未挂载(画面正常但 _ready/_input 不执行)。诊断：`current_scene.has_method("方法")==false`。
- **`GameManager.input_locked` 是输入总闸**(`Player._physics_process` 见 true 即 velocity=0 return)。所有设 true 路径(ESC 暂停/死亡/生日/驿站/地图/词条)回到 Game 时必归位；最稳修法 Game._ready 开头 input_locked=false + reset_run 内归位。⚠️ 若运行期狂刷 `Invalid access to property or key 'input_locked' on Node (GameManager.gd)`：含义=**运行中的 Godot 进程手里那份 GameManager.gd 实例未绑定成员**(autoload 退化成裸 Node)，故 Game._ready 第49行 `GameManager.input_locked=false` 直接崩溃→房间构建/开场/相机设置全被掐断→**相机左上角是此崩溃的下游症状，不是相机代码问题**。判定：逐个通读 GameManager/SaveManager/MapData/_restart_test/Weapons/FloatingText 全部干净、`.godot`(uid_cache/global_script_class_cache/filesystem_cache) 与 `.uid` 均正常→**磁盘与缓存无损坏，错误纯属运行期陈旧脚本实例**。根治：**完全关闭 Godot 后**删除 `.godot`（运行中删会被进程用陈旧实例重建，无效）；若项目在 OneDrive/云同步盘，先暂停同步或挪到本地非同步目录，否则 `.godot` 被云同步回陈旧版→报错依旧。重开等导入完成后 F5，应零报错且角色居中。补8~补15 的相机改动都被这个上游故障拖累，相机在 补16 改为显式激活(`Player.tscn` `current=true` + `Player.gd _ready` 顶部 `make_current()` 且置于任何 GameManager 调用前解耦)，并给全部 `input_locked` 读写加 `_set_gm_locked/_is_gm_locked` 守卫(`"input_locked" in GameManager` 先判存在)消除刷屏；守卫使相机立即居中、游戏可跑便于验证。

## 合并地图(三层合一)
- `MapData.merged`(`"f{层}-{rid}"`→{floor,rid,type,gx,gy,state,links})；`build_merged()` 三趟：建节点→层内连线→跨层连线(须全建好再加)。`Game.transition_to` 含"-"键→拆层→`_switch_floor`。

## 美术资产管线(v3.0)
- 清单 `DevelopmentRequirements/梦境逐影_美术素材清单_最终版.xlsx`；尺寸：角色/普通怪/精英=130×250，Boss=260×500。命名 `{编号}_{snake_case}.png`。
- 场景构建 v4.0 预制整图：`RoomManager._build_floor` 读 `_data.scene_img` 作背景(z_index=-4000)。玩家 `_sprite.scale=0.28`，敌人=0.45。

## 编辑器可见性(@tool 预览)
- 本作 .tscn 仅骨架，房间/墙/门/敌/Boss 运行时 add_child；默认编辑器空。给 Game/RoomManager/Enemy/Boss + Player 加 @tool，_ready 用 `Engine.is_editor_hint()` 走预览分支(只建视觉、跳过物理/计时器)，运行期不变。
- 防重复 build：Game._ready 编辑器分支 return；RoomManager._ready 仅 `is_editor_hint() and _rid=="" and get_parent()==null` 才自 build；Enemy/Boss 靠 setup() 先于 add_child 调用(_eid 非空)跳过。
- Enemy/Boss 的 `_physics_process` 首行 `if Engine.is_editor_hint(): return`。
- **玩家相机（补17 确定性手动驱动，推翻补16 Camera2D 路线）**：本 Godot 4.7.1 中 Camera2D 的 `current=true` 声明式静默失效、`make_current()` 不接管视口、`enabled` 单相机也不自动激活——补6~补16 在 Camera2D 上打转全失败（补16 对 Player.tscn 的 current/enabled 编辑还因 old_string 不匹配静默未生效）。**最终正确解法（补17）= 不依赖 Camera2D**：`Player.tscn` 的 `Camera2D` 设 `enabled=false`；`Game.gd` 新增 `_update_camera()` 每帧直接写 `get_viewport().canvas_transform = Transform2D(_cam_zoom, center - _cam_zoom * player.global_position)`（center=视口尺寸/2），数学上保证玩家居中，与 stretch_mode=canvas_items 兼容。在 `_physics_process` 顶部（早于开场/锁输入提前 return）调用，故开场/锁输入期间也居中。此方案与 GameManager 是否加载无关——即使 `input_locked` 守卫兜底、GameManager 陈旧，玩家也稳定居中可移动。开局无放大（`_cam_zoom` 默认 1.0）；受击抖动原 `Player.shake()` tween 相机 offset 现已无效（Camera2D disabled），需抖动就给 `_update_camera` 加偏移量。编辑器预览仍 `cam.enabled=false` + `_focus_editor_viewport` 手动聚焦（运行期隔离）。
- **矩阵顺序坑（仅编辑器聚焦用）**：`Transform2D().scaled(s).translated(t)` 是 `Scale*Translate`，平移会被乘 `s`（错）；必须 `.translated(t).scaled(s)` 才是 `Translate*Scale`（正确居中）。仅 `_focus_editor_viewport` 用，运行期已不手写 transform。
- **编辑器 2D 视口默认不跟随 @tool 动态 Camera2D**→`_editor_build_preview` 末尾聚焦：取编辑器接口必须 `Engine.get_singleton("EditorInterface")`（**不要 `get_node("/root/EditorInterface")`**，Godot4 下该路径取不到→返回 null→整段静默失效，等于没修）；`EditorInterface` 非 GDScript 通用已知类型，故 `ei.call("get_editor_viewport_2d") as SubViewport` + `set_canvas_transform`(缩放0.6 平移到玩家中心)聚焦。开 `Game.tscn` 直接看到角色居中。

## 场景内武器拾取/开场序列
- 开场序列（补17 去掉放大）：`Game._play_prologue` 锁输入→**不再 tween cam.zoom**(无拉近)→0.5s 后对话框(_ui_layer 屏幕空间)→3.4s 或 ESC(ui_cancel)跳过→`_end_prologue` 移除对话框、生成3把起始武器(Weapons.STARTERS)。相机全程由 `_update_camera()` 手动居中（见相机条目）。
- 起始武器 spawn 时机：新游戏仅 `_end_prologue` spawn；非序列路径 `_swap` 末尾 `if rid=="r1" and not prologue_pending: _spawn_starter_weapons()`；`weapon_id` 跳过已装备。
- 地面武器 `WeaponPickup`(Node2D)：weapon_id 导出+图标+浮动；`just_dropped()`(0.6s 免疫防交换死循环)；拾取/交换 F(interact=70)，旧武器掉地免疫。邻近64px 检测，提示框挂 `_ui_layer`。

## 已修连带坑
- `GameManager.get_weapon()` 无武器返回 `{}`(非 null，否则 "Trying to return Nil from Dictionary")；所有调用方 `w.is_empty()` 判无武器。
- headless 不复扫 global_script_class_cache：新建 class_name 后别用全局类型(解析期 "Could not find type Xxx")，用 `preload`+`Node2D`+`call/get/set`。
- 零依赖武器图标：`tools/gen_weapon_icons.py`(PIL+managed venv) 重绘 staff/sword/scythe 96×96。

## 无头测试注意
- headless 下 E 级错误非致命，只看退出码0 会漏检；跑完 grep 日志 `Invalid access`/`SCRIPT ERROR`。
