extends StaticBody2D

## 检测节点
@onready var detection: Area2D = $Detection

func _ready() -> void:
	# 绑定信号
	detection.body_entered.connect(_on_body_entered)


## 当有物体进入检测区域时触发
func _on_body_entered(body: Node2D) -> void:
	# 只有属于 Player 分组的节点才能触发传送。
	if body.is_in_group("Player") and GameState.step >= 3:
		go_laboratory();

# ## 返回农场
func go_laboratory() -> void:
	# 加载并切换到农场场景。
	IrisTransition.close_to_black(0.9)
	await IrisTransition.tween_finished
	TransitionAnimation.play_animation()
	await TransitionAnimation.tween_finished
	
	# 更换场景
	get_tree().change_scene_to_file(
		"res://scenes/laboratory/laboratory.tscn"
	)
