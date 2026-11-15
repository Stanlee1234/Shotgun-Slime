extends Node2D

const END_SCREEN_SCENE_PATH := "res://Scenes/end_screen.tscn"
const FINAL_TIME_META := &"final_speedrun_time"
const SHELLS_USED_META := &"shells_used"

@export_group("Camera Follow (Try 1: Vertical Deadzone)")
@export var room_center_x: float = 576.0
@export var room_height: float = 648.0
## Half-height of the vertical band where the player can move without moving the camera.
@export var vertical_deadzone: float = 110.0
## Shifts the camera slightly higher (negative Y) so you can see more above while aiming up.
@export var upward_bias: float = 50.0
## Higher = snappier catch-up, lower = floatier smoothing.
@export var follow_speed: float = 6.0
## Prevents the camera from scrolling below the bottom room center (324 = y 0..648).
@export var max_camera_y: float = 324.0

@export_group("Screen Rumble")
@export var shot_trauma: float = 0.78
@export var max_rumble_offset: float = 22.0
@export var landing_rumble_offset: float = 54.0
@export var max_rumble_roll: float = 0.0
@export var trauma_decay: float = 2.4
@export var landing_trauma_decay: float = 1.05
@export var rumble_speed: float = 48.0

@export_group("End Transition")
@export var end_hold_time: float = 0.35
@export var end_fade_in_speed: float = 0.45

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = get_node_or_null("Camera2D")
@onready var end_area: Area2D = get_node_or_null("Bkg/EndArea")
@onready var hud: Node = get_node_or_null("UILayer/HUD")
@onready var pause_ui: Node = get_node_or_null("UILayer/PauseUI")

var _target_y: float = 324.0
var _trauma: float = 0.0
var _active_trauma_decay: float = 2.4
var _active_rumble_offset: float = 22.0
var _noise_t: float = 0.0
var _noise := FastNoiseLite.new()
var _ending: bool = false
var _shells_used: int = 0


func _ready() -> void:
	var tree := get_tree()
	if tree != null:
		if tree.has_meta(FINAL_TIME_META):
			tree.remove_meta(FINAL_TIME_META)
		if tree.has_meta(SHELLS_USED_META):
			tree.remove_meta(SHELLS_USED_META)

	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0

	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		add_child(camera)

	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE
	camera.ignore_rotation = is_zero_approx(max_rumble_roll)
	camera.enabled = true

	if player != null:
		var start_room := floori(player.global_position.y / room_height)
		_target_y = minf(max_camera_y, float(start_room) * room_height + room_height * 0.5)
		camera.position = Vector2(room_center_x, _target_y)
		player.shot_fired.connect(_on_player_shot_fired)
		if player.has_signal("impacted"):
			player.impacted.connect(_on_player_impacted)
	else:
		_target_y = max_camera_y
		camera.position = Vector2(room_center_x, _target_y)

	if end_area != null:
		end_area.body_entered.connect(_on_end_area_body_entered)


func _physics_process(delta: float) -> void:
	if player == null or camera == null:
		return

	var desired_y := player.global_position.y - upward_bias
	var diff := desired_y - _target_y
	if diff < -vertical_deadzone and player.velocity.y < 0.0:
		_target_y = desired_y + vertical_deadzone
	elif diff > vertical_deadzone:
		_target_y = desired_y - vertical_deadzone

	_target_y = minf(_target_y, max_camera_y)
	camera.position.x = room_center_x
	camera.position.y = lerpf(camera.position.y, _target_y, 1.0 - exp(-follow_speed * delta))


func _process(delta: float) -> void:
	if camera == null:
		return
	if _trauma <= 0.0:
		camera.offset = Vector2.ZERO
		camera.rotation = 0.0
		return

	_trauma = maxf(0.0, _trauma - _active_trauma_decay * delta)
	_noise_t += delta * rumble_speed

	var shake := _trauma * _trauma
	camera.offset = Vector2(
		_active_rumble_offset * shake * _noise.get_noise_2d(13.7, _noise_t),
		_active_rumble_offset * shake * _noise.get_noise_2d(91.3, _noise_t)
	).round()
	camera.rotation = max_rumble_roll * shake * _noise.get_noise_2d(217.5, _noise_t)


func add_rumble(amount: float, decay_rate: float = -1.0, rumble_offset: float = -1.0) -> void:
	var target_decay := trauma_decay if decay_rate <= 0.0 else decay_rate
	var target_offset := max_rumble_offset if rumble_offset <= 0.0 else rumble_offset
	if _trauma <= 0.05 or target_offset >= _active_rumble_offset:
		_active_rumble_offset = target_offset
		_active_trauma_decay = target_decay
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _on_player_shot_fired() -> void:
	if not _ending:
		_shells_used += 1
	add_rumble(shot_trauma, trauma_decay, max_rumble_offset)


func _on_player_impacted(strength: float) -> void:
	var heavy_factor := clampf((strength - 0.5) / 0.5, 0.0, 1.0)
	var decay := lerpf(trauma_decay, landing_trauma_decay, heavy_factor)
	var offset := lerpf(max_rumble_offset, landing_rumble_offset, heavy_factor)
	add_rumble(strength, decay, offset)


func _is_player_body(body: Node) -> bool:
	if player == null or body == null:
		return false
	return body == player or player.is_ancestor_of(body)


func _on_end_area_body_entered(body: Node2D) -> void:
	if _ending or not _is_player_body(body):
		return
	var scene_manager := get_node_or_null("/root/SceneManager")
	if scene_manager != null and scene_manager.is_transitioning:
		return
	_trigger_end_sequence()


func _trigger_end_sequence() -> void:
	_ending = true
	if end_area != null:
		end_area.set_deferred("monitoring", false)
	var final_time := 0.0
	if hud != null:
		if hud.has_method("set_timer_running"):
			hud.set_timer_running(false)
		if hud.has_method("get_elapsed_time"):
			final_time = float(hud.get_elapsed_time())
	var tree := get_tree()
	if tree != null:
		tree.set_meta(FINAL_TIME_META, final_time)
		tree.set_meta(SHELLS_USED_META, _shells_used)
	if pause_ui != null:
		pause_ui.set_process_unhandled_input(false)
		var pause_btn := pause_ui.get_node_or_null("PauseButton") as BaseButton
		if pause_btn != null:
			pause_btn.disabled = true
	if player != null:
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)

	var scene_manager := get_node_or_null("/root/SceneManager")
	if scene_manager == null:
		get_tree().change_scene_to_file(END_SCREEN_SCENE_PATH)
		return

	await scene_manager.fade_out({
		"pattern": "fade",
		"color": Color.WHITE,
		"speed": 1000.0,
	})
	scene_manager.change_scene(END_SCREEN_SCENE_PATH, {
		"skip_fade_out": true,
		"pattern": "fade",
		"color": Color.WHITE,
		"speed": end_fade_in_speed,
		"wait_time": end_hold_time,
	})
