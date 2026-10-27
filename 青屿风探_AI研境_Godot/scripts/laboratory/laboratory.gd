extends Node2D


@onready var player: Player = FunctionLibrary.get_player()
@onready var director: Npc = $Scene/Decoration/Director

## 实验室里的三个导航点
@onready var target1: Node2D = $NavigationTarget/Target1
@onready var target2: Node2D = $NavigationTarget/Target2
@onready var target3: Node2D = $NavigationTarget/Target3
@onready var target4: Node2D = $NavigationTarget/Target4
@onready var tip_location: Node2D = $TipLocation

func _ready() -> void:
	# 生成导航区域（实验室场景没有，导航需要它）
	_bake_navigation()
	# 初始朝向
	FunctionLibrary.set_player_Initial_direction("up")
	# 入场效果
	IrisTransition.open_from_black(0.9)
	await IrisTransition.tween_finished
	
	if GameState.step == 3:
		TaskPanel._hide_task_panel()
		_step_4()
	else:
		pass

		
## 生成导航区域，让玩家和 Director 能自动行走。
## 场景里已经有 NavigationRegion2D 就跳过。
func _bake_navigation() -> void:
	if get_node_or_null("NavigationRegion2D") != null:
		return

	var region := NavigationRegion2D.new()
	region.name = "NavigationRegion2D"
	region.enabled = true
	add_child(region)

	# 用地面 tile 的范围作为可行走区域
	var rect := Rect2(-32.0, -32.0, 320.0, 320.0)
	var ground := get_node_or_null("Scene/Ground") as TileMapLayer
	if ground != null and ground.tile_set != null:
		var used := ground.get_used_rect()
		var tile_size := Vector2(ground.tile_set.tile_size)
		rect = Rect2(Vector2(used.position) * tile_size, Vector2(used.size) * tile_size)

	var corners := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])

	var polygon := NavigationPolygon.new()
	polygon.agent_radius = 4.0
	polygon.vertices = corners
	polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_polygon = polygon


func _step_4() -> void:
	GameState.step = 4

	# 帷幕
	Curtain._curtain_show()

	# 更新玩家状态
	PlayerState.current_state = PlayerState.State.UNCONTROL

	# 玩家走到 Target1
	await player._move_to_navigation_position(target1.global_position)

	# 更新玩家状态
	PlayerState.current_state = PlayerState.State.UNCONTROL
	
	# 主角说话
	await _say("res://dialogues/laboratory/step4.dialogue")

	# Director 先走到 Target2
	await director._move_to_navigation_position(target2.global_position)
	# 朝向下
	director.facing_direction = "down"
	director.play_animation("idle_" + "down")
	
	await _say("res://dialogues/laboratory/step4_2.dialogue")
	

	await director._move_to_navigation_position(target3.global_position)
	
	await _say("res://dialogues/laboratory/step4_3.dialogue")

	# Director 先走到 Target2
	await director._move_to_navigation_position(target2.global_position)
	# 朝向下
	director.facing_direction = "down"
	director.play_animation("idle_" + "down")

	await _say("res://dialogues/laboratory/step4_4.dialogue")
	
	# 更新玩家状态
	PlayerState.current_state = PlayerState.State.NORMAL
	tip_location._play_show()
	# 帷幕升起
	await Curtain._curtain_hide()
	TaskPanel._change_task("回到农场，收集数据")




func _physics_process(_delta: float) -> void:
	pass
	
## 播放一段对话，播完返回。
func _say(dialogue_path: String) -> void:
	DialogueManager.show_dialogue_balloon_scene(
		"res://scenes/widget/dialogue/balloon.tscn",
		load(dialogue_path),
		"start"
	)
	await DialogueManager.dialogue_ended