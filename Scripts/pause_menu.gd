extends Control

const MAIN_MENU_SCENE_PATH := "res://Scenes/main_menu.tscn"
const HOVER_SFX := preload("res://Assets/Music + SFX/hover-fx.wav")
const SHOOT_SFX := preload("res://Assets/Music + SFX/gun-firing-fx.mp3")

const NORMAL_TEX_TINT := Color(0.88, 0.88, 0.90, 1.0)
const HOVER_TEX_TINT := Color(1.0, 1.0, 1.0, 1.0)
const PRESS_TEX_TINT := Color(0.76, 0.72, 0.72, 1.0)

const NORMAL_TEXT_COLOR := Color(0.961, 1.0, 0.949, 1.0)
const HOVER_TEXT_COLOR := Color(0.776, 0.988, 0.659, 1.0)
const PRESS_TEXT_COLOR := Color(0.969, 0.769, 0.0, 1.0)

@export_group("Button Feel")
@export var hover_scale: Vector2 = Vector2(1.04, 1.04)
@export var press_scale: Vector2 = Vector2(0.95, 1.04)
@export var hover_sfx_volume_db: float = -8.0
@export var click_sfx_volume_db: float = -18.0
@export_range(0.0, 0.2, 0.01) var sfx_pitch_jitter: float = 0.05

@export_group("Scene Transition")
@export var transition_pattern: String = "squares"
@export var transition_color: Color = Color(0.106, 0.110, 0.157, 1.0)
@export var transition_speed: float = 2.2
@export var transition_wait_time: float = 0.15

@onready var pause_button: BaseButton = $PauseButton
@onready var pause_overlay: Control = $PauseOverlay
@onready var resume_button: BaseButton = $PauseOverlay/MenuPanel/ResumeButton
@onready var main_menu_button: BaseButton = $PauseOverlay/MenuPanel/MainMenuButton
@onready var sfx_player: AudioStreamPlayer = get_node_or_null("SFXPlayer")

var _hovered: Dictionary = {}
var _active_state: Dictionary = {}
var _scale_tweens: Dictionary = {}
var _labels: Dictionary = {}
var _buttons: Array[BaseButton] = []
var _is_transitioning: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sfx_player != null:
		sfx_player.max_polyphony = 4

	var tree := get_tree()
	if tree != null:
		tree.paused = false

	pause_overlay.visible = false
	pause_button.visible = true

	_setup_button(pause_button)
	_setup_button(resume_button)
	_setup_button(main_menu_button)

	pause_button.pressed.connect(_on_pause_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false


func _unhandled_input(event: InputEvent) -> void:
	if _is_transitioning:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		var tree := get_tree()
		if tree != null:
			set_paused(not tree.paused)
			get_viewport().set_input_as_handled()


func set_paused(paused: bool) -> void:
	if _is_transitioning:
		return
	var tree := get_tree()
	if tree == null:
		return

	tree.paused = paused
	pause_overlay.visible = paused
	pause_button.visible = not paused

	_reset_all_buttons()
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()


func _setup_button(btn: BaseButton) -> void:
	if btn == null:
		return
	_buttons.append(btn)
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


func _reset_all_buttons() -> void:
	for btn in _buttons:
		if not is_instance_valid(btn):
			continue
		_hovered[btn] = false
		_active_state[btn] = false
		_kill_tween(btn)
		btn.scale = Vector2.ONE
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

	var label := _labels.get(btn) as Label
	var tween := _replace_tween(btn)

	if is_active:
		_play_sfx(HOVER_SFX, hover_sfx_volume_db)
		btn.self_modulate = HOVER_TEX_TINT
		if label != null:
			label.add_theme_color_override("font_color", HOVER_TEXT_COLOR)
		tween.tween_property(btn, "scale", Vector2(hover_scale.x + 0.03, hover_scale.y - 0.05), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", hover_scale, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		btn.self_modulate = NORMAL_TEX_TINT
		if label != null:
			label.add_theme_color_override("font_color", NORMAL_TEXT_COLOR)
		tween.tween_property(btn, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_button_down(btn: BaseButton) -> void:
	if btn.disabled:
		return
	btn.self_modulate = PRESS_TEX_TINT
	var label := _labels.get(btn) as Label
	if label != null:
		label.add_theme_color_override("font_color", PRESS_TEXT_COLOR)
	var tween := _replace_tween(btn)
	tween.tween_property(btn, "scale", press_scale, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_button_up(btn: BaseButton) -> void:
	if btn.disabled:
		return
	var is_active: bool = _hovered.get(btn, false) or btn.has_focus()
	btn.self_modulate = HOVER_TEX_TINT if is_active else NORMAL_TEX_TINT
	var label := _labels.get(btn) as Label
	if label != null:
		label.add_theme_color_override("font_color", HOVER_TEXT_COLOR if is_active else NORMAL_TEXT_COLOR)
	var tween := _replace_tween(btn)
	tween.tween_property(btn, "scale", hover_scale if is_active else Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _kill_tween(btn: BaseButton) -> void:
	var existing: Tween = _scale_tweens.get(btn)
	if existing != null and existing.is_valid():
		existing.kill()
	_scale_tweens.erase(btn)


func _replace_tween(btn: BaseButton) -> Tween:
	_kill_tween(btn)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_scale_tweens[btn] = tween
	return tween


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
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = SHOOT_SFX
	player.volume_db = click_sfx_volume_db
	player.pitch_scale = 1.0 + randf_range(-sfx_pitch_jitter, sfx_pitch_jitter)
	tree.root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _on_pause_pressed() -> void:
	_play_shoot_sfx()
	set_paused(true)


func _on_resume_pressed() -> void:
	_play_shoot_sfx()
	set_paused(false)


func _on_main_menu_pressed() -> void:
	if _is_transitioning:
		return
	var scene_manager := get_node_or_null("/root/SceneManager")
	if scene_manager != null and scene_manager.get("is_transitioning"):
		return

	_is_transitioning = true
	_play_shoot_sfx()
	for btn in _buttons:
		if is_instance_valid(btn):
			btn.disabled = true

	var tree := get_tree()
	if tree != null:
		if tree.current_scene != null:
			var player := tree.current_scene.get_node_or_null("Player")
			if player != null:
				player.process_mode = Node.PROCESS_MODE_DISABLED
		tree.paused = false

	if scene_manager != null:
		scene_manager.change_scene(MAIN_MENU_SCENE_PATH, {
			"pattern": transition_pattern,
			"color": transition_color,
			"speed": transition_speed,
			"wait_time": transition_wait_time,
		})
	elif tree != null:
		tree.change_scene_to_file(MAIN_MENU_SCENE_PATH)
