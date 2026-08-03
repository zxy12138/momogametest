class_name RoomLayout
extends Resource

## 单个房间的可编辑布局（每房一个 .tres）。
## 运行期由 RoomManager 按「层 + rid」读取，覆盖门的默认位置、刷怪点、禁区与背景对齐。
## 在编辑器中通过 RoomLayoutEditor 场景可视化拖拽生成并保存。

## 门：每条对应一个邻居房，position 为门在房间内的局部坐标；缺省时退回四边中点。
@export var doors: Array[DoorDef] = []

## 敌人放置（拖入式）：每个元素是一个 EnemyPlacementDef（enemy_id + 房间局部坐标）。
## 取代原 LevelData.enemies 数据驱动刷怪——你在编辑器里拖放敌人，运行期它们就出现在这些位置。
@export var enemy_placements: Array[EnemyPlacementDef] = []

## 各类型敌人数量（编辑器「敌人放置（各类型数量）」列表的数据来源）：
## 每种敌人一行，enemy_id(类型) + count(数量)。RoomLayoutEditor 编辑后随 .tres 保存，运行期据此生成手柄。
@export var enemy_specs: Array[EnemyTypeCount] = []

## 角色出生点（房间局部坐标）：由 RoomLayoutEditor 拖拽「出生点」手柄设置。
## 运行期 Game._swap 在首进/无来源房间时用作角色初始位置（过门进入仍走门逻辑）。
@export var spawn_point: Vector2 = Vector2.ZERO

## 禁区/不可走矩形区域。
@export var blocked: Array[RectDef] = []

## 背景整图偏移（局部坐标，默认 0）与缩放（默认 1）。用于对齐美术整图。
@export var bg_offset: Vector2 = Vector2.ZERO
@export var bg_scale: float = 1.0
