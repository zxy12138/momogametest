class_name EnemyTypeCount
extends Resource

## 一种敌人类型的放置数量（编辑器用）。配合 RoomLayoutEditor 的「敌人放置（各类型数量）」列表，
## 每个元素 = 一个敌人类型(enemy_id，下拉选择) + 该类型要刷出的数量(count)。
## 运行期 RoomManager 按各类型的 count 生成对应数量的可拖拽手柄，位置由你在视口摆放。
## 该列表按房间保存在 RoomLayout.enemy_specs，随 .tres 落盘；切换房间会自动重载。

@export_enum("overtime_ghost", "kpi", "printer", "meeting", "phone", "commuter", "escalator", "rider", "revolving", "package", "message", "overdue", "rejected", "heart_beat", "elite_996")
var enemy_id: String = "overtime_ghost"

@export var count: int = 0
