# 临时无头测试：复现「ESC→暂停→重新开始→无法操作」并断言输入已解锁。
# 平时无害：仅当命令行带 --run-restart-test 时才执行；正常开编辑器不触发。
# 验证后如不需要，可删除本文件并移除 project.godot [autoload] 里的 RestartTest 一行。
extends Node

func _ready() -> void:
	if not _should_run():
		return
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://src/scenes/Game.tscn")
	for i in 40:
		await get_tree().process_frame
		var sc := get_tree().current_scene
		if sc != null and sc.has_method("transition_to"):
			_run_test(sc)
			return
	printerr("RESTART_TEST: Game scene did not become current")
	get_tree().quit(2)


func _should_run() -> bool:
	for a in OS.get_cmdline_args():
		if a == "--run-restart-test":
			return true
	return false


func _run_test(game: Node) -> void:
	# 1) 模拟按 ESC 开暂停（会把 input_locked 锁成 true）
	game.call("_open_pause")
	var locked_after_pause: bool = GameManager.input_locked
	# 2) 模拟点「重新开始」按钮（调用 _restart_game）
	game.call("_restart_game")
	var locked_after_restart: bool = GameManager.input_locked
	# 3) 等场景真正切回新的 Game（change_scene_to_file 是异步的）
	await get_tree().process_frame
	await get_tree().process_frame
	var locked_after_swap: bool = GameManager.input_locked

	var ok := locked_after_pause and (not locked_after_restart) and (not locked_after_swap)
	print("RESTART_TEST locked_after_pause=", locked_after_pause,
		" locked_after_restart=", locked_after_restart,
		" locked_after_swap=", locked_after_swap, " => ", ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
