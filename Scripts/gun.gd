extends Node2D

@export_range(0.0, 0.25, 0.01) var sfx_pitch_jitter: float = 0.04

@onready var cpu_particles: CPUParticles2D = $CPUParticles2D
@onready var fire_sound: AudioStreamPlayer2D = get_node_or_null("FireSound")
@onready var reload_sound: AudioStreamPlayer2D = get_node_or_null("ReloadSound")


func _ready() -> void:
	var parent := get_parent()
	if parent != null:
		if parent.has_signal("shot_fired"):
			parent.shot_fired.connect(_on_player_shot_fired)
		if parent.has_signal("reloaded"):
			parent.reloaded.connect(_on_player_reloaded)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	look_at(get_global_mouse_position())

	rotation_degrees = wrap(rotation_degrees, 0, 360)
	if rotation_degrees > 90 and rotation_degrees < 270:
		scale.y = -1
	else:
		scale.y = 1


func spawn_shot_particles(aim_dir: Vector2) -> void:
	if cpu_particles == null:
		return

	var dir := aim_dir.normalized() if aim_dir.length_squared() > 0.001 else Vector2.RIGHT
	# Sync gun aim before triggering the editor-configured CPUParticles2D.
	rotation = dir.angle()
	var deg := wrapf(rotation_degrees, 0.0, 360.0)
	scale.y = -1.0 if (deg > 90.0 and deg < 270.0) else 1.0
	cpu_particles.restart()


func _on_player_shot_fired() -> void:
	_play_sfx(fire_sound)


func _on_player_reloaded() -> void:
	_play_sfx(reload_sound)


func _play_sfx(sfx_player: AudioStreamPlayer2D) -> void:
	if sfx_player == null:
		return
	sfx_player.pitch_scale = randf_range(1.0 - sfx_pitch_jitter, 1.0 + sfx_pitch_jitter)
	sfx_player.play()
