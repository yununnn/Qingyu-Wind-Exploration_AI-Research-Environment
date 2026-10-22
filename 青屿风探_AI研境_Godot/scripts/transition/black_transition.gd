extends CanvasLayer

@onready var color_rect: ColorRect = $ColorRect
## 黑幕完成信号
signal tween_finished

## 黑幕渐变速度
@export var speed: float = 2.0

func _ready() -> void:
	hide()

## 由黑转亮
func _black_to_light(time: float = speed) -> void:
	show()
	# 一开始完全黑
	color_rect.color = Color(0, 0, 0, 1)
	speed = time
	# 创建渐变动画
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_IN)
	# speed 秒内透明度从 1 变成 0
	tween.tween_property(
		color_rect,
		"color",
		Color(0, 0, 0, 0),
		speed
	)

	# 渐变完成后隐藏黑幕
	await tween.finished
	# 黑幕结束，发出信号
	tween_finished.emit()
	GameState.is_first_farm = false
	hide()
	

func _on_laboratory_ready() -> void:
	_black_to_light()
