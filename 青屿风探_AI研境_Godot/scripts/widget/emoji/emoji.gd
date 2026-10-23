extends CanvasLayer
@onready var animated_sprite_2d: AnimatedSprite2D = $Control/Sprite2D/AnimatedSprite2D
@onready var control: Control = $Control
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	hide()

## 显示表情
func _show_emoji(emoji_name: String, character: String, show_time: float):
	# 获取说话位置标记
	var marker: DialogueMarker2D = DialogueMarker2D.find_for_character(character)
	if not is_instance_valid(marker): return
	# 设置新位置
	transform = Transform2D(0, marker.get_position_in_viewport())
	# 延迟显示
	await get_tree().create_timer(0.5).timeout
	# 播放出现动效
	show()
		# 第一帧隐藏
	control.modulate.a = 0.0
	animation_player.play("show_hide")
	await animation_player.animation_finished
	# 播放表情动画
	animated_sprite_2d.play(emoji_name)

	# 显示一段时间后消失
	await get_tree().create_timer(show_time).timeout
	# 消失动效
	animation_player.play_backwards("show_hide")
	await animation_player.animation_finished
	hide()
