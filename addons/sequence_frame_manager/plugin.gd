@tool
extends EditorPlugin

## 序列帧素材管理器 —— 编辑器插件入口。
## 在底部 Dock 注册一个管理面板（SeqFramePanel），用于选取图片、探测/切分序列帧、
## 实时预览并生成可拖入场景的素材。
## 同时在顶部「工具」菜单提供入口，保证即使底部 Dock 被收起也能打开。

const SeqFramePanelScript: Script = preload("res://addons/sequence_frame_manager/SeqFramePanel.gd")

const TOOL_MENU_ITEM := "序列帧素材管理器"

var _panel: SeqFramePanel

func _enter_tree() -> void:
	_panel = SeqFramePanelScript.new()
	_panel.name = "序列帧素材"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_BOTTOM, _panel)
	# 顶部「工具」菜单入口，作为 Dock 之外可靠的打开方式。
	add_tool_menu_item(TOOL_MENU_ITEM, _on_tool_menu_pressed)

func _on_tool_menu_pressed() -> void:
	# 确保面板与其所在 dock 可见（编辑器未提供稳定的「选中底部 dock 标签」API，
	# 这里至少把面板本身 show 出来，并从父节点向上尝试展示 dock 容器）。
	if _panel != null:
		_panel.show()
		var p := _panel.get_parent()
		while p != null:
			if p is CanvasItem:
				(p as CanvasItem).show()
			p = p.get_parent()

func _exit_tree() -> void:
	remove_tool_menu_item(TOOL_MENU_ITEM)
	if _panel != null:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null
