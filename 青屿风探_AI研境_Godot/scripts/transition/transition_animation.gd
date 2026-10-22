extends CanvasLayer

@onready var animation_player_boat: AnimationPlayer = $AnimationPlayerBoat
@onready var animation_player_rabbit: AnimationPlayer = $AnimationPlayerRabbit
@onready var color_rect: ColorRect = $ColorRect

var tween:Tween

@export var show_time : float = 0.9
@export var hide_time : float = 0.9
@export var black_time : float = 1.5

signal tween_finished


func _ready() -> void:
	# 隐藏自身
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_rect.modulate.a = 0.0
	hide()

	

func play_animation() -> void:
	show()
	# 播放动画
	animation_player_rabbit.play("normal_rabbit")
	animation_player_boat.play("normal_boat")
	# 逐渐出现
	await _show_Control(show_time)
	# 延迟
	await get_tree().create_timer(black_time).timeout
	# 逐渐消失
	await _hide_Control(hide_time)
	tween_finished.emit()
	hide()
	


## 显示控件，并播放tween
func _show_Control(time: float = 1.5) -> void:
	# 如果 tween 变量中已有 Tween，就先停止它
	if tween: tween.kill()

	tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(color_rect, "modulate:a", 1.0, time).from(0.0)
	await tween.finished

## 隐藏控件，并播放tween
func _hide_Control(time: float = 1.5) -> void:
	# 如果 tween 变量中已有 Tween，就先停止它
	if tween: tween.kill()
	
	tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(color_rect, "modulate:a", 0.0, time).from(1.0)
	await tween.finished
