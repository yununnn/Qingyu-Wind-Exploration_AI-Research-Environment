extends Node

@export var position_offset : Vector2 = Vector2(0, -15)

## 获取当前场景中的玩家节点
func get_player() -> Player:
	var player : Player = get_tree().get_first_node_in_group("Player")
	return player


## 获取玩家的全局位置
func get_player_position() -> Vector2:
	var player := get_player()

	if player == null:
		push_warning("当前场景中没有找到玩家节点")
		return Vector2.ZERO

	return player.global_position + position_offset

## 设置玩家初始位置
func set_player_position(position: Vector2) -> void:
	var player : Player = get_player()

	if player == null:
		push_warning("当前场景中没有找到玩家节点")
		return
	player.position = position


## 获取玩家在屏幕上的归一化坐标（UV）
func get_player_viewport_uv() -> Vector2:
	## 获取玩家视口大小
	var viewport_size : Vector2 = get_player().get_viewport().get_visible_rect().size
	## 获取玩家在视口中相对的像素坐标
	var viewport_pos: Vector2 = get_player().get_global_transform_with_canvas().origin + position_offset

	return viewport_pos / viewport_size

## 判断当前场景是否存在玩家
func has_player() -> bool:
	return get_player() != null


## 设置玩家初始朝向
func set_player_Initial_direction(facing_direction: String):
	# 初始朝向
	get_player().facing_direction = facing_direction
	get_player().play_animation("idle_" + facing_direction)
	

## 相机动画结束信号
signal tween_camera_finished
var tween_camera: Tween
## 缩放玩家相机
func _camera_scale_tween(scale_value: Vector2, tween_speed: float) -> void:
	# 玩家相机
	var player_Camera: Camera2D = get_player().get_node("Camera2D")
	# 等待动画完成
	if tween_camera: tween_camera.kill()

	tween_camera = create_tween();
	tween_camera.set_trans(Tween.TRANS_QUAD)
	tween_camera.set_ease(Tween.EASE_IN_OUT)
	tween_camera.tween_property(player_Camera, "zoom", scale_value, tween_speed)

	await tween_camera.finished
	tween_camera_finished.emit()
	
## 设置玩家相机缩放
func _set_camera_scale(scale_value: Vector2) -> void:
	# 玩家相机
	var player_Camera: Camera2D = get_player().get_node("Camera2D")
	player_Camera.zoom = scale_value
