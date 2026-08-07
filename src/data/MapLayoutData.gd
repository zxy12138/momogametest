class_name MapLayoutData
extends Resource

## 地图手动布局数据：key "f{层}-{rid}"（如 "f1-r3"）-> 归一化坐标 Vector2(x, y)，取值 0~1。
## 由 MapLayoutEditor（可视化拖拽工具场景）编辑并写回 map_layout.tres；
## 运行期 MapData.build_merged 优先读取它，没有的条目回退 LevelData.pos。
## 坐标语义与 LevelData.pos 完全一致：地图分三栏（层1左/层2中/层3右），
## 层内 x=0 最左、x=1 最右；y=0 顶部、y=1 底部。
@export var positions: Dictionary = {}
