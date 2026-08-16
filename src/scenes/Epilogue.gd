# 《梦境逐影》结局剧情场景（花海 · 三段式 Galgame 演出）
# 流程：第3层Boss击败 -> Epilogue(花海背景 + 三段对话) -> Game(通关状态，两选项)
# 三段式（v4.0 §5.4）：①灵魂融合（旁白）②花海重逢（粉丝清醒版 zhujue_happy + 弥绘）③生日蛋糕反转。
extends Control

## 完成后回到主玩法场景，由 GameManager.game_completed 标志判定为「通关」状态。
const NEXT_SCENE := "res://src/scenes/Game.tscn"

# 演出立绘
const MOMO_HAPPY := preload("res://assets/Live2d/momo/momo_happy.png")
const MOMO_PITY := preload("res://assets/Live2d/momo/momo_pity.png")
const MOMO_MOVE := preload("res://assets/Live2d/momo/momo_move.png")
const ZHUJUE_HAPPY := preload("res://assets/Live2d/zhujue/zhujue_happy.png")

var _finished := false


func _ready() -> void:
	# 重置视口相机变换：从 Game 跳过来时，Game 每帧写的 viewport.canvas_transform（缩放跟随）
	# 会残留，导致花海背景/对话框被错误缩放（画面黑屏或错位）。change_scene 不会自动重置。
	get_viewport().set_canvas_transform(Transform2D.IDENTITY)
	# 延迟半拍让花海背景先呈现，再起对话
	var dlg := GalgameDialog.new()
	add_child(dlg)
	dlg.play(_build_lines(), func() -> void:
		if _finished:
			return
		_finished = true
		get_tree().change_scene_to_file(NEXT_SCENE))


func _build_lines() -> Array[Dictionary]:
	return [
		# —— 第一段 · 灵魂融合 ——
		{ "name": "旁白", "narration": true, "text": "击败老板的瞬间，一道金色光柱从房间中央升起，灵魂坠入弥绘口袋里的本体。" },
		{ "name": "旁白", "narration": true, "text": "世界开始崩解成白色碎片——碎片落地生根，长成了花。" },
		# —— 第二段 · 花海重逢 ——
		{ "name": "粉丝", "role": "zhujue", "text": "……这、这里是哪里？我好像……做了一个很长的噩梦……", "portrait_right": ZHUJUE_HAPPY },
		{ "name": "弥绘", "role": "momo", "text": "冷静点，已经没事了。你的负能量在梦里爆发，把灵魂卷进了最深处——我一路追到核心，把噩梦清干净了。现在，你已经全都安全了。", "portrait_left": MOMO_MOVE, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "粉丝", "role": "zhujue", "text": "你是…… momo？！那个、那个我一直看你直播的……", "portrait_left": MOMO_MOVE, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "弥绘", "role": "momo", "text": "是我呀。我可是每天都会看到你的弹幕。", "portrait_left": MOMO_HAPPY, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "粉丝", "role": "zhujue", "text": "……谢谢。真的，谢谢你。这段时间我压力太大了……如果不是你，我可能真的要被困在那种梦里了。", "portrait_left": MOMO_HAPPY, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "弥绘", "role": "momo", "text": "说什么谢呀。看你每天那么累，我哪能坐视不管。", "portrait_left": MOMO_HAPPY, "portrait_right": ZHUJUE_HAPPY },
		# —— 第三段 · 生日蛋糕（反转：是弥绘的生日） ——
		{ "name": "粉丝", "role": "zhujue", "text": "啊，差点忘了——今天……今天是你的生日吧？", "portrait_left": MOMO_HAPPY, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "弥绘", "role": "momo", "text": "哎？我……我没跟你说过啊……", "portrait_left": MOMO_PITY, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "粉丝", "role": "zhujue", "text": "你直播的时候说过一次，『生日那天会早点下播』。我一直记得。这是……我一直没机会送的礼物。在你给我救回来的梦里，终于能送出去了。", "portrait_left": MOMO_PITY, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "弥绘", "role": "momo", "text": "……你还记得这种小事啊。", "portrait_left": MOMO_MOVE, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "粉丝", "role": "zhujue", "text": "祝你生日快乐——祝你生日快乐——", "portrait_left": MOMO_MOVE, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "弥绘", "role": "momo", "text": "……谢谢你。这是我最棒的生日礼物。", "portrait_left": MOMO_MOVE, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "弥绘", "role": "momo", "text": "以后压力大的时候，别硬撑——我还会来找你的。把噩梦一口吃掉，给你留一屋子好梦。", "portrait_left": MOMO_MOVE, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "弥绘", "role": "momo", "text": "那我许愿——希望我所有的粉丝，都能睡个好觉、做个好梦。", "portrait_left": MOMO_MOVE, "portrait_right": ZHUJUE_HAPPY },
		{ "name": "旁白", "narration": true, "text": "花瓣随风飘起，两人在花海里相视而笑……画面渐黑。" },
		# —— 谢幕字卡（v4.0 §5.4）——
		{ "name": "旁白", "narration": true, "text": "献给弥绘 · 以及所有在深夜里努力生活的人。愿你们的梦里，都有好梦。" },
	]
