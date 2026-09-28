extends Control

## 弹出ui的动画名称
const POP_UP_ANIMATION_NAME := "pop_up"


@onready var animation_player: AnimationPlayer = $BoxContainer/AnimationPlayer
@onready var professor: CharacterBody2D = $"../../Professor"
@onready var button: Button = $BoxContainer/Button


func _ready() -> void:
	# 开始时隐藏自身
	hide()
	# 绑定信号
	if is_instance_valid(professor):
		professor.wave_welcome_finished.connect(_pop_up_ui)
	
	button.pressed.connect(_go_farm)

## 延迟一定时间后显示并弹出ui。delay_time：延迟时间
func _pop_up_ui(delay_time: float) -> void:
	## 延迟
	await get_tree().create_timer(delay_time).timeout
	show()
	animation_player.play(POP_UP_ANIMATION_NAME)
	# 强制立即刷新、播放动画。否则ui会出现一瞬间的默认状态
	animation_player.advance(0.0)
	

## 转换场景到农场
func _go_farm():
	get_tree().change_scene_to_file("res://scenes/fram/farm.tscn")
