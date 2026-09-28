extends CharacterBody2D

## 招手欢迎 结束信号
signal wave_welcome_finished

## 角色动画节点，负责播放动画
@onready var body_sprite: AnimatedSprite2D = $BodySprite


## 播放招手欢迎动画
func wave_welcome() -> void:
	## 待机动画名
	const idle_name := "idle"
	## 招手动画名
	const wave_name := "wave"
	
	# 播放招手动画
	body_sprite.play(wave_name)
	# 等待当前动画播放结束
	await body_sprite.animation_finished
	# 招手结束后播放待机动画
	body_sprite.play(idle_name)
	# 招手欢迎 结束，发出信号
	wave_welcome_finished.emit(0.1)


func _on_color_rect_black_finished() -> void:
	wave_welcome()
	
