class_name RectDef
extends Resource

## 禁区/不可走区域（房间局部坐标，相对房间中心 0,0）。
## 兼容旧数据：旧 .tres 只有 center/size 也能正常加载（新字段走默认值）。
## - shape_type = 0：矩形，由 size 定义（默认，兼容旧矩形禁区）。
## - shape_type = 1：多边形，由 points 定义（points 为相对 center 的局部坐标，可表达不规则物体）。
## rotation_deg：整体旋转角度（度）。用于让矩形/多边形对齐场景中倾斜的障碍。
@export var center: Vector2 = Vector2.ZERO
@export var size: Vector2 = Vector2(120.0, 120.0)
@export var rotation_deg: float = 0.0
@export var shape_type: int = 0            # 0 = 矩形, 1 = 多边形
@export var points: PackedVector2Array = []   # 仅 shape_type=1 生效，局部坐标(相对 center)
