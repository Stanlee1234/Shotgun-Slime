extends Node2D

@export_group("Flicker")
@export var warm_base_energy: float = 2.45
@export var warm_base_scale: float = 2.85
@export var hot_base_energy: float = 0.85
@export var hot_base_scale: float = 0.95
@export var flicker_speed: float = 11.0
@export var flicker_strength: float = 0.20
@export var sway_pixels: float = 2.5

@export_group("Halo")
@export var halo_base_alpha: float = 0.34
@export var halo_base_scale: float = 1.15

@export_group("Blast Reactivity")
@export var blast_react_radius: float = 300.0
@export var blast_flare_energy: float = 1.1
@export var blast_flare_decay: float = 4.5

@onready var sprite: AnimatedSprite2D = $TorchSprite
@onready var warm_light: PointLight2D = $WarmLight
@onready var hot_light: PointLight2D = $HotCoreLight
@onready var glow_halo: Sprite2D = $GlowHalo
@onready var embers: CPUParticles2D = $Embers
@onready var blast_sparks: CPUParticles2D = $BlastSparks

var _noise := FastNoiseLite.new()
var _phase: float = 0.0
var _time: float = 0.0
var _flame_origin: Vector2 = Vector2(0.0, -18.0)
var _blast_flare: float = 0.0
var _blast_push: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group(&"torches")
	_phase = fposmod(global_position.x * 0.13 + global_position.y * 0.07, 100.0)
	_noise.seed = hash(Vector2i(roundi(global_position.x), roundi(global_position.y)))
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0

	if warm_light != null:
		_flame_origin = warm_light.position

	if sprite != null:
		sprite.speed_scale = randf_range(0.88, 1.15)
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(&"burn"):
			var count := sprite.sprite_frames.get_frame_count(&"burn")
			if count > 0:
				sprite.frame = randi() % count
			sprite.play(&"burn")


func _process(delta: float) -> void:
	_time += delta * flicker_speed
	_blast_flare = maxf(0.0, _blast_flare - blast_flare_decay * delta)
	_blast_push = _blast_push.lerp(Vector2.ZERO, 1.0 - exp(-9.0 * delta))

	var n1 := _noise.get_noise_2d(_phase, _time)
	var n2 := _noise.get_noise_2d(_phase + 37.1, _time * 2.15)
	var ripple := sin(_time * 1.45 + _phase) * 0.35 + n1 * 0.65
	var fast_ripple := cos(_time * 2.7 + _phase * 1.7) * 0.4 + n2 * 0.6

	var energy_factor := 1.0 + ripple * flicker_strength + _blast_flare * 0.65
	var scale_factor := 1.0 + ripple * (flicker_strength * 0.45) + _blast_flare * 0.24
	var sway := Vector2(n2 * sway_pixels, -absf(n1) * (sway_pixels * 0.6)) + _blast_push

	if warm_light != null:
		warm_light.energy = maxf(0.1, warm_base_energy * energy_factor)
		warm_light.texture_scale = maxf(0.2, warm_base_scale * scale_factor)
		warm_light.position = _flame_origin + sway * 0.7

	if hot_light != null:
		hot_light.energy = maxf(0.1, hot_base_energy * (1.0 + fast_ripple * flicker_strength * 1.2 + _blast_flare * 0.8))
		hot_light.texture_scale = maxf(0.1, hot_base_scale * (1.0 + fast_ripple * 0.14 + _blast_flare * 0.3))
		hot_light.position = _flame_origin + sway

	if glow_halo != null:
		var halo_scale := halo_base_scale * (1.0 + fast_ripple * 0.12 + _blast_flare * 0.35)
		glow_halo.scale = Vector2(halo_scale, halo_scale)
		glow_halo.position = _flame_origin + sway
		glow_halo.modulate.a = clampf(halo_base_alpha * (1.0 + ripple * 0.25) + _blast_flare * 0.22, 0.05, 0.85)


func on_shot_fired(blast_pos: Vector2) -> void:
	var flame_world := global_position + _flame_origin
	var diff := flame_world - blast_pos
	var dist := diff.length()
	if dist > blast_react_radius:
		return

	var strength := 1.0 - (dist / blast_react_radius)
	var strength_sq := strength * strength
	_blast_flare = maxf(_blast_flare, blast_flare_energy * strength)
	var push_dir := diff.normalized() if dist > 1.0 else Vector2.UP
	_blast_push += push_dir * (10.0 * strength)

	if blast_sparks != null and strength_sq > 0.08:
		blast_sparks.direction = (push_dir + Vector2(0.0, -0.75)).normalized()
		blast_sparks.initial_velocity_min = 38.0 + 40.0 * strength
		blast_sparks.initial_velocity_max = 88.0 + 70.0 * strength
		blast_sparks.restart()
		blast_sparks.emitting = true
