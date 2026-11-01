extends Node2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var area_2d: Area2D = $Area2D
var _wanted_open := false
var _door_open := false

func _ready() -> void:
    area_2d.body_entered.connect(open_door)
    area_2d.body_exited.connect(close_door)

func open_door(body: Node2D) -> void:
    if not body.is_in_group("Player"): return
    _wanted_open = true
    if animated_sprite_2d.is_playing():
        await animated_sprite_2d.animation_finished
    if not _wanted_open or _door_open: return
    _door_open = true
    animated_sprite_2d.play("normal")
    AudioManager.play_sfx("door_open", global_position, -1.0)
    
func close_door(body: Node2D) -> void:
    if not body.is_in_group("Player"): return
    _wanted_open = false
    if animated_sprite_2d.is_playing():
        await animated_sprite_2d.animation_finished
    if _wanted_open or not _door_open: return
    _door_open = false
    animated_sprite_2d.play_backwards("normal")
    AudioManager.play_sfx("door_close", global_position, -7.0)
