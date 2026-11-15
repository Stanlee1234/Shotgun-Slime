extends Control # Or Control, depending on your HUD root node

@export_group("Hover Fade")
@export_range(0.0, 1.0, 0.05) var hovered_alpha: float = 0.25
@export_range(0.0, 1.0, 0.05) var normal_alpha: float = 1.0
@export var fade_speed: float = 12.0
## Extra margin around visible HUD items (matches crosshair radius) so the HUD fades as you aim over it.
@export var hover_padding: float = 16.0

# Update these paths to match your scene tree
@onready var hud_sprite: AnimatedSprite2D = $Shell1
@onready var speedrun_timer_label: Label = get_node_or_null("SpeedrunTimer")
@onready var player: CharacterBody2D = $"../../Player"

var elapsed_time: float = 0.0
var timer_running: bool = true
var _mouse_in_window: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = normal_alpha
	hud_sprite.play("normal")
	_update_timer_display()
	
	# Connect player signals
	player.shot_fired.connect(_on_player_shot_fired)
	player.reloaded.connect(_on_player_reloaded)
	
	# Return to "normal" once the "refresh" animation finishes
	hud_sprite.animation_finished.connect(_on_hud_animation_finished)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_mouse_in_window = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER:
		_mouse_in_window = true


func _process(delta: float) -> void:
	if timer_running:
		elapsed_time += delta
		_update_timer_display()

	var target_alpha := hovered_alpha if (_mouse_in_window and _is_mouse_over_hud()) else normal_alpha
	modulate.a = move_toward(modulate.a, target_alpha, fade_speed * delta)


func reset_timer() -> void:
	elapsed_time = 0.0
	_update_timer_display()


func set_timer_running(running: bool) -> void:
	timer_running = running


func get_elapsed_time() -> float:
	return elapsed_time


func _update_timer_display() -> void:
	if speedrun_timer_label != null:
		speedrun_timer_label.text = format_time(elapsed_time)


static func format_time(seconds: float) -> String:
	var clamped := maxf(seconds, 0.0)
	var total_ms := floori(clamped * 1000.0)
	var ms := total_ms % 1000
	var total_seconds := floori(float(total_ms) / 1000.0)
	var secs := total_seconds % 60
	var total_minutes := floori(float(total_seconds) / 60.0)
	var mins := total_minutes % 60
	var hours := floori(float(total_minutes) / 60.0)
	if hours > 0:
		return "%d:%02d:%02d.%03d" % [hours, mins, secs, ms]
	return "%02d:%02d.%03d" % [mins, secs, ms]


func _is_mouse_over_hud() -> bool:
	for child in get_children():
		if _is_mouse_over_node(child):
			return true
	return false


func _is_mouse_over_node(node: Node) -> bool:
	var item := node as CanvasItem
	if item == null or not item.is_visible_in_tree():
		return false

	if node is AnimatedSprite2D:
		var anim_sprite := node as AnimatedSprite2D
		var frames := anim_sprite.sprite_frames
		if frames != null and frames.has_animation(anim_sprite.animation):
			var tex := frames.get_frame_texture(anim_sprite.animation, anim_sprite.frame)
			if tex != null:
				var rect := _get_padded_sprite_rect(tex.get_size(), anim_sprite.centered, anim_sprite.offset, anim_sprite.global_scale)
				if rect.has_point(anim_sprite.get_local_mouse_position()):
					return true
	elif node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.texture != null:
			var rect := _get_padded_sprite_rect(sprite.texture.get_size(), sprite.centered, sprite.offset, sprite.global_scale)
			if rect.has_point(sprite.get_local_mouse_position()):
				return true
	elif node is Control:
		var ctrl := node as Control
		if ctrl.size.x > 0.0 and ctrl.size.y > 0.0:
			var rect := Rect2(Vector2.ZERO, ctrl.size).grow(hover_padding)
			if rect.has_point(ctrl.get_local_mouse_position()):
				return true

	for grandchild in node.get_children():
		if _is_mouse_over_node(grandchild):
			return true
	return false


func _get_padded_sprite_rect(tex_size: Vector2, centered: bool, offset: Vector2, world_scale: Vector2) -> Rect2:
	var origin := (-tex_size * 0.5 if centered else Vector2.ZERO) + offset
	var pad_x := hover_padding / maxf(absf(world_scale.x), 0.001)
	var pad_y := hover_padding / maxf(absf(world_scale.y), 0.001)
	return Rect2(origin, tex_size).grow_individual(pad_x, pad_y, pad_x, pad_y)


func _on_player_shot_fired() -> void:
	hud_sprite.play("shoot")


func _on_player_reloaded() -> void:
	hud_sprite.play("refresh")


func _on_hud_animation_finished() -> void:
	if hud_sprite.animation == "refresh":
		hud_sprite.play("normal")
