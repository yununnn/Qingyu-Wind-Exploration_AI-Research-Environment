extends Node2D

## 水波纹子视口，用于渲染波纹效果
@onready var sub_viewport_ripple: SubViewport = $CanvasLayer/SubViewportRipple
## 水面倒影子视口，用于渲染倒影效果
@onready var sub_viewport_reflection: SubViewport = $CanvasLayer/SubViewportReflection
## 2D 精灵节点，用于显示水坑的纹理
@onready var sprite_2d: Sprite2D = $Sprite2D

func _ready() -> void:
	# 设置子视口的 HDR 模式与主视口一致
	sub_viewport_reflection.use_hdr_2d = get_viewport().use_hdr_2d
	# 为这个水坑复制一份材质，避免多个水坑共享纹理参数。
	var water_material : ShaderMaterial = sprite_2d.material.duplicate() as ShaderMaterial
	sprite_2d.material = water_material

	# 将子视口的纹理传递给水坑材质的 shader 参数
	water_material.set_shader_parameter(
		"ripple_texture",
		sub_viewport_ripple.get_texture()
	)
	
	water_material.set_shader_parameter(
		"reflection_texture",
		sub_viewport_reflection.get_texture()
	)


func _process(_delta: float) -> void:
	# 获取水坑在 Puddle 局部坐标中的矩形。
	# 包含 Sprite2D 的位置、缩放、centered 和 offset。
	var rect: Rect2 = sprite_2d.transform * sprite_2d.get_rect()
	var viewport_size := Vector2(sub_viewport_reflection.size)
	var water_material := sprite_2d.material as ShaderMaterial

	water_material.set_shader_parameter(
		"reflection_uv_origin",
		rect.position / viewport_size
	)
	water_material.set_shader_parameter(
		"reflection_uv_size",
		rect.size / viewport_size
	)
