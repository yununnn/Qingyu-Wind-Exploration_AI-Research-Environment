extends CanvasLayer

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var label: Label = $Control/PanelContainer/MarginContainer/Label


signal finished

func _ready() -> void:
    hide()


## 显示任务面板
func _show_task_panel() -> void:
    show()
    animation_player.play("show_hide")
    await animation_player.animation_finished
    finished.emit()


## 隐藏任务面板
func _hide_task_panel() -> void:
    animation_player.play_backwards("show_hide")
    await animation_player.animation_finished
    finished.emit()
    hide()


## 更改任务文字
func _change_task(text: String) -> void:
    # 如果面板是隐藏的就不用再播放隐藏动画了
    if visible == true:
        await _hide_task_panel()
    label.text = text
    await _show_task_panel()
