extends Node2D

@onready var tip_location_farmland: Node2D = %TipLocationFarmland

func _ready() -> void:
	if GameState.is_first_farm:
		# 设置位置
		FunctionLibrary.set_player_position(Vector2(165.0, 115.0))
		# 初始朝向
		FunctionLibrary.set_player_Initial_direction("down")
		# 放大摄像机
		FunctionLibrary._set_camera_scale(Vector2(2.3, 2.3))
		# 进入不可控制状态
		PlayerState.current_state = PlayerState.State.UNCONTROL
		# 开场背景介绍
		TextIntro.play(
			"在遥远的海面上，有一个名叫“胡萝卜岛”的安静小岛...[wait=0.5]
			岛上的小兔子日出而作，日落而息。[wait=0.5]
			每天干活前，它都会看一眼气象局发送的天气预报。[wait=0.5]
			今天，小兔子像往常一样看了一眼预报面板[speed=0.3]...",
			0.13, 0.0, -1, 2.0
		)
		await TextIntro.finished
		# 帷幕落下
		await Curtain._curtain_show()
		# 开场对话
		DialogueManager.show_dialogue_balloon_scene(
        	"res://scenes/widget/dialogue/balloon.tscn",
        	load("res://dialogues/first_farm/first.dialogue"),
        	"start"
    	)
		await DialogueManager.dialogue_ended
		# 帷幕升起
		await Curtain._curtain_hide()
		# 进入正常状态
		PlayerState.current_state = PlayerState.State.NORMAL
		# 出现面板
		TaskPanel._change_task("前往农田，查看作物情况吧！")
		TipAction._change_tip(
			"移动：WASD
			奔跑：Shift"
		)
		# 触发事件绑定到步骤1
		tip_location_farmland.trigger.connect(_Step1)

	else:
		# 设置位置
		FunctionLibrary.set_player_position(Vector2(205.0, 274.0))
		# 初始朝向
		FunctionLibrary.set_player_Initial_direction("up")

		# 转场效果
		IrisTransition.open_from_black(0.9)
		await IrisTransition.tween_finished

## 步骤1
func _Step1() -> void:
	## 更新游戏步骤
	GameState.step = 1
	# 提示收集胡萝卜
	PlayerState.current_state = PlayerState.State.UNMOVE
	DialogueManager.show_dialogue_balloon_scene(
        "res://scenes/widget/dialogue/balloon.tscn",
        load("res://dialogues/first_farm/Step1.dialogue"),
        "start"
    )
	await DialogueManager.dialogue_ended
	PlayerState.current_state = PlayerState.State.NORMAL
	TipAction._change_tip(
			"互动：E"
		)
