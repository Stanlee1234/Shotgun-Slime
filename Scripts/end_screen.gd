extends Node2D

const HudScript = preload("res://Scripts/hud.gd")
const MAIN_MENU_SCENE_PATH := "res://Scenes/main_menu.tscn"
const FINAL_TIME_META := &"final_speedrun_time"
const SHELLS_USED_META := &"shells_used"

@export_group("Scene Transition")
@export var transition_pattern: String = "squares"
@export var transition_color: Color = Color(0.106, 0.110, 0.157, 1.0)
@export var transition_speed: float = 2.2
@export var transition_wait_time: float = 0.15

@onready var time_label: Label = get_node_or_null("TimeLabel")

var _is_transitioning: bool = false


func _ready() -> void:
	var final_seconds := 0.0
	var shells_used := 0
	var tree := get_tree()
	if tree != null:
		if tree.has_meta(FINAL_TIME_META):
			final_seconds = float(tree.get_meta(FINAL_TIME_META))
		if tree.has_meta(SHELLS_USED_META):
			shells_used = int(tree.get_meta(SHELLS_USED_META))
	if time_label != null:
		time_label.text = "Final Time: %s\nShells used: %d" % [HudScript.format_time(final_seconds), shells_used]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER):
			get_viewport().set_input_as_handled()
			_return_to_main_menu()


func _return_to_main_menu() -> void:
	if _is_transitioning:
		return
	var scene_manager := get_node_or_null("/root/SceneManager")
	if scene_manager != null and scene_manager.get("is_transitioning"):
		return

	_is_transitioning = true
	var tree := get_tree()
	if tree != null:
		if tree.has_meta(FINAL_TIME_META):
			tree.remove_meta(FINAL_TIME_META)
		if tree.has_meta(SHELLS_USED_META):
			tree.remove_meta(SHELLS_USED_META)

	if scene_manager != null:
		scene_manager.change_scene(MAIN_MENU_SCENE_PATH, {
			"pattern": transition_pattern,
			"color": transition_color,
			"speed": transition_speed,
			"wait_time": transition_wait_time,
		})
	elif tree != null:
		tree.change_scene_to_file(MAIN_MENU_SCENE_PATH)
