# 项目长期记忆 · 《梦境逐影》Godot 4.7.1

## 用户约定（必守）
- **每次对话结束必须把对话内容与所做工作追加写入 `docs/会话日志.md`**（用户明确要求）。
- **同时追加 `.workbuddy/memory/YYYY-MM-DD.md`**（当月工作日志）。
- 称呼：momo（弥绘貘貘/虚拟主播）粉丝牌名**弥果卷**；弥绘称呼粉丝用「弥果卷」不用「梦主」。

## 架构
- 入口：Main→Intro(视频)→Prologue(剧情)→Game→(3层Boss后)Epilogue→Game(通关态)→Main。
- Autoload：GameManager(全局状态/成长/瞬态标志)、SaveManager(user://save.json)、MapData(房间状态机)。
- 玩家=食梦貘 2.5D 8向动作射击；占位素材验证玩法。

## 关卡（2026-08-07 场景化重构）
- 每房独立场景 `src/rooms/scenes/f{层}_{房}.tscn`（22 个，根=RoomManager+导出 layer/room_id）；每层世界场景 `src/rooms/worlds/Layer{1,2,3}.tscn`（房间锚点 rid 按 LevelData.pos 摆布）。
- Game 切房：`_ensure_world()`→`_swap` 在锚点下实例化房间→`setup(rid,...)`；出生点=锚点 global+房间局部；相机 focus=房间实例 global_position。
- 背景 S_00{层}_{房}.png/.ogv 由 LevelData.TILES→tile_path 注入；门/敌人/禁区/出生点存 layouts/{层}_{房}.tres。
- f1/f2: r1→r2→r3/r4→r5→r6→r7(boss)；f3 加 r0 共8房。boss 全挂 r7。通关：3 Boss 全清→Epilogue。
- 武器（2026-08-07 回退单武器）：WeaponSystem 单武器；开局地面随机 3 把 F 选 1；每新房首进掉 1~2 把 F。

## Godot 4.x 关键坑（必守）
- 严格模式：变量必显式标类型；推断 Variant 解析失败。
- 循环 class_name：跨类用 `as Node2D`+`.call()/.set()`；只留 `Boss extends Enemy`。无头 `extends Enemy` 改 `extends "res://src/enemies/Enemy.gd"`。
- Theora 必须 .ogv(高16对齐，1072非1080)。VideoStreamPlayer 4.7 无 stretch_mode→用 `expand=true`。
- **黑屏元凶**：play() 须在 add_child 之后→`vp.call_deferred("play")`。
- **tile_path 选背景**：ogv 优先于同名 png（ResourceLoader.exists 先 ogv 再 png）。
- **多边形碰撞用 CollisionPolygon2D 节点**：本构建 `PolygonShape2D.new()` 解析期报错，不可用；用 CollisionPolygon2D（直接吃 polygon 局部顶点）。
- **@tool setter 别在注册期调 get_tree()**：用 `is_inside_tree()` 短路守卫。
- **@tool 预览禁用 autoload**：预览期 autoload 是 placeholder，调其方法崩；取数据用 class_name 全局类。
- **编辑器插件 API 坑(4.7.1)**：①DirAccess.make_dir_recursive 是实例方法；②AnimatedSprite2D 无 playing 属性；**Node2D/AnimatedSprite2D 等 2D 节点加进 Dock 的 Control 容器不会渲染**——面板显示图片必须用 Control 系 TextureRect+Timer；③EditorFileSystem 刷新用 `Engine.get_singleton("EditorFileSystem").call("scan")`；④无头验证插件 UI 须 `-s` 脚本 `load(面板).new()` 后手动 `_ready()` 再数 `get_child_count()`，`--headless --editor --quit` 只查脚本编译。Dock 空白先删 `.godot` 缓存重开。
- Autoload 用全局名 GameManager。动态 UI 挂 CanvasLayer。Rewrite .tscn 必须保留根 script=ExtResource("1")。input_locked 总闸回 Game 必归位。

## 相机（确定性手动驱动）
- 不用 Camera2D。Game._update_camera 每帧写 `get_viewport().canvas_transform=Transform2D(_cam_zoom, center-_cam_zoom*player.global_position)`。

## @tool 可视化编辑器（RoomLayoutEditor）
- add_child 生成节点须 `owner=edited_scene_root` 才能点选拖拽；手柄用 Node2D+Polygon2D。
- 摆放坐标 880×500 世界单位，与背景无关→换视频不错位；编辑器与运行期同变换保证所见即所得。

## 敌人行为体系（2026-08-15 v5.0）
- behavior 6 类：chase/charger/shooter/aoe/patrol/hybrid（远距弹幕+近身 melee）。patrol=始终锁定玩家直线追击+近身近战。
- 动画键：idle→fi / walk_down→fwd / walk_right→fwr / walk_up→fwu / walk_left→fwl / attack→fa / dead→fd / melee→fme（缺省8）。攻击/死亡**双向**：右键+镜像 `*_left`（逐帧 FLIP_LEFT_RIGHT，勿整条翻转）。
- 16 怪体系（alarm_clock/lamp/dog/mower + 精英 road_daredevil/office_ghost/spider/hypno_tv/zombie + 精英 centipede / overtime1/kpi_group/printer2/overtime2/overtime3 + 精英 hardware_core）；命名表 `C:/Users/17930_ueiiii0/Desktop/怪物说明.txt`。
- 弹道全自定义 `{id}_proj.png`；近战判定（WeaponSystem）必须 + 敌人碰撞半径。多行动画表 N行×8列 1024×1024。

## 体型·碰撞·形状 全局类型级可调（ScaleConfig，2026-08-17 v3 含形状）
- **按类型全局调**（调某类型→所有同类型怪生效），核心 `src/data/ScaleConfig.gd`（class_name 全局类，无 autoload），数据 `res://src/data/enemy_scale.json`。
- JSON 结构：`{enemies:{id:{scale,collision,shape,w,h,ox,oy,poly}}, bosses:{...}}`。shape: 0矩形/1三角/2圆/3多边形；w/h/ox/oy 缺省回落该怪 CB（Enemy.CB / Boss 形态 cb），poly=顶点数组([[x,y],...])。
- 静态 get/set：`get/set_{enemy,boss}_{scale,collision,shape,w,h,ox,oy,poly}`；`_get_any`/`_set_val_any` 支持缺省回落与数组；读文件无缓存，编辑器即时生效。
- 运行期：Enemy._apply_collision_box / Boss._apply_form_cb 读 ScaleConfig→`_apply_shape_to_colliders`（三角/多边形走 CollisionPolygon2D，矩形/圆走 CollisionShape2D；两套节点并存按形状启用其一）。最终尺寸=基础值×(scale_mult×collision_mult)，中心点偏移同样缩放（-4 对齐 sprite.position.y）。
- 编辑器：EnemyHandle._redraw / BossHandle._redraw 用 `Enemy._shape_points()` 画真实形状（圆用24边近似）+中心偏移；RoomDockPanel 全局调节区块加形状下拉+宽/高/中心X/Y滑块+多边形顶点编辑（+/-顶点、逐顶点x/y SpinBox、重置为矩形），改动后 `_redraw_handles_of_type` 触发重绘。
- 踩坑：GDScript 静态函数不能命名 `_get`/`_set`（Object 内置虚函数冲突）→ 改名 `_get_val`/`_set_val`；函数返回 Array 不能 unpack 到 typed 变量。

## 其他
- 合并地图 MapData.merged；地面武器 WeaponPickup（F 拾取/交换，just_dropped 0.6s 免疫）。
- 无头测试只看退出码0会漏检；grep 日志 `Invalid access`/`SCRIPT ERROR`。
- 插件勾选框开关可视化须「写 project.godot + 遍历场景重绘手柄」两步。
- 进入关卡演出状态机放 Game（相机/玩家/输入锁），敌人暂停用 `GameManager.cutscene_frozen`。
- 切片去黑边：BFS 逐轮拷贝最近不透明像素颜色（只拷贝不平均），勿用邻居平均（彩虹）。
