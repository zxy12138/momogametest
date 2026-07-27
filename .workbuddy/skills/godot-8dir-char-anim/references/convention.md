# 8 向角色动画 · 项目约定与代码模板（梦境逐影 / Godot 4）

本文件是 `godot-8dir-char-anim` 技能的详细参考。SKILL.md 只给流程，这里给可复制粘贴的代码与硬规范。

---

## 1. 8 个方向（DIR_ORDER）

行序即方向索引，必须和打包脚本、`make_frames` 行号、`_anim_update` 解析器三者完全一致：

```
索引 0: down        (下 / 南)   角度 90°
索引 1: down_right  (右下 / 东南) 角度 45°
索引 2: right       (右 / 东)   角度 0°
索引 3: up_right    (右上 / 东北) 角度 315°  (-45°)
索引 4: up          (上 / 北)   角度 270°  (-90°)
索引 5: up_left     (左上 / 西北) 角度 225°  (-135°)
索引 6: left        (左 / 西)   角度 180°
索引 7: down_left   (左下 / 西南) 角度 135°
```

行序口诀：**从「下」开始顺时针一圈**：下 → 右下 → 右 → 右上 → 上 → 左上 → 左 → 左下。

---

## 2. 命名与尺寸规范（来自 v3.0 美术素材清单）

- 角色精灵帧尺寸：**130 × 250**（Boss 是 260×500，本技能只处理角色/普通怪/精英怪）。
- 文件命名铁律：`{编号}_{英文snake_case}.png`，如 `A-001_miai_idle.png`。
- 8 向图集按**动作**拆分，每个动作为一张图集：
  `A-001_miai_{action}.png`，例如 `A-001_miai_idle.png`、`A-001_miai_walk.png`、`A-001_miai_attack.png`。
- 图集内部布局：**8 行（方向）× F 列（帧）**，每格 130×250。
- 玩家精灵路径前缀常量（Player.gd）：`const SPR = "res://assets/sprites/player/"`。

> 注：旧的 `A-001_all.png` 是 128×128 格、多动作打包的遗留图集（只含 下/右/上 + 镜像）。新 8 向流程改用「每动作一张 130×250 图集」，与文档规格一致。

---

## 3. `make_frames` 规格写法

项目用 `GameManager.make_frames(spec)` 从图集抽帧，格式：

```
spec[动画名] = [图路径, 帧宽, 帧高, 帧数, fps, 行号]
```

8 向 idle（6 帧，fps 6）示例：

```gdscript
var spec := {
    "idle_down":      [SPR+"A-001_miai_idle.png", 130, 250, 6, 6, 0],
    "idle_down_right":[SPR+"A-001_miai_idle.png", 130, 250, 6, 6, 1],
    "idle_right":     [SPR+"A-001_miai_idle.png", 130, 250, 6, 6, 2],
    "idle_up_right":  [SPR+"A-001_miai_idle.png", 130, 250, 6, 6, 3],
    "idle_up":        [SPR+"A-001_miai_idle.png", 130, 250, 6, 6, 4],
    "idle_up_left":   [SPR+"A-001_miai_idle.png", 130, 250, 6, 6, 5],
    "idle_left":      [SPR+"A-001_miai_idle.png", 130, 250, 6, 6, 6],
    "idle_down_left": [SPR+"A-001_miai_idle.png", 130, 250, 6, 6, 7],
}
```

> `make_frames` 自动把除 `"dead"` 外的动画设为循环。行号 = 上表 DIR_ORDER 索引。

---

## 4. 方向解析器（角度 → 方向名）

放在角色脚本里，把移动向量转成 8 向之一：

```gdscript
const DIR_ORDER := ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]

func dir_from_vector(v: Vector2) -> String:
    if v.length_squared() < 0.001:
        return "down"  # 静止默认朝下
    var a := fmod(rad_to_deg(v.angle()) + 360.0, 360.0)  # 0..360, 0=右
    var best := "down"
    var best_d := 999.0
    for d in DIR_ORDER:
        var diff := abs(_angle_diff(a, _dir_angle(d)))
        if diff < best_d:
            best_d = diff
            best = d
    return best

func _dir_angle(d: String) -> float:
    match d:
        "down": return 90.0
        "down_right": return 45.0
        "right": return 0.0
        "up_right": return 315.0
        "up": return 270.0
        "up_left": return 225.0
        "left": return 180.0
        "down_left": return 135.0
    return 90.0

func _angle_diff(a: float, b: float) -> float:
    var d := abs(a - b)
    return min(d, 360.0 - d)
```

---

## 5. 动画选择（_anim_update 模板，真 8 向）

当 8 个方向都画了，不需要 `flip_h`，直接拼 `{action}_{dir}`：

```gdscript
func _anim_update(delta: float) -> void:
    if _dead:
        return
    var next := ""
    var moving := velocity.length() > 12.0
    if _atk_timer > 0:
        next = "attack_" + dir_from_vector(velocity if moving else _aim_dir())
    elif moving:
        next = "walk_" + dir_from_vector(velocity)
    else:
        next = "idle_" + dir_from_vector(_aim_dir())
    if next != "" and next != _anim and _sprite.sprite_frames.has_animation(next):
        _anim = next
        _sprite.play(next)

# 瞄准方向（鼠标 -> 朝鼠标那一侧）
func _aim_dir() -> Vector2:
    return _aim if _aim != Vector2.ZERO else Vector2.DOWN
```

### 省美术版（4 向 + 镜像）

若只画 下/右/上 三向、左右共用（左 = 右镜像），解析器只返回这三个 + 用 `flip_h` 派生：

```gdscript
func dir_4(v: Vector2) -> String:
    if v.length_squared() < 0.001: return "down"
    if abs(v.x) >= abs(v.y):
        return "right" if v.x >= 0 else "right"   # 左由 flip_h 处理
    return "down" if v.y > 0 else "up"

# 选中后：
# next = "walk_" + dir_4(velocity)
# _sprite.flip_h = velocity.x < 0   # 左行走镜像
```

---

## 6. ImageGen 提示词模板（AI 出图用）

逐方向出图时，**角色描述必须逐张完全一致**，只换方向/动作关键词，否则 8 张脸会各不相同。模板：

```
{角色描述}，游戏角色精灵，{动作}姿态，面朝{direction_cn}，
2D 横版/俯视像素风，单色透明背景 PNG，居中，全身入镜，
固定 {cell_w}x{cell_h} 画幅，无文字无边框无阴影，平光，
风格参考：{style_ref}
```

- `{direction_cn}`：下 / 右下 / 右 / 右上 / 上 / 左上 / 左 / 左下。
- `{动作}`：待机(idle) / 行走(walk) / 奔跑(run) / 攻击(attack) / 受击(hurt) / 死亡(dead) / 终极(ult) / 跳(jump)。
- **一致性建议**：先出一张「正面/3-4 视基准参考图」固定角色外观，再让后续每张都引用该描述；对角线方向（右下/右上/左上/左下）可由基准的 右/上 姿态在图像工具里旋转 45° 派生，比纯文生更稳。
- 每动作每方向若多帧，需分帧出图（或出一张后拆帧），最终拼成水平帧条喂给 `pack_8dir.py`。

---

## 7. 打包命令

生成的结构：`./gen/player/<action>/<dir>.png`（每 `<dir>.png` 是 F 帧水平条，130×250/帧）。

```bash
python pack_8dir.py ./gen/player ./assets/sprites/player 130 250 A-001_miai_
```

输出 `A-001_miai_idle.png` 等 8 行图集，直接被 `make_frames` 按行号读取。
