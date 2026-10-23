extends Node2D

func _ready() -> void:
	if GameState.is_first_farm:
		# 设置位置
		FunctionLibrary.set_player_position(Vector2(165.0, 110.0))
		# 初始朝向
		FunctionLibrary.set_player_Initial_direction("down")
		# 放大摄像机
		FunctionLibrary._set_camera_scale(Vector2(2.3, 2.3))
		# 进入不可控制状态
		PlayerState.current_state = PlayerState.State.UNCONTROL
		# 开场背景介绍
		TextIntro.play("在遥远的海面上，有一个名叫“胡萝卜岛”的安静小岛...[wait=0.5]
		岛上的小兔子日出而作，日落而息。[wait=0.5]
		每天干活前，它都会看一眼气象局发送的天气预报。[wait=0.5]
		今天，小兔子像往常一样看了一眼预报面板[speed=0.3]...", 0.13, 0.0, -1, 2.0)
		await TextIntro.finished
		# 帷幕落下
		Curtain._curtain_show()
		await Curtain.animation_finished
		# 开场对话
		DialogueManager.show_dialogue_balloon_scene(
        "res://scenes/widget/dialogue/balloon.tscn",
        load("res://dialogues/first_farm/first.dialogue"),
        "start"
    	)
	else:
		# 设置位置
		FunctionLibrary.set_player_position(Vector2(205.0, 274.0))
		# 初始朝向
		FunctionLibrary.set_player_Initial_direction("up")

		# 转场效果
		IrisTransition.open_from_black(0.9)
		await IrisTransition.tween_finished
		
