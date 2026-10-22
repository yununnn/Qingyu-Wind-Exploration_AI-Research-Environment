extends Area2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
    self.body_entered.connect(open_chest)
    self.body_exited.connect(close_chest)

func open_chest(body: Node2D) -> void:
    if not body.is_in_group("Player"): return

    if animated_sprite_2d.is_playing():
        await animated_sprite_2d.animation_finished
    animated_sprite_2d.play("normal")
    
func close_chest(body: Node2D) -> void:
    if not body.is_in_group("Player"): return

    if animated_sprite_2d.is_playing():
        await animated_sprite_2d.animation_finished
    animated_sprite_2d.play_backwards("normal")


