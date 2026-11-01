extends Node
## 玩家和 NPC 共用：落脚帧与实际位移同时成立才发声。

@onready var body: CharacterBody2D = get_parent() as CharacterBody2D
@onready var sprite: AnimatedSprite2D = body.get_node("BodySprite")
var last_position: Vector2
var last_step_position: Vector2


func _ready() -> void:
	last_position = body.global_position
	last_step_position = last_position
	sprite.frame_changed.connect(_on_frame_changed)


func _physics_process(_delta: float) -> void:
	if body.global_position.distance_to(last_position) > 8.0:
		last_step_position = body.global_position
	last_position = body.global_position


func _on_frame_changed() -> void:
	var action := String(sprite.animation)
	if not (action.begins_with("walk_") or action.begins_with("run_")):
		return
	var frames := sprite.sprite_frames.get_frame_count(sprite.animation)
	if sprite.frame != 0 and sprite.frame != frames / 2:
		return
	var distance := body.global_position.distance_to(last_step_position)
	if distance < 1.0 or body.get_real_velocity().length() < 1.0:
		return
	last_step_position = body.global_position
	var surface: String = body.get_meta("footstep_surface", "soft")
	var level := -8.0 if body.is_in_group("Player") else -14.0
	AudioManager.play_sfx("step_" + surface, body.global_position, level)
