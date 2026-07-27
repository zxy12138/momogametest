---
name: godot-8dir-char-anim
description: "Build and wire 8-direction (8-way) character animations for the 梦境逐影 Godot 4 project. Trigger when generating 8-directional character actions (idle/walk/run/attack/hurt/dead/ult) via AI image generation, atlas packing, or Godot AnimatedSprite2D wiring. Codifies the A-XXX_miai_* naming, 130x250 frame size, 8-direction row order, GameManager.make_frames spec, and angle-to-direction resolver. Trigger phrases: 8 向角色动画, 8方向角色, 生成 8 向动作, character animation, 8-way sprite, add directional character animation."
agent_created: true
---

# Godot 8 向角色动画生成（梦境逐影）

## Overview

为《梦境逐影》Godot 4 项目生成**真正 8 向**（下/右下/右/右上/上/左上/左/左下）的角色动作资源，并把它们接进 Godot 的 `AnimatedSprite2D` 动画系统。覆盖三件事：AI 出图（精灵图）、图集打包、Godot 代码接线。所有规范以 `references/convention.md` 为准，可复制粘贴。

当前 `Player.gd` 只是 3 方向（下/右/上）+ `flip_h` 镜像，本技能把它升级为完整 8 向，并产出可复用的流水线。

## When to use

- 用户说「生成 8 向角色动作」「做 8 方向动画」「idle/walk/attack 八向」等。
- 需要给玩家或敌人补一套带方向的动画，且要符合本项目 `A-XXX_miai_*` 命名与 `make_frames` 格式。
- 要把现有 3 向 / 4 向角色扩成 8 向。

## Core conventions（硬规范，详见 references/convention.md）

- **8 方向行序（DIR_ORDER）**：`down, down_right, right, up_right, up, up_left, left, down_left`（从「下」顺时针一圈）。图集行号、解析器、`make_frames` 行号三者必须一致。
- **帧尺寸**：角色 **130×250**（Boss 260×500，本技能不涉及）。
- **命名**：`A-001_miai_{action}.png`，每个动作为一张 8 行×F 列图集。
- **抽帧**：`GameManager.make_frames(spec)`，格式 `[路径, 帧宽, 帧高, 帧数, fps, 行号]`。
- **路径前缀**：`res://assets/sprites/player/`（玩家）。

## Workflow

### Phase 1 — 生成 8 向精灵图（AI 出图）

1. 确认目标角色与动作集。默认玩家「弥绘」动作：`idle, walk, run, attack, hurt, dead, ult, jump`。
2. 固定一份**角色外观描述**（颜色/发型/服饰/武器），逐方向逐动作复用，只换 `{direction_cn}` 与 `{动作}`。
3. 用 ImageGen（文生图）逐张出图，提示词模板见 `references/convention.md` §6。每条 130×250、透明背景、无文字。
4. **一致性技巧**：先出一张基准参考图锁外观；对角线方向（右下/右上/左上/左下）优先由「右/上」姿态旋转 45° 派生，比纯文生更稳。
5. 多帧动作（如 walk 6 帧）需分帧出图或拆帧，最终每个 {action}/{dir}.png 是一张水平 F 帧条。

### Phase 2 — 打包成图集

1. 目录结构：`./gen/player/{action}/{dir}.png`（`{dir}` ∈ DIR_ORDER）。
2. 运行打包脚本（见 scripts/pack_8dir.py）：
   ```bash
   python pack_8dir.py ./gen/player ./assets/sprites/player 130 250 A-001_miai_
   ```
3. 输出 `A-001_miai_idle.png` 等，内部 8 行（方向）×F 列（帧），每格 130×250。

### Phase 3 — 接进 Godot

1. 在角色脚本 `_ready()` 里按 `references/convention.md` §3 写 `make_frames` 的 8 向 spec（每个 action × 8 dir 一条）。
2. 加入 §4 的方向解析器 `dir_from_vector(v)`。
3. 把 `_anim_update` 改成 §5 的真 8 向选择（拼 `"{action}_" + dir_from_vector(...)`）。若选「4 向 + 镜像」省美术，用 §5 省美术版 + `flip_h`。
4. 保持 `_sprite.scale = Vector2(0.28, 0.28)`（本项目角色视觉比例）。
5. 用 Godot 无头加载校验：进入场景后 `current_scene.has_method(...)` 与动画名存在性，零 `SCRIPT ERROR`。

## Scripts

- `scripts/pack_8dir.py`：把 {action}/{dir}.png 水平帧条打包成 8 行图集。用法见文件头与 convention.md §7。

## References

- `references/convention.md`：DIR_ORDER、命名/尺寸、make_frames 规格示例、方向解析器与 _anim_update 完整 GDScript、ImageGen 提示词模板、打包命令。

## Pitfalls

- **行序错位是头号 bug**：图集行号、DIR_ORDER、解析器三者顺序必须完全相同，否则「朝上走却播下动画」。
- **角色描述不一致**：8 张图若描述各异，同一角色会脸/服装乱跳；务必复用同一段外观描述。
- **帧尺寸必须 130×250**：与文档一致；旧 `A-001_all.png` 是 128×128 遗留，新流程不要混用。
- **静止朝向**：`dir_from_vector(Vector2.ZERO)` 默认返回 `"down"`，但静止时通常应朝鼠标（`_aim`），用 §5 的 `_aim_dir()` 处理。
