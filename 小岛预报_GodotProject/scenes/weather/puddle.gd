extends Node2D

## 水波纹子视口，用于渲染波纹效果
@onready var sub_viewport_ripple: SubViewport = $CanvasLayer/SubViewportRipple
## 水面倒影子视口，用于渲染倒影效果
@onready var sub_viewport_reflection: SubViewport = $CanvasLayer/SubViewportReflection
## 2D 精灵节点，用于显示水坑的纹理
@onready var sprite_2d: Sprite2D = $Sprite2D


## 噪波差值换算成水深的倍率；越大，物体被淹没的深度越大。
@export var depth_scale: float = 20.0

## 物体水位线上下起伏的最大幅度，单位为世界像素；不影响水域边界。
@export var wave_height: float = 0.8

## 一次完整起伏在世界 X 方向上的长度，单位为世界像素，必须大于 0。
## 越大，波形越平缓；越小，起伏越密集。
@export var wave_length: float = 64.0

## 水位线起伏的相位速度，单位为弧度/秒；设为 0 时停止起伏。
@export var wave_speed: float = 1.8

## 容纳多个 Polygon2D；它们的并集决定水面的可见范围。
@onready var water_areas: Node2D = $WaterAreas

## Tree 节点下的树木；每帧更新它们的水深、水线和图集采样范围。
@onready var trees: Array[Node] = $Tree.get_children()

## 当前水面的独立材质实例，用于设置水位、遮罩和折射等参数。
var water_material: ShaderMaterial

## 当前水坑噪波纹理，与水面 Shader 使用同一份资源。
var noise_texture: Texture2D

## 缓存的噪波图像，供脚本读取树根位置的噪波值，计算水深。
var noise_image: Image

## 多边形距离遮罩：R 通道保存边缘距离 / 64，A 通道保存范围内外。
## 范围内 A = 1，范围外 A = 0；不用于透明度渐隐。
var mask_image: Image

## 最终水域距离场对应的形状参数；形状变化才重新生成。
var outline_parameters := Vector4(INF, INF, INF, INF)

## 累计动画时间，单位为秒，用于驱动水面折射和物体水线起伏。
var water_time: float = 0.0


func _ready() -> void:
	# 复制水面材质，避免修改参数时影响共用原材质的其他水坑。
	water_material = sprite_2d.material.duplicate() as ShaderMaterial
	sprite_2d.material = water_material

	# 先让波纹视口覆盖完整水面，避免 400×400 被拉伸到 2200×360。
	setup_ripples()
	water_material.set_shader_parameter("ripple_texture", sub_viewport_ripple.get_texture())
	# 停止倒影视口的渲染，并禁用它及其继承处理模式的子节点更新。
	sub_viewport_reflection.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sub_viewport_reflection.process_mode = Node.PROCESS_MODE_DISABLED

	# 隐藏所有多边形的可视填充，实际水面仍由 Sprite2D 绘制。
	water_areas.hide()

	# 创建屏幕拷贝节点，供水面 Shader 通过 ground_screen 采样。
	var copy := BackBufferCopy.new()

	# 拷贝整个视口中已经绘制的内容，供地面折射使用。
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT

	# 在父节点 Sprite2D 绘制水面之前执行拷贝，避免采到水面自身。
	copy.show_behind_parent = true
	sprite_2d.add_child(copy)

	# 根据多边形生成距离遮罩，并更新水面范围及材质中的遮罩纹理。
	rebuild_water_mask()


func _process(delta: float) -> void:
	# 累计动画时间，delta 为上一帧到当前帧经过的秒数。
	water_time += delta

	# 更新水面动画时间和水深倍率；时间驱动折射，不改变水域边界。
	water_material.set_shader_parameter("water_time", water_time)
	water_material.set_shader_parameter("depth_scale", depth_scale)

	# 获取水面实际使用的噪波纹理，确保脚本与 Shader 采样同一份资源。
	var current_noise := water_material.get_shader_parameter("puddle_noise") as Texture2D

	# 仅在噪波纹理被替换时，切换信号连接并重新缓存图像。
	if current_noise != noise_texture:
		# 断开旧纹理的监听，避免旧资源变化时仍触发刷新。
		if noise_texture != null:
			noise_texture.changed.disconnect(refresh_noise_image)

		noise_texture = current_noise

		# 当前纹理内容发生变化时，刷新 CPU 端缓存的噪波图像。
		noise_texture.changed.connect(refresh_noise_image)
		refresh_noise_image()

	# 噪波图像尚未就绪时，跳过本帧的树木水深计算。
	if noise_image == null:
		return

	# 所有岸线共用最终水域距离场；参数不变时直接复用缓存。
	update_water_outline()

	for tree: Sprite2D in trees:
		# 读取树根在 Sprite2D 本地坐标中的 Y 位置。
		var root_y: float = tree.material.get_shader_parameter("root_y")

		# 将树根位置转换成世界坐标，用于采样水面。
		var root := tree.to_global(Vector2(0.0, root_y))

		# sample.x：基础水深，可为负值。
		# sample.y：树根是否位于有效水域范围内，1 为范围内，0 为范围外。
		var sample := sample_root(root)

		# 获取树木本地 Y 轴对应的世界缩放，包含父节点的缩放。
		var scale_y := tree.global_transform.y.length()

		# 将世界像素水深换算成树木本地像素，单独传给当前树木。
		tree.set_instance_shader_parameter("submerge_depth", sample.x / scale_y)

		# 水线起伏参数：
		# x：换算到树木本地像素的振幅。
		# y：世界 X 方向的空间频率，TAU 为一个完整周期的弧度。
		# z：共享时间相位，让不同树木的水线按同一时间推进。
		# w：范围遮罩，范围外的树木不显示水下效果。
		tree.set_instance_shader_parameter("water_wave", Vector4(wave_height / scale_y, TAU / wave_length, water_time * wave_speed, sample.y))

		# 传入当前精灵在图集中的 UV 范围，限制折射采样，避免串到相邻素材。
		tree.set_instance_shader_parameter("atlas_uv_rect", atlas_rect(tree))



## 多个多边形先合并为像素遮罩，再计算到合并后外边界的距离。
## 修改任一多边形的位置、顶点，或增删节点后，调用一次即可。
func rebuild_water_mask() -> void:
	# 始终使用完整水面的尺寸，不改变 Sprite2D 的位置、缩放或 UV。
	var rect := sprite_2d.get_rect()
	var size := Vector2i((rect.size * sprite_2d.scale.abs()).ceil())
	mask_image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	mask_image.fill(Color.TRANSPARENT)

	for child in water_areas.get_children():
		if not child is Polygon2D:
			continue
		var area := child as Polygon2D
		if area.polygon.size() < 3:
			continue # 编辑过程中尚未画完的多边形不参与遮罩。
		# 两者同属 Puddle；计入容器和多边形自身的变换。
		var relative := sprite_2d.transform.affine_inverse() * water_areas.transform * area.transform
		var points := PackedVector2Array()
		for point in area.polygon:
			points.append((relative * point - rect.position) / rect.size * Vector2(size))
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		var start := Vector2i(bounds.position.floor()).clamp(Vector2i.ZERO, size)
		var end := Vector2i(bounds.end.ceil()).clamp(Vector2i.ZERO, size)
		for y in range(start.y, end.y):
			for x in range(start.x, end.x):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
					# 任意多边形包含该像素就保留它，重叠区不相互覆盖或挖空。
					mask_image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))

	# 多边形距离只用于静态形状不规则控制；亮边改用最终水域距离。
	write_edge_distances(mask_image)
	water_material.set_shader_parameter("water_mask", ImageTexture.create_from_image(mask_image))
	outline_parameters = Vector4(INF, INF, INF, INF)
	update_water_outline()


## 为二值图像写入向内的边缘距离：R=距离/64，A 保留原范围。
## 多边形并集与最终水域复用同一套像素距离计算。
func write_edge_distances(image: Image) -> void:
	var size := image.get_size()
	var bounds := image.get_used_rect()
	var first := bounds.position
	var last := bounds.end
	var distances := PackedFloat32Array()
	distances.resize(size.x * size.y)
	for y in range(first.y, last.y):
		for x in range(first.x, last.x):
			if image.get_pixel(x, y).a > 0.5:
				distances[y * size.x + x] = 64.5
	# 在合并后的二值遮罩上做两遍八邻域距离扫描。
	# 这是像素距离近似；不会把各多边形交叠处当成岸线。
	# 只需保留 64 像素内的距离，沿用现有 Shader 的 R×64 约定。
	var diagonal := sqrt(2.0)
	for y in range(first.y, last.y):
		for x in range(first.x, last.x):
			var i := y * size.x + x
			if distances[i] == 0.0:
				continue
			var d := minf(distances[i], float(mini(x + 1, y + 1)))
			if x > 0:
				d = minf(d, distances[i - 1] + 1.0)
			if y > 0:
				d = minf(d, distances[i - size.x] + 1.0)
				if x > 0:
					d = minf(d, distances[i - size.x - 1] + diagonal)
				if x + 1 < size.x:
					d = minf(d, distances[i - size.x + 1] + diagonal)
			distances[i] = d
	for y in range(last.y - 1, first.y - 1, -1):
		for x in range(last.x - 1, first.x - 1, -1):
			var i := y * size.x + x
			if distances[i] == 0.0:
				continue
			var d := minf(distances[i], float(mini(size.x - x, size.y - y)))
			if x + 1 < size.x:
				d = minf(d, distances[i + 1] + 1.0)
			if y + 1 < size.y:
				d = minf(d, distances[i + size.x] + 1.0)
				if x > 0:
					d = minf(d, distances[i + size.x - 1] + diagonal)
				if x + 1 < size.x:
					d = minf(d, distances[i + size.x + 1] + diagonal)
			distances[i] = d
			# 减去半像素，使距离从像素外边界起算；A 仍为内外标记。
			image.set_pixel(x, y, Color(minf((d - 0.5) / 64.0, 1.0), 0.0, 0.0, 1.0))


## 先求“噪波水坑 ∩ 不规则多边形并集”，再求到最终岸线的距离。
## 时间、亮边宽度和折射不改变水域形状，因此不触发重建。
func update_water_outline() -> void:
	if noise_image == null or mask_image == null:
		return
	var parameters := Vector4(
		water_material.get_shader_parameter("threshold"),
		water_material.get_shader_parameter("border_margin"),
		water_material.get_shader_parameter("border_irregularity"),
		water_material.get_shader_parameter("area_irregularity")
	)
	if parameters == outline_parameters:
		return
	outline_parameters = parameters
	var size := mask_image.get_size()
	var noise_size := Vector2(noise_image.get_size())
	var shore := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	shore.fill(Color.TRANSPARENT)
	var bounds := mask_image.get_used_rect()
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var mask := mask_image.get_pixel(x, y)
			if mask.a < 0.5:
				continue
			# 与现有 Shader 和树根采样相同的最近邻噪波像素。
			var uv := Vector2(x + 0.5, y + 0.5) / Vector2(size)
			var cell := Vector2i((uv * noise_size + Vector2(0.0001, 0.0001)).floor())
			uv = (Vector2(cell) + Vector2(0.5, 0.5)) / noise_size
			var noise := noise_image.get_pixelv(cell).r
			if mask.r * 64.0 - noise * parameters.w < 0.0:
				continue
			var edge := minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
			var margin := maxf(parameters.y + (noise * 2.0 - 1.0) * parameters.z, 0.001)
			var border := smoothstep(0.0, margin, edge)
			if minf(noise, border) >= parameters.x:
				shore.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
	# 统一的距离场包含内部孔洞、原噪波岸线和裁剪岸线。
	write_edge_distances(shore)
	water_material.set_shader_parameter("shore_distance", ImageTexture.create_from_image(shore))


## 获取并缓存噪波图像，供 CPU 读取像素值。
## 噪波纹理被替换或其内容变化时调用，不需要每帧获取。
func refresh_noise_image() -> void:
	noise_image = noise_texture.get_image()

	# 压缩图像需要先解压，后面才能通过 get_pixelv() 读取像素。
	if noise_image != null and noise_image.is_compressed():
		noise_image.decompress()
	# 噪波内容变化也会改变岸线；下次有效采样时重建。
	outline_parameters = Vector4(INF, INF, INF, INF)
	update_water_outline()


## 输入：树根的世界坐标。
## 返回 x：带正负号的基础水深，尚未叠加物体水线起伏。
## 返回 y：是否处于多边形及其不规则边缘限定的范围内。
## y=1 不代表一定有水，还需要根据 x 和水线起伏判断。
func sample_root(root_world: Vector2) -> Vector2:
	# 获取水面 Sprite2D 的本地绘制矩形。
	var rect := sprite_2d.get_rect()

	# 世界坐标 → Sprite2D 本地坐标 → 归一化 UV。
	var uv := (sprite_2d.to_local(root_world) - rect.position) / rect.size

	# 超出水面矩形时，返回范围外。
	# UV=1 对应图像尺寸之外，因此也需要排除。
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return Vector2.ZERO

	# 将 UV 转换为距离遮罩的像素索引。
	var mask_cell := Vector2i((uv * Vector2(mask_image.get_size())).floor())

	# A 通道为 0，说明树根位于多边形外。
	if mask_image.get_pixelv(mask_cell).a < 0.5:
		return Vector2.ZERO

	var size := Vector2(noise_image.get_size())

	# 按最近邻采样规则找到噪波像素。
	# 微小偏移用于减小 CPU/GPU 在像素边界处的浮点舍入分歧，
	# 必须与水面 Shader 中的计算保持一致。
	var cell := Vector2i((uv * size + Vector2(0.0001, 0.0001)).floor())

	# 将 UV 对齐到所选噪波像素的中心，用于后续边界计算。
	uv = (Vector2(cell) + Vector2(0.5, 0.5)) / size

	# 读取噪波的 R 通道，与 Shader 使用相同的基础噪波值。
	var noise := noise_image.get_pixelv(cell).r

	# 获取多边形边缘的不规则程度，单位为 Puddle 本地像素。
	var area_irregularity: float = water_material.get_shader_parameter("area_irregularity")

	# 还原到多边形边界的距离，再减去静态噪波产生的向内偏移。
	# 小于 0 表示被不规则边缘排除，按范围外处理。
	if mask_image.get_pixelv(mask_cell).r * 64.0 - noise * area_irregularity < 0.0:
		return Vector2.ZERO

	# 读取原水坑形状参数，与 Shader 的 create_puddle_noise() 保持一致。
	var margin: float = water_material.get_shader_parameter("border_margin")
	var irregularity: float = water_material.get_shader_parameter("border_irregularity")
	var threshold: float = water_material.get_shader_parameter("threshold")

	# 当前 UV 到水面矩形四条边的最小距离，单位为归一化 UV。
	var edge := minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))

	# 生成原水坑在矩形边缘附近的衰减值，并通过噪波改变衰减宽度。
	# 这是原水坑形状计算，不是多边形遮罩的透明度渐隐。
	var border := smoothstep(0.0, maxf(margin + (noise * 2.0 - 1.0) * irregularity, 0.001), edge)

	# 使用噪波和边界衰减中较小的值，减去水位阈值，再换算成水深。
	# 正值表示基础水深为正；负值保留给物体水线起伏继续判断。
	# y=1 表示通过了范围检查。
	return Vector2((minf(noise, border) - threshold) * depth_scale, 1.0)


## 返回当前树木素材在底层纹理中的归一化矩形：
## Vector4(左上角 U, 左上角 V, UV 宽度, UV 高度)。
## Shader 用它限制折射采样，避免采到图集中的相邻素材。
func atlas_rect(tree: Sprite2D) -> Vector4:
	# 默认允许采样整张纹理：UV 范围为 0～1。
	var rect := Rect2(Vector2.ZERO, Vector2.ONE)

	if tree.texture is AtlasTexture:
		# AtlasTexture：将切片的像素区域换算成底层图集的 UV 区域。
		var atlas := tree.texture as AtlasTexture
		var size := Vector2(atlas.atlas.get_size())
		rect = Rect2(atlas.region.position / size, atlas.region.size / size)

	elif tree.region_enabled:
		# 普通纹理开启 Region：使用 Sprite2D 的裁剪区域计算 UV。
		var size := Vector2(tree.texture.get_size())
		rect = Rect2(tree.region_rect.position / size, tree.region_rect.size / size)

	# 将位置和尺寸打包，供实例 Shader 参数使用。
	return Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)

## 波纹覆盖完整水面，但不缩放单个粒子。
func setup_ripples() -> void:
	var size := Vector2i((sprite_2d.get_rect().size * sprite_2d.scale.abs()).ceil())
	sub_viewport_ripple.size = size
	var ripple := $CanvasLayer/SubViewportRipple/Ripple as GPUParticles2D
	ripple.position = Vector2(size) * 0.5
	var process := ripple.process_material.duplicate() as ParticleProcessMaterial
	process.emission_box_extents = Vector3(size.x * 0.5, size.y * 0.5, 0.0)
	ripple.process_material = process
	ripple.visibility_rect = Rect2(-Vector2(size) * 0.5 - Vector2(32,32), Vector2(size) + Vector2(64,64))
	ripple.restart()
