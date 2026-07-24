# 弹射物：玩家/敌人通用。from_player 决定碰撞层与命中逻辑。
extends Area2D
class_name Projectile

var direction := Vector2.RIGHT
var speed := 300.0
var damage := 10
var is_crit := false
var pierce := 0
var bounce := 0
var aoe := 0.0
var from_player := true
var effects := ""
var effect_time := 0.0
var homing := false
var texture_path := ""
var _life := 3.0
var _hit := []   # 已命中敌人，避免穿透重复结算


func _ready() -> void:
	if texture_path != "":
		var sp := get_node("Sprite")
		sp.texture = GameManager.load_tex(texture_path)
	# 碰撞层配置
	if from_player:
		collision_layer = 8      # 玩家弹（layer 4）
		collision_mask = 2 + 16   # 敌人 + 墙
	else:
		collision_layer = 8      # 敌弹（同 layer 4，靠 mask 区分）
		collision_mask = 1 + 16   # 玩家 + 墙
	connect("body_entered", _on_body_entered)
	add_to_group("projectile")


func _physics_process(delta: float) -> void:
	if homing and not from_player:
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p != null:
			var to := (p.global_position - global_position).normalized()
			direction = direction.lerp(to, 0.06).normalized()
	global_position += direction * speed * delta
	rotation = direction.angle() if not from_player else 0.0
	_life -= delta
	if _life <= 0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("wall"):
		_hit_wall()
		return
	if from_player:
		if body.is_in_group("enemy"):
			_hit_enemy(body)
	else:
		if body.is_in_group("player"):
			GameManager.damage_player(damage)
			_impact(global_position)
			queue_free()


func _hit_enemy(body: Node) -> void:
	if body in _hit:
		return
	_hit.append(body)
	var en := body as Node2D
	if en == null:
		return
	en.call("take_damage", damage, is_crit, effects, effect_time)
	if aoe > 0:
		_aoe_at(en.global_position)
	if pierce > 0:
		pierce -= 1
		return
	_impact(global_position)


func _aoe_at(pos: Vector2) -> void:
	GameManager.fx("res://assets/fx/FX-015_hammer_slam_shockwave.png", pos, 64, 16, 5, 0.4)
	var space := get_world_2d().direct_space_state
	for en in get_tree().get_nodes_in_group("enemy"):
		var e := en as Node2D
		if e == null or not e.has_method("take_damage"):
			continue
		if e.global_position.distance_to(pos) <= aoe:
			e.call("take_damage", int(damage * 0.6), false, effects, effect_time)


func _hit_wall() -> void:
	if bounce > 0:
		bounce -= 1
		# 简易反射：反转主轴
		if abs(direction.x) >= abs(direction.y):
			direction.x = -direction.x
		else:
			direction.y = -direction.y
		GameManager.fx("res://assets/fx/FX-015_hammer_slam_shockwave.png", global_position, 64, 16, 5, 0.25)
	else:
		_impact(global_position)


func _impact(pos: Vector2) -> void:
	if aoe > 0 or is_crit:
		GameManager.fx("res://assets/fx/FX-010_staff_attack_explosion.png", pos, 32, 32, 6, 0.4)
	queue_free()
