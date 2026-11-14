extends Control

const CROSSHAIR_TEX := preload("res://Assets/shotgun_crosshair.png")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.set_custom_mouse_cursor(CROSSHAIR_TEX, Input.CURSOR_ARROW, Vector2(16, 16))
	Input.set_custom_mouse_cursor(CROSSHAIR_TEX, Input.CURSOR_POINTING_HAND, Vector2(16, 16))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/game.tscn")
