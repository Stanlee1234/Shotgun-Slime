extends Control # Or Control, depending on your HUD root node

# Update these paths to match your scene tree
@onready var hud_sprite: AnimatedSprite2D = $Shell1
@onready var player: CharacterBody2D = $"../Player"

func _ready() -> void:
	hud_sprite.play("normal")
	
	# Connect player signals
	player.shot_fired.connect(_on_player_shot_fired)
	player.reloaded.connect(_on_player_reloaded)
	
	# Return to "normal" once the "refresh" animation finishes
	hud_sprite.animation_finished.connect(_on_hud_animation_finished)


func _on_player_shot_fired() -> void:
	hud_sprite.play("shoot")


func _on_player_reloaded() -> void:
	hud_sprite.play("refresh")


func _on_hud_animation_finished() -> void:
	if hud_sprite.animation == "refresh":
		hud_sprite.play("normal")
