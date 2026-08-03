class_name EnemyPlacementDef
extends Resource

## 单个敌人放置：enemy_id 为 Enemies.DATA 中的类型键（普通小怪 / 精英）；pos 为房间局部坐标。
## 由 RoomLayoutEditor 在编辑器中拖拽生成并随 RoomLayout(.tres) 保存；运行期 RoomManager 据此
## 在对应位置实例化敌人。取代原 LevelData.enemies 数据驱动刷怪——你在编辑器里摆哪，运行时就出在哪。

@export var enemy_id: String = ""
@export var pos: Vector2 = Vector2.ZERO
