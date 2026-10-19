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

func _ready() -> void:
	# 绑定信号
	detection.body_entered.connect(_on_body_entered)
	detection.body_exited.connect(_on_body_exited)
	DialogueManager.dialogue_started.connect(_started_dialogue)
	DialogueManager.dialogue_ended.connect(_end_dialogue)


func _process(_delta: float) -> void:
	# 玩家进入了检测区域并且按下了交互键，且不在进行对话，才可触发对话。
	if is_entered and not is_dialogue_active and Input.is_action_just_pressed("interact"):
		_try_start_dialogue()

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

## 尝试开始对话
func _try_start_dialogue() -> void:
	pass
	
func _started_dialogue(_resource: DialogueResource) -> void:
	# 进入对话状态
	PlayerState.current_state = PlayerState.State.CUTSCENE
	is_dialogue_active = true

## 结束对话
func _end_dialogue(_resource: DialogueResource) -> void:
	# 恢复正常状态
	PlayerState.current_state = PlayerState.State.NORMAL
	is_dialogue_active = false
