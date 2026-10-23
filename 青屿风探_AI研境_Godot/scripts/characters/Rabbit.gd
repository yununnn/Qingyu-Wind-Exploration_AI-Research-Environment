extends CharacterBody2D
class_name Player
## 俯视角兔子角色：WASD 或方向键移动，按住 Shift 奔跑。
## 将本脚本挂在 Rabbit 根节点，BodySprite 使用“动作_方向”动画命名。

## 移动速度，单位为像素/秒。
@export var move_speed: float = 50.0
## 按住 Shift 时的奔跑速度，单位为像素/秒。
@export var run_speed: float = 60.0

## 记录最后一次移动的朝向，松开方向键后仍朝向该方向。也可以用于设置初始方向
@export var facing_direction: String = "up"

## 负责播放序列帧的节点。
@onready var body_sprite: AnimatedSprite2D = $BodySprite

## 导航代理
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
## 是否在导航
var _is_navigating: bool = false



func _physics_process(_delta: float) -> void:
	match PlayerState.current_state:
		# 正常
		0:
			# 项目输入映射：A/左、D/右、W/上、S/下；run 对应 Shift。
			# get_vector 会限制向量长度，避免斜向移动比水平或垂直移动更快。
			var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			# Shift 只改变移动速度与动作；没有方向输入时仍然播放待机动画。
			var is_running : bool = Input.is_action_pressed("run")
			update_movement(input_direction, is_running)
			update_animation(input_direction, is_running)
		# 对话
		1:
			# 对话状态下：停止移动，播放待机动画，并直接返回。
			update_animation(Vector2.ZERO, false)
			pass
		# 过场动画
		2:
			pass
	if _is_navigating:
		move_to_navigation_position()
		



## 根据输入设置速度，并执行带碰撞的移动。
func update_movement(input_direction: Vector2, is_running: bool = false) -> void:
	var speed := run_speed if is_running else move_speed
	velocity = input_direction * speed
	# velocity 的单位已经是像素/秒；move_and_slide 内部处理时间步长，
	# 因此这里不要再乘以 delta。碰到障碍时由 CharacterBody2D 处理滑动。
	move_and_slide()


## 选择待机、走路或奔跑动画；停止时沿用最后一次移动朝向。
func update_animation(input_direction: Vector2, is_running: bool = false) -> void:
	var action := "idle"
	if input_direction != Vector2.ZERO:
		action = "run" if is_running else "walk"
		update_facing_direction(input_direction)

	# 只在动作或朝向改变时切换动画，让当前动画持续播放。
	var animation_name := action + "_" + facing_direction
	if body_sprite.animation != animation_name:
		play_animation(animation_name)


## 播放指定名称的动画。
func play_animation(animation_name: String) -> void:
	body_sprite.play(animation_name)


## 根据非零移动输入记录朝向；素材只有四方向，斜向时优先朝左右。
func update_facing_direction(input_direction: Vector2) -> void:
	if input_direction.x != 0.0:
		facing_direction = "right" if input_direction.x > 0.0 else "left"
	else:
		facing_direction = "down" if input_direction.y > 0.0 else "up"

## 外部调用：移动到导航位置
func _move_to_navigation_position(target_position: Vector2) -> void:
	# 更新导航代理的导航目标位置
	navigation_agent.target_position = target_position

	_is_navigating = true

	# 导航结束信号
	await navigation_agent.navigation_finished
	
	_is_navigating = false

## 内部调用：移动到导航位置
func move_to_navigation_position() -> void:
	# 更新玩家状态
	PlayerState.current_state = PlayerState.State.UNCONTROL

	# 导航结束后不再移动
	if not navigation_agent.is_navigation_finished():
		# 获取移动到导航位置所面朝的方向，需要进行本地、归一化处理
		var direction: Vector2 = to_local(navigation_agent.get_next_path_position()).normalized().round()
		# 开始移动
		update_movement(direction)
		update_animation(direction)
	