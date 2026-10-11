shader_type canvas_item;
render_mode unshaded;


// ==================== 水域形状 ====================

group_uniforms PuddleShape;

/**
 * 形状噪波，使用 R 通道。
 */
uniform sampler2D puddle_noise : repeat_enable, filter_nearest;

/**
 * 水位阈值；越大，有水的区域越少。
 */
uniform float threshold : hint_range(0.0, 1.0) = 0.5;

/**
 * 整张纹理边缘的限制宽度，单位为 UV。
 */
uniform float border_margin : hint_range(0.0, 0.5) = 0.08;

/**
 * 纹理边缘限制宽度的不规则程度。
 */
uniform float border_irregularity : hint_range(0.0, 0.1) = 0.03;

/**
 * 多边形并集遮罩：R = 边缘距离 / 64，A = 范围内外。
 */
uniform sampler2D water_mask : repeat_disable, filter_nearest;

/**
 * 多边形边界静态向内偏移的程度，单位为像素。
 */
uniform float area_irregularity : hint_range(0.0, 32.0, 0.5) = 6.0;

/**
 * 噪波差值转水深的倍率，由脚本同步。
 */
uniform float depth_scale = 20.0;


// ==================== 统一岸线 ====================

group_uniforms PuddleEdge;

/**
 * 最终水域距离场：R = 到实际岸线的距离 / 64，由脚本生成。
 */
uniform sampler2D shore_distance : repeat_disable, filter_nearest;

/**
 * 所有岸线共同的向内宽度，单位为像素。
 */
uniform float edge_width : hint_range(0.0, 16.0, 0.5) = 1.5;

/**
 * 亮边宽度的扰动幅度，单位为像素，不移动水域边界。
 */
uniform float edge_noise_strength : hint_range(0.0, 8.0, 0.25) = 0.75;

/**
 * 轮廓噪波移动速度，单位为 UV/秒。
 */
uniform vec2 edge_noise_speed = vec2(0.02, 0.01);

/**
 * 岸线亮色强度；0 隐藏亮边。
 */
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.26;


// ==================== 水面波纹 ====================

group_uniforms Ripple;

/**
 * 波纹视口纹理，使用 Alpha 通道。
 */
uniform sampler2D ripple_texture : repeat_disable, filter_nearest;

/**
 * 波纹引起的地面折射强度。
 */
uniform float ripple_distortion : hint_range(0.0, 6.0) = 1.5;

/**
 * 波纹亮色强度，不影响波纹折射。
 */
uniform float ripple_opacity : hint_range(0.0, 1.0) = 0.38;


// ==================== 水色与折射 ====================

group_uniforms WaterSurface;

/**
 * 水面绘制前的屏幕，由 BackBufferCopy 提供。
 */
uniform sampler2D ground_screen : hint_screen_texture, repeat_disable, filter_nearest;

/**
 * 脚本传入的动画时间，单位为秒。
 */
uniform float water_time = 0.0;

/**
 * 水面染色，仅使用 RGB。
 */
uniform vec4 water_color : source_color = vec4(0.42, 0.60, 0.62, 1.0);

/**
 * 水色混合强度，不控制最终 Alpha。
 */
uniform float water_opacity : hint_range(0.0, 1.0) = 0.22;

/**
 * 缓慢流动的地面折射幅度，单位为世界像素。
 */
uniform float refraction_pixels : hint_range(0.0, 6.0) = 1.0;


// ==================== 顶点数据 ====================

// 世界位置，用于计算水内流动。
varying vec2 world_position;

// 世界坐标到屏幕方向的变换，包含相机缩放和旋转。
varying vec2 canvas_x;
varying vec2 canvas_y;


// ==================== 形状计算 ====================

// 生成受纹理边缘限制的水坑噪波。
float create_puddle_noise(vec2 uv) {
	float raw_noise = texture(puddle_noise, uv).r;

	// 到整张纹理四条边的最近距离。
	vec2 edge_distance = min(uv, vec2(1.0) - uv);
	float nearest_edge = min(edge_distance.x, edge_distance.y);

	float irregular_margin = max(
		border_margin + (raw_noise * 2.0 - 1.0) * border_irregularity,
		0.001
	);

	float border_mask = smoothstep(0.0, irregular_margin, nearest_edge);

	return min(raw_noise, border_mask);
}


// ==================== 顶点阶段 ====================

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;

	canvas_x = CANVAS_MATRIX[0].xy;
	canvas_y = CANVAS_MATRIX[1].xy;
}


// ==================== 片元阶段 ====================

void fragment() {
	// ---------- 固定水域形状 ----------

	// 对齐噪波像素中心，与脚本采样保持一致。
	vec2 size = vec2(textureSize(puddle_noise, 0));
	vec2 shape_uv = (
		floor(UV * size + vec2(0.0001)) + vec2(0.5)
	) / size;

	float value = create_puddle_noise(shape_uv);
	float signed_depth = (value - threshold) * depth_scale;

	// 多边形范围叠加静态不规则偏移。
	vec4 mask = texture(water_mask, UV);
	float area_distance = (
		mask.r * 64.0
		- texture(puddle_noise, shape_uv).r * area_irregularity
	);
	float area_shape = mask.a * step(0.0, area_distance);

	// 最终水域 = 噪波水坑 ∩ 多边形并集，不随时间变化。
	float shape = step(0.0, signed_depth) * area_shape;

	// 深度只影响染色和折射，不改变水域范围。
	float depth = smoothstep(0.0, depth_scale * 0.18, signed_depth);


	// ---------- 统一岸线 ----------

	float shore = texture(shore_distance, UV).r * 64.0;
	float moving_noise = texture(
		puddle_noise,
		shape_uv - water_time * edge_noise_speed
	).r;

	// 所有岸线使用同一个宽度和扰动公式。
	float width = max(
		0.0,
		edge_width + (moving_noise * 2.0 - 1.0) * edge_noise_strength
	);
	float edge = shape * (1.0 - step(width, shore));


	// ---------- 波纹折射 ----------

	vec2 texel = vec2(1.0) / vec2(textureSize(ripple_texture, 0));

	// 相邻 Alpha 的差值近似波纹坡度。
	vec2 slope = vec2(
		texture(ripple_texture, UV + vec2(texel.x, 0.0)).a
			- texture(ripple_texture, UV - vec2(texel.x, 0.0)).a,
		texture(ripple_texture, UV + vec2(0.0, texel.y)).a
			- texture(ripple_texture, UV - vec2(0.0, texel.y)).a
	);


	// ---------- 水内流动 ----------

	vec2 flow = vec2(
		sin(world_position.y * 0.065 + water_time * 1.4),
		cos(world_position.x * 0.037 + water_time)
	);

	vec2 displacement = (
		flow * refraction_pixels + slope * ripple_distortion
	) * depth;

	// 世界像素偏移转换为屏幕 UV 偏移。
	vec2 offset = (
		canvas_x * displacement.x + canvas_y * displacement.y
	) * SCREEN_PIXEL_SIZE;

	vec3 ground = texture(
		ground_screen,
		clamp(SCREEN_UV + offset, vec2(0.0), vec2(1.0))
	).rgb;


	// ---------- 颜色合成 ----------

	// 叠加水色，浅水染色较弱。
	vec3 color = mix(
		ground,
		water_color.rgb,
		water_opacity * mix(0.35, 1.0, depth)
	);

	// 叠加统一岸线亮色。
	color = mix(
		color,
		vec3(0.90, 0.95, 0.94),
		edge * edge_opacity
	);

	// 叠加波纹亮色。
	float ripple = texture(ripple_texture, UV).a;
	color = mix(
		color,
		vec3(0.90, 0.95, 0.94),
		clamp(ripple * ripple_opacity * depth, 0.0, 1.0)
	);

	// 范围外透明，范围内显示折射后的地面与水面效果。
	COLOR = vec4(color, shape);
}