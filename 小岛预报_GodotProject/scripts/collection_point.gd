extends Node2D
## 收集点：按 X 吸收光球，每颗抵达玩家后弹出天气数据，全部收完后提示。

## 触发信号
signal trigger
## 数据全部吸收完时发出
signal collected

## 每颗光球吸收后显示的天气数据
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
## 光球围绕收集点的半径（像素）
@export var data_radius: float = 34.0
## 数据的不透明度
@export var data_alpha: float = 0.55
## 文字字号
@export var font_size: int = 8
## 单个数据飞向玩家的时长
@export var absorb_duration: float = 0.7
## 每个数据之间错开的延迟
@export var absorb_stagger: float = 0.18

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
	var time := Time.get_ticks_msec() / 1000.0
	var index := 0
	for orb in _data_home:
		orb.position = _data_home[orb] + Vector2(0.0, sin(time * 2.0 + index) * 2.0)
		index += 1
	# 持续按下 X 才吸收
	if Input.is_physical_key_pressed(KEY_X):
		_absorb_all()


## 共享一张柔光纹理，每颗光球对应一条天气数据。
func _setup_data() -> void:
	# 清掉旧的，支持重复调用
	for child in weather_data.get_children():
		child.queue_free()
	_data_home.clear()

	var total := weather_texts.size()
	if total == 0:
		return

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 0.9), Color(0.8, 1.0, 1.0),
		Color(0.3, 0.85, 1.0, 0.5), Color(0.3, 0.85, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 12
	texture.height = 12
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	for i in range(total):
		var orb := Sprite2D.new()
		orb.texture = texture
		orb.z_index = 1
		weather_data.add_child(orb)
		var angle := TAU * float(i) / float(total)
		orb.position = Vector2(cos(angle), sin(angle)) * data_radius * (0.75 if i % 2 == 0 else 1.0)
		_data_home[orb] = orb.position


## 把数据节点放回原位（离开范围时）。
func _reset_data() -> void:
	for node in _data_home.keys():
		if is_instance_valid(node):
			node.position = _data_home[node]
			node.scale = Vector2.ONE
			node.show()


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
	if visible and not _collected:
		AudioManager.play_sfx("data_open", global_position, -2.0)


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	_player_in_range = false
	if not _absorbing:
		AudioManager.stop_loop(self)
		weather_data.hide()
		_reset_data()
		_player = null


## 按住 X 时把所有数据吸到玩家身上，吸完收起自身。
func _absorb_all() -> void:
	if _absorbing or _collected or _player == null:
		return
	_absorbing = true
	AudioManager.start_loop("data_absorb", self)

	var tweens: Array[Tween] = []
	var delay := 0.0
	var index := 0
	for node in weather_data.get_children():
		tweens.append(_make_absorb_tween(node, delay, index))
		delay += absorb_stagger
		index += 1

	# 等全部飞完
	if not tweens.is_empty():
		await tweens[-1].finished

	weather_data.hide()
	AudioManager.stop_loop(self)

	await _play_hide()

	# 收尾顺序很重要：先标记已收 + 清掉吸收中，
	# 否则 _play_hide 那 0.4 秒里再按 X 会重跑一遍、重复发信号。
	_collected = true
	_absorbing = false
	_show_collected_bubble()

	# 通知外部：这个点收完了
	collected.emit()


## 光球先慢后快地飞向玩家；抵达之前不显示文字。
func _make_absorb_tween(node: Sprite2D, delay: float, index: int) -> Tween:
	var start := node.position
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_EXPO)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_interval(delay)
	# 每帧朝玩家当前位置靠拢，玩家在吸收过程中走动也能追上
	tween.tween_method(
		func(progression: float) -> void:
			if not is_instance_valid(node) or not is_instance_valid(_player):
				return
			var target: Vector2 = weather_data.to_local(_player.global_position + Vector2(0.0, -10.0))
			node.position = start.lerp(target, progression)
			node.scale = Vector2.ONE * lerpf(1.0, 0.35, progression),
		0.0, 1.0, absorb_duration
	)
	tween.tween_callback(func() -> void:
		node.hide()
		if is_instance_valid(_player):
			_show_weather_text(index)
	)
	return tween


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _show_weather_text(index: int) -> void:
	var label := _make_label(weather_texts[index])
	label.name = "WeatherDatum"
	label.z_index = 50
	_player.add_child(label)
	label.size = label.get_minimum_size()
	label.position = Vector2(0.0, -12.0) - label.size * 0.5
	label.modulate.a = 0.0
	var drift := Vector2(-42.0 if index % 2 == 0 else 42.0, -20.0 - (index % 3) * 6.0)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position", label.position + drift, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", data_alpha, 0.12)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)


func _show_collected_bubble() -> void:
	if not is_instance_valid(_player):
		return
	var bubble := Node2D.new()
	bubble.name = "CollectionBubble"
	bubble.position = Vector2(0.0, -25.0)
	bubble.z_index = 60
	_player.add_child(bubble)
	var color := Color("fff4d6")
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(-4, -5), Vector2(4, -5), Vector2.ZERO])
	tail.color = color
	bubble.add_child(tail)
	var label := _make_label("收集了温度、风速等\n气象信息")
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("9e8051")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_color_override("font_color", Color("55452f"))
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	bubble.add_child(label)
	label.size = label.get_minimum_size()
	label.position = Vector2(-label.size.x * 0.5, -label.size.y - 4.0)
	bubble.scale = Vector2.ONE * 0.8
	bubble.modulate.a = 0.0
	var tween := bubble.create_tween().set_parallel(true)
	# 等最后一条数据飘字退场，再显示完成气泡。
	tween.tween_interval(0.6)
	tween.chain().tween_property(bubble, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(bubble, "modulate:a", 1.0, 0.15)
	tween.chain().tween_interval(1.8)
	tween.chain().tween_property(bubble, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(bubble.queue_free)


func _play_show() -> void:
	show()
	animation_player.play_backwards("hide")
	await animation_player.animation_finished
	animation_player.play("beat")


func _play_hide() -> void:
	animation_player.play("hide")
	await animation_player.animation_finished
	hide()
