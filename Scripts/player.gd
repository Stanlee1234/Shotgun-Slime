extends CharacterBody2D

signal shot_fired
signal reloaded
signal impacted(strength: float)

const SpentShellScene := preload("res://Scenes/spent_shell.tscn")
const SOFT_BODY_NODE_RADIUS := 3.5

@export var speed: float = 300.0
@export var jump_velocity: float = -400.0
@export var ground_friction: float = 950.0
@export var shotgun_power: float = 700.0
@export var max_shells: int = 1
@export var fire_cooldown: float = 0.14
@export var min_bounce_speed: float = 180.0
@export var hard_landing_speed: float = 680.0
@export var min_impact_trauma: float = 0.22
@export var max_impact_trauma: float = 1.0
@export var slope_angle_threshold: float = 0.05
@export var reload_stop_speed: float = 20.0
@export var reload_stop_delay: float = 0.08
@export var blob_restore_stiffness: float = 280.0
@export var blob_restore_damping: float = 8.0
@export var blob_linear_damp: float = 0.6
@export var max_fall_speed: float = 850.0

@onready var soft_body: SoftBody2D = $SoftBody2D

var shells: int = 1
var _cooldown_timer: float = 0.0
var _stop_timer: float = 0.0
var _just_fired: bool = false
var _soft_body_nodes: Array[Dictionary] = []
var _prev_velocity: Vector2 = Vector2.ZERO
var _is_grounded: bool = false
var _peak_fall_speed: float = 0.0
var _impact_cooldown: float = 0.0


func _ready() -> void:
	shells = max_shells
	collision_layer = 0
	collision_mask = 0
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		col.disabled = true
	_setup_soft_body()


func _setup_soft_body() -> void:
	if soft_body == null:
		return

	var bodies := soft_body.get_rigid_bodies()
	if bodies.is_empty():
		return

	var initial_center := _compute_average_position(bodies)
	for child in bodies:
		var rb: RigidBody2D = child.rigidbody
		var gpos := rb.global_position
		# Keep SoftBody2D/Skeleton2D parented to Player to prevent offscreen culling while simulating RigidBody2Ds in world space.
		rb.top_level = true
		rb.global_position = gpos
		rb.linear_damp = blob_linear_damp
		rb.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
		rb.contact_monitor = true
		rb.max_contacts_reported = 4
		rb.add_collision_exception_with(self)
		_soft_body_nodes.append({
			"body": rb,
			"offset": gpos - initial_center,
			"prev_pos": gpos,
		})

	global_position = initial_center


func _compute_average_position(bodies: Array) -> Vector2:
	var sum := Vector2.ZERO
	for child in bodies:
		sum += child.rigidbody.global_position
	return sum / float(bodies.size())


func _process(_delta: float) -> void:
	if _soft_body_nodes.is_empty():
		return
	var sum_pos := Vector2.ZERO
	var count := 0
	for entry in _soft_body_nodes:
		var rb: RigidBody2D = entry["body"]
		if is_instance_valid(rb):
			sum_pos += rb.global_position
			count += 1
	if count > 0:
		global_position = sum_pos / float(count)


func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)

	if Input.is_action_just_pressed("shoot") and not _is_mouse_over_blocking_ui():
		shoot()

	if _soft_body_nodes.is_empty():
		return

	var count := 0
	var sum_pos := Vector2.ZERO
	var sum_vel := Vector2.ZERO
	var any_contact := false
	var on_floor := false
	var on_slope := false
	var min_floor_normal_y := -cos(floor_max_angle)
	var space_state := get_world_2d().direct_space_state

	for entry in _soft_body_nodes:
		var rb: RigidBody2D = entry["body"]
		if not is_instance_valid(rb):
			continue

		var clamped_hit := _depenetrate_soft_body_node(rb, entry["prev_pos"] as Vector2, space_state)
		if clamped_hit.has("normal"):
			any_contact = true
			var hn: Vector2 = clamped_hit["normal"]
			if hn.y <= min_floor_normal_y:
				on_floor = true
				if absf(hn.x) >= slope_angle_threshold:
					on_slope = true

		sum_pos += rb.global_position
		sum_vel += rb.linear_velocity
		count += 1

		var state := PhysicsServer2D.body_get_direct_state(rb.get_rid())
		if state != null:
			for c_idx in range(state.get_contact_count()):
				any_contact = true
				var n := state.get_contact_local_normal(c_idx)
				if n.y <= min_floor_normal_y:
					on_floor = true
					if absf(n.x) >= slope_angle_threshold:
						on_slope = true

	if count == 0:
		return

	var center_pos := sum_pos / float(count)
	var avg_vel := sum_vel / float(count)
	global_position = center_pos
	velocity = avg_vel
	_is_grounded = on_floor

	if not on_floor:
		_peak_fall_speed = maxf(_peak_fall_speed, avg_vel.y)

	# Detect high-speed collisions or heavy landings on the softbody for screen shake.
	if any_contact and not _just_fired and _impact_cooldown <= 0.0:
		var delta_v := (avg_vel - _prev_velocity).length()
		var fall_arrest := (_peak_fall_speed - maxf(avg_vel.y, 0.0)) if on_floor else 0.0
		if delta_v > min_bounce_speed or fall_arrest > min_bounce_speed:
			var impact_speed := maxf(delta_v, _peak_fall_speed if fall_arrest > min_bounce_speed else 0.0)
			var weight := clampf(inverse_lerp(min_bounce_speed, hard_landing_speed, impact_speed), 0.0, 1.0)
			impacted.emit(lerpf(min_impact_trauma, max_impact_trauma, weight))
			_peak_fall_speed = 0.0
			_impact_cooldown = 0.15
	elif on_floor and avg_vel.y <= reload_stop_speed:
		_peak_fall_speed = 0.0

	# Gentle upright jelly shape restoration + horizontal settle friction on flat floors.
	var fire_damping := 0.25 if _just_fired else 1.0
	for entry in _soft_body_nodes:
		var rb: RigidBody2D = entry["body"]
		if not is_instance_valid(rb):
			continue
		var target_pos: Vector2 = center_pos + (entry["offset"] as Vector2)
		var restore_force: Vector2 = (target_pos - rb.global_position) * (blob_restore_stiffness * fire_damping) - (rb.linear_velocity - avg_vel) * blob_restore_damping
		rb.apply_central_force(restore_force)

		if on_floor and not on_slope and not _just_fired:
			var next_vx := move_toward(rb.linear_velocity.x, 0.0, ground_friction * delta)
			rb.linear_velocity.x = next_vx
		if rb.linear_velocity.y > max_fall_speed:
			rb.linear_velocity.y = max_fall_speed

	_just_fired = false
	_prev_velocity = avg_vel
	for entry in _soft_body_nodes:
		var rb: RigidBody2D = entry["body"]
		if is_instance_valid(rb):
			entry["prev_pos"] = rb.global_position

	# Reload only once the slime comes to rest on a floor/surface.
	var is_stopped := on_floor and avg_vel.length() <= reload_stop_speed
	if is_stopped and _cooldown_timer <= 0.0:
		_stop_timer += delta
		if _stop_timer >= reload_stop_delay and shells < max_shells:
			shells = max_shells
			reloaded.emit()
	else:
		_stop_timer = 0.0


func can_shoot() -> bool:
	return _cooldown_timer <= 0.0 and shells > 0


func _is_mouse_over_blocking_ui() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var hovered := viewport.gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter == Control.MOUSE_FILTER_STOP


func _depenetrate_soft_body_node(rb: RigidBody2D, prev_pos: Vector2, space_state: PhysicsDirectSpaceState2D) -> Dictionary:
	if space_state == null:
		return {}
	var delta_vec := rb.global_position - prev_pos
	var move_len := delta_vec.length()
	if move_len <= 0.5 or move_len > 64.0:
		return {}

	var move_dir := delta_vec / move_len
	var ray_end := rb.global_position + move_dir * SOFT_BODY_NODE_RADIUS
	var query := PhysicsRayQueryParameters2D.create(prev_pos, ray_end, 1)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return {}

	var hit_pos: Vector2 = hit["position"]
	var hit_normal: Vector2 = hit["normal"]
	# Only depenetrate when moving into the surface and overlapping past circle radius.
	var signed_dist := (rb.global_position - hit_pos).dot(hit_normal)
	if signed_dist < SOFT_BODY_NODE_RADIUS and delta_vec.dot(hit_normal) < 0.0:
		var safe_pos := hit_pos + hit_normal * SOFT_BODY_NODE_RADIUS
		rb.global_position = safe_pos
		PhysicsServer2D.body_set_state(rb.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, safe_pos))
		var vn := rb.linear_velocity.dot(hit_normal)
		if vn < 0.0:
			var bounce_factor := rb.physics_material_override.bounce if rb.physics_material_override else 0.2
			rb.linear_velocity -= hit_normal * (vn * (1.0 + bounce_factor))
			PhysicsServer2D.body_set_state(rb.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, rb.linear_velocity)
		return hit
	return {}


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

	if _is_grounded and new_vel.y > -70.0:
		new_vel.y = minf(new_vel.y, -80.0)

	velocity = new_vel
	_prev_velocity = new_vel

	var launch_dir := new_vel.normalized() if new_vel.length_squared() > 0.01 else Vector2.UP
	for entry in _soft_body_nodes:
		var rb: RigidBody2D = entry["body"]
		if not is_instance_valid(rb):
			continue
		var offset: Vector2 = entry["offset"]
		# Give the front side slightly more velocity than the tail so the slime stretches on launch.
		var stretch_factor := 1.0 + clampf(offset.dot(launch_dir) * 0.015, -0.15, 0.15)
		var rb_vel := new_vel * stretch_factor
		rb.linear_velocity = rb_vel
		PhysicsServer2D.body_set_state(rb.get_rid(), PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, rb_vel)

	var aim_dir := Vector2(cos(rot_z), sin(rot_z))
	var gun_node := get_node_or_null("Gun")
	if gun_node != null and gun_node.has_method("spawn_shot_particles"):
		gun_node.spawn_shot_particles(aim_dir)
	_eject_spent_shell(aim_dir)


func _eject_spent_shell(aim_dir: Vector2) -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return

	var shell := SpentShellScene.instantiate() as RigidBody2D
	if shell == null:
		return
	shell.add_collision_exception_with(self)
	for entry in _soft_body_nodes:
		var rb: RigidBody2D = entry["body"]
		if is_instance_valid(rb):
			shell.add_collision_exception_with(rb)

	var safe_start := global_position
	var desired_pos := global_position + Vector2(aim_dir.x * 6.0, -6.0)
	var space_state := get_world_2d().direct_space_state
	if space_state != null:
		var query := PhysicsRayQueryParameters2D.create(safe_start, desired_pos, 1)
		query.exclude = [get_rid()]
		var hit := space_state.intersect_ray(query)
		if not hit.is_empty():
			desired_pos = (hit["position"] as Vector2) + (hit["normal"] as Vector2) * 6.0
	shell.global_position = desired_pos

	var eject_x := -signf(aim_dir.x) if absf(aim_dir.x) > 0.2 else randf_range(-1.0, 1.0)
	shell.linear_velocity = Vector2(
		eject_x * randf_range(45.0, 95.0) + velocity.x * 0.15,
		randf_range(-155.0, -95.0)
	)
	shell.angular_velocity = randf_range(-14.0, 14.0)
	parent_node.add_child(shell)
