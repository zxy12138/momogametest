# 拾取物：经验球 / 梦晶
extends Area2D
class_name Pickup

var kind := "xp"     # "xp" | "crystal"
var value := 10

func _ready() -> void:
	var sp := get_node("Sprite")
	if kind == "xp":
		sp.texture = GameManager.load_tex("res://assets/fx/FX-021_exp_orb.png")
	else:
		sp.texture = GameManager.load_tex("res://assets/fx/FX-022_dream_crystal_currency.png")
	connect("body_entered", _on_body_entered)
	add_to_group("pickup")
	# 轻微漂浮动画
	var t := get_tree().create_tween()
	t.set_loops(3)
	t.tween_property(self, "position:y", position.y - 3, 0.5)
	t.chain().tween_property(self, "position:y", position.y, 0.5)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if kind == "xp":
		GameManager.add_xp(value)
	else:
		GameManager.add_crystals(value)
	queue_free()
