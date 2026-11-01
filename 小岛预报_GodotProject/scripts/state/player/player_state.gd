extends Node

## 玩家状态{正常，无法移动，无法控制，收集}
enum State { NORMAL, UNMOVE, UNCONTROL, COLLECTION }
## 当前状态
var current_state : State = State.NORMAL


## 光标放大倍数：2 = 32×32，3 = 48×48，4 = 64×64。
const CURSOR_SCALE: int = 3
## 鼠标指针素材。
const CURSOR_TEXTURE: Texture2D = preload(
	"res://assets/mouse_sprites/Arrow Mouse icon 1.png"
)


func _ready() -> void:
	# 设置初始鼠标光标
	set_mouse_cursor()
	# 隐藏光标
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


## 设置初始鼠标光标
func set_mouse_cursor() -> void:
	# 获取图片像素数据
	var image: Image = CURSOR_TEXTURE.get_image()

	# 调整纹理大小、过滤方式
	image.resize(
		image.get_width() * CURSOR_SCALE,
		image.get_height() * CURSOR_SCALE,
		Image.INTERPOLATE_NEAREST
	)
	# 设置鼠标光标
	Input.set_custom_mouse_cursor(
		image,
		Input.CURSOR_ARROW,
		Vector2.ZERO
	)
	