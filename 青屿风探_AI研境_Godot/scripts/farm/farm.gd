extends Node2D

@onready var tip_location_farmland: Node2D = %TipLocationFarmland
## 农田里的所有作物
@onready var crops_root: Node2D = $排序层/农作物
## 雨天效果（雨、风、雾）
@onready var weather_rain: Node2D = $WeatherRain
## 积水效果
@onready var puddle: Node2D = $Puddle
## 场景里的树
@onready var trees_root: Node2D = $排序层/树木

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

## 会随风摇摆的树（只挂 tree.gdshader，不做水位）
var _sway_trees: Array[Sprite2D] = []


func _ready() -> void:
	# 天气和积水先全部关掉
	_setup_weather_initial()
	# 监听作物的收获信号
	_connect_crops()
	# 给场景里的树套上摇摆材质
	_setup_sway_trees()

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
		# 触发事件绑定到步骤1
		tip_location_farmland.trigger.connect(_Step1)

	else:
		# 设置位置
		FunctionLibrary.set_player_position(Vector2(205.0, 274.0))
		# 初始朝向
		FunctionLibrary.set_player_Initial_direction("up")

		# 转场效果
		IrisTransition.open_from_black(0.9)
		await IrisTransition.tween_finished


## 步骤 1
func _Step1() -> void:
	GameState.step = 1
	PlayerState.current_state = PlayerState.State.UNMOVE

	await _say("res://dialogues/first_farm/Step1.dialogue")

	TaskPanel._change_task("按“E”收集成熟的胡萝卜吧！")
	PlayerState.current_state = PlayerState.State.NORMAL
	TipAction._change_tip("互动：E")


## 步骤 2：收两个作物后触发，天气转坏
func _Step2() -> void:
	GameState.step = 2
	PlayerState.current_state = PlayerState.State.UNMOVE
	TaskPanel._hide_task_panel()
	TipAction._hide_tip()
	# 帷幕落下（升起由后续流程处理）
	await Curtain._curtain_show()

	await _say("res://dialogues/first_farm/Step2.dialogue")

	# 天气渐强、积水蔓延
	await _start_storm()


## 播放一段对话，播完返回。
func _say(dialogue_path: String) -> void:
	DialogueManager.show_dialogue_balloon_scene(
		"res://scenes/widget/dialogue/balloon.tscn",
		load(dialogue_path),
		"start"
	)
	await DialogueManager.dialogue_ended


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


## 作物收获回调：不管哪种萝卜，满 2 个就进入步骤 2
func _on_crop_harvested(crop: Node2D) -> void:
	if _step2_started or crop == null:
		return
	_harvested += 1
	if _harvested >= 2:
		_step2_started = true
		_Step2()

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
