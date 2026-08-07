# 世界场景（整层关卡总览）根脚本。
# 编辑器里：锚点占位框(Ghost)与邻居连线可见，直观看到整层房间拓扑。
# 运行时：隐藏占位框与连线（真实房间内容由 Game 在锚点下实例化），避免遮挡。
@tool
extends Node2D

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for n in get_tree().get_nodes_in_group("layer_ghost"):
		n.visible = false
