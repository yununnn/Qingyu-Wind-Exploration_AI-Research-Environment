@tool
class_name Crop
extends Node2D
## 农作物。
##
## 按 [member stage] 切换生长阶段贴图；玩家进入 [code]Detection[/code] 范围时描边高亮，
## 同一时刻只有优先级最高的一个作物高亮；成熟后可按 [code]interact[/code] 收集。
##
## 贴图四周会按 [constant OUTLINE_PADDING] 补透明边，避免描边在贴图边缘被裁掉。

## 收集完成时发出，参数为作物自身。
signal harvested(crop: Crop)

## 裁剪阶段贴图时四周补充的透明像素数，供描边 shader 采样。
const OUTLINE_PADDING := 1

## 生长阶段。0 为幼苗，越大越接近成熟；超出阶段数时夹到最后一帧。
@export_range(0, 20) var stage := 0:
	set(value):
		stage = value
		_apply_stage()

## 各生长阶段的图集区域，按幼苗到成熟排列。
@export var regions: Array = []

## 玩家靠近时的描边颜色。
@export var outline_color := Color.WHITE

## 描边粗细。
@export var outline_size := 1.0

## 玩家是否在检测范围内。
var player_in_range := false

## 当前高亮的作物，全局唯一。
static var _highlighted: Crop

## 裁剪后的阶段贴图缓存，所有实例共享。
static var _texture_cache := {}

## 图集原图，首次使用时加载。
static var _atlas_image: Image


func _ready() -> void:
	_apply_stage()
	_connect_detection()
	_set_outline(false)


func _exit_tree() -> void:
	if _highlighted == self:
		_highlighted = null


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_highlight()


#region 公共接口

## 最大阶段索引，即成熟阶段。
func get_max_stage() -> int:
	return maxi(regions.size() - 1, 0)


## 是否已成熟。
func is_mature() -> bool:
	return stage >= get_max_stage()


## 是否可以收集：已成熟且玩家在范围内。
func can_harvest() -> bool:
	return is_mature() and player_in_range


## 当前是否正在高亮。
func is_highlighted() -> bool:
	return _highlighted == self


## 收集作物。不满足 [method can_harvest] 时不做任何事。
func harvest() -> void:
	if not can_harvest():
		return
	_do_harvest()


## 实际的收集行为，可被子类或后续需求覆盖。
func _do_harvest() -> void:
	harvested.emit(self)

#endregion


#region 高亮

## 每帧根据优先级决定是否抢占高亮。
func _update_highlight() -> void:
	if not player_in_range:
		if _highlighted == self:
			_highlighted = null
			_set_outline(false)
		return

	if not is_instance_valid(_highlighted) or not _highlighted.player_in_range:
		_take_highlight()
	elif _highlighted == self:
		_set_outline(true)
	elif _priority_score() > _highlighted._priority_score():
		_take_highlight()


## 抢占高亮，并关闭上一个高亮者。
func _take_highlight() -> void:
	if is_instance_valid(_highlighted) and _highlighted != self:
		_highlighted._set_outline(false)
	_highlighted = self
	_set_outline(true)


## 高亮优先级：正面朝向的更高，同方向时距离更近的更高。
func _priority_score() -> float:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return 0.0

	var offset: Vector2 = global_position - player.global_position
	var dist := offset.length()
	if dist < 0.001:
		return 1000.0

	var facing := _facing_to_vector(player.get("facing_direction"))
	# 朝向权重 1000，远大于距离，保证朝向优先于距离
	return offset.normalized().dot(facing) * 1000.0 - dist


## 朝向字符串转方向向量，未知值按向下处理。
func _facing_to_vector(value: Variant) -> Vector2:
	match value:
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
	return Vector2.DOWN

#endregion


#region 检测与描边

## 连接 Detection 的信号，重复调用安全。
func _connect_detection() -> void:
	var area := get_node_or_null("Detection") as Area2D
	if area == null:
		return
	if not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)
	if not area.body_exited.is_connected(_on_body_exited):
		area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	player_in_range = false
	if _highlighted == self:
		_highlighted = null
		_set_outline(false)


## 开关描边：修改 Sprite2D 上 ShaderMaterial 的 outline_color。
func _set_outline(on: bool) -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var mat := sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("outline_size", outline_size)
	mat.set_shader_parameter("outline_color", outline_color if on else Color(0, 0, 0, 0))

#endregion


#region 阶段贴图

## 把当前阶段对应的贴图应用到 Sprite2D。
func _apply_stage() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or regions.is_empty():
		return

	var rect: Rect2 = regions[clampi(stage, 0, regions.size() - 1)]
	var texture := _get_padded_texture(rect)
	if texture != null:
		sprite.region_enabled = false
		sprite.texture = texture

	# 贴图多了 padding，但内容中心不变，偏移公式仍按原始高度算
	sprite.offset = Vector2(0, -(rect.size.y / 2.0 - 4.0))


## 从图集裁出指定区域，四周补透明边，结果缓存复用。
static func _get_padded_texture(rect: Rect2) -> Texture2D:
	var key := "%d,%d,%d,%d" % [int(rect.position.x), int(rect.position.y), int(rect.size.x), int(rect.size.y)]
	if _texture_cache.has(key):
		return _texture_cache[key]

	if _atlas_image == null:
		var atlas := load("res://assets/farm/objects/Farming Plants.png") as Texture2D
		if atlas == null:
			return null
		_atlas_image = atlas.get_image()
		if _atlas_image == null:
			return null

	var w := int(rect.size.x)
	var h := int(rect.size.y)
	var image := Image.create_empty(w + OUTLINE_PADDING * 2, h + OUTLINE_PADDING * 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var src := _atlas_image.get_region(Rect2i(int(rect.position.x), int(rect.position.y), w, h))
	image.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(OUTLINE_PADDING, OUTLINE_PADDING))

	var texture := ImageTexture.create_from_image(image)
	_texture_cache[key] = texture
	return texture

#endregion
