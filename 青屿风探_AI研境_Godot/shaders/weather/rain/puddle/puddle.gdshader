shader_type canvas_item;

// 原始噪波：控制整体形状与白边
/**
 * 原始噪波的切层起点。
 * 灰度低于此值的区域透明，露出下面的地图。
 * 数值越大，黑色覆盖区域越小。
 */
uniform float threshold : hint_range(0.0, 1.0) = 0.5;

/**
 * 整条白边的灰度区间宽度，包含固定外圈和移动内圈。
 * 数值越大，白边通常越宽；不是固定的像素宽度。
 */
uniform float edge_width : hint_range(0.0, 0.1) = 0.03;

// 固定白色外圈的宽度，占用白边总宽度的一部分
/**
 * 始终保持白色的外圈宽度。
 * 移动内圈宽度为 edge_width 减去 outer_width。
 * 大于等于 edge_width 时，整条白边固定为白色。
 */
uniform float outer_width : hint_range(0.0, 0.1) = 0.01;

// 额外的移动噪波
/**
 * 用于内圈流动纹理的灰度噪波。
 * 可指定 NoiseTexture2D，并在 Noise 中创建 FastNoiseLite。
 * 建议开启 Seamless，减少重复采样时的接缝。
 */
uniform sampler2D edge_noise : repeat_enable, filter_nearest;

/**
 * 移动噪波的 UV 缩放。
 * X、Y 分别控制横向和纵向的重复次数。
 * 数值越大，纹理越细碎。
 */
uniform vec2 noise_scale = vec2(4.0, 4.0);

/**
 * 移动噪波每秒的采样坐标偏移。
 * X 控制横向，Y 控制纵向；设为 0 时该方向停止。
 * 正值使显示纹理向负方向移动，负值则反向。
 */
uniform vec2 flow_speed = vec2(0.05, 0.02);

// 移动噪波：独立控制切层位置与宽度
/**
 * 移动噪波的切层起点。
 * 与 moving_edge_width 一起决定保留的灰度区间。
 * 调整此值可选取移动噪波中的不同层。
 */
uniform float moving_threshold : hint_range(0.0, 1.0) = 0.2;

/**
 * 移动噪波保留的灰度区间宽度。
 * 保留范围为 moving_threshold 到两者之和，不包含上限。
 * 设为 0 时移动内圈全黑，固定外圈仍为白色。
 * 建议与 moving_threshold 的和不超过 1.0。
 */
uniform float moving_edge_width : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	// 灰度噪波的 RGB 相同，取一个通道即可
	float noise_value = texture(TEXTURE, UV).r;

	// 超过第一个阈值：白边 + 黑色区域
	float mask = step(threshold, noise_value);

	// 超过第二个阈值：黑色区域
	float inside = step(threshold + edge_width, noise_value);

	// 两个区域相减，只留下中间的白边
	float edge = mask - inside;

	// 从白边中分出固定外圈，宽度不超过白边总宽度
	float inner_start = step(
		threshold + min(outer_width, edge_width),
		noise_value
	);
	float outer_edge = mask - inner_start;

	// 剩余的内圈用于显示移动噪波
	float inner_edge = edge - outer_edge;

	// 随时间移动的采样坐标
	vec2 flow_uv = UV * noise_scale + TIME * flow_speed;
	float moving_noise = texture(edge_noise, flow_uv).r;

	// 移动噪波同样使用两个阈值
	float moving_mask = step(moving_threshold, moving_noise);
	float moving_inside = step(
		moving_threshold + moving_edge_width,
		moving_noise
	);

	// 两个区域相减，只留下移动噪波中选定的一层
	float moving_edge = moving_mask - moving_inside;

	// 将移动噪波切成黑白，限制在白边内
	// 只影响内圈，固定外圈始终保持白色
	inner_edge *= moving_edge;

	// 合并固定白色外圈和带移动噪波的内圈
	edge = outer_edge + inner_edge;

	COLOR = vec4(vec3(edge), mask);
}