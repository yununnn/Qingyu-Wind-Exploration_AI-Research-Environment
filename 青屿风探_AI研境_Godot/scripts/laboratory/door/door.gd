extends Area2D

## 碰撞节点
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	# 连接“有物理物体进入区域”的信号。
	# 进入时，Godot 会调用 _on_body_entered，并传入进入的物体。
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# 只有属于 Player 分组的节点才能触发传送。
	if body.is_in_group("Player"):
		# 延后执行切换，避免在物理检测回调中直接移除当前场景。
		back.call_deferred()

## 返回农场
func back() -> void:
	# 加载并切换到农场场景。
	get_tree().change_scene_to_file("res://scenes/fram/farm.tscn")