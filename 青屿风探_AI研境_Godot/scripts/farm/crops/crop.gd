@tool
class_name Crop
extends Area2D
## 农作物。
##
## 按 [member stage] 切换生长阶段贴图；被玩家射线命中时描边高亮；
## 成熟后按住 [code]interact[/code] 采集，采集过程中头顶显示环形进度，
## 完成后原地生成掉落物（弹跳一下），作物自身移除。
##
## 根节点 [Area2D] 放在 [code]Detection[/code] 层，负责被玩家射线检测；
## 子节点 [StaticBody2D] 放在 [code]World[/code] 层，负责玩家行走时的物理碰撞。

## 收集完成时发出，参数为作物自身。
signal harvested(crop: Crop)

## 裁剪阶段贴图时四周补充的透明像素数，供描边 shader 采样。
const OUTLINE_PADDING := 1

## 射线停止命中后，超过这么多物理帧就熄灭描边。
const HIGHLIGHT_TIMEOUT_FRAMES := 2

## 掉落物图集。
const DROP_ATLAS := "res://assets/farm/items/农作物物品_UnOutline.png"

## 生长阶段。0 为幼苗，越大越接近成熟；超出阶段数时夹到最后一帧。
@export_range(0, 20) var stage := 0:
	set(value):
		stage = value
		_apply_stage()

## 各生长阶段的图集区域，按幼苗到成熟排列。
@export var regions: Array = []

## 被射线命中时的描边颜色。
@export var outline_color := Color.WHITE

## 描边粗细。
@export var outline_size := 1.0

## 采集耗时（秒）。按住 E 累积到这个时长才算采完。
@export var harvest_time := 1.0

## 掉落物在物品图集里的区域。
@export var drop_region := Rect2(16, 32, 16, 16)

## 当前高亮的作物，全局唯一。
static var _highlighted: Crop

## 裁剪后的阶段贴图缓存，所有实例共享。
static var _texture_cache := {}

## 图集原图，首次使用时加载。
static var _atlas_image: Image

## 玩家是否在 Area2D 检测范围内。
var player_in_range := false

## 最后一次被射线命中的物理帧。
var _last_hit_frame: int = -1000

## 采集进度，0~1。
var _harvest_progress := 0.0


func _ready() -> void:
	_apply_stage()
	_set_outline(false)
	_set_ring_visible(false)
	_connect_detection()


func _exit_tree() -> void:
	if _highlighted == self:
		_highlighted = null


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# 一段时间没被射线命中就熄灭
	if _highlighted == self and Engine.get_physics_frames() - _last_hit_frame > HIGHLIGHT_TIMEOUT_FRAMES:
		_highlighted = null
		_set_outline(false)

	_update_highlight()
	_update_harvest(delta)


#region 公共接口

## 被玩家射线命中时调用。保留接口，高光统一由 [method _update_highlight] 决定。
## 射线从玩家中心出发时，起点可能落在 Area2D 内部而漏检，所以不依赖它。
func on_ray_detected() -> void:
	_update_highlight()


## 根据 Area2D 范围更新高光：范围内的作物里，离玩家最近的那个亮。
func _update_highlight() -> void:
	if not player_in_range:
		if _highlighted == self:
			_highlighted = null
			_set_outline(false)
		return

	if _highlighted == self:
		return

	# 已有高亮者且它也在范围内，就比距离
	if is_instance_valid(_highlighted) and _highlighted.player_in_range:
		if _distance_to_player() >= _highlighted._distance_to_player():
			return

	if is_instance_valid(_highlighted):
		_highlighted._set_outline(false)
	_highlighted = self
	_set_outline(true)


## 到玩家的距离。
func _distance_to_player() -> float:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		return INF
	return global_position.distance_to(player.global_position)


## 连接 Area2D 的进入/离开信号，重复调用安全。
func _connect_detection() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	player_in_range = false
	# 离开范围时立刻熄灭，不用等超时
	if _highlighted == self:
		_highlighted = null
		_set_outline(false)


## 最大阶段索引，即成熟阶段。
func get_max_stage() -> int:
	return maxi(regions.size() - 1, 0)


## 是否已成熟。
func is_mature() -> bool:
	return stage >= get_max_stage()


## 当前是否正在高亮。
func is_highlighted() -> bool:
	return _highlighted == self


## 是否可以收集：已成熟且正在高亮。
func can_harvest() -> bool:
	return is_mature() and is_highlighted()


## 立即采集（跳过进度条）。不满足 [method can_harvest] 时不做任何事。
## 玩家按住 E 的流程走 [method _update_harvest]，不需要调这里。
func harvest() -> void:
	if not can_harvest():
		return
	_complete_harvest()

#endregion


#region 采集流程

## 按住 interact 累积进度，满了就完成采集。
func _update_harvest(delta: float) -> void:
	if not can_harvest() or not Input.is_action_pressed("interact"):
		_cancel_harvest()
		return

	_harvest_progress = minf(_harvest_progress + delta / maxf(harvest_time, 0.01), 1.0)
	_update_ring()

	if _harvest_progress >= 1.0:
		_complete_harvest()


## 取消采集，进度清零。
func _cancel_harvest() -> void:
	if _harvest_progress > 0.0:
		_harvest_progress = 0.0
		_update_ring()


## 采集完成：生成掉落物、发信号、移除自身。
func _complete_harvest() -> void:
	_harvest_progress = 0.0
	_set_ring_visible(false)
	_spawn_drop()
	harvested.emit(self)
	queue_free()


## 在作物位置生成掉落物，并播放一次弹跳。
func _spawn_drop() -> void:
	var parent := get_parent()
	if parent == null:
		return

	var atlas := load(DROP_ATLAS) as Texture2D
	if atlas == null:
		return

	var drop := Sprite2D.new()
	drop.texture = atlas
	drop.region_enabled = true
	drop.region_rect = drop_region
	drop.z_index = z_index
	parent.add_child(drop)
	drop.global_position = global_position

	# 弹跳：先上抛 10px 再落回。
	# 用本地 position:y 而不是 global_position:y —— 后者是计算属性，Tween 写入不稳定。
	var base_y := drop.position.y
	var tween := drop.create_tween()
	tween.tween_property(drop, "position:y", base_y - 10.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(drop, "position:y", base_y, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

#endregion


#region 进度圈

## 按当前进度刷新进度圈帧号并显示。
func _update_ring() -> void:
	var ring := get_node_or_null("ProgressRing") as Sprite2D
	if ring == null:
		return

	ring.visible = _harvest_progress > 0.0
	if ring.hframes > 1:
		ring.frame = clampi(int(_harvest_progress * (ring.hframes - 1)), 0, ring.hframes - 1)


## 直接显示/隐藏进度圈。
func _set_ring_visible(on: bool) -> void:
	var ring := get_node_or_null("ProgressRing") as Sprite2D
	if ring != null:
		ring.visible = on

#endregion


#region 描边与贴图

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
