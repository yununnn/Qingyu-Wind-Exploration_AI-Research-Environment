extends Node

@export var position_offset : Vector2 = Vector2(0, -15)

## 获取当前场景中的玩家节点
func get_player() -> Node2D:
    var player : Node = get_tree().get_first_node_in_group("Player")
    return player


## 获取玩家的全局位置
func get_player_position() -> Vector2:
    var player := get_player()

    if player == null:
        push_warning("当前场景中没有找到玩家节点")
        return Vector2.ZERO

    return player.global_position + position_offset

## 获取玩家在屏幕上的归一化坐标（UV）
func get_player_viewport_uv() -> Vector2:
    ## 获取玩家视口大小
    var viewport_size : Vector2 = get_player().get_viewport().get_visible_rect().size
    ## 获取玩家在视口中相对的像素坐标
    var viewport_pos: Vector2 = get_player().get_global_transform_with_canvas().origin + position_offset

    return viewport_pos / viewport_size

## 判断当前场景是否存在玩家
func has_player() -> bool:
    return get_player() != null

func print11() -> void:
    print(111)
    await get_tree().create_timer(10.0).timeout
    