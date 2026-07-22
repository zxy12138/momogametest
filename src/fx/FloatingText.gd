# 伤害 / 暴击飘字（世界坐标）
extends Node2D

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	_label.position = Vector2(-40, -10)
	_label.size = Vector2(80, 20)
	# 不受世界缩放影响，保持清晰
	_label.scale = Vector2(1, 1)


func popup(text: String, color: Color, big: bool) -> void:
	_label.text = text
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_font_size_override("font_size", 20 if big else 13)
	var base_scale := 1.9 if big else 1.2
	_label.scale = Vector2(base_scale, base_scale)
	var t := get_tree().create_tween()
	t.tween_property(self, "position", position + Vector2(0, -34), 0.8)
	t.parallel().tween_property(_label, "modulate:a", 0.0, 0.8)
	t.tween_callback(queue_free).set_delay(0.8)
