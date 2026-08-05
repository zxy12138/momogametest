# 项目长期记忆 · 《梦境逐影》Godot 4.7.1（已精简）

## 架构
- 入口：Main→Intro(视频)→Prologue(剧情)→Game→(3层Boss后)Epilogue→Game(通关态)→Main。
- Autoload：GameManager(全局状态/成长/瞬态标志 prologue_pending·game_completed)、SaveManager(user://save.json)、MapData(房间状态机)。
- 玩家=食梦貘 2.5D 8向动作射击；占位素材验证玩法。

## 关卡(2026-08-03 扩7房)
- f1/f2: r1(start)→r2→r3/r4→r5→r6→r7(boss)；f3 加 r0(start) 共8房。start_room(idx) 第三层=r0 其余=r1。
- neighbors 线性(去网状)；boss=f1 b_director/f2 b_train/f3 b_fear 全挂 r7。
- 背景 S_00{层}_{房}.png/.ogv 由 LevelData.TILES→MapData.load_layer 注入 scene_img，RoomManager prefab 整图(z=-4000)。f3 r7 额外 boss_intro_img=S_003_7+boss_intro_time=2.5。
- 通关：3 Boss 全清→game_completed→Epilogue→回 Game 走 _enter_completed_state(transition_to("r7",true))。

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
