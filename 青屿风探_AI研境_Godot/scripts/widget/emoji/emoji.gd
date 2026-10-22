extends CanvasLayer
@onready var animated_sprite_2d: AnimatedSprite2D = $Control/Sprite2D/AnimatedSprite2D

func _ready() -> void:
	hide()

## 显示表情
func _show_emoji(emoji_name: String, character: String, time: float):
	# 获取说话位置标记
	var marker: DialogueMarker2D = DialogueMarker2D.find_for_character(character)
	if not is_instance_valid(marker): return
	# 设置新位置
	transform = Transform2D(0, marker.get_position_in_viewport())

	show()

	animated_sprite_2d.play(emoji_name)

	# 显示一段时间后消失
	await get_tree().create_timer(time).timeout
	hide()
