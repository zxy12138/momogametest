@tool
extends VBoxContainer

## 梦境编辑器主面板：TabContainer 两个 Tab，界面排布合理——
## ①「房间布局」= RoomDockPanel（房间场景手柄编辑 + 黑白图导入生成禁区）
## ②「素材库」= SeqFramePanel（序列帧/单图素材生成与拖入）
## 复用两个子面板脚本（preload），不重复实现。
## EditorPlugin 注入 _plugin 供子面板调用（取 EditorUndoRedoManager 等插件级能力）。

const RoomPanelScript: Script = preload("res://addons/room_layout_dock/RoomDockPanel.gd")
const SeqPanelScript: Script = preload("res://addons/sequence_frame_manager/SeqFramePanel.gd")

var _plugin: EditorPlugin = null


func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)
	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	# 容器(VBoxContainer)子节点必须用 size_flags 撑满，锚点预设对容器子节点无效（会导致高度坍缩成一点点）
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	var room_panel: Control = RoomPanelScript.new()
	room_panel.name = "房间布局"
	tabs.add_child(room_panel)
	if _plugin != null and room_panel.has_method("set_plugin"):
		room_panel.call("set_plugin", _plugin)

	var seq_panel: Control = SeqPanelScript.new()
	seq_panel.name = "素材库"
	tabs.add_child(seq_panel)


func set_plugin(p: EditorPlugin) -> void:
	_plugin = p
	# 若子面板已创建则立即转发（_ready 之后注入的场景）
	for c in get_children():
		if c is TabContainer:
			for tab in c.get_children():
				if tab.has_method("set_plugin"):
					tab.call("set_plugin", _plugin)
