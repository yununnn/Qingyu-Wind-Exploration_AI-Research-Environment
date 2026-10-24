extends Node2D

@onready var area_2d: Area2D = $Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## 触发信号
signal trigger

func _ready() -> void:
    if GameState.is_first_farm:
        area_2d.body_entered.connect(on_tip_location)
    else:
        hide()

## 在提示位置上时
func on_tip_location(body: Node2D) -> void:
    if body.is_in_group("Player"):
        trigger.emit()
        animation_player.play("hide")
        # 只执行一次，所以断开
        area_2d.body_entered.disconnect(on_tip_location)
        await animation_player.animation_finished
        hide()

