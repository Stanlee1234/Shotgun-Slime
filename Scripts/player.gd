extends CharacterBody2D

signal shot_fired
signal reloaded

const SpentShellScript := preload("res://Scripts/spent_shell.gd")
const MAX_SPENT_SHELLS := 65

@export var speed: float = 300.0
@export var jump_velocity: float = -400.0
@export var ground_friction: float = 1400.0
@export var shotgun_power: float = 600.0
@export var max_shells: int = 1
@export var fire_cooldown: float = 0.14
@export var wall_bounciness: float = 0.7 # 1.0 = full bounce, 0.5 = half speed
@export var floor_bounciness: float = 0.35
@export var min_bounce_speed: float = 180.0
@export var slope_angle_threshold: float = 0.05 # radians (~2.9 deg)
@export var reload_stop_speed: float = 15.0
@export var reload_stop_delay: float = 0.08
@export var air_spin_factor: float = 0.025
@export var slope_roll_factor: float = 0.04
@export var upright_speed: float = 14.0

@onready var player: AnimatedSprite2D = $PlayerSprite

var gravity: float = 1000
var shells: int = 1
var angular_velocity: float = 0.0
var _cooldown_timer: float = 0.0
var _stop_timer: float = 0.0
var _just_fired: bool = false


func _ready() -> void:
	shells = max_shells


func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	var mouse_pos := get_global_mouse_position()

	if Input.is_action_just_pressed("shoot"):
		shoot()

	var on_floor := is_on_floor()
	var on_slope := on_floor and get_floor_angle() >= slope_angle_threshold

	# Apply gravity in the air and on slopes so slopes accelerate the player downhill.
	if not on_floor or on_slope:
		velocity.y += gravity * delta

	if mouse_pos.x > global_position.x:
		update_facing_direction(1)
	else:
		update_facing_direction(-1)

	# Only apply ground friction on flat surfaces so slopes stay frictionless.
	if on_floor and not on_slope and not _just_fired:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)

	# Disable floor snapping when firing or moving upward so shots launch cleanly off slopes.
	var saved_snap := floor_snap_length
	if _just_fired or velocity.y < 0.0:
		floor_snap_length = 0.0

	var pre_slide_velocity := velocity
	move_and_slide()
	floor_snap_length = saved_snap
	_just_fired = false

	# Reflect off walls, ceilings, and hard floor/slope impacts like a ragdoll,
	# while preventing horizontal/upward momentum from climbing up slopes.
	var best_collision: KinematicCollision2D = null
	var best_impact: float = min_bounce_speed
	var hit_uphill_slope := false
	var uphill_slope_normal := Vector2.ZERO

	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if n.y < -0.05 and absf(n.x) >= slope_angle_threshold:
			var downhill := Vector2(signf(n.x) * -n.y, absf(n.x)).normalized()
			if pre_slide_velocity.dot(downhill) < 0.0:
				hit_uphill_slope = true
				uphill_slope_normal = n
				continue
		var impact := -pre_slide_velocity.dot(n)
		if impact > best_impact:
			best_impact = impact
			best_collision = col

	if hit_uphill_slope:
		var n := uphill_slope_normal
		var downhill := Vector2(signf(n.x) * -n.y, absf(n.x)).normalized()
		if absf(pre_slide_velocity.x) > min_bounce_speed:
			velocity.x = signf(n.x) * absf(pre_slide_velocity.x) * wall_bounciness
			velocity.y = minf(pre_slide_velocity.y, 0.0) * 0.5
			angular_velocity = clampf(velocity.x * air_spin_factor, -18.0, 18.0)
		else:
			var uphill_speed := -velocity.dot(downhill)
			if uphill_speed > 0.0:
				velocity += downhill * uphill_speed
	elif best_collision != null:
		var normal := best_collision.get_normal()
		var bounciness := floor_bounciness if normal.y < -0.5 else wall_bounciness
		velocity = pre_slide_velocity.bounce(normal) * bounciness
		angular_velocity = clampf((velocity.x - velocity.y * 0.25 * normal.x) * air_spin_factor, -18.0, 18.0)

	# Reload only once the player comes to rest on a surface (not while flying or sliding).
	var post_on_floor := is_on_floor()
	var is_stopped := post_on_floor and velocity.length() <= reload_stop_speed

	if is_stopped and _cooldown_timer <= 0.0:
		_stop_timer += delta
		if _stop_timer >= reload_stop_delay and shells < max_shells:
			shells = max_shells
			reloaded.emit()
	else:
		_stop_timer = 0.0

	# Tumble in the air, roll along slides/slopes, and upright when stopped.
	if is_stopped:
		angular_velocity = 0.0
		player.rotation = lerp_angle(player.rotation, 0.0, upright_speed * delta)
	elif post_on_floor:
		angular_velocity = velocity.x * slope_roll_factor
		player.rotation += angular_velocity * delta
	else:
		player.rotation += angular_velocity * delta


func update_facing_direction(direction: float) -> void:
	if direction > 0:
		player.scale.x = 1
	elif direction < 0:
		player.scale.x = -1


func can_shoot() -> bool:
	return _cooldown_timer <= 0.0 and shells > 0


func shoot() -> void:
	if not can_shoot():
		return

	var rot := get_global_mouse_position() - global_position
	if rot.length_squared() < 0.001:
		rot = Vector2.RIGHT
	var rot_z := atan2(rot.y, rot.x)

	shells -= 1
	_cooldown_timer = fire_cooldown
	_stop_timer = 0.0
	_just_fired = true
	shot_fired.emit()

	var sx := -signf(rot.x) if absf(rot.x) > 0.001 else 0.0
	var sy := -signf(rot.y) if absf(rot.y) > 0.001 else 0.0
	var new_vel := Vector2(
		0.75 * sx * absf(shotgun_power * cos(rot_z)),
		sy * absf(shotgun_power * sin(rot_z))
	)

	if is_on_floor() and new_vel.y > -70.0:
		new_vel.y = minf(new_vel.y, -80.0)

	velocity = new_vel
	angular_velocity = clampf(new_vel.x * air_spin_factor, -18.0, 18.0)
	_eject_spent_shell(Vector2(cos(rot_z), sin(rot_z)))


func _eject_spent_shell(aim_dir: Vector2) -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return

	var existing := get_tree().get_nodes_in_group("spent_shells")
	if existing.size() >= MAX_SPENT_SHELLS:
		var oldest := existing[0]
		if is_instance_valid(oldest):
			oldest.queue_free()

	var shell := SpentShellScript.new()
	shell.add_to_group("spent_shells")
	shell.add_collision_exception_with(self)

	var gun_node := get_node_or_null("Gun") as Node2D
	var origin := gun_node.global_position if gun_node != null else global_position
	shell.global_position = origin + aim_dir * 18.0 + Vector2(0.0, -3.0)

	var eject_x := -signf(aim_dir.x) if absf(aim_dir.x) > 0.2 else randf_range(-1.0, 1.0)
	shell.linear_velocity = Vector2(
		eject_x * randf_range(45.0, 95.0) + velocity.x * 0.15,
		randf_range(-155.0, -95.0)
	)
	shell.angular_velocity = randf_range(-14.0, 14.0)
	parent_node.add_child(shell)
