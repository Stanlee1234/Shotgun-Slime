extends CharacterBody2D

signal shot_fired
signal reloaded

@export var speed: float = 300.0
@export var jump_velocity: float = -400.0
@export var ground_friction: float = 1400.0
@export var shotgun_power: float = 600.0
@export var max_shells: int = 1
@export var fire_cooldown: float = 0.14
@export var wall_bounciness: float = 0.7 # 1.0 = full bounce, 0.5 = half speed

@onready var player: AnimatedSprite2D = $PlayerSprite

var gravity: float = 1000
var shells: int = 1
var _cooldown_timer: float = 0.0
var _was_on_floor: bool = true
var _just_fired: bool = false


func _ready() -> void:
	shells = max_shells


func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	var mouse_pos = get_global_mouse_position()
	
	# Reload shells upon landing or while standing on the floor
	if not _was_on_floor and is_on_floor():
		if shells < max_shells:
			shells = max_shells
			reloaded.emit()
	elif is_on_floor() and shells < max_shells and _cooldown_timer <= 0.0:
		shells = max_shells
		reloaded.emit()
	_was_on_floor = is_on_floor()

	if not is_on_floor():
		velocity.y += gravity * delta

	if mouse_pos.x > global_position.x:
		update_facing_direction(1)
	else:
		update_facing_direction(-1)

	if is_on_floor() and not _just_fired:
		velocity.x = move_toward(velocity.x, 0, ground_friction * delta)

	if Input.is_action_just_pressed("shoot"):
		shoot()

	_just_fired = false
	
	# 1. Store velocity before move_and_slide() zeroes out wall impacts
	var pre_slide_velocity := velocity
	move_and_slide()

	# 2. Reflect horizontal velocity if we hit a wall
	if is_on_wall():
		var wall_normal := get_wall_normal()
		# Ensure we are actually moving into the wall before bouncing
		if signf(pre_slide_velocity.x) != signf(wall_normal.x):
			velocity.x = -pre_slide_velocity.x * wall_bounciness


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
