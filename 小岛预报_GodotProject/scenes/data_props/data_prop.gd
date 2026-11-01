extends Area2D


@onready var sprite_2d: Sprite2D = $Sprite2D
## 描边材质
@export var outline_material: Material
## 是否悬停
var is_hover := false

# 鼠标进入CollisionShape2D时
func _on_mouse_entered() -> void:
	# 设置材质
	is_hover = true
	if is_hover:
		sprite_2d.set_material(outline_material)
		
	# 点击数据道具时
	if Input.is_action_pressed("Clicked"):
		_click_data_prop()
		
# 鼠标离开CollisionShape2D时
func _on_mouse_exited() -> void:
	# 取消材质
	is_hover = false
	if !is_hover:
		sprite_2d.set_material(null)
	
## 点击数据道具
func _click_data_prop() -> void:
	print(111);
