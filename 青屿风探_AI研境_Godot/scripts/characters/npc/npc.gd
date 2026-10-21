extends CharacterBody2D
class_name Npc


## NPC动画节点
@onready var body_sprite: AnimatedSprite2D = $BodySprite
## NPC检测区域
@onready var detection: Area2D = $Detection
## BodySprite 上的 Shader 材质。
@onready var shader_material: ShaderMaterial = body_sprite.material as ShaderMaterial
## 玩家是否进入NPC检测区域
var is_entered: bool = false
## 是否正在进行对话
var is_dialogue_active: bool = false


## 移动速度，单位为像素/秒。
@export var move_speed: float = 50.0
## 记录最后一次移动的朝向，松开方向键后仍朝向该方向。也可以用于设置初始方向
@export var facing_direction: String = "up"
## 导航代理
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
## 是否在导航
var _is_navigating: bool = false


func _ready() -> void:
	# 初始朝向
	play_animation("idle_" + facing_direction)
	# 绑定信号
	detection.body_entered.connect(_on_body_entered)
	detection.body_exited.connect(_on_body_exited)
	DialogueManager.dialogue_started.connect(_started_dialogue)
	DialogueManager.dialogue_ended.connect(_end_dialogue)


func _process(_delta: float) -> void:
	# 玩家进入了检测区域并且按下了交互键，且不在进行对话，才可触发对话。
	if is_entered and not is_dialogue_active and Input.is_action_just_pressed("interact"):
		_try_start_dialogue()

## ------ 移动 ------ ##
## 根据输入设置速度，并执行带碰撞的移动。
func update_movement(input_direction: Vector2) -> void:
	var speed := move_speed
	velocity = input_direction * speed
	# velocity 的单位已经是像素/秒；move_and_slide 内部处理时间步长，
	# 因此这里不要再乘以 delta。碰到障碍时由 CharacterBody2D 处理滑动。
	move_and_slide()

## 选择待机、走路或奔跑动画；停止时沿用最后一次移动朝向。
func update_animation(input_direction: Vector2) -> void:
	var action := "idle"
	if input_direction != Vector2.ZERO:
		action = "walk"
		update_facing_direction(input_direction)

	# 只在动作或朝向改变时切换动画，让当前动画持续播放。
	var animation_name : String = action + "_" + facing_direction
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


## ------ 导航 ------ ##
func _physics_process(_delta: float) -> void:
	if _is_navigating:
		move_to_navigation_position()

## 外部调用：移动到导航位置
func _move_to_navigation_position(target_position: Vector2) -> void:
	# 更新导航代理的导航目标位置
	navigation_agent.target_position = target_position

	_is_navigating = true

	# 导航结束信号
	await navigation_agent.navigation_finished

	_is_navigating = false
	# 停止移动，播放待机
	velocity = Vector2.ZERO
	update_animation(Vector2.ZERO)

## 内部调用：移动到导航位置
func move_to_navigation_position() -> void:
	# 导航结束后不再移动
	if not navigation_agent.is_navigation_finished():
		# 获取移动到导航位置所面朝的方向，需要进行本地、归一化处理
		var direction: Vector2 = to_local(navigation_agent.get_next_path_position()).normalized().round()
		# 开始移动
		update_movement(direction)
		update_animation(direction)
	

## ------ 检测 ------ ##
## 当有物体进入碰撞区域时触发
func _on_body_entered(body: Node2D) -> void:
	# 只有属于 Player 分组的节点才能触发。
	if body.is_in_group("Player"):
		is_entered = true
		# 显示轮廓
		show_outline()
		
## 当有物体离开碰撞区域时触发
func _on_body_exited(body: Node2D) -> void:
	# 只有属于 Player 分组的节点才能触发。
	if body.is_in_group("Player"):
		is_entered = false
		# 关闭轮廓
		hide_outline()
		

## 显示轮廓
func show_outline() -> void:	
	shader_material.set_shader_parameter("outline_color", Color.WHITE)

## 隐藏轮廓
func hide_outline() -> void:
	shader_material.set_shader_parameter("outline_color", Color(0, 0, 0, 0))


## ------ 对话 ------ ##
## 尝试开始对话
func _try_start_dialogue() -> void:
	pass
	
func _started_dialogue(_resource: DialogueResource) -> void:
	# 进入对话状态
	PlayerState.current_state = PlayerState.State.UNMOVE
	is_dialogue_active = true

## 结束对话
func _end_dialogue(_resource: DialogueResource) -> void:
	# 恢复正常状态
	PlayerState.current_state = PlayerState.State.NORMAL
	is_dialogue_active = false
