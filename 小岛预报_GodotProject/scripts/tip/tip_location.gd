extends Node2D

@onready var area_2d: Area2D = $Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## 触发信号
signal trigger

func _ready() -> void:
    area_2d.body_entered.connect(on_tip_location)
    hide()

## 在提示位置上时
func on_tip_location(body: Node2D) -> void:
    if body.is_in_group("Player"):
        trigger.emit()
        if visible != false:
            animation_player.play("hide")
            await animation_player.animation_finished
            hide()


func _play_show() -> void:
    show()
    animation_player.play_backwards("hide")
    await animation_player.animation_finished
    animation_player.play("beat")
    