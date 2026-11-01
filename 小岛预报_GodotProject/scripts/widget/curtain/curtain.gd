extends CanvasLayer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
## 动画结束信号
signal animation_finished

func _ready() -> void:
    hide()

## 帷幕升起
func _curtain_hide():
    animation_player.play_backwards("show_hide")
    await animation_player.animation_finished
    animation_finished.emit()
    hide()

## 帷幕落下
func _curtain_show():
    show()
    animation_player.play("show_hide")
    await animation_player.animation_finished
    animation_finished.emit()