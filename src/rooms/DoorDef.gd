class_name DoorDef
extends Resource

## 单扇门：连接到目标房 rid，position 为该门在房间局部坐标系中的位置
## （房间中心为原点，X∈[-W/2, W/2]、Y∈[-H/2, H/2]）。
@export var target: String = ""
@export var position: Vector2 = Vector2.ZERO
