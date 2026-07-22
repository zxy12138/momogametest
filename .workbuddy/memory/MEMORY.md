# 项目长期记忆 · 《梦境逐影》Godot 4.7.1

## 架构
- 入口：`project.godot` → `Main.tscn`（主菜单）→ `WeaponSelect.tscn`（选武器）→ `Game.tscn`（主玩法）。
- Autoload 单例：`GameManager`（全局状态/属性成长/暴击/存档/占位切片）、`SaveManager`（`user://save.json`，击败每层 Boss 自动存）、`MapData`（房间状态机）。
- 数据驱动：`src/data/` 下 `Weapons.gd`/`Enemies.gd`/`LevelData.gd` 全静态数据，通用 `Enemy`/`Boss`/`Weapon` 脚本读取。

## Godot 4.x 关键坑（已踩过）
- **`FloatingText.tscn` 必须存在**：`GameManager.gd` 用 `preload` 加载它，缺文件则项目启动即崩。
- **`CanvasLayer` 不是 CanvasItem**：不能用 `get_viewport_rect()`；在 MapUI 中改用 `get_window().get_visible_rect()`。
- `snappedf` 在 4.x 已合并进 `snapped(value, step)`，不要再写 `snappedf`。
- 场景间的预加载（`preload`/`change_scene_to_file`）路径必须真实存在，否则引擎加载失败——提交前用脚本核对所有 `res://` 引用。
- **严格模式把"变量类型从 Variant 推断"当硬错误**：所有 `var x := some_variant_returning_call()` 必须显式标注类型（`:int/:float/:bool/:Array/:Dictionary`），否则脚本整体解析失败、其 `class_name` 不注册，进而引发下游全项目 `Could not find type X`。这是本项目大量报错的根因。
- **循环 `class_name` 强转会连锁拖垮所有参与类型**：`Player↔Weapon↔Enemy↔Projectile`、`Boss→Enemy` 之间用 `as Player/Enemy/Boss/Weapon/Projectile/Pickup/RoomManager` 制造循环依赖，使循环内所有类型解析期找不到。改法：跨类引用一律用引擎基类 `as Node2D/Area2D/Node` + `.call("method",args)`/`.set("prop",val)` 打破循环，仅保留单向 `Boss extends Enemy`。
- **无头模式下 `extends Enemy`（按类名）找不到基类**：`class_name` 全局注册表在无头下不登记。改用**按脚本路径继承** `extends "res://src/enemies/Enemy.gd"` 绕开注册表；同时把 `const BOSS = preload(...)` 改为运行期 `load()`，解除启动期加载链。
- **Autoload 单例不能用 `Engine.get_singleton("Name")` 取**：autoload 是全局名而非 singleton 注册，应直接在脚本里写全局名 `GameManager`。`Engine.get_singleton` 取不到会报 "Failed to retrieve non-existent singleton"。
- **`create_timer()` 返回 `SceneTreeTimer`（RefCounted，非 Node）**：不能 `add_child`，直接 `get_tree().create_timer(2.5).timeout.connect(cb)` 即可。
- **字典缺键访问会运行期崩**：对数据字典用 `.get("key", default)` 而非 `["key"]` 直接索引（尤其基类 Enemy 被 Boss 继承、Boss 数据缺 `speed` 键时），防御性取值。
- **`AnimatedSprite2D.frames` → `sprite_frames`（Godot 3→4 改名坑）**：Godot 3 叫 `frames`，Godot 4 改名为 `sprite_frames`（同理 `AnimatedSprite`）。访问/赋值 `.frames` 会运行期报 `Invalid access to property or key 'frames' on a base object of type 'AnimatedSprite2D'`。本项目 5 处（GameManager/Player/Enemy/Boss 的精灵帧赋值与 `.has_animation` 读取）统一改 `.sprite_frames`。
- **`Sprite2D` 无 `play()`/`sprite_frames`**：只有 `AnimatedSprite2D` 才有动画播放与 `sprite_frames`，场景里放动画节点要确认类型是 `AnimatedSprite2D`。
- **`Camera2D.zoom` 在 Godot 4 是 `Vector2`**（Godot 3 是 float）。设 `zoom = Vector2(2, 2)`，别写 `zoom = 2.0`（会类型错）。
- **960×540 设计稿升级 1080p 窗口的标准做法**：`window/size/viewport_width=1920`/`viewport_height=1080` 把视口（即窗口）拉到 1080p；同时把 `Camera2D.zoom` 设为 `Vector2(2,2)`，让 1080p 下看到的世界范围与原来 960×540 完全一致（只是更清晰、窗口更大）。只拉视口不调相机，画面会"缩小 2 倍"看到 2 倍世界范围。
- **`Camera2D.z_index` 合法范围 `[-4096, 4096]`**：别写 -10000 之类会报 `Tried to set Z index to an invalid value`。用 `int(global_position.y)` 做 Y 轴排序时，**地板/背景必须设到很负的 z（如 -4000）**，否则 y<0 的实体 z<0 会被默认 z=0 的地板矩形盖住→「上移消失、下移重现」。-4000 仍在所有实体 y∈[-250,250] 之下，永久最底层。
- **子节点贴图必须在 `add_child` 之前 `set` 好**：`add_child` 会立刻触发 `_ready`，若 `_ready` 里才读 `texture_path` 等属性取贴图，而属性在 `add_child` 之后才 `set`，则 `_ready` 读到空值→精灵隐形。本项目 `Weapon._spawn_proj` 曾把 `texture_path` 设在 `_spawn()`（含 `add_child`）之后，导致远程弹道全隐形。
- **`load_tex` 用 `load()` 而非 `ResourceLoader.exists()+load()`**：`exists()` 不规范化 `..` 路径，会让 `res://.../../x.png` 类路径误判为「资源不存在」返回 null→贴图缺失。直接 `load(path)` 会规范化 `..` 并优雅返回 null。
- **敌人弹道贴图路径坑**：`Enemies.gd` 的 `B+"../weapons/projectiles/..."`（`B="res://assets/sprites/bosses/"`）实际解析成 `res://assets/sprites/weapons/...`（多退了一级目录，错的）。统一用 `res://assets/weapons/projectiles/` 绝对路径，与玩家 `Weapons.gd` 的 `PROJ` 常量一致。
- **`project.godot` 自定义输入动作的键码**：`ui_cancel` 是 Godot 内置、ESC 自动绑定，抓 ESC 直接用 `event.is_action_pressed("ui_cancel")` 即可（无需改 input map）；新增字母键用 `physical_keycode`（F=70，字母 keycode=ASCII）；⚠️ **`dev` 动作键码**：`4194320` 是 `KEY_KP_0`（小键盘 0），不是 F2；F2=`4194305`（`KEY_F1=4194304`，+1），**F12=`4194315`（+11）**。开发者模式动作 `dev` 的 `keycode`/`physical_keycode` 现绑定 **F12=`4194315`**（应大鹏要求由 F2 改 F12）。
- **编辑会重复定义函数的坑**：对已有同名函数定义的脚本（如 `MapUI.gd` 的 `_close()`），若替换字符串把「目标函数 + 另一份同名函数」整段塞入，会造成**重复函数定义** → `Parse Error: Function "X" has the same name as a previously declared function`，整脚本加载失败（按 M 看地图会崩）。编辑前先 Read 确认目标函数唯一，替换锚点只覆盖一次性出现的片段。

## 无头测试注意（验证真实性）
- headless 运行期 **`E` 级错误是非致命的**（只中断当前方法、游戏继续），所以只看 `RT_OK`/退出码 0 会**漏检**这类 bug（如 `.frames` 改名坑曾因此逃过）。
- 正确验证：进战斗房让玩家/敌人每帧跑动画逻辑，再 **grep 日志里的 `Invalid access` / `E ` 前缀 / `SCRIPT ERROR`**，而非仅看退出码。
- 临时测试 autoload 进玩法：把 `project.godot` 的 `run/main_scene` 临时指向 `Game.tscn`，挂一个 `_chk.gd`（await→`GameManager.reset_run("staff")`→`current_scene.transition_to("r2", true)`→等数秒→打印标记→`quit`），跑完还原。
- **动态 UI 必须挂 CanvasLayer（屏幕空间）**：游戏主场景若含 `Camera2D`(zoom≠1 或跟随)，直接 `add_child` 到场景根/世界节点的 Control 面板会按**世界坐标**渲染；用 `get_viewport_rect().size/2` 等"屏幕中心"定位会被相机变换推到屏幕外（现象：面板看不见、按钮没反应）。一律新建专用 `CanvasLayer`(设 `layer` 高于 HUD/MapUI）并把动态面板/提示都 `add_child` 到它；定位用 `get_window().get_visible_rect()` 取屏幕坐标。HUD/MapUI 本就是 CanvasLayer 故正常。

## 合并地图（三层合一）
- 需求：地图从"逐层切换"改为**一张大图显示全部 3 层**（18 房间），3 层并排成左/中/右三栏，跨层连线为每层 boss(r6)→下一层 start(r1)；全部房间一开始可见且可点（"全可见"，类型也显示，等同常驻 dev 全开）；正常逐层玩法（走路/打怪/打 Boss 进门进下一层 `_go_next_layer`）不动。
- 实现（仅改 `MapData.gd`/`Game.gd`/`MapUI.gd`）：
  - `MapData.merged`（`"f{层}-{rid}"` → `{floor,rid,type,gx,gy,state,links}`）；`build_merged()` **三趟**：趟1 建所有节点（gx=栏起点+pos.x*栏宽，栏宽=1/层数）、趟2 层内连线、趟3 跨层连线（boss→下一层 r1）。⚠️ 跨层连线必须在"所有节点建好之后"加，否则 `_merged_add_link` 因目标键不存在提前 return（曾踩此坑：单循环内加跨层连线时下一层节点未建，连线丢失）。
  - `Game.transition_to` 解析含 `"-"` 的合并键 → 拆出层数 → 不等当前层则 `_switch_floor(target, room)`（设 `GameManager.layer_index`+`load_layer`+标 CURRENT+刷新地图），再走原逐层逻辑。`_go_next_layer` 不动。
  - `MapUI._draw_map` 遍历 `MapData.merged`，`gx/gy∈[0,1]` 映射画布，连线遍历 `links`，按钮文本=合并键+类型（全 VISITED→全显示类型），点击 `transition_to(合并键)`。
- 验证：无头挂 `_diag_map.gd` autoload（临时入口切 `Game.tscn`），实测 `merged.size()=18`、`f1-r6.links` 含 `f2-r1`、点 `f2-r3` 后 `GameManager.layer_index` 由 1→2，零 `SCRIPT ERROR`。

## 美术一键替换约定
- 全部美术为同名占位 PNG，路径严格对应 `assets/` 结构（sprites/weapons/fx/ui/tiles/audio）。
- 替换方式：用同名同尺寸 PNG 覆盖，`assets/GENERATED_PLACEHOLDERS.json` 是完整清单（104 张）。
- 精灵表必须保持帧数与数据表（`Player.gd` spec、`Enemies.gd` fw/fh、`make_frames` 调用）一致，否则循环错位。
- `audio/bgm` 与 `audio/sfx` 目录预留，路径尚未接入播放节点（目前静音，避免悬空引用报错）。

## 玩家（大鹏 / dapeng）
- 用 Godot 4 开发食梦貘主题 2.5D 8 向动作射击游戏，为虚拟主播「弥绘」庆生。
- 当前阶段：前期设计 + 占位素材验证完整玩法；美术后期替换。
