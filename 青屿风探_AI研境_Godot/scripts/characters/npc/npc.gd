extends CharacterBody2D
class_name Npc

## NPC动画节点
@onready var body_sprite: AnimatedSprite2D = $BodySprite
## NPC检测区域
@onready var detection: Area2D = $Detection
## BodySprite 上的 Shader 材质。
@onready var shader_material: ShaderMaterial = body_sprite.material as ShaderMaterial

func _ready() -> void:
	# 绑定信号
	detection.body_entered.connect(_on_body_entered)
	detection.body_exited.connect(_on_body_exited)


## 当有物体进入碰撞区域时触发
func _on_body_entered(body: Node2D) -> void:
	# 只有属于 Player 分组的节点才能触发。
	if body.is_in_group("Player"):
		show_outline()
		
## 当有物体离开碰撞区域时触发
func _on_body_exited(body: Node2D) -> void:
	# 只有属于 Player 分组的节点才能触发。
	if body.is_in_group("Player"):
		hide_outline()

## 显示轮廓
func show_outline() -> void:	
	shader_material.set_shader_parameter("outline_color", Color.WHITE)

## 隐藏轮廓
func hide_outline() -> void:
	shader_material.set_shader_parameter("outline_color", Color(0, 0, 0, 0))
