extends Node2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var area_2d: Area2D = $Area2D

func _ready() -> void:
    area_2d.body_entered.connect(open_door)
    area_2d.body_exited.connect(close_door)

func open_door(body: Node2D) -> void:
    if not body.is_in_group("Player"): return
    if animated_sprite_2d.is_playing():
        await animated_sprite_2d.animation_finished
    animated_sprite_2d.play("normal")
    
func close_door(body: Node2D) -> void:
    if not body.is_in_group("Player"): return
    if animated_sprite_2d.is_playing():
        await animated_sprite_2d.animation_finished
    animated_sprite_2d.play_backwards("normal")
