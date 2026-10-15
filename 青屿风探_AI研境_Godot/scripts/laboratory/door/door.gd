extends Area2D

## 碰撞节点
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	# 绑定信号
	body_entered.connect(_on_body_entered)

## 当有物体进入碰撞区域时触发
func _on_body_entered(body: Node2D) -> void:
	# 只有属于 Player 分组的节点才能触发传送。
	if body.is_in_group("Player"):
		back();

## 返回农场
func back() -> void:
	# 加载并切换到农场场景。
	get_tree().change_scene_to_file("res://scenes/fram/farm.tscn")