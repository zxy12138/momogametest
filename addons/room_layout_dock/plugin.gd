@tool
extends EditorPlugin

## 房间布局编辑器 —— 编辑器插件入口。
## 在右侧 Dock 注册管理面板（RoomDockPanel），用于在房间场景里一键添加
## 门/敌人/禁区/出生点/武器手柄并直接拖放编辑（替代 RoomLayoutEditor 工具场景）。
## 同时在顶部「工具」菜单提供入口，保证即使 Dock 被收起也能打开。

const PanelScript: Script = preload("res://addons/room_layout_dock/RoomDockPanel.gd")
const TOOL_MENU_ITEM := "房间布局编辑器"

var _panel: Control

func _enter_tree() -> void:
	_panel = PanelScript.new()
	_panel.name = "房间布局"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _panel)
	# 顶部「工具」菜单入口，作为 Dock 之外可靠的打开方式。
	add_tool_menu_item(TOOL_MENU_ITEM, _on_tool_menu_pressed)

func _on_tool_menu_pressed() -> void:
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
