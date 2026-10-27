extends Node2D

@onready var tip_location_farmland: Node2D = %TipLocationFarmland
@onready var tip_location_boat: Node2D = $TipLocationBoat
## 农田里的所有作物
@onready var crops_root: Node2D = $排序层/农作物
## 雨天效果（雨、风、雾）
@onready var weather_rain: Node2D = $WeatherRain
## 积水效果
@onready var puddle: Node2D = $Puddle
## 场景里的树
@onready var trees_root: Node2D = $排序层/树木
## 玩家节点
@onready var player: Node2D = $排序层/Rabbit
## 导航目标容器，子节点就是要依次走到的点
@onready var navigation_target: Node2D = $NavigationTarget

@onready var collection_point: Node2D = $CollectionPoint
@onready var collection_point_2: Node2D = $CollectionPoint2
@onready var collection_point_3: Node2D = $CollectionPoint3

#region 天气参数（都是「最终要到达」的值，按需改）

## 渐变总时长（秒）。
@export var storm_duration: float = 6.0

## 雨粒子最终数量。
@export var rain_max_amount: int = 2800

## 风的不透明度（0~1）。
@export var wind_max_opacity: float = 0.25

## 水雾密度（Fog1）。
@export var fog1_max_density: float = 0.25

## 雾气透明度（Fog2 的 alpha_p，越小越浓）。
@export var fog2_min_alpha: float = 5.0

## 雾气颗粒大小（Fog2 的 strength）。
@export var fog2_max_strength: float = 10.0

## 积水阈值（0~1，越小积水越多）。
@export var puddle_threshold: float = 0.55

## 积水不透明度。
@export var puddle_opacity: float = 0.22

#endregion

## 风效果材质（复制一份，避免影响其他实例）
var _wind_material: ShaderMaterial
## 水雾材质（Fog1）
var _fog_material: ShaderMaterial
## 雾气强度材质（Fog2）
var _fog2_material: ShaderMaterial

## 已收获的作物数量
var _harvested: int = 0
## 步骤 2 是否已经触发过
var _step2_started: bool = false

## 已收集的天气数据点数量
var _collected_count: int = 0
## 步骤 6 是否已经触发过
var _step6_started: bool = false

## 会随风摇摆的树（只挂 tree.gdshader，不做水位）
var _sway_trees: Array[Sprite2D] = []


func _ready() -> void:
	# 生成导航区域（供玩家自动行走）
	_bake_navigation()
	# 天气和积水先全部关掉
	_setup_weather_initial()
	# 监听作物的收获信号
	_connect_crops()
	# 监听天气数据收集点
	_connect_collection_points()
	# 给场景里的树套上摇摆材质
	_setup_sway_trees()
	# 
	tip_location_boat.hide()

	if GameState.is_first_farm:
		# 设置位置
		FunctionLibrary.set_player_position(Vector2(165.0, 115.0))
		# 初始朝向
		FunctionLibrary.set_player_Initial_direction("down")
		# 放大摄像机
		FunctionLibrary._set_camera_scale(Vector2(2.3, 2.3))
		# 进入不可控制状态
		PlayerState.current_state = PlayerState.State.UNCONTROL
		# 开场背景介绍
		TextIntro.play(
			"在遥远的海面上，有一个名叫“胡萝卜岛”的安静小岛...[wait=0.5]
			岛上的小兔子日出而作，日落而息。[wait=0.5]
			每天干活前，它都会看一眼气象局发送的天气预报。[wait=0.5]
			今天，小兔子像往常一样看了一眼预报面板[speed=0.3]...",
			0.13, 0.0, -1, 2.0
		)
		await TextIntro.finished
		# 帷幕落下
		await Curtain._curtain_show()
		# 开场对话
		DialogueManager.show_dialogue_balloon_scene(
			"res://scenes/widget/dialogue/balloon.tscn",
			load("res://dialogues/first_farm/first.dialogue"),
			"start"
		)
		await DialogueManager.dialogue_ended
		# 帷幕升起
		await Curtain._curtain_hide()
		# 进入正常状态
		PlayerState.current_state = PlayerState.State.NORMAL
		# 出现提示面板
		TaskPanel._change_task("前往农田，查看作物情况吧！")
		TipAction._change_tip(
			"移动：WASD
			奔跑：Shift"
		)

		tip_location_farmland._play_show()
		# 触发事件绑定到步骤1
		tip_location_farmland.trigger.connect(_Step1)
		GameState.is_first_farm = false

	else:
		# 设置位置
		FunctionLibrary.set_player_position(Vector2(205.0, 274.0))
		# 初始朝向
		FunctionLibrary.set_player_Initial_direction("up")
		_remove_random_crops(15, 1)

		# 转场效果
		IrisTransition.open_from_black(0.9)
		await IrisTransition.tween_finished

		if GameState.step == 4:
			_Step5()



## 步骤 1
func _Step1() -> void:
	# 触发事件解绑
	tip_location_farmland.trigger.disconnect(_Step1)
	GameState.step = 1
	PlayerState.current_state = PlayerState.State.UNMOVE

	await _say("res://dialogues/first_farm/Step1.dialogue")

	TaskPanel._change_task("按“E”收集成熟的胡萝卜吧！")
	PlayerState.current_state = PlayerState.State.NORMAL
	TipAction._change_tip("互动：E")


## 步骤 2：收两个作物后触发，天气转坏
func _Step2() -> void:
	GameState.step = 2
	# 无法移动
	PlayerState.current_state = PlayerState.State.UNMOVE
	# 隐藏面板
	TaskPanel._hide_task_panel()
	TipAction._hide_tip()
	# 帷幕落下（升起由后续流程处理）
	await Curtain._curtain_show()
	# 天气渐强、积水蔓延
	_start_storm()
	# 播放对话
	await _say("res://dialogues/first_farm/Step2.dialogue")

	# 沿 NavigationTarget 的子节点依次移动
	_move_along_targets()
	await get_tree().create_timer(2).timeout
	# 黑幕，讲述暴风雨结束后
	TextIntro.play(
		"暴风雨结束后[speed=0.3]...",
		0.25, 0.5, 0.5, 3.0
	)
	await get_tree().create_timer(1).timeout
	# 设置位置、朝向
	FunctionLibrary.set_player_position(Vector2(270.0, 220.0))
	FunctionLibrary.set_player_Initial_direction("right")
	
	# 停止风雨
	_stop_storm()
	_remove_random_crops(15, 1)
	_clear_drops()
	await TextIntro.finished
	
	_Step3()


## 步骤 3
func _Step3() -> void:
	GameState.step = 3
	# 播放对话
	await _say("res://dialogues/first_farm/Step3.dialogue")
	# 帷幕升起
	await Curtain._curtain_hide()
	PlayerState.current_state = PlayerState.State.NORMAL
	# 出现任务面板
	TaskPanel._change_task("乘坐小船，前往天气局")
	tip_location_boat._play_show()


## 步骤5
func _Step5() -> void:
	TaskPanel._change_task("前往指定地点，持续按“X”收集数据")
	collection_point._play_show()
	collection_point_2._play_show()
	collection_point_3._play_show()
	


## 播放一段对话，播完返回。
func _say(dialogue_path: String) -> void:
	DialogueManager.show_dialogue_balloon_scene(
		"res://scenes/widget/dialogue/balloon.tscn",
		load(dialogue_path),
		"start"
	)
	await DialogueManager.dialogue_ended


## 生成导航区域，让玩家能沿 NavigationTarget 自动行走。
## 直接给 NavigationPolygon 填顶点和面，避免 make_polygons_from_outlines 在 4.x 的兼容问题。
## 场景里已经有 NavigationRegion2D 就跳过。
func _bake_navigation() -> void:
	if get_node_or_null("NavigationRegion2D") != null:
		return

	var region := NavigationRegion2D.new()
	region.name = "NavigationRegion2D"
	region.enabled = true
	add_child(region)

	# 覆盖农田的矩形
	var corners := PackedVector2Array([
		Vector2(80.0, 60.0),
		Vector2(520.0, 60.0),
		Vector2(520.0, 340.0),
		Vector2(80.0, 340.0),
	])

	var polygon := NavigationPolygon.new()
	polygon.agent_radius = 6.0
	polygon.vertices = corners
	polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = polygon


## 让玩家沿 NavigationTarget 下子节点的顺序依次走过去。
## 直接复用玩家脚本里的 _move_to_navigation_position，靠它的 _is_navigating 判断是否走完。
func _move_along_targets() -> void:
	if player == null or navigation_target == null:
		return

	for child in navigation_target.get_children():
		if not (child is Node2D):
			continue
		var goal := (child as Node2D).global_position

		player.call("_move_to_navigation_position", goal)

		# call 之后 _is_navigating 已被置 true，等它变回 false 就是到点了
		var waited := 0.0
		while waited < 15.0:
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
			if not player.get("_is_navigating"):
				break


#region 作物计数

## 连接所有作物的收获信号
func _connect_crops() -> void:
	if crops_root == null:
		return
	for child in crops_root.get_children():
		if not child.has_signal("harvested"):
			continue
		if not child.harvested.is_connected(_on_crop_harvested):
			child.harvested.connect(_on_crop_harvested)


## 作物收获回调：收满 2 个就进入风暴剧情（第 2 步）。
## 只在第 6 步之前生效 —— 后面"回农场收胡萝卜"那一段不应该再触发风暴。
func _on_crop_harvested(crop: Node2D) -> void:
	if _step2_started or crop == null:
		return
	if GameState.step >= 6:
		return
	_harvested += 1
	if _harvested >= 2:
		_step2_started = true
		_Step2()

#endregion


#region 天气数据收集

## 监听场景里所有收集点。
func _connect_collection_points() -> void:
	for cp in get_tree().get_nodes_in_group("collection_point"):
		if not cp.has_signal("collected"):
			continue
		if not cp.collected.is_connected(_on_collection_point_collected):
			cp.collected.connect(_on_collection_point_collected)

	# 场景里的收集点如果有后加入的，等一帧再补连一次
	await get_tree().process_frame
	for cp in get_tree().get_nodes_in_group("collection_point"):
		if not cp.has_signal("collected"):
			continue
		if not cp.collected.is_connected(_on_collection_point_collected):
			cp.collected.connect(_on_collection_point_collected)


## 某个收集点收完后回调，集齐三个触发步骤 6。
func _on_collection_point_collected() -> void:
	if _step6_started:
		return
	_collected_count += 1
	print("[Farm] 天气数据已收集 ", _collected_count, " / 3")

	if _collected_count >= 3:
		_step6_started = true
		_step6()


## 步骤 6：三处天气数据都收集完后触发。
func _step6() -> void:
	GameState.step = 6

	# 记下这一关要收多少个成熟胡萝卜（后面放箱子要按这个数判断完成）
	GameState.carrots_required = 0
	if crops_root != null:
		for child in crops_root.get_children():
			if not child.name.begins_with("胡萝卜"):
				continue
			if child.has_method("is_mature") and child.call("is_mature"):
				GameState.carrots_required += 1
	print("[Farm] 需要收集的成熟胡萝卜 = ", GameState.carrots_required)

	# 任务面板更新
	TaskPanel._change_task("前往气象局提交数据")
	# 恢复玩家控制
	PlayerState.current_state = PlayerState.State.NORMAL
	TipAction._change_tip(
		"移动：WASD
		奔跑：Shift"
	)

#endregion


#region 作物增删

## 删除场景中的一部分胡萝卜。
## count 要删除的数量，传 <= 0 表示全部删掉。
## 删除后剩下的胡萝卜不受影响，收获计数也不变。
func _remove_carrots(count: int = 1) -> void:
	if crops_root == null:
		return

	# 先收集所有还活着的胡萝卜
	var carrots: Array[Node] = []
	for child in crops_root.get_children():
		if child.name.begins_with("胡萝卜"):
			carrots.append(child)

	var total := carrots.size()
	var to_remove := total if count <= 0 else mini(count, total)

	# 立即从场景里移走，避免本帧内还被射线或信号碰到
	for i in range(to_remove):
		var carrot := carrots[i]
		if not is_instance_valid(carrot):
			continue
		crops_root.remove_child(carrot)
		carrot.queue_free()

	print("[Farm] 删除胡萝卜 ", to_remove, " / ", total)


## 随机删除场景中的作物（胡萝卜、白萝卜、紫萝卜都算）。
## count      要删除的总数。
## seed_value 随机种子；传 0 表示自动生成。
## 返回实际使用的种子 —— 拿它再调一次就能复刻同样的删除结果。
func _remove_random_crops(count: int, seed_value: int = 0) -> int:
	if crops_root == null or count <= 0:
		return seed_value

	# 收集全部作物，顺序沿用场景里 get_children() 的顺序，保证可复现
	var all: Array[Node] = []
	for child in crops_root.get_children():
		if not (child is Node2D):
			continue
		if _is_crop(child):
			all.append(child)

	var total := all.size()
	if total == 0:
		print("[Farm] 场景里已经没有作物了")
		return seed_value

	var to_remove := mini(count, total)

	# 决定种子
	var used_seed := seed_value
	if used_seed == 0:
		used_seed = randi()

	# 用指定种子做 Fisher-Yates 洗牌
	var rng := RandomNumberGenerator.new()
	rng.seed = used_seed

	var order: Array[int] = []
	for i in range(total):
		order.append(i)

	for i in range(total - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp

	# 按洗好的顺序删前 to_remove 个
	for k in range(to_remove):
		var crop := all[order[k]]
		if not is_instance_valid(crop):
			continue
		crops_root.remove_child(crop)
		crop.queue_free()

	print("[Farm] 随机删除 ", to_remove, " / ", total, "  种子 = ", used_seed)
	return used_seed



## 判断节点是不是作物（胡萝卜 / 白萝卜 / 紫萝卜）。
func _is_crop(node: Node) -> bool:
	var n := node.name
	if n.begins_with("胡萝卜"):
		return true
	if n.begins_with("白萝卜"):
		return true
	if n.begins_with("紫萝卜"):
		return true
	return false


## 清除场景里所有掉落物。
## 掉落物是作物收获后弹出来的 Sprite2D，带 group "drop"。
func _clear_drops() -> void:
	var drops := get_tree().get_nodes_in_group("drop")
	var count := 0
	for drop in drops:
		if not is_instance_valid(drop):
			continue
		var parent := drop.get_parent()
		if parent != null:
			parent.remove_child(drop)
		drop.queue_free()
		count += 1
	print("[Farm] 清除掉落物 ", count, " 个")


#endregion


#region 树木摇摆

## 会摇摆的树节点名（排序层/树木 下）
const SWAY_TREE_NAMES := [
	"Tree4", "Tree2", "Tree3", "Tree1", "Tree",
	"树_中", "树_中2", "树_中3",
	"树丛_中", "树丛_中2", "树丛_中3",
]


## 给场景里这批树套上 tree.gdshader，风起时才摇。
func _setup_sway_trees() -> void:
	if trees_root == null:
		return
	var shader := load("res://shaders/weather/rain/tree/tree.gdshader") as Shader
	if shader == null:
		return

	for node_name in SWAY_TREE_NAMES:
		var node := trees_root.get_node_or_null(node_name)
		if node == null:
			continue
		var sprite := _find_sprite(node)
		if sprite == null or _sway_trees.has(sprite):
			continue

		var tex_size := Vector2(32.0, 32.0)
		if sprite.texture != null:
			tex_size = sprite.texture.get_size()

		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("tree_height", tex_size.y)
		mat.set_shader_parameter("root_y", tex_size.y * 0.5 - 4.0)
		mat.set_shader_parameter("right_bend", 12.0)
		mat.set_shader_parameter("rebound_ratio", 0.15)
		mat.set_shader_parameter("cycle_seconds", 1.4)
		# 风还没来，先完全不动
		mat.set_shader_parameter("wind_strength", 0.0)
		sprite.material = mat
		_sway_trees.append(sprite)


## 找节点下的第一个 Sprite2D。
func _find_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node
	for child in node.get_children():
		if child is Sprite2D:
			return child
	return null

#endregion


#region 天气与积水

## 初始把天气、积水全部关掉
func _setup_weather_initial() -> void:
	if weather_rain != null:
		weather_rain.visible = false

		_wind_material = _duplicate_shader(weather_rain.get_node_or_null("Wind") as ColorRect)
		if _wind_material != null:
			_wind_material.set_shader_parameter("opacity", 0.0)

		_fog_material = _duplicate_shader(weather_rain.get_node_or_null("Fog1") as ColorRect)
		if _fog_material != null:
			_fog_material.set_shader_parameter("density", 0.0)

		_fog2_material = _duplicate_shader(weather_rain.get_node_or_null("Fog2") as ColorRect)
		if _fog2_material != null:
			# alpha_p 越大越透明，先设成 100 等于没有雾
			_fog2_material.set_shader_parameter("alpha_p", 100.0)
			_fog2_material.set_shader_parameter("strength", 2.0)

		var rain := _find_rain()
		if rain != null:
			# amount 固定不变；用 amount_ratio 控制雨量，
			# 因为每帧改 amount 会重建粒子缓冲区，导致雨一直重置、到渐变结束才突然出现。
			rain.amount = rain_max_amount
			rain.amount_ratio = 0.0
			rain.emitting = true

	for sway_tree in _sway_trees:
		var sway_mat := sway_tree.material as ShaderMaterial
		if sway_mat != null:
			sway_mat.set_shader_parameter("wind_strength", 0.0)

	if puddle != null:
		puddle.visible = false
		var water_mat := puddle.get("water_material") as ShaderMaterial
		if water_mat != null:
			water_mat.set_shader_parameter("threshold", 1.0)
			water_mat.set_shader_parameter("water_opacity", 0.0)


## 天气渐变：雨从小变大、风渐强、雾变浓、积水蔓延。
func _start_storm() -> void:
	if weather_rain == null or puddle == null:
		return

	# 隐藏 Puddle 里的示例树
	var demo_tree := puddle.get_node_or_null("Tree")
	if demo_tree != null:
		demo_tree.visible = false

	weather_rain.visible = true
	puddle.visible = true

	# 恢复水波纹（之前 _stop_storm 关掉过）
	var rise_water := puddle.get("water_material") as ShaderMaterial
	if rise_water != null:
		rise_water.set_shader_parameter("ripple_opacity", 0.38)
	var rise_ripple := puddle.get_node_or_null("CanvasLayer/SubViewportRipple") as SubViewport
	if rise_ripple != null:
		rise_ripple.process_mode = Node.PROCESS_MODE_INHERIT
		rise_ripple.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var rain := _find_rain()
	var splash := _find_splash()
	var duration := storm_duration

	var tween := create_tween()
	tween.set_parallel(true)

	if rain != null:
		rain.emitting = true
		tween.tween_method(_set_rain_ratio, 0.0, 1.0, duration)

	# 风起：树木摇摆幅度从 0 涨到 1
	for sway_tree in _sway_trees:
		var sway_mat := sway_tree.material as ShaderMaterial
		if sway_mat == null:
			continue
		tween.tween_method(
			func(v: float) -> void: sway_mat.set_shader_parameter("wind_strength", v),
			0.0, 1.0, duration
		)

	if _wind_material != null:
		# 只提不透明度；speed 保持场景原值，改它会让风看起来像在加速
		tween.tween_method(
			func(v: float) -> void: _wind_material.set_shader_parameter("opacity", v),
			0.0, wind_max_opacity, duration
		)

	if _fog_material != null:
		tween.tween_method(
			func(v: float) -> void: _fog_material.set_shader_parameter("density", v),
			0.0, fog1_max_density, duration
		)

	if _fog2_material != null:
		# alpha_p 从 100（几乎透明）收到目标浓度
		tween.tween_method(
			func(v: float) -> void: _fog2_material.set_shader_parameter("alpha_p", v),
			100.0, fog2_min_alpha, duration
		)
		# 颗粒由细到粗
		tween.tween_method(
			func(v: float) -> void: _fog2_material.set_shader_parameter("strength", v),
			2.0, fog2_max_strength, duration
		)

	# 积水蔓延：分步改 threshold，避免每帧重建岸线
	_spread_puddle(duration)

	await tween.finished

	if splash != null:
		splash.emitting = true


## 雨停、风停，但积水保留。
## duration 传 <= 0 时用 storm_duration。
func _stop_storm(duration: float = -1.0) -> void:
	if weather_rain == null:
		return

	var d: float = duration if duration > 0.0 else storm_duration

	var rain := _find_rain()
	var rain_from := 0.0
	if rain != null:
		rain_from = rain.amount_ratio

	var wind_from := _float_param(_wind_material, "opacity")
	var fog1_from := _float_param(_fog_material, "density")
	var fog2_alpha_from := _float_param(_fog2_material, "alpha_p")
	var fog2_strength_from := _float_param(_fog2_material, "strength")

	var tween := create_tween()
	tween.set_parallel(true)

	# 雨：雨量收回到 0
	if rain != null:
		tween.tween_method(_set_rain_ratio, rain_from, 0.0, d)

	# 风停
	if _wind_material != null:
		tween.tween_method(
			func(v: float) -> void: _wind_material.set_shader_parameter("opacity", v),
			wind_from, 0.0, d
		)

	# 树停止摇摆：从当前幅度收回 0
	if not _sway_trees.is_empty():
		var sway_sample := _sway_trees[0].material as ShaderMaterial
		var sway_from := _float_param(sway_sample, "wind_strength")
		for sway_tree in _sway_trees:
			var sway_mat := sway_tree.material as ShaderMaterial
			if sway_mat == null:
				continue
			tween.tween_method(
				func(v: float) -> void: sway_mat.set_shader_parameter("wind_strength", v),
				sway_from, 0.0, d
			)

	# 水雾散掉
	if _fog_material != null:
		tween.tween_method(
			func(v: float) -> void: _fog_material.set_shader_parameter("density", v),
			fog1_from, 0.0, d
		)

	if _fog2_material != null:
		tween.tween_method(
			func(v: float) -> void: _fog2_material.set_shader_parameter("alpha_p", v),
			fog2_alpha_from, 100.0, d
		)
		tween.tween_method(
			func(v: float) -> void: _fog2_material.set_shader_parameter("strength", v),
			fog2_strength_from, 2.0, d
		)

	# 积水保留，但把水波纹关掉（雨停了就不该再有雨点打在水面上的涟漪）
	var water_mat := puddle.get("water_material") as ShaderMaterial
	if water_mat != null:
		water_mat.set_shader_parameter("ripple_opacity", 0.0)
	# 涟漪粒子也停掉，省性能（SubViewport 没有 visible，用渲染模式控制）
	var ripple_viewport := puddle.get_node_or_null("CanvasLayer/SubViewportRipple") as SubViewport
	if ripple_viewport != null:
		ripple_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		ripple_viewport.process_mode = Node.PROCESS_MODE_DISABLED

	await tween.finished

	# 雨彻底停掉、天气层隐藏
	if rain != null:
		rain.amount_ratio = 0.0
		rain.emitting = false
	weather_rain.visible = false


## 读某个材质上的 float 参数，取不到就当 0。
func _float_param(mat: ShaderMaterial, param: String) -> float:
	if mat == null:
		return 0.0
	var value = mat.get_shader_parameter(param)
	if value is float:
		return value
	return 0.0


## 雨量渐变（给 tween_method 用）。
## 只改 amount_ratio，不动 amount —— 改 amount 会重建粒子缓冲区，雨会不停重置。
func _set_rain_ratio(value: float) -> void:
	var rain := _find_rain()
	if rain != null:
		rain.amount_ratio = clampf(value, 0.0, 1.0)


## 积水从无到有，分步调 threshold（每帧改会每帧重建岸线，太慢）
func _spread_puddle(duration: float) -> void:
	var water_mat := puddle.get("water_material") as ShaderMaterial
	if water_mat == null:
		return

	var steps := 12
	var wait := duration / steps
	for i in range(steps + 1):
		var t := float(i) / steps
		water_mat.set_shader_parameter("threshold", lerpf(1.0, puddle_threshold, t))
		water_mat.set_shader_parameter("water_opacity", lerpf(0.0, puddle_opacity, t))
		if i < steps:
			await get_tree().create_timer(wait).timeout


## 雨粒子（递归查找，不怕场景层级变化）
func _find_rain() -> GPUParticles2D:
	return weather_rain.find_child("GPUParticles2D_Rain", true, false) as GPUParticles2D


## 雨溅起的水花粒子
func _find_splash() -> GPUParticles2D:
	return weather_rain.find_child("GPUParticles2D_Splash", true, false) as GPUParticles2D


## 复制 ColorRect 上的 ShaderMaterial，避免改到共享材质
func _duplicate_shader(rect: ColorRect) -> ShaderMaterial:
	if rect == null or not (rect.material is ShaderMaterial):
		return null
	var mat := rect.material.duplicate() as ShaderMaterial
	rect.material = mat
	return mat

#endregion
