extends Area2D
## 箱子：玩家走近会开盖并描边高光，带着萝卜时按一次 E 全部倒进去，
## 萝卜会从玩家身上一个个飞进箱子。放满需要的数量后收尾。

## 胡萝卜物品图集
const CARROT_ATLAS := "res://assets/farm/items/农作物物品_UnOutline.png"
## 胡萝卜在物品图集里的区域
const CARROT_REGION := Rect2(16, 32, 16, 16)
## 每个萝卜飞进箱子的间隔
const FLY_STAGGER := 0.06
## 单个萝卜飞行时长
const FLY_DURATION := 0.45
## 飞行弧线高度
const FLY_ARC := 20.0

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

## 玩家靠近时的描边颜色
@export var outline_color: Color = Color.WHITE
## 描边粗细
@export var outline_size: float = 1.0

## 玩家是否在范围内
var _player_in_range: bool = false
## 范围内的玩家
var _player: Node2D = null
## 是否已经在收尾，防止重复触发
var _finishing: bool = false
## 本实例独立的描边材质
var _material: ShaderMaterial = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# 复制材质，避免多个箱子共享描边状态
	if animated_sprite_2d != null and animated_sprite_2d.material is ShaderMaterial:
		_material = animated_sprite_2d.material.duplicate() as ShaderMaterial
		animated_sprite_2d.material = _material
	_set_outline(false)


func _process(_delta: float) -> void:
	if _finishing or not _player_in_range:
		return
	if GameState.carrots_held <= 0:
		return
	if Input.is_action_just_pressed("interact"):
		_deposit_all()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	_player_in_range = true
	_player = body
	_set_outline(true)
	open_chest(body)


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	_player_in_range = false
	_player = null
	_set_outline(false)
	close_chest(body)


## 开关描边。
func _set_outline(on: bool) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("outline_size", outline_size)
	_material.set_shader_parameter("outline_color", outline_color if on else Color(0, 0, 0, 0))


func open_chest(body: Node2D) -> void:
	if animated_sprite_2d.is_playing():
		await animated_sprite_2d.animation_finished
	animated_sprite_2d.play("normal")


func close_chest(body: Node2D) -> void:
	if animated_sprite_2d.is_playing():
		await animated_sprite_2d.animation_finished
	animated_sprite_2d.play_backwards("normal")


## 按一次 E 把身上的萝卜全部倒进箱子。
func _deposit_all() -> void:
	var count := GameState.carrots_held
	if count <= 0:
		return

	# 先扣掉，避免飞行过程中重复按 E
	GameState.carrots_held = 0

	var from_pos := global_position
	if is_instance_valid(_player):
		from_pos = _player.global_position

	# 一个个飞进箱子
	for i in range(count):
		_spawn_flying_carrot(from_pos, i * FLY_STAGGER)

	# 等最后一个飞完
	var total_time := FLY_DURATION + FLY_STAGGER * float(count - 1)
	await get_tree().create_timer(total_time).timeout

	GameState.carrots_in_chest += count
	var need := GameState.carrots_required
	print("[箱子] 放入 ", count, " 个，箱子共 ", GameState.carrots_in_chest, " / ", need)

	if need > 0:
		TaskPanel._change_task("把成熟的胡萝卜放进箱子（" + str(GameState.carrots_in_chest) + " / " + str(need) + "）")

	if need > 0 and GameState.carrots_in_chest >= need:
		_finish_game()


## 生成一个飞进箱子的胡萝卜。
func _spawn_flying_carrot(from_pos: Vector2, delay: float) -> void:
	var atlas := load(CARROT_ATLAS) as Texture2D
	if atlas == null:
		return

	var parent := get_parent()
	if parent == null:
		return

	var carrot := Sprite2D.new()
	carrot.texture = atlas
	carrot.region_enabled = true
	carrot.region_rect = CARROT_REGION
	carrot.z_index = 100
	parent.add_child(carrot)
	carrot.global_position = from_pos

	var start := from_pos
	var target := global_position + Vector2(0.0, -8.0)
	var tween := carrot.create_tween()
	tween.tween_interval(delay)
	# 抛物线：水平方向线性靠拢，垂直方向先上抛再落下
	tween.tween_method(
		func(progression: float) -> void:
			if not is_instance_valid(carrot):
				return
			var pos: Vector2 = start.lerp(target, progression)
			pos.y -= sin(progression * PI) * FLY_ARC
			carrot.global_position = pos,
		0.0, 1.0, FLY_DURATION
	)
	tween.tween_callback(carrot.queue_free)


## 全部放完之后收尾：淡出 + 结束文字。
func _finish_game() -> void:
	if _finishing:
		return
	_finishing = true

	TaskPanel._change_task("任务完成")
	TipAction._hide_tip()

	await Curtain._curtain_show()

	TextIntro.play("胡萝卜岛上的作物都已收好。\n三天后的暴雨，也许不会再那么措手不及了。", 0.06, 0.4, 0.6, 1.6)
	await TextIntro.finished

	get_tree().quit()
