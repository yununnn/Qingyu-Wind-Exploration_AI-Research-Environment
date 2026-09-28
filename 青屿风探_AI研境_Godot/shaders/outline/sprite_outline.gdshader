shader_type canvas_item;

// 轮廓颜色
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// 轮廓粗细
uniform float outline_size = 1.0;

// 透明度阈值
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	// 原始颜色
	vec4 original_color = texture(TEXTURE, UV);
	

	// 获取上下左右偏移的UV
	vec2 uv = UV;
	vec2 uv_left = uv + vec2(TEXTURE_PIXEL_SIZE.x, 0) * outline_size;
	vec2 uv_right = uv + vec2(-TEXTURE_PIXEL_SIZE.x, 0) * outline_size;
	vec2 uv_up = uv + vec2(0, TEXTURE_PIXEL_SIZE.y) * outline_size;
	vec2 uv_down = uv + vec2(0, -TEXTURE_PIXEL_SIZE.y) * outline_size;

	// 获取上下左右偏移后的颜色
	vec4 color_left = texture(TEXTURE, uv_left);
	vec4 color_right = texture(TEXTURE, uv_right);
	vec4 color_up = texture(TEXTURE, uv_up);
	vec4 color_down = texture(TEXTURE, uv_down);

	// 获取周围透明度最高的值
	float neighbor_alpha = max(
		max(color_left.a, color_right.a),
		max(color_up.a, color_down.a)
	);

	// 当前像素属于图像本体
	if (original_color.a > alpha_threshold) {
		COLOR = original_color;
	}
	// 当前像素透明，但旁边存在有效像素 → 绘制描边
	else if (neighbor_alpha > alpha_threshold) {
		COLOR = outline_color;
	}
	// 其他情况保持原样
	else {
		COLOR = original_color;
	}
}