extends CanvasLayer

## 遮罩层
@onready var overlay: ColorRect = $Iris
## 转场shader
@onready var shader_material: ShaderMaterial = (
    overlay.material as ShaderMaterial
)

var tween:Tween

func _ready() -> void:
    # 隐藏自身
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hide()
    # 设置初始值
    _set_progress(0.0)


## 圆形收拢，最终变成纯黑
func close_to_black(
    time: float = 0.7,
    center_uv: Vector2 = FunctionLibrary.get_player_viewport_uv()
) -> void:
    show()
    _set_progress(0.0)
    _set_center(center_uv)
    PlayerState.current_state = PlayerState.State.CUTSCENE
    
    # 如果 tween 变量中已有 Tween，就先停止它
    if tween: tween.kill()

    tween = create_tween()
    tween.set_trans(Tween.TRANS_QUART)
    tween.set_ease(Tween.EASE_IN)
    tween.tween_method(_set_progress, 0.0, 1.0, time)
    await tween.finished


## 从纯黑开始，圆形向外扩张直至显示完整场景
func open_from_black(
    time: float = 0.7,
    center_uv: Vector2 = FunctionLibrary.get_player_viewport_uv()
) -> void:
    show()
    _set_progress(1.0)
    _set_center(center_uv)

    # 如果 tween 变量中已有 Tween，就先停止它
    if tween: tween.kill()

    tween= create_tween()
    tween.set_trans(Tween.TRANS_QUART)
    tween.set_ease(Tween.EASE_IN)
    tween.tween_method(_set_progress, 1.0, 0.0, time)
    await tween.finished

    PlayerState.current_state = PlayerState.State.NORMAL
    hide()


## 设置遮罩值
func _set_progress(value: float) -> void:
    shader_material.set_shader_parameter(
        "progress", value
    )

## 设置圆形原点位置。 范围：(0, 0) -> (1, 1)
func _set_center(value: Vector2) -> void:
    shader_material.set_shader_parameter(
        "center", value
    )