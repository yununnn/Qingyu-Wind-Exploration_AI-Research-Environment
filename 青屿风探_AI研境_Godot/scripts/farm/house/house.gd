extends Node2D


@onready var roof: TileMapLayer = $Roof
@onready var area_2d: Area2D = $Area2D
@onready var mask: Sprite2D = %Mask

var tween_roof: Tween
@export var speed_roof: float = 0.5

var tween_mask: Tween
@export var speed_mask: float = 0.5

@export var up_scale_value: Vector2 = Vector2(2.0, 2.0)
@export var down_scale_value: Vector2 = Vector2(1.5, 1.5)
@export var tween_speed: float = 0.4

## 屋顶动画结束信号
signal tween_roof_finished
## 遮罩动画结束信号
signal tween_mask_finished

func _ready() -> void:
    area_2d.body_entered.connect(hide_roof)
    area_2d.body_entered.connect(show_mask)
    area_2d.body_entered.connect(up_camera_scale)

    area_2d.body_exited.connect(show_roof)
    area_2d.body_exited.connect(hide_mask)
    area_2d.body_exited.connect(down_camera_scale)


func hide_roof(body: Node2D) -> void:
    if not body.is_in_group("Player"): return
    
    # 如果 tween_roof 变量中已有 Tween，就先停止它
    if tween_roof: tween_roof.kill()

    tween_roof = create_tween()
    tween_roof.set_trans(Tween.TRANS_QUAD)
    tween_roof.set_ease(Tween.EASE_IN_OUT)
    tween_roof.tween_property(roof, "modulate:a", 0.0, speed_roof)

    await tween_roof.finished
    tween_roof_finished.emit()

func show_roof(body: Node2D) -> void:
    if not body.is_in_group("Player"): return

    # 如果 tween_roof 变量中已有 Tween，就先停止它
    if tween_roof: tween_roof.kill()

    tween_roof = create_tween()
    tween_roof.set_trans(Tween.TRANS_QUAD)
    tween_roof.set_ease(Tween.EASE_IN_OUT)
    tween_roof.tween_property(roof, "modulate:a", 1.0, speed_roof)

    await tween_roof.finished
    tween_roof_finished.emit()


func hide_mask(body: Node2D) -> void:
    if not body.is_in_group("Player"): return

    if tween_mask: tween_mask.kill()

    tween_mask = create_tween()
    tween_mask.set_trans(Tween.TRANS_QUAD)
    tween_mask.set_ease(Tween.EASE_IN_OUT)
    tween_mask.tween_property(mask, "modulate:a", 0.0, speed_mask)

    await tween_mask.finished
    tween_mask_finished.emit()

func show_mask(body: Node2D) -> void:
    if not body.is_in_group("Player"): return

    if tween_mask: tween_mask.kill()

    tween_mask = create_tween()
    tween_mask.set_trans(Tween.TRANS_QUAD)
    tween_mask.set_ease(Tween.EASE_IN_OUT)
    tween_mask.tween_property(mask, "modulate:a", 0.7, speed_mask)

    await tween_mask.finished
    tween_mask_finished.emit()


func up_camera_scale(body: Node2D) -> void:
    if not body.is_in_group("Player"): return
    FunctionLibrary._camera_scale_tween(up_scale_value, tween_speed)
    
func down_camera_scale(body: Node2D) -> void:
    if not body.is_in_group("Player"): return
    FunctionLibrary._camera_scale_tween(down_scale_value, tween_speed)
