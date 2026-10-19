extends ColorRect

## 黑幕完成信号
signal black_finished

## 黑幕渐变速度，默认0.5秒完成
@export var speed : float = 0.5


## 由黑转亮
func _black_to_light() -> void:
	# 一开始完全黑
	color = Color(0, 0, 0, 1)
	
	# 创建渐变动画
	var tween := create_tween()

	# speed 秒内透明度从 1 变成 0
	tween.tween_property(
		self,
		"color",
		Color(0, 0, 0, 0),
		speed
	)

	# 渐变完成后隐藏黑幕
	await tween.finished
	hide()
	# 黑幕结束，发出信号
	black_finished.emit()

func _on_laboratory_ready() -> void:
	_black_to_light()
