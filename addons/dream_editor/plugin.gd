@tool
extends EditorPlugin

## 梦境编辑器（素材 + 房间布局）—— 多功能插件入口。
## 在右侧 Dock 注册主面板（DreamEditorPanel），内含两个 Tab：
##   「房间布局」复用 RoomDockPanel：在房间场景里一键添加门/敌人/禁区/出生点/武器/装饰手柄并拖放编辑，
##                  支持黑白图导入自动生成禁区（黑=禁区/白=可行走）；
##   「素材库」复用 SeqFramePanel：序列帧/单图素材切分、生成 SpriteFrames 并拖入场景。
## 同时在顶部「工具」菜单提供入口，保证即使 Dock 被收起也能打开。

const MainPanelScript: Script = preload("res://addons/dream_editor/DreamEditorPanel.gd")
const TOOL_MENU_ITEM := "梦境编辑器"

var _panel: Control

func _enter_tree() -> void:
	_panel = MainPanelScript.new()
	_panel.name = "梦境编辑器"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _panel)
	add_tool_menu_item(TOOL_MENU_ITEM, _on_tool_menu_pressed)
	# 注入插件引用：面板需要 EditorPlugin.get_undo_redo_manager() 实现导入撤销
	if _panel.has_method("set_plugin"):
		_panel.call("set_plugin", self)

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
