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

## 射线长度
@export var ray_length: float = 20
## 射线偏移
@export var ray_offset: Vector2 = Vector2(0.0, -5.0)

## 导航代理
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
## 是否在导航
var _is_navigating: bool = false



func _physics_process(_delta: float) -> void:
	# 项目输入映射：A/左、D/右、W/上、S/下；run 对应 Shift。
	# get_vector 会限制向量长度，避免斜向移动比水平或垂直移动更快。
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Shift 只改变移动速度与动作；没有方向输入时仍然播放待机动画。
	## 是否奔跑
	var is_running : bool = Input.is_action_pressed("run")
	## 是否收集：必须站在成熟作物的范围内，按 E 才播放采集动作
	var is_collection: bool = Input.is_action_pressed("interact") and has_harvestable_nearby()

	match PlayerState.current_state:
		# 正常
		0:
			update_movement(input_direction, is_running)
			update_animation(input_direction, is_running, is_collection)

			
			# 用朝向发线，松手后朝向仍然保留
			var dir : Vector2 = Vector2.ZERO
			match facing_direction:
				"up":
					dir = Vector2.UP
				"down":
					dir = Vector2.DOWN
				"left":
					dir = Vector2.LEFT
				"right":
					dir = Vector2.RIGHT
			## 获取检测结果
			var detection_result : Dictionary = ray_detection(global_position + ray_offset, (global_position + ray_offset) + dir * ray_length)
			if not detection_result.is_empty():
				var target: Object = detection_result["collider"]
				if is_instance_valid(target):
				## 调用被检测物体的方法
					if target.has_method("on_ray_detected"):
						target.call("on_ray_detected")
		# 无法移动
		1:
			# 无法移动状态下：停止移动
			update_animation(Vector2.ZERO, false)
		# 无法控制
		2:
			pass
			
	if _is_navigating:
		move_to_navigation_position()
		



## 附近是否有可采集的作物（已成熟且在 Area2D 范围内）。
func has_harvestable_nearby() -> bool:
	for crop in get_tree().get_nodes_in_group("crop"):
		if not is_instance_valid(crop):
			continue
		if crop.get("player_in_range") and crop.call("is_mature"):
			return true
	return false


## 根据输入设置速度，并执行带碰撞的移动。
func update_movement(input_direction: Vector2, is_running: bool = false) -> void:
	var speed : float = run_speed if is_running else move_speed
	velocity = input_direction * speed
	# velocity 的单位已经是像素/秒；move_and_slide 内部处理时间步长，
	# 因此这里不要再乘以 delta。碰到障碍时由 CharacterBody2D 处理滑动。
	move_and_slide()


## 选择待机、走路或奔跑动画；停止时沿用最后一次移动朝向。
func update_animation(input_direction: Vector2, is_running: bool = false, is_collection: bool = false) -> void:
	var action : String = "idle"
	if input_direction != Vector2.ZERO:
		action = "run" if is_running else "walk"
		update_facing_direction(input_direction)

	if input_direction == Vector2.ZERO:
		action = "hoe" if is_collection else "idle"

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

## 外部调用：移动到导航位置
func _move_to_navigation_position(target_position: Vector2) -> void:
	# 更新导航代理的导航目标位置
	navigation_agent.target_position = target_position

	_is_navigating = true

	# 导航结束信号
	await navigation_agent.navigation_finished
	
	_is_navigating = false


## 射线检测
func ray_detection(from_position: Vector2, to_position: Vector2) -> Dictionary:
	## 空间状态
	var space_state := get_world_2d().direct_space_state
	## 创建射线
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		from_position,
		to_position,
		1 << 2
	)
	# 开启检测area
	query.collide_with_areas = true
	## 检测结果
	var result = space_state.intersect_ray(query)

	# ## 保存调试数据
	# debug_ray_from = from_position
	# debug_ray_to = to_position
	# debug_ray_has_hit = not result.is_empty()

	# if debug_ray_has_hit:
	# 	debug_ray_hit_position = result["position"]
	# ## 请求重新绘制
	# queue_redraw()

	return result
	
# ## 射线调试绘制
# var debug_ray_from: Vector2
# var debug_ray_to: Vector2
# var debug_ray_hit_position: Vector2
# var debug_ray_has_hit: bool = false

# ## 绘制调试射线
# func _draw() -> void:
# 	## 从全局坐标转换为当前节点的局部坐标
# 	var start := to_local(debug_ray_from)
# 	var end := to_local(debug_ray_to)

# 	## 绘制射线起点
# 	draw_circle(start, 3.0, Color.CYAN)

# 	if debug_ray_has_hit:
# 		## 命中：绿色线段从起点延伸到碰撞位置
# 		var hit := to_local(debug_ray_hit_position)
# 		draw_line(start, hit, Color.LIME_GREEN, 2.0)
# 		draw_circle(hit, 4.0, Color.RED)
# 	else:
# 		## 未命中：红色线段延伸到射线终点
# 		draw_line(start, end, Color.RED, 2.0)


## 内部调用：移动到导航位置
func move_to_navigation_position() -> void:
	# 更新玩家状态
	PlayerState.current_state = PlayerState.State.UNCONTROL

	# 导航结束后不再移动
	if not navigation_agent.is_navigation_finished():
		# 移动用真实方向，不能取整：取整后斜向长度为 1.414，速度会忽快忽慢，
		# 加上路径点每帧变化，方向会在 (1,0) 和 (1,1) 之间跳，看起来就像抽搐。
		var move_direction: Vector2 = (navigation_agent.get_next_path_position() - global_position).normalized()
		# 动画朝向仍按四方向取整，避免动画频繁切换。
		var face_direction: Vector2 = move_direction.round()

		update_movement(move_direction)
		update_animation(face_direction)
	
