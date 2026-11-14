extends RigidBody2D

var _age: float = 0.0
var _fading: bool = false


func _ready() -> void:
	# Layer 3 (4) only collides with layer 1 (world TileMap); player exclusion is added on spawn.
	collision_layer = 4
	collision_mask = 1
	gravity_scale = 0.9
	linear_damp = 0.35
	angular_damp = 1.4

	var mat := PhysicsMaterial.new()
	mat.bounce = 0.42
	mat.friction = 0.85
	physics_material_override = mat

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(7.5, 3.0)
	col.shape = shape
	add_child(col)

	var sprite := Sprite2D.new()
	sprite.texture = preload("res://Assets/spent_shell.png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(1.5, 1.5)
	add_child(sprite)


func _process(delta: float) -> void:
	_age += delta
	# Keep shells resting on the ground for a long time; fade gently only when very old.
	if _age > 25.0 and not _fading:
		_fading = true
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.6)
		tw.tween_callback(queue_free)
