# 项目长期记忆 · 《梦境逐影》Godot 4.7.1（已精简）

## 用户约定（必守）
- **每次对话结束后必须把对话内容与所做工作追加写入 `docs/会话日志.md`**（用户明确要求，2026-08-11 重申："每个执行的任务都要文档写在本地"）。
- **本轮起同时追加 `.workbuddy/memory/YYYY-MM-DD.md`**（工作日志，保留所有当月；MEMORY.md 长期项目笔记限额 3000 字/会话）。
- 称呼规范：momo（弥绘貘貘/虚拟主播）的粉丝牌名叫**弥果卷**；弥绘称呼粉丝时用「弥果卷」不用「梦主」。「梦主」仅用于角色设定/叙述（设定处已注明粉丝牌名）。

## 架构
- 入口：Main→Intro(视频)→Prologue(剧情)→Game→(3层Boss后)Epilogue→Game(通关态)→Main。
- Autoload：GameManager(全局状态/成长/瞬态标志 prologue_pending·game_completed)、SaveManager(user://save.json)、MapData(房间状态机)。
- 玩家=食梦貘 2.5D 8向动作射击；占位素材验证玩法。

## 关卡(2026-08-07 场景化大重构)
- **架构**：每房独立场景 `src/rooms/scenes/f{层}_{房}.tscn`（22 个，根=RoomManager+导出 layer/room_id，F6 可单跑）；每层一个世界场景 `src/rooms/worlds/Layer{1,2,3}.tscn`（房间锚点节点名=rid 按 LevelData.pos 摆布 SPACING=6000×2240 + Ghost 占位框 group `layer_ghost` + 邻居 Line2D 连线；Layer.gd 运行时隐藏占位）。
- **Game 切房**：`_ensure_world()` 按层名实例化世界场景（切层自动重建）→ `_swap` 在锚点下实例化房间场景 → `setup(rid, MapData.room(rid), layer, anchor, self)`（RoomManager._setup_done 防重：场景 _ready 已自建）；出生点=锚点 global + 房间局部；相机 focus=当前房间实例 global_position。
- 房间内容数据流不变：背景 S_00{层}_{房}.png/.ogv 由 LevelData.TILES→tile_path 注入 scene_img；门/敌人/禁区/出生点存 layouts/{层}_{房}.tres（RoomLayoutEditor 仍编辑它）。
- f1/f2: r1(start)→r2→r3/r4→r5→r6→r7(boss)；f3 加 r0(start) 共8房。start_room(idx) 第三层=r0 其余=r1。boss=f1 b_director/f2 b_train/f3 b_fear 全挂 r7。通关：3 Boss 全清→Epilogue→回 Game _enter_completed_state。
- **武器（2026-08-07 回退单武器）**：WeaponSystem 单武器模式（loadout 至多 1 把，图标固定悬浮 (34,-40)，8 形态攻击保留）；开局地面随机 3 把 F 选 1（_starter_pickups 拾取后其余消失）；每新房首进掉 1~2 把 F 替换；拾取物挂 $World 世界坐标，_swap 显式清 group `weapon_pickup`。

## Godot 4.x 关键坑（必守）
- 严格模式：变量必显式标类型；推断 Variant 解析失败。
- 循环 class_name：跨类用 `as Node2D`+`.call()/.set()`；只留 `Boss extends Enemy`。无头 `extends Enemy` 改 `extends "res://src/enemies/Enemy.gd"`；const BOSS=preload 改运行期 load。
- Theora 必须 .ogv(高16对齐，1072非1080)；本构建导入正常(ResourceLoader.exists(ogv)=true, load is VideoStream=true)。
- VideoStreamPlayer 4.7 无 stretch_mode 枚举→用 expand=true/loop=true/audio_track=-1；作 Control 加进 Node2D 父须 set_anchors_preset(PRESET_TOP_LEFT)。
- **黑屏元凶**：play() 须在 add_child 之后→`vp.call_deferred("play")`；提前调用报 !is_inside_tree 且视频不播，若同时隐藏底层 TextureRect 则全黑。RoomManager._add_video_floor 与 RoomLayoutEditor._build_bg 均须遵守。
- **tile_path 选背景**：必须 ogv 优先于同名 png(用 ResourceLoader.exists 跨两目录先 ogv 再 png)，否则 png 盖住 ogv→背景"不动"。
- **多边形碰撞用 CollisionPolygon2D 节点**：本构建 `PolygonShape2D.new()` GDScript 解析期报 "not declared/cannot infer type"，不可用；改 `CollisionPolygon2D`(直接吃 `polygon` 局部顶点，节点 position/rotation 变换) 更稳。禁区/不规则障碍(RectDef.shape_type=1 + points) 即此方案。
- **@tool setter 别在注册期调 get_tree()**：脚本注册期会触发 @export setter(如 blocked_count)，此时无场景树，`get_tree()` 抛 "data.tree is null"；改用 `is_inside_tree()` 短路守卫。
- **@tool 预览禁用 autoload**：预览期 autoload 是 placeholder 实例，调其方法崩→取数据用 class_name 全局类(LevelData)，别用 MapData/GameManager。运行期正常。
- **编辑器插件 API 坑(4.7.1)**：①`DirAccess.make_dir_recursive()` 是实例方法，须 `DirAccess.open("res://").make_dir_recursive(path)`；②`AnimatedSprite2D` 无 `playing` 属性(用 `autoplay="default"` 进树即播)；**`Node2D`/`AnimatedSprite2D` 等 2D 节点加进编辑器 Dock 的 `Control` 容器(GUI 体系)不会渲染、整块空白**——编辑器面板里要显示图片/动画必须用 `Control` 系的 `TextureRect`+`Timer` 轮播帧，不能塞 `Node2D`；③`EditorInterface.get_resource_filesystem()` 与静态 `EditorFileSystem.scan()` 在本构建均不存在/非静态，刷新文件系统须 `Engine.get_singleton("EditorFileSystem").call("scan")`；④无头验证插件：光跑 `--headless --editor --quit` 只查**脚本语法编译**，`EditorPlugin._enter_tree`→`add_control_to_dock`→面板 `_build_ui` 这套**UI 构建在无头下不会真正执行**，所以 `_build_ui` 里的运行时错误(如空引用)查不到；要真测 UI 须 `-s` 脚本 `load(面板脚本).new()` 后手动调 `_ready()`，再数 `get_child_count()` 确认控件生成。插件改完后若用户报"Dock 里没按钮/空白"，先怀疑 `.godot` 缓存(旧版插件报过错会记失败态)→关 Godot 删 `.godot` 重开；并给面板 ScrollContainer 设 `custom_minimum_size`、在 `工具` 菜单加入口防 Dock 被收起时无入口。
- Autoload 用全局名 GameManager，不用 Engine.get_singleton。
- 动态 UI 挂 CanvasLayer；屏幕尺寸用 get_window().get_visible_rect().size。
- Rewrite .tscn 必须保留根 script=ExtResource("1")，否则脚本静默未挂载(诊断 current_scene.has_method==false)。
- input_locked 总闸：所有设 true 路径回 Game 必归位；若狂刷 Invalid access on GameManager→陈旧 .godot 缓存，关 Godot 删 .godot 重开(云同步盘先暂停)。

## 相机(补17 确定性手动驱动)
- 不用 Camera2D(current/make_current 静默失效)。Game._update_camera 每帧写 get_viewport().canvas_transform=Transform2D(_cam_zoom, center-_cam_zoom*player.global_position)。Transform2D(value,pos) 第一参是旋转非缩放→用显式轴向量 Vector2(z,0)/Vector2(0,z)。

## @tool 可视化编辑器(RoomLayoutEditor)
- add_child 生成的节点须 `owner=get_tree().edited_scene_root` 才能视口点选拖拽；手柄用 Node2D+Polygon2D(别用 Marker2D)。新增项用 @export count+_adjust_* 增删，NOTIFICATION_EDITOR_PRE_SAVE 写回 RoomLayout.tres。
- 摆放坐标空间固定 880×500 世界单位，与背景 PNG/OGV 无关→换视频不错位；编辑器与运行期用相同变换(size/z/offset/scale)保证所见即所得。视频背景：优先 call_deferred play + autoplay；同名 .png 作兜底底图。

## 其他
- 合并地图 MapData.merged("f{层}-{rid}")；Game.transition_to 含"-"键→拆层→_switch_floor。
- 地面武器 WeaponPickup(Node2D)：F 拾取/交换，just_dropped 0.6s 免疫防死循环。
- 开局武器仅 _end_prologue spawn；瞬态标志 prologue_pending/game_completed 不入存档。
- 无头测试只看退出码0会漏检；跑完 grep 日志 `Invalid access`/`SCRIPT ERROR`。
- **敌人行为(2026-08-15 v5.0 更新)**：behavior 现有 6 类 chase/charger/shooter/aoe/**patrol**/**hybrid**（混合怪：远距 hybrid_range 外 shooter 弹幕、近身 melee_range 内 melee 近战；`_melee_attack(anim_base)` patrol→attack、hybrid→melee）。patrol=始终直线锁定玩家追击，近身 atk_range 内按 atk_cd 近战攻击。动画键体系 anim_frame_key：idle→fi / walk_down→fwd / walk_right→fwr / walk_up→fwu / walk_left→fwl / attack→fa / attack_left→fa / dead→fd / dead_left→fd / melee→fme / melee_left→fme（缺省 8）。**攻击/死亡动作双向**：向右主键 + 镜像生成 `*_left`（朝左攻击/死亡播镜像版，不靠 flip_h 翻转动作，避免动作方向奇怪）；`_facing_left` 移动时按 dir.x 更新，攻击/死亡按朝向选 left/right。**新 16 怪体系**（替换旧 15 怪，全完整动画）：alarm_clock/lamp/dog/mower + 精英 road_daredevil (层1) / office_ghost(远程)/spider(hybrid)/hypno_tv(远程)/zombie + 精英 centipede(hybrid) (层2) / overtime1/kpi_group(远程)/printer2/overtime2/overtime3(远程) + 精英 hardware_core(远程) (层3)；命名对应表 `C:/Users/17930_ueiiii0/Desktop/怪物说明.txt`。**弹道全自定义**：远程怪弹道都从精灵图切出（`{id}_proj.png`），无独立弹道帧的怪复用同层 proj（centipede→F2_N_002_proj）；小怪不用橙色 W-020（仅 Boss 用）。**怪物大小调整**：EnemyHandle `scale_mult`(0.1~3.0) → RoomManager._spawn_enemy → Enemy.set_scale_mult（sprite scale×sm + 碰撞/受击半径×sm）。**近战判定（WeaponSystem）必须 + 敌人碰撞半径**（_enemy_radius 读 CircleShape2D，兜底 20）。**多行动画表**：N行×8列 1024×1024，行序即行为。**切片关键坑：行带检测用「每行 alpha>60 计数」勿用完全透明**；**帧数不一定是 8**（AI 图可能 10/6/4 帧不等，固定网格必裂）→ 用「帧间距中位数分析（1024/间距）」或「列投影内容带自适应」或「用户提供帧数（最可靠，FRAMES 表）」确定每行帧数，均匀切 + 跳空帧；单向动作（walk_right/attack/dead/melee）镜像生成 left；弹道行导出 `{id}_proj.png`，混在攻击行末尾的弹道用 `make_proj_from_frame`（均匀切定位末尾帧）；**攻击帧与弹道帧粘连**（无空白，如 F3_N_003 攻击帧3 和弹道间仅 3px 过渡）→ 用「攻击帧等宽（前2帧宽中位数）+ 帧间距」推断攻击帧边界，弹道帧紧跟其后按弹道帧数切（**弹道帧宽明显大于攻击帧** 245 vs 135px）；**弹道多帧动画**：Projectile `proj_frames` 字段 + `_frame_t/_cur_frame` 轮播（Sprite.hframes），Enemy._spawn_proj 传 proj_frames，Enemies.gd 配 proj_frames；独立弹道行（供 Projectile 单帧）取最大内容带（过滤 2px 碎片）；工具 `tools/slice_enemy_rows.py`（ROWS 行序表 + FRAMES 帧数表 + ATTACK_PROJ 攻击/弹道分离表驱动，行可标记 skip 跳多余行）。插件 EnemyHandle.IDS/@export_enum 与 Enemies.gd 需同步加新怪 id；预览无 idle 兜底 walk_down。
- **去黑边 color_bleed.py v2**：AI 素材半透明边缘 RGB 是黑（羽化只降 alpha 没变 RGB）→ 黑边；**勿用「邻居颜色平均」扩散**（会把门框深色+门洞亮色混成彩虹/灰，RGB 标准差飙到 80+），正确做法是 **BFS 逐轮拷贝「最近不透明像素」的颜色（只拷贝不平均）**，auto-terminate。验证口径：处理后羽化区(0<alpha<255)平均 RGB≈不透明区颜色、标准差~20（正常）而非 80（彩虹）或 0（黑边）。
- **插件勾选框开关可视化**（门/禁区判定框等）：必须「写 project.godot 设置 + 遍历场景重绘手柄（_collect_xxx + call("_redraw")）」两步，缺重绘则编辑器画面不刷新；project.godot 残留旧值会让「默认态」反直觉（表现为"无论勾不勾都不显示"）。门判定框开关 = `BlockedHandle.HIDE_DOOR_VISUAL_SETTING`（放 BlockedHandle 避免 DoorHandle↔RoomManager 循环依赖）。
- **进入关卡演出（过场动画）**：状态机放 **Game**（相机/玩家/输入锁都在 Game），RoomManager 只暴露数据接口（`get_enter_door_anim()`/`get_enemy_center_local()`）不自己播。敌人暂停用全局 `GameManager.cutscene_frozen`（Enemy._physics_process 读到 velocity=ZERO+return）；固定视角相机做「平移演出」= `_update_camera` 的 focus 叠加 `_cam_focus_offset`，用 `smoothstep` 逐帧 lerp（不动 Camera2D）。门动画等播完用 `AnimatedSprite2D.is_playing()`（非循环动画播完变 false）。
