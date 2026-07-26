## 拾取物：经验球 / 梦晶。
## 掉落 HOMING_DELAY 秒后进入「磁吸」状态，自动飞向玩家并被拾取；
## 玩家也可直接走上去（Area2D 重叠）提前拾取。向上通信一律走 GameManager，不向下 get_parent。
extends Area2D
class_name Pickup

@export var homing_delay: float = 2.0    ## 掉落后多久开始飞向玩家（秒）
@export var homing_speed: float = 420.0  ## 磁吸飞行速度（像素/秒）
const PICKUP_RADIUS: float = 14.0        ## 距玩家多近算拾取成功

var kind: String = "xp"     # "xp" | "crystal"
var value: int = 10

var _homing: bool = false
var _player: Node2D = null
var _float_tween: Tween = null
var _homing_timer: SceneTreeTimer = null

func _ready() -> void:
	var sp := get_node("Sprite") as Sprite2D
	if kind == "xp":
		sp.texture = GameManager.load_tex("res://assets/fx/FX-021_exp_orb.png")
	else:
		sp.texture = GameManager.load_tex("res://assets/fx/FX-022_dream_crystal_currency.png")
	body_entered.connect(_on_body_entered)
	add_to_group("pickup")
	# 落地轻微漂浮动画（磁吸启动前）
	_float_tween = get_tree().create_tween()
	_float_tween.set_loops(3)
	_float_tween.tween_property(self, "position:y", position.y - 3.0, 0.5)
	_float_tween.chain().tween_property(self, "position:y", position.y, 0.5)
	# 延迟后进入磁吸
	_homing_timer = get_tree().create_timer(homing_delay)
	_homing_timer.timeout.connect(_start_homing)

func _start_homing() -> void:
	if _homing or is_queued_for_deletion():
		return
	if is_instance_valid(_float_tween):
		_float_tween.kill()
	_homing = true
	_player = get_tree().get_first_node_in_group("player") as Node2D

func _process(delta: float) -> void:
	if not _homing or not is_instance_valid(_player):
		return
	global_position = global_position.move_toward(_player.global_position, homing_speed * delta)
	if global_position.distance_to(_player.global_position) <= PICKUP_RADIUS:
		_collect()

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_collect()

func _collect() -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(_homing_timer) and _homing_timer.is_connected("timeout", _start_homing):
		_homing_timer.timeout.disconnect(_start_homing)
		_homing_timer = null
	if is_instance_valid(_float_tween):
		_float_tween.kill()
		_float_tween = null
	if kind == "xp":
		GameManager.add_xp(value)
	else:
		GameManager.add_crystals(value)
	queue_free()
