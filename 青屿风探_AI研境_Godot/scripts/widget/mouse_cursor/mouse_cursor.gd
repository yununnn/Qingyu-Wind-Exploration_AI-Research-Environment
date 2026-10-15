extends Node

# 放大倍数：2 = 32×32，3 = 48×48，4 = 64×64。
const CURSOR_SCALE: int = 3

# 使用项目当前的鼠标指针素材。
const CURSOR_TEXTURE: Texture2D = preload(
	"res://assets/mouse_sprites/Arrow Mouse icon 1.png"
)


func _ready() -> void:
	# 获取图片像素数据；不会修改原始 PNG 文件。
	var image: Image = CURSOR_TEXTURE.get_image()

	# 使用最近邻放大，让像素风指针保持清晰。
	image.resize(
		image.get_width() * CURSOR_SCALE,
		image.get_height() * CURSOR_SCALE,
		Image.INTERPOLATE_NEAREST
	)

	# 热点是图片中真正负责点击的位置。
	# 当前项目没有单独设置热点，因此沿用左上角 (0, 0)。
	# 如果以后调整热点，需要将原图上的热点坐标也乘以放大倍数。
	Input.set_custom_mouse_cursor(
		image,
		Input.CURSOR_ARROW,
		Vector2.ZERO
	)