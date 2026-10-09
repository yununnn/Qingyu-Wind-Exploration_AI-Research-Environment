extends Node2D

@onready var sub_viewport_ripple: SubViewport = $CanvasLayer/SubViewport_Ripple
@onready var sprite_2d: Sprite2D = $Sprite2D

func _ready() -> void:
	# 为这个水坑复制一份材质，避免多个水坑共享纹理参数。
	var water_material : ShaderMaterial = sprite_2d.material.duplicate() as ShaderMaterial
	sprite_2d.material = water_material

	water_material.set_shader_parameter(
		"ripple_texture",
		sub_viewport_ripple.get_texture()
	)
