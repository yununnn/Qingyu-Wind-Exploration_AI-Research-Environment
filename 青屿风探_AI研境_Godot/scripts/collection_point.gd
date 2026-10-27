extends Node2D
## 收集点：玩家走进范围后冒出半透明天气数据，按住 X 把它们吸到身上，
## 全部吸完后收起本身（_play_hide）。
##
## 之前这个节点的职责只是"走到这里触发信号"，现在再叠加一层"吸收数据"的表现。

## 触发信号
signal trigger
## 数据全部吸收完时发出
signal collected

## 要显示的天气数据文字
@export var weather_texts: PackedStringArray = PackedStringArray([
	"26°C",
	"风速 12m/s",
	"湿度 87%",
	"气压 998hPa",
	"降雨 92%",
	"多云",
	"紫外线 弱",
	"能见度 3km",
	"东南风",
	"露点 22°C",
	"阵风 18m/s",
	"海平面 1002hPa",
])
## 数据围绕收集点的半径（像素）
@export var data_radius: float = 34.0
## 数据的不透明度
@export var data_alpha: float = 0.55
## 文字字号
@export var font_size: int = 8
## 单个数据飞向玩家的时长
@export var absorb_duration: float = 0.7
## 每个数据之间错开的延迟
@export var absorb_stagger: float = 0.08

@onready var area_2d: Area2D = $Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var weather_data: Node2D = $WeatherData

## 玩家是否在范围内
var _player_in_range: bool = false
## 范围内的玩家
var _player: Node2D = null
## 是否正在吸收，避免重复触发
var _absorbing: bool = false
## 是否已经收完，保证 collected 只发一次
var _collected: bool = false
## 每个数据节点的初始偏移，离开范围时复位用
var _data_home: Dictionary = {}


func _ready() -> void:
	# 加入组，farm 靠它统一监听
	add_to_group("collection_point")
	area_2d.body_entered.connect(_on_body_entered)
	area_2d.body_exited.connect(_on_body_exited)
	_setup_data()
	weather_data.hide()
	hide()


func _process(_delta: float) -> void:
	if _collected or not _player_in_range or _absorbing:
		return
	# 持续按下 X 才吸收
	if Input.is_physical_key_pressed(KEY_X):
		_absorb_all()


## 在收集点周围生成一圈半透明的天气数据文字。
func _setup_data() -> void:
	# 清掉旧的，支持重复调用
	for child in weather_data.get_children():
		child.queue_free()
	_data_home.clear()

	var total := weather_texts.size()
	if total == 0:
		return

	for i in range(total):
		var label := Label.new()
		label.text = weather_texts[i]
		label.modulate = Color(1.0, 1.0, 1.0, data_alpha)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", font_size)
		# 文字默认带阴影的话在浅色背景上更清楚
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)

		weather_data.add_child(label)

		# Label 的坐标是左上角，要让它绕中心摆，先把锚点设到中心
		label.size = label.get_minimum_size()
		label.pivot_offset = label.size * 0.5

		# 均匀分布在一个圆上
		var angle := TAU * float(i) / float(total)
		var pos := Vector2(cos(angle), sin(angle)) * data_radius
		label.position = pos - label.size * 0.5
		_data_home[label] = label.position


## 把数据节点放回原位（离开范围时）。
func _reset_data() -> void:
	for node in _data_home.keys():
		if is_instance_valid(node):
			node.position = _data_home[node]
			node.modulate = Color(1.0, 1.0, 1.0, data_alpha)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	_player_in_range = true
	_player = body
	# 原来的触发信号保留
	trigger.emit()
	# 露出数据
	_reset_data()
	weather_data.show()


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	_player_in_range = false
	if not _absorbing:
		weather_data.hide()
		_reset_data()
	_player = null


## 按住 X 时把所有数据吸到玩家身上，吸完收起自身。
func _absorb_all() -> void:
	if _absorbing or _collected or _player == null:
		return
	_absorbing = true

	var tweens: Array[Tween] = []
	var delay := 0.0
	for node in weather_data.get_children():
		# Label 是 Control，Sprite2D 是 Node2D，两者都有 position
		if node is CanvasItem:
			tweens.append(_make_absorb_tween(node as CanvasItem, delay))
			delay += absorb_stagger

	# 等全部飞完
	for tween in tweens:
		await tween.finished

	weather_data.hide()

	await _play_hide()

	# 收尾顺序很重要：先标记已收 + 清掉吸收中，
	# 否则 _play_hide 那 0.4 秒里再按 X 会重跑一遍、重复发信号。
	_collected = true
	_absorbing = false

	# 通知外部：这个点收完了
	collected.emit()


## 单个数据节点飞向玩家的 Tween。
## 用本地 position 而不是 global_position —— Label（Control）的 global_position 是只读的。
func _make_absorb_tween(node: CanvasItem, delay: float) -> Tween:
	var start: Vector2 = node.get("position")
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_EXPO)
	tween.tween_interval(delay)
	# 每帧朝玩家当前位置靠拢，玩家在吸收过程中走动也能追上
	tween.tween_method(
		func(progression: float) -> void:
			if not is_instance_valid(node) or not is_instance_valid(_player):
				return
			var target: Vector2 = weather_data.to_local(_player.global_position + Vector2(0.0, -10.0))
			node.set("position", start.lerp(target, progression))
			node.modulate.a = lerpf(data_alpha, 0.0, progression),
		0.0, 1.0, absorb_duration
	)
	return tween


func _play_show() -> void:
	show()
	animation_player.play_backwards("hide")
	await animation_player.animation_finished
	animation_player.play("beat")


func _play_hide() -> void:
	animation_player.play("hide")
	await animation_player.animation_finished
	hide()
