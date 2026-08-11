@tool
extends EditorPlugin

## 日志导出工具（log_copy v2）：
## ① 「📋 复制最近日志到剪贴板」——复制 godot.log 末尾 800 行，直接粘贴给 AI / bug 报告。
## ② 「📤 导出完整日志到文件」——把 godot.log 全文（含 Output/Debugger 面板全部 print/报错/警告）
##    导出到项目根目录 debug_logs/godot_log_<时间戳>.txt，方便存档/分析/发给他人。
## 说明：运行时(F5)的 print/push_error/push_warning 都会写入该文件
##      （%APPDATA%/Godot/app_userdata/{项目名}/logs/godot.log），Output/Debugger 面板内容同源。

const LOG_PATH := "user://logs/godot.log"
const MAX_LINES := 800   ## 复制最近多少行（太长会占满粘贴框，800 行足够覆盖一次启动的完整报错）

func _enter_tree() -> void:
	add_tool_menu_item("📋 复制最近日志到剪贴板", Callable(self, "_copy_logs"))
	add_tool_menu_item("📤 导出完整日志到文件", Callable(self, "_export_logs"))


func _exit_tree() -> void:
	remove_tool_menu_item("📋 复制最近日志到剪贴板")
	remove_tool_menu_item("📤 导出完整日志到文件")


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


## 导出完整日志到文件：读 godot.log 全文 → 写到项目根目录 debug_logs/godot_log_<时间戳>.txt。
## 时间戳文件名避免覆盖，多次导出各留一份；成功后在 Output 面板打印完整路径。
func _export_logs() -> void:
	var src: String = ProjectSettings.globalize_path(LOG_PATH)
	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		var msg := "找不到日志文件：" + src
		push_error("log_copy: " + msg)
		_popup(msg)
		return
	var all_text: String = f.get_as_text()
	f.close()

	# 导出目录：项目根目录下 debug_logs/（globalize 后是绝对路径，开发期可写）
	var project_root: String = ProjectSettings.globalize_path("res://")
	var out_dir := project_root.path_join("debug_logs")
	var err := DirAccess.make_dir_recursive_absolute(out_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		_popup("创建导出目录失败：" + out_dir)
		return

	# 时间戳文件名（Windows 文件名不允许冒号，替换为 -）
	var stamp: String = Time.get_datetime_string_from_system(true).replace(":", "-")
	var out_path := out_dir.path_join("godot_log_%s.txt" % stamp)
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		_popup("写入失败：" + out_path)
		return
	out.store_string(all_text)
	out.close()

	var msg := "已导出完整日志（%d 行 / %.1f KB）→ %s" % [all_text.split("\n").size(), float(all_text.length()) / 1024.0, out_path]
	print("[log_copy] " + msg)
	_popup(msg)


func _popup(msg: String) -> void:
	# 编辑器 toast 提示（API 存在性防御，避免特定版本报错）
	var ei := Engine.get_singleton("EditorInterface")
	if ei != null and ei.has_method("get_editor_toaster"):
		var toaster: Object = ei.call("get_editor_toaster")
		if toaster != null and toaster.has_method("popup_text"):
			toaster.call("popup_text", msg)
