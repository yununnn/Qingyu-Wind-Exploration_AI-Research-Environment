extends Node2D


@onready var player: Player = FunctionLibrary.get_player()
@onready var director: Npc = $Scene/Decoration/Director

@onready var player_move_location: Node2D = $NavigationLayer/PlayerMoveLocation
@onready var director_move_location: Node2D = $NavigationLayer/DirectorMoveLocation


func _ready() -> void:
	await IrisTransition.open_from_black()
	# 更新玩家状态
	PlayerState.current_state = PlayerState.State.UNCONTROL
	player._move_to_navigation_position(player_move_location.position)
	await get_tree().create_timer(0.5).timeout
	director._move_to_navigation_position(director_move_location.position)
	await get_tree().create_timer(1.0).timeout
	
	# 更新玩家状态
	PlayerState.current_state = PlayerState.State.NORMAL

func _physics_process(_delta: float) -> void:
	pass
	
