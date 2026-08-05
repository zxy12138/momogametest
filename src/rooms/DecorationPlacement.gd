class_name DecorationPlacement
extends Resource

## 单个装饰性动态素材放置：scene_path 为序列帧插件生成的 AnimatedSprite2D .tscn 路径，
## pos 为房间局部坐标（与敌人/门同一坐标空间）。
## scale/rotation/flip_h/flip_v 完整记录编辑器里的视觉调整（缩放/旋转/翻转），
## 运行期原样还原，做到「编辑器里调成什么样，游戏里就是什么样」。
## 由 RoomLayoutEditor 在编辑器里从序列帧插件素材库拖入生成，并随 RoomLayout(.tres) 保存；
## 运行期 RoomManager._spawn_decorations 据此在对应位置实例化动画（autoplay 自动播放）。
## 取代「直接把 .tscn 拖进 RoomLayoutEditor 场景树」——那种做法只会留在工具场景里，进不了游戏。

@export var scene_path: String = ""
@export var pos: Vector2 = Vector2.ZERO
## 视觉变换（与 AnimatedSprite2D 同字段）。默认 1.0/0.0/false 等同未调整的 .tscn。
@export var scale_xy: Vector2 = Vector2.ONE
@export var rotation_deg: float = 0.0
@export var flip_h: bool = false
@export var flip_v: bool = false
