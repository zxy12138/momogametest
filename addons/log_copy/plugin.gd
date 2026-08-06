@tool
extends EditorPlugin

## 一键复制最近日志：读取 user://logs/godot.log（Godot 4 默认日志文件，含所有 print/push_error 输出）
## 末尾的最近若干行，复制到系统剪贴板。
## 使用：菜单「项目(Project) → 工具 → 📋 复制最近日志到剪贴板」→ 粘贴给 AI / 提交 bug 报告。
## 说明：运行时(F5)的报错也会写入该文件（%APPDATA%/Godot/app_userdata/{项目名}/logs/godot.log）。

const LOG_PATH := "user://logs/godot.log"
const MAX_LINES := 800   ## 复制最近多少行（太长会占满粘贴框，800 行足够覆盖一次启动的完整报错）

func _enter_tree() -> void:
	add_tool_menu_item("📋 复制最近日志到剪贴板", Callable(self, "_copy_logs"))


func _exit_tree() -> void:
	remove_tool_menu_item("📋 复制最近日志到剪贴板")


func _copy_logs() -> void:
	var path: String = ProjectSettings.globalize_path(LOG_PATH)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		var msg := "找不到日志文件：" + path
		push_error("log_copy: " + msg)
		_popup(msg)
		return
	var all_text: String = f.get_as_text()
	f.close()
	var lines: PackedStringArray = all_text.split("\n")
	var tail: PackedStringArray = lines.slice(maxi(0, lines.size() - MAX_LINES))
	var text: String = "\n".join(tail)
	DisplayServer.clipboard_set(text)
	var msg := "已复制最近 %d 行日志（文件共 %d 行）→ 直接 Ctrl+V 粘贴即可" % [tail.size(), lines.size()]
	print("[log_copy] " + msg)
	_popup(msg)


func _popup(msg: String) -> void:
	# 编辑器 toast 提示（API 存在性防御，避免特定版本报错）
	var ei := Engine.get_singleton("EditorInterface")
	if ei != null and ei.has_method("get_editor_toaster"):
		var toaster: Object = ei.call("get_editor_toaster")
		if toaster != null and toaster.has_method("popup_text"):
			toaster.call("popup_text", msg)
