extends Control

@onready var right_button: TextureButton = $RightButton
@onready var left_button: TextureButton = $LeftButton
@onready var camera_2d: Camera2D = $"../../Camera2D"

## 每次移动距离
@export var pan_distance: float = 1920.0

## 移动时间
@export var pan_duration: float = 0.5

var camera_tween: Tween


func _ready() -> void:
	# 绑定信号
	left_button.pressed.connect(_viewport_pan_left)
	right_button.pressed.connect(_viewport_pan_right)

	# 初始化按钮状态
	_update_button_visibility()


## 视角左移
func _viewport_pan_left() -> void:
	_pan_camera(Vector2.LEFT)


## 视角右移
func _viewport_pan_right() -> void:
	_pan_camera(Vector2.RIGHT)


## 平滑移动摄像机
func _pan_camera(direction: Vector2) -> void:
	if not is_instance_valid(camera_2d):
		return

	# 正在移动时，不允许再次移动
	if camera_tween != null and camera_tween.is_running():
		return

	var visible_size := _get_visible_size()

	var min_x := float(camera_2d.limit_left)
	var max_x := float(camera_2d.limit_right) - visible_size.x

	# 防止视口宽度大于地图宽度
	max_x = max(min_x, max_x)

	# 计算目标位置
	var target_position := camera_2d.position + direction * pan_distance

	target_position.x = clamp(
		target_position.x,
		min_x,
		max_x
	)

	# 已经无法继续移动
	if is_equal_approx(target_position.x, camera_2d.position.x):
		_update_button_visibility()
		return

	# 移动期间直接隐藏全部按钮
	_hide_buttons()

	# 创建平滑移动 Tween
	camera_tween = create_tween()

	camera_tween.set_trans(Tween.TRANS_QUAD)
	camera_tween.set_ease(Tween.EASE_IN_OUT)

	camera_tween.tween_property(
		camera_2d,
		"position",
		target_position,
		pan_duration
	)

	# 等待移动完成
	await camera_tween.finished

	camera_tween = null

	# 移动完成后，根据当前位置决定按钮显示状态
	_update_button_visibility()


## 获取当前摄像机实际可视区域大小
func _get_visible_size() -> Vector2:
	var viewport_size := camera_2d.get_viewport_rect().size
	return viewport_size / camera_2d.zoom


## 移动过程中隐藏所有按钮
func _hide_buttons() -> void:
	left_button.hide()
	right_button.hide()


## 根据当前摄像机位置更新按钮显示状态
func _update_button_visibility() -> void:
	if not is_instance_valid(camera_2d):
		return

	var visible_size := _get_visible_size()

	var min_x := float(camera_2d.limit_left)
	var max_x := float(camera_2d.limit_right) - visible_size.x

	max_x = max(min_x, max_x)

	var current_x := camera_2d.position.x

	# 只要还能向左移动，就显示左按钮
	left_button.visible = current_x > min_x + 0.1

	# 只要还能向右移动，就显示右按钮
	right_button.visible = current_x < max_x - 0.1
