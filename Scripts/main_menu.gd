extends Node3D

const CROSSHAIR_TEX := preload("res://Assets/shotgun_crosshair.png")
const HOVER_SFX := preload("res://Assets/Music + SFX/hover-fx.wav")
const RELOAD_SFX := preload("res://Assets/Music + SFX/gun-reloading-fx.wav")
const SHOOT_SFX := preload("res://Assets/Music + SFX/gun-firing-fx.mp3")
const GAME_SCENE_PATH := "res://Scenes/game.tscn"

const NORMAL_TEX_TINT := Color(0.88, 0.88, 0.90, 1.0)
const HOVER_TEX_TINT := Color(1.0, 1.0, 1.0, 1.0)
const HOVER_EXIT_TEX_TINT := Color(1.0, 0.72, 0.72, 1.0)
const PRESS_TEX_TINT := Color(0.76, 0.72, 0.72, 1.0)

const NORMAL_TEXT_COLOR := Color(0.961, 1.0, 0.949, 1.0)
const HOVER_TEXT_COLOR := Color(0.776, 0.988, 0.659, 1.0)
const HOVER_EXIT_TEXT_COLOR := Color(1.0, 0.35, 0.35, 1.0)
const PRESS_TEXT_COLOR := Color(0.969, 0.769, 0.0, 1.0)

@export_group("3D Aim & Feel")
@export var rest_aim_speed: float = 9.0
@export var danger_aim_speed: float = 12.0
@export var default_fov: float = 46.0
@export var danger_fov: float = 42.5

@export_group("Button Feel")
@export var hover_slide_offset: float = -10.0
@export var hover_scale: Vector2 = Vector2(1.04, 1.04)
@export var press_scale: Vector2 = Vector2(0.95, 1.04)
@export var press_drop_offset: float = 2.0
@export var hover_sfx_volume_db: float = -8.0
@export var reload_sfx_volume_db: float = -10.0
@export var click_sfx_volume_db: float = -18.0
@export_range(0.0, 0.2, 0.01) var sfx_pitch_jitter: float = 0.05

@export_group("Scene Transition")
@export var transition_pattern: String = "squares"
@export var transition_color: Color = Color(0.106, 0.110, 0.157, 1.0)
@export var transition_speed: float = 2.2
@export var transition_wait_time: float = 0.15

@onready var camera: Camera3D = $Camera3D
@onready var slime_root: Node3D = $SlimeRoot
@onready var slime_squash: Node3D = $SlimeRoot/SlimeSquash
@onready var gun_pivot: Node3D = $SlimeRoot/GunPivot
@onready var shotgun_model: Node3D = $SlimeRoot/GunPivot/ShotgunModel

@onready var menu_clip: Control = $UI/MenuRoot/MenuPanel/MenuClip
@onready var menu_list: Control = $UI/MenuRoot/MenuPanel/MenuClip/MenuList
@onready var options_list: Control = $UI/MenuRoot/MenuPanel/MenuClip/OptionsList
@onready var quit_button: TextureButton = $UI/MenuRoot/MenuPanel/MenuClip/MenuList/Quit
@onready var volume_label: Label = $UI/MenuRoot/MenuPanel/MenuClip/OptionsList/VolumeLabel
@onready var volume_slider: HSlider = $UI/MenuRoot/MenuPanel/MenuClip/OptionsList/VolumeSlider
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer
@onready var shot_flash: ColorRect = $UI/ShotFlash

var _aiming_at_player: bool = false
var _danger_amount: float = 0.0
var _recoil_amount: float = 0.0
var _camera_punch: float = 0.0
var _camera_base_pos: Vector3
var _rest_target: Vector3 = Vector3(1.8, 0.45, 0.5)
var _gun_pivot_base_pos: Vector3
var _shotgun_base_pos: Vector3
var _last_aim_target: Vector3
var _idle_anim_time: float = 0.0
var _options_open: bool = false
var _menu_rest_x: float = 0.0
var _menu_off_x: float = 332.0
var _menu_tween: Tween
var _shotgun_mesh: MeshInstance3D

var _base_positions: Dictionary = {}
var _hovered: Dictionary = {}
var _active_state: Dictionary = {}
var _button_tweens: Dictionary = {}
var _scale_tweens: Dictionary = {}
var _labels: Dictionary = {}
var _is_transitioning: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.set_custom_mouse_cursor(CROSSHAIR_TEX, Input.CURSOR_ARROW, Vector2(16, 16))
	Input.set_custom_mouse_cursor(CROSSHAIR_TEX, Input.CURSOR_POINTING_HAND, Vector2(16, 16))

	sfx_player.max_polyphony = 4
	camera.fov = default_fov
	_camera_base_pos = camera.position

	_shotgun_mesh = shotgun_model.get_node_or_null("model") as MeshInstance3D
	_gun_pivot_base_pos = gun_pivot.position
	_shotgun_base_pos = shotgun_model.position
	_last_aim_target = _rest_target
	gun_pivot.global_basis = _basis_looking_at(_rest_target)

	_menu_rest_x = menu_list.position.x
	_menu_off_x = menu_clip.size.x + 8.0
	options_list.visible = false
	options_list.position.x = _menu_off_x

	_sync_volume_slider()
	_setup_button_group(menu_list, true)
	_setup_button_group(options_list, false)


func _unhandled_input(event: InputEvent) -> void:
	if _options_open and event.is_action_pressed("ui_cancel"):
		_set_options_open(false)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_idle_anim_time += delta
	_recoil_amount = lerpf(_recoil_amount, 0.0, 1.0 - exp(-14.0 * delta))
	_camera_punch = lerpf(_camera_punch, 0.0, 1.0 - exp(-18.0 * delta))

	var target_danger := 1.0 if _aiming_at_player else 0.0
	_danger_amount = lerpf(_danger_amount, target_danger, 1.0 - exp(-10.0 * delta))
	camera.fov = lerpf(default_fov, danger_fov, _danger_amount)
	if _camera_punch > 0.001:
		camera.position = _camera_base_pos + Vector3(randf_range(-1.0, 1.0) * 0.06, randf_range(-1.0, 1.0) * 0.06, 0.14) * _camera_punch
	else:
		camera.position = _camera_base_pos

	var breath := sin(_idle_anim_time * 3.1)
	var squash_x := (1.0 + 0.04 * breath) + 0.06 * _danger_amount + 0.14 * _recoil_amount
	var squash_y := (1.0 - 0.04 * breath) - 0.06 * _danger_amount - 0.12 * _recoil_amount
	slime_squash.scale = Vector3(squash_x, squash_y, 1.0)

	var target_point: Vector3 = _get_aim_target()
	var pivot_origin: Vector3 = slime_root.to_global(_gun_pivot_base_pos)
	var aim_dir: Vector3 = target_point - pivot_origin
	var down_lift: float = 0.0
	if not _aiming_at_player and aim_dir.length_squared() > 0.0001:
		down_lift = clampf(-aim_dir.normalized().y, 0.0, 1.0) * 0.34
	var target_local_pos: Vector3 = _gun_pivot_base_pos + Vector3(0.0, down_lift, 0.0)
	gun_pivot.position = gun_pivot.position.lerp(target_local_pos, 1.0 - exp(-rest_aim_speed * delta))

	var target_basis: Basis = _basis_looking_at(target_point)
	if _recoil_amount > 0.001:
		target_basis = target_basis.rotated(target_basis.x.normalized(), 0.28 * _recoil_amount)

	var speed: float = danger_aim_speed if _aiming_at_player else rest_aim_speed
	var current_quat := gun_pivot.global_basis.get_rotation_quaternion()
	var desired_quat := target_basis.get_rotation_quaternion()
	gun_pivot.global_basis = Basis(current_quat.slerp(desired_quat, 1.0 - exp(-speed * delta)))
	shotgun_model.position = _shotgun_base_pos + Vector3(0.0, 0.03 * _recoil_amount, 0.18 * _recoil_amount)
	_clamp_gun_above_floor()


func _clamp_gun_above_floor() -> void:
	if _shotgun_mesh == null or _shotgun_mesh.mesh == null:
		return
	var aabb := _shotgun_mesh.mesh.get_aabb()
	var xform := _shotgun_mesh.global_transform
	var min_y := INF
	for i in range(8):
		min_y = minf(min_y, (xform * aabb.get_endpoint(i)).y)
	if min_y < 0.04:
		var pos := gun_pivot.global_position
		pos.y += (0.04 - min_y)
		gun_pivot.global_position = pos


func _get_aim_target() -> Vector3:
	if _aiming_at_player:
		return camera.global_position + Vector3(0.0, -0.05, 0.0)

	var pivot_origin := slime_root.to_global(_gun_pivot_base_pos)
	var mouse_pos := get_viewport().get_mouse_position()
	var screen_offset := mouse_pos - camera.unproject_position(pivot_origin)
	if screen_offset.length_squared() >= 4.0:
		var clamped_offset := Vector2(maxf(screen_offset.x, 48.0), screen_offset.y)
		var d2 := clamped_offset.normalized()
		if d2.y > 0.30:
			d2 = Vector2(sqrt(1.0 - 0.30 * 0.30), 0.30)
		var plane_normal := slime_root.global_basis.z.normalized()
		var circle_dir := (slime_root.global_basis.x * d2.x + Vector3.UP * (-d2.y) + plane_normal * 0.12).normalized()
		_last_aim_target = pivot_origin + circle_dir * 1.5
	return _last_aim_target


func _basis_looking_at(world_target: Vector3) -> Basis:
	var dir := world_target - gun_pivot.global_position
	if dir.length_squared() < 0.0001:
		return gun_pivot.global_basis
	var normalized_dir := dir.normalized()
	var up_ref := Vector3.UP if absf(normalized_dir.dot(Vector3.UP)) < 0.995 else slime_root.global_basis.z.normalized()
	return Basis.looking_at(normalized_dir, up_ref)


func _setup_button_group(container: Control, play_intro: bool) -> void:
	var idx := 0
	for child in container.get_children():
		if child is BaseButton:
			_setup_button(child as BaseButton, idx, play_intro)
			idx += 1


func _setup_button(btn: BaseButton, index: int, play_intro: bool) -> void:
	_base_positions[btn] = btn.position
	_hovered[btn] = false
	_active_state[btn] = false
	btn.pivot_offset = btn.size * 0.5
	btn.self_modulate = NORMAL_TEX_TINT

	var label := btn.get_node_or_null("Label") as Label
	if label != null:
		label.add_theme_color_override("font_color", NORMAL_TEXT_COLOR)
		_labels[btn] = label

	btn.mouse_entered.connect(_on_button_hovered.bind(btn, true))
	btn.mouse_exited.connect(_on_button_hovered.bind(btn, false))
	btn.focus_entered.connect(_on_button_focused.bind(btn, true))
	btn.focus_exited.connect(_on_button_focused.bind(btn, false))
	btn.button_down.connect(_on_button_down.bind(btn))
	btn.button_up.connect(_on_button_up.bind(btn))
	btn.pressed.connect(_on_button_pressed)

	if play_intro:
		_play_intro(btn, index)


func _play_intro(btn: BaseButton, index: int) -> void:
	var base_pos: Vector2 = _base_positions.get(btn, btn.position)
	btn.position = base_pos + Vector2(36.0, 0.0)
	btn.modulate.a = 0.0

	var tween := _reset_tween(btn)
	if index > 0:
		tween.tween_interval(float(index) * 0.055)
	tween.set_parallel(true)
	tween.tween_property(btn, "position:x", base_pos.x, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _reset_group_buttons(container: Control) -> void:
	for child in container.get_children():
		if not (child is BaseButton):
			continue
		var btn := child as BaseButton
		_hovered[btn] = false
		_active_state[btn] = false
		_kill_button_tween(_button_tweens, btn)
		_kill_button_tween(_scale_tweens, btn)
		var base_pos: Vector2 = _base_positions.get(btn, btn.position)
		btn.position = base_pos
		btn.scale = Vector2.ONE
		btn.modulate.a = 1.0
		btn.self_modulate = NORMAL_TEX_TINT
		var label := _labels.get(btn) as Label
		if label != null:
			label.add_theme_color_override("font_color", NORMAL_TEXT_COLOR)


func _on_button_hovered(btn: BaseButton, is_hovered: bool) -> void:
	if btn.disabled:
		return
	_hovered[btn] = is_hovered
	if is_hovered:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner != null and focus_owner != btn:
			focus_owner.release_focus()
	_refresh_button_visual(btn)


func _on_button_focused(btn: BaseButton, _is_focused: bool) -> void:
	if btn.disabled:
		return
	_refresh_button_visual(btn)


func _refresh_button_visual(btn: BaseButton) -> void:
	var is_active: bool = _hovered.get(btn, false) or btn.has_focus()
	var was_active: bool = _active_state.get(btn, false)
	if is_active == was_active:
		return
	_active_state[btn] = is_active

	var is_quit := btn == quit_button
	if is_quit:
		_aiming_at_player = is_active

	var base_pos: Vector2 = _base_positions.get(btn, btn.position)
	var label := _labels.get(btn) as Label
	var tween := _reset_tween(btn)
	tween.set_parallel(true)
	tween.tween_property(btn, "modulate:a", 1.0, 0.12)
	tween.tween_property(btn, "position:y", base_pos.y, 0.10)

	var scale_tween := _reset_scale_tween(btn)

	if is_active:
		if is_quit:
			_play_sfx(RELOAD_SFX, reload_sfx_volume_db)
		else:
			_play_sfx(HOVER_SFX, hover_sfx_volume_db)

		var target_tint := HOVER_EXIT_TEX_TINT if is_quit else HOVER_TEX_TINT
		var target_text := HOVER_EXIT_TEXT_COLOR if is_quit else HOVER_TEXT_COLOR
		tween.tween_property(btn, "position:x", base_pos.x + hover_slide_offset, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "self_modulate", target_tint, 0.10)
		if label != null:
			label.add_theme_color_override("font_color", target_text)

		scale_tween.tween_property(btn, "scale", Vector2(hover_scale.x + 0.03, hover_scale.y - 0.05), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		scale_tween.tween_property(btn, "scale", hover_scale, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(btn, "position:x", base_pos.x, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "self_modulate", NORMAL_TEX_TINT, 0.12)
		if label != null:
			label.add_theme_color_override("font_color", NORMAL_TEXT_COLOR)

		scale_tween.tween_property(btn, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_button_down(btn: BaseButton) -> void:
	if btn.disabled:
		return
	var is_active: bool = _active_state.get(btn, false)
	var base_pos: Vector2 = _base_positions.get(btn, btn.position)
	var label := _labels.get(btn) as Label
	var scale_tween := _reset_scale_tween(btn)
	scale_tween.tween_property(btn, "scale", press_scale, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if label != null:
		label.add_theme_color_override("font_color", PRESS_TEXT_COLOR)

	var tween := _reset_tween(btn)
	tween.set_parallel(true)
	tween.tween_property(btn, "modulate:a", 1.0, 0.05)
	tween.tween_property(btn, "self_modulate", PRESS_TEX_TINT, 0.05)
	tween.tween_property(btn, "position:x", base_pos.x + (hover_slide_offset if is_active else 0.0), 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "position:y", base_pos.y + press_drop_offset, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_button_up(btn: BaseButton) -> void:
	if btn.disabled:
		return
	var is_active: bool = _hovered.get(btn, false) or btn.has_focus()
	var is_quit := btn == quit_button
	var base_pos: Vector2 = _base_positions.get(btn, btn.position)
	var label := _labels.get(btn) as Label
	var scale_tween := _reset_scale_tween(btn)
	scale_tween.tween_property(btn, "scale", hover_scale if is_active else Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if label != null:
		var active_color := HOVER_EXIT_TEXT_COLOR if is_quit else HOVER_TEXT_COLOR
		label.add_theme_color_override("font_color", active_color if is_active else NORMAL_TEXT_COLOR)

	var tween := _reset_tween(btn)
	tween.set_parallel(true)
	var active_tint := HOVER_EXIT_TEX_TINT if is_quit else HOVER_TEX_TINT
	tween.tween_property(btn, "self_modulate", active_tint if is_active else NORMAL_TEX_TINT, 0.08)
	tween.tween_property(btn, "position:x", base_pos.x + (hover_slide_offset if is_active else 0.0), 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "position:y", base_pos.y, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _kill_button_tween(tweens: Dictionary, btn: BaseButton) -> void:
	var existing: Tween = tweens.get(btn)
	if existing != null and existing.is_valid():
		existing.kill()
	tweens.erase(btn)


func _replace_button_tween(tweens: Dictionary, btn: BaseButton) -> Tween:
	_kill_button_tween(tweens, btn)
	var tween := create_tween()
	tweens[btn] = tween
	return tween


func _reset_tween(btn: BaseButton) -> Tween:
	return _replace_button_tween(_button_tweens, btn)


func _reset_scale_tween(btn: BaseButton) -> Tween:
	return _replace_button_tween(_scale_tweens, btn)


func _on_button_pressed() -> void:
	_recoil_amount = 1.0
	_play_shoot_sfx()


func _play_sfx(stream: AudioStream, volume_db: float) -> void:
	if stream == null or sfx_player == null:
		return
	sfx_player.stream = stream
	sfx_player.volume_db = volume_db
	sfx_player.pitch_scale = 1.0 + randf_range(-sfx_pitch_jitter, sfx_pitch_jitter)
	sfx_player.play()


func _play_shoot_sfx() -> void:
	var tree := get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree == null or tree.root == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = SHOOT_SFX
	player.volume_db = click_sfx_volume_db
	player.pitch_scale = 1.0 + randf_range(-sfx_pitch_jitter, sfx_pitch_jitter)
	tree.root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _set_buttons_disabled(disabled_state: bool) -> void:
	for btn in _base_positions.keys():
		if is_instance_valid(btn):
			(btn as BaseButton).disabled = disabled_state


func _set_options_open(open: bool) -> void:
	if _options_open == open or _is_transitioning:
		return
	_options_open = open
	if open:
		_aiming_at_player = false

	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()

	if _menu_tween != null and _menu_tween.is_valid():
		_menu_tween.kill()

	var outgoing: Control = menu_list if open else options_list
	var incoming: Control = options_list if open else menu_list
	_reset_group_buttons(incoming)
	if not incoming.visible:
		incoming.position.x = _menu_off_x
	incoming.visible = true
	outgoing.visible = true

	_menu_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_menu_tween.tween_property(outgoing, "position:x", _menu_off_x, 0.24)
	_menu_tween.tween_property(incoming, "position:x", _menu_rest_x, 0.26).set_delay(0.04)
	_menu_tween.chain().tween_callback(func() -> void:
		if _options_open == open:
			outgoing.visible = false
			_reset_group_buttons(outgoing)
	)


func _sync_volume_slider() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus == -1:
		return
	var percent := 0.0 if AudioServer.is_bus_mute(bus) else clampf(db_to_linear(AudioServer.get_bus_volume_db(bus)) * 50.0, 0.0, 100.0)
	volume_slider.set_value_no_signal(roundf(percent))
	volume_label.text = "Volume %d%%" % int(roundf(volume_slider.value))


func _on_volume_slider_mouse_entered() -> void:
	_play_sfx(HOVER_SFX, hover_sfx_volume_db)


func _on_volume_changed(value: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus != -1:
		var linear := clampf(value / 50.0, 0.0, 2.0)
		AudioServer.set_bus_mute(bus, linear <= 0.001)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(linear, 0.0001)))
	volume_label.text = "Volume %d%%" % int(roundf(value))


func _on_volume_drag_ended(_value_changed: bool) -> void:
	_play_sfx(HOVER_SFX, hover_sfx_volume_db)


func _on_start_pressed() -> void:
	if _is_transitioning:
		return
	var scene_manager := get_node_or_null("/root/SceneManager")
	if scene_manager != null:
		if scene_manager.get("is_transitioning"):
			return
		_is_transitioning = true
		_set_buttons_disabled(true)
		scene_manager.change_scene(GAME_SCENE_PATH, {
			"pattern": transition_pattern,
			"color": transition_color,
			"speed": transition_speed,
			"wait_time": transition_wait_time,
		})
	elif is_inside_tree():
		_is_transitioning = true
		get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_options_pressed() -> void:
	_set_options_open(true)


func _on_back_pressed() -> void:
	_set_options_open(false)


func _on_quit_pressed() -> void:
	if OS.has_feature("web") or _is_transitioning:
		return
	_is_transitioning = true
	_aiming_at_player = true
	_recoil_amount = 1.0
	_camera_punch = 1.0
	_set_buttons_disabled(true)
	shot_flash.color = Color(1.0, 1.0, 1.0, 1.0)
	await get_tree().create_timer(0.25).timeout
	get_tree().quit()
