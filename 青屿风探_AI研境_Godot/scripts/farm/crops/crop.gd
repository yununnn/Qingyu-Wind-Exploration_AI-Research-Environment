@tool
extends Node2D
## 农作物：按 stage 切换生长阶段图片，数字越大越成熟。
##
## 图像来自 res://assets/farm/objects/Farming Plants.png。
## 原点在作物根部（底部），切换高阶段时不会悬空。

## 当前生长阶段。0 = 刚种下，数字越大越接近成熟。
## 超过阶段数会自动夹到最后一帧，不会报错。
@export_range(0, 20) var stage: int = 0:
	set(value):
		stage = value
		_apply_stage()

## 每个生长阶段的图集区域，按「幼苗 -> 成熟」顺序排列。
## 由场景生成时写好，一般不需要手动改。
@export var regions: Array = []


func _ready() -> void:
	_apply_stage()


## 把 stage 对应的区域应用到 Sprite2D 上。
func _apply_stage() -> void:
	var s := get_node_or_null("Sprite2D") as Sprite2D
	if s == null:
		return
	if regions.is_empty():
		return

	var i: int = clampi(stage, 0, regions.size() - 1)
	var r: Rect2 = regions[i]

	s.region_enabled = true
	s.region_rect = r
	# 让 region 的底边压在节点原点上（作物根部）。
	# 不同阶段高度不同（16 或 32），所以这里必须动态算。
	s.offset = Vector2(0, -(r.size.y / 2.0 - 4.0))
