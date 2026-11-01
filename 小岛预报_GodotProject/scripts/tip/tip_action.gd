extends CanvasLayer

## 用显式路径取节点，不依赖 % 唯一名。
## （autoload 场景在启动瞬间 unique name 可能还没注册好，% 会找不到）
@onready var animation_player: AnimationPlayer = $TipAnimationPlayer
@onready var label: Label = $Control/TipLabel

signal finished

func _ready() -> void:
	hide()


## 显示操作提示
func _show_tip() -> void:
	show()
	animation_player.play("show_hide")
	await animation_player.animation_finished
	finished.emit()


## 隐藏操作提示
func _hide_tip() -> void:
	animation_player.play_backwards("show_hide")
	await animation_player.animation_finished
	finished.emit()
	hide()


## 更改操作提示文字
func _change_tip(text: String) -> void:
	# 如果面板是隐藏的就不用再播放隐藏动画了
	if visible == true:
		await _hide_tip()
	label.text = text
	await _show_tip()
