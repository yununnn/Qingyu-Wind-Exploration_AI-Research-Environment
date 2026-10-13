extends Control



## 消息行场景
const MESSAGE_ROW = preload("res://scenes/widget/communication_device/message_row.tscn")
## 消息容器
@onready var messages: VBoxContainer = $ChatScroll/Padding/Messages
## 对话资源
@export var dialogue_resource: DialogueResource

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

	var row = MESSAGE_ROW.instantiate()
	var row1 = MESSAGE_ROW.instantiate()
	var row2 = MESSAGE_ROW.instantiate()
	var row3 = MESSAGE_ROW.instantiate()
	var row4 = MESSAGE_ROW.instantiate()
	var row5 = MESSAGE_ROW.instantiate()

	# 添加到消息容器中
	messages.add_child(row)
	messages.add_child(row1)
	messages.add_child(row2)
	messages.add_child(row3)
	messages.add_child(row4)
	messages.add_child(row5)
	# row.setup(current_line.character, current_line.text)

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
