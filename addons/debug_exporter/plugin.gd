@tool
extends EditorPlugin

## Debug Exporter：解析 GDScript 编译错误/警告 → Markdown 报告
##
## 菜单（工具菜单 → Debug Exporter）：
##   📋 复制错误报告到剪贴板  —— 解析 godot.log 最近行 → Markdown 报告 → clipboard
##   💾 导出错误报告到文件      —— 解析 godot.log 最近行 → debug_logs/errors_report_<时间戳>.md
##
## 支持识别的错误类型（来自 GDScript::reload 输出）：
##   - NARROWING_CONVERSION: float 转 int 丢精度（建议 int(x) / round(x) / roundi(x)）
##   - SHADOWED_VARIABLE_BASE_CLASS: 参数遮蔽 Node 基类属性（建议改名为 _name 等，避免用 name/class/script）
##   - UNUSED_VARIABLE / UNUSED_PARAMETER: 未使用变量/参数（建议删或加 _ 前缀让编辑器忽略）
##   - INFERENCE_ON_VARIANT: 类型推断失败（建议显式标类型）
##   - 其它 GDScript 警告/错误（按原文列出）

const LOG_PATH := "user://logs/godot.log"
const MAX_LINES := 2000   ## 解析日志末尾多少行（覆盖一次启动完整报错足够）
const OUTPUT_DIR := "res://debug_logs/"   ## 报告输出目录（项目根目录下的 debug_logs）

# 单条错误记录
class Issue:
    var file: String = ""     # res://.../xxx.gd
    var line: int = 0         # 行号
    var code: String = ""     # 错误类型，如 NARROWING_CONVERSION
    var snippet: String = ""  # 原始日志片段
    var hint: String = ""     # 修复建议


func _enter_tree() -> void:
    add_tool_menu_item("📋 复制错误报告到剪贴板", Callable(self, "_copy_report"))
    add_tool_menu_item("💾 导出错误报告到文件", Callable(self, "_export_report"))


func _exit_tree() -> void:
    remove_tool_menu_item("📋 复制错误报告到剪贴板")
    remove_tool_menu_item("💾 导出错误报告到文件")


# ---------------- 核心：解析日志 ----------------

## 解析日志末尾 MAX_LINES 行，提取 GDScript 编译错误/警告。
## godot.log 实际行格式：
##   <GDScript::reload> Narrowing conversion (float is converted to int and loses precision).
##   <GDScript>     GameManager.gd:117 @ GDScript::reload()
##   <GDScript::reload> The local function parameter "name" is shadowing an already-declared property in the base class "Node".
##   <GDScript>     GameManager.gd:220 @ GDScript::reload()
## 错误描述和文件定位行**交替**出现，描述行 <GDScript::reload> 开头，定位行 <GDScript>（无 ::reload）开头。
func parse_issues() -> Array:
    var log_path: String = ProjectSettings.globalize_path(LOG_PATH)
    var f := FileAccess.open(log_path, FileAccess.READ)
    if f == null:
        return []
    var all_text: String = f.get_as_text()
    f.close()
    var lines: PackedStringArray = all_text.split("\n")
    var start: int = maxi(0, lines.size() - MAX_LINES)
    var issues: Array = []

    var i: int = start
    while i < lines.size():
        var line: String = lines[i]
        if line.begins_with("<GDScript::reload>") or line.begins_with("GDScript::reload"):
            # 错误描述行；下一行通常是 <GDScript> 文件:行号
            var gt_pos: int = line.find(">")
            var desc: String = line.substr(gt_pos + 1).strip_edges() if gt_pos >= 0 else line.strip_edges()
            var code: String = _classify(desc)
            var hint: String = _hint_for(code, desc)
            var snippet: String = desc
            var file: String = ""
            var lineno: int = 0
            # 查找后面的 <GDScript> xxx.gd:N @ ... 定位行（向后最多 5 行）
            for j in range(i + 1, mini(i + 5, lines.size())):
                var loc: String = lines[j]
                if loc.begins_with("<GDScript>") and not loc.begins_with("<GDScript::"):
                    var colon_idx: int = loc.find(".gd:")
                    if colon_idx >= 0:
                        var spc: int = loc.rfind(" ", colon_idx)
                        file = loc.substr(spc + 1, colon_idx - spc - 1 + 3)
                        var after: String = loc.substr(colon_idx + 4).strip_edges()
                        var spc2: int = after.find(" ")
                        var num_str: String = after.substr(0, spc2 if spc2 >= 0 else after.length())
                        lineno = int(num_str)
                        snippet += "  →  " + loc.strip_edges()
                    break
            var iss := Issue.new()
            iss.file = file
            iss.line = lineno
            iss.code = code
            iss.snippet = snippet
            iss.hint = hint
            issues.append(iss)
        i += 1
    return issues


func _strip_prefix(s: String, prefixes: Array) -> String:
    for p in prefixes:
        if s.begins_with(p):
            return s.substr(p.length()).strip_edges()
    return s.strip_edges()


## 把错误描述归类到已知类型（其他归 OTHER）
func _classify(desc: String) -> String:
    if desc.find("Narrowing conversion") >= 0:
        return "NARROWING_CONVERSION"
    if desc.find("shadowing an already-declared property") >= 0:
        return "SHADOWED_VARIABLE_BASE_CLASS"
    if desc.find("UNUSED") >= 0:
        return "UNUSED_VARIABLE_OR_PARAMETER"
    if desc.find("Could not infer the type") >= 0 or desc.find("INFERENCE_ON_VARIANT") >= 0:
        return "INFERENCE_ON_VARIANT"
    if desc.find("Parse Error") >= 0 or desc.find("Parse error") >= 0:
        return "PARSE_ERROR"
    if desc.find("Not declared in the base class") >= 0:
        return "UNDECLARED_PROPERTY"
    if desc.find("Function") >= 0 and desc.find("not found") >= 0:
        return "FUNCTION_NOT_FOUND"
    return "OTHER"


## 给每类错误出修复建议（贴报告时给用户/AI 看）
func _hint_for(code: String, desc: String) -> String:
    match code:
        "NARROWING_CONVERSION":
            return "float → int 会丢精度。建议加显式转换：int(x) / round(x) / roundi(x) / floor(x) / ceil(x)。"
        "SHADOWED_VARIABLE_BASE_CLASS":
            return "参数名遮蔽了 Node 基类属性（常用冲突名：name/class/script/process_mode 等）。建议改名为 _name / p_name 等加前缀形式。"
        "UNUSED_VARIABLE_OR_PARAMETER":
            return "未使用的变量/参数。建议删除，或加 _ 前缀（GDScript 工具会忽略 _ 开头的未使用变量）。"
        "INFERENCE_ON_VARIANT":
            return "类型推断失败（变量是 Variant）。建议显式标类型，如 `var x: int = ...`。"
        "PARSE_ERROR":
            return "解析错误：脚本有语法问题，请检查对应行。"
        "UNDECLARED_PROPERTY":
            return "访问了未声明的属性。请检查拼写或是否在父类中存在。"
        "FUNCTION_NOT_FOUND":
            return "调用了不存在的函数。请检查函数名拼写或参数签名。"
        _:
            return "无内置建议。参考原文搜索 GDScript 文档。"


# ---------------- 输出报告 ----------------

## 把 issues 渲染成 Markdown 报告（按文件分组 + 类型汇总 + 修复建议）
func _render_report(issues: Array) -> String:
    var md := "# GDScript 调试器错误/警告报告\n\n"
    md += "生成时间: %s\n\n" % Time.get_datetime_string_from_system(true)

    # 类型汇总
    var type_count: Dictionary = {}
    var file_count: Dictionary = {}
    for iss in issues:
        type_count[iss.code] = type_count.get(iss.code, 0) + 1
        if iss.file != "":
            file_count[iss.file] = file_count.get(iss.file, 0) + 1

    md += "## 总览\n\n"
    md += "- 错误/警告总数: **%d**\n" % issues.size()
    md += "- 涉及文件数: %d\n" % file_count.size()
    md += "- 类型分布:\n"
    for t in type_count:
        md += "  - `%s`: %d\n" % [t, type_count[t]]
    md += "\n"

    # 按文件分组
    var by_file: Dictionary = {}
    for iss in issues:
        var k: String = iss.file if iss.file != "" else "(unknown)"
        if not by_file.has(k):
            by_file[k] = []
        by_file[k].append(iss)

    md += "## 按文件分组\n\n"
    var keys: Array = by_file.keys()
    keys.sort()
    for f in keys:
        md += "### `%s` (%d 处)\n\n" % [f, by_file[f].size()]
        for iss in by_file[f]:
            md += "- **第 %d 行** `%s`\n" % [iss.line, iss.code]
            md += "  - 原文: %s\n" % iss.snippet
            md += "  - 建议: %s\n" % iss.hint
        md += "\n"

    # 修复总览（按类型聚合建议）
    md += "## 修复建议汇总\n\n"
    var seen_codes: Dictionary = {}
    for iss in issues:
        if seen_codes.has(iss.code):
            continue
        seen_codes[iss.code] = true
        md += "- **`%s`**: %s\n" % [iss.code, iss.hint]
    md += "\n"

    md += "---\n*由 debug_exporter 插件自动生成 · 复制给 AI 时直接整段贴上即可*\n"
    return md


# ---------------- 菜单执行 ----------------

func _copy_report() -> void:
    var issues: Array = parse_issues()
    if issues.is_empty():
        _popup("日志中没有 GDScript 错误/警告（解析了最近 %d 行）。如需触发，请在 Godot 中打开有问题的脚本让解析器跑一次。" % MAX_LINES)
        return
    var md: String = _render_report(issues)
    DisplayServer.clipboard_set(md)
    var msg := "已复制 %d 条错误/警告到剪贴板（Markdown 格式）→ 直接 Ctrl+V 粘贴给 AI / 存档" % issues.size()
    print("[debug_exporter] " + msg)
    _popup(msg)


func _export_report() -> void:
    var issues: Array = parse_issues()
    if issues.is_empty():
        _popup("日志中没有 GDScript 错误/警告（解析了最近 %d 行）。" % MAX_LINES)
        return

    # 导出目录 res://debug_logs/（globalize 后是项目根目录下的 debug_logs/）
    var project_root: String = ProjectSettings.globalize_path("res://")
    var out_dir: String = project_root.path_join("debug_logs")
    DirAccess.make_dir_recursive_absolute(out_dir)

    var stamp: String = Time.get_datetime_string_from_system(true).replace(":", "-")
    var out_path: String = out_dir.path_join("errors_report_%s.md" % stamp)

    var md: String = _render_report(issues)
    var out := FileAccess.open(out_path, FileAccess.WRITE)
    if out == null:
        _popup("写入失败：" + out_path)
        return
    out.store_string(md)
    out.close()

    var msg := "已导出 %d 条错误到 → %s\n（%d 个文件涉及）" % [issues.size(), out_path, _count_files(issues)]
    print("[debug_exporter] " + msg)
    _popup(msg)


func _count_files(issues: Array) -> int:
    var files: Dictionary = {}
    for iss in issues:
        if iss.file != "":
            files[iss.file] = true
    return files.size()


func _popup(msg: String) -> void:
    var ei := Engine.get_singleton("EditorInterface")
    if ei != null and ei.has_method("get_editor_toaster"):
        var toaster: Object = ei.call("get_editor_toaster")
        if toaster != null and toaster.has_method("popup_text"):
            toaster.call("popup_text", msg)