extends Area2D
## 作物收获后掉在地上的胡萝卜。玩家走进范围会描边高光，按 E 拾取。

## 被拾取时发出
signal picked_up

## 允许拾取的最小游戏步骤。
## 第 7 步（气象局回来、开始收胡萝卜）之后才能把掉落物捡进背包。
const PICKUP_MIN_STEP := 7

## 掉落物在图集里的区域，由作物生成时写入
@export var drop_region: Rect2 = Rect2(16, 32, 16, 16)
## 在图集里的纹理
@export var atlas: Texture2D = null
## 玩家靠近时的描边颜色
@export var outline_color: Color = Color.WHITE
## 描边粗细
@export var outline_size: float = 1.0

@onready var sprite: Sprite2D = $Sprite2D

## 玩家是否在范围内
var _player_in_range: bool = false
## 本实例独立的描边材质
var _material: ShaderMaterial = null


func _ready() -> void:
	add_to_group("drop")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if sprite != null:
		if atlas != null:
			sprite.texture = atlas
		sprite.region_enabled = true
		sprite.region_rect = drop_region

		# 复制一份材质，多个掉落物之间互不影响
		if sprite.material is ShaderMaterial:
			_material = sprite.material.duplicate() as ShaderMaterial
			sprite.material = _material
	_set_outline(false)


func _process(_delta: float) -> void:
	if not _player_in_range:
		return
	if Input.is_action_just_pressed("interact"):
		_pick_up()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		_player_in_range = true
		_set_outline(true)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		_player_in_range = false
		_set_outline(false)


## 开关描边。
func _set_outline(on: bool) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("outline_size", outline_size)
	_material.set_shader_parameter("outline_color", outline_color if on else Color(0, 0, 0, 0))


## 拾取：计数 +1，然后消失。
## 第六步之前还不允许捡（先专心收集天气数据）。
func _pick_up() -> void:
	if GameState.step < PICKUP_MIN_STEP:
		return

	GameState.carrots_held += 1
	print("[掉落物] 拾取胡萝卜，身上共 ", GameState.carrots_held, " 个")
	picked_up.emit()
	queue_free()
