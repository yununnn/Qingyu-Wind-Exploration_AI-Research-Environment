extends Node2D

func _ready() -> void:
	if GameState.is_first_farm:
		# 设置位置
		FunctionLibrary.set_player_position(Vector2(165.0, 110.0))
		# 初始朝向
		FunctionLibrary.set_player_Initial_direction("down")
		# 放大摄像机
		FunctionLibrary._set_camera_scale(Vector2(2.3, 2.3))
		# 黑幕渐隐
		BlackTransition._black_to_light(2.0)
		await BlackTransition.tween_finished
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
		
