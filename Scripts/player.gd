extends CharacterBody2D

@export var speed: float = 300.0
@export var jump_velocity: float = -400.0

# Reference your visual node (AnimatedSprite2D or Sprite2D)
@onready var player: Node2D = $Player

# Get the default gravity from Project Settings
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

func _physics_process(delta: float) -> void:
	# 1. Apply gravity when in the air
	if not is_on_floor():
		velocity.y += gravity * delta

	# 2. Handle jump input
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# 3. Get horizontal input (-1 for left, 1 for right, 0 for idle)
	var direction: float = Input.get_axis("ui_left", "ui_right")
	
	if direction != 0:
		velocity.x = direction * speed
		update_facing_direction(direction)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)

	move_and_slide()

func update_facing_direction(direction: float) -> void:
	if direction > 0:
		player.scale.x = 1
	elif direction < 0:
		player.scale.x = -1
