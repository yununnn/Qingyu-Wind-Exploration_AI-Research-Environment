shader_type canvas_item;
render_mode unshaded, blend_mix;


/**
 * 屏幕纹理
 */
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;


/**
 * 创建水波纹
 */
vec4 create_ripple(
	vec2 uv,
	vec4 ripple_color,
	float duration,
	float min_radius,
	float max_radius,
	float thickness,
	float softness
) {
	vec2 p = uv - vec2(0.5);
	float dist = length(p);
	float t = fract(TIME / max(duration, 0.001));
	float radius = mix(min_radius, max_radius, t);

	float ring = 1.0 - smoothstep(
		thickness,
		thickness + softness,
		abs(dist - radius)
	);

	float alpha = ring * (1.0 - t);
	return vec4(ripple_color.rgb, ripple_color.a * alpha);
}


/**
 * 计算扰动权重（0~1）：比波纹更宽，且带延迟
 */
float ripple_disturb_weight(
	vec2 uv,
	float duration,
	float min_radius,
	float max_radius,
	float delay,
	float width
) {
	vec2 p = uv - vec2(0.5);
	float dist = length(p);

	float t = fract(TIME / max(duration, 0.001));
	float t_disturb = fract(t - delay);

	float radius = mix(min_radius, max_radius, t_disturb);
	float d = abs(dist - radius);

	// 平滑衰减的扰动带（宽度比波纹厚度大）
	float strength = 1.0 - smoothstep(width * 0.5, width, d);
	return strength * (1.0 - t_disturb);
}


/**
 * 波纹参数
 */
uniform vec4 ripple_color : source_color = vec4(1.0);
uniform float duration = 0.8;
uniform float min_radius = 0.02;
uniform float max_radius = 0.35;
uniform float thickness = 0.02;
uniform float softness = 0.01;

/**
 * 扰动参数（参考您给的参考代码）
 */
// 频率：参考代码中对应 100.0，控制波纹密度
uniform float disturb_frequency : hint_range(10.0, 300.0) = 100.0;
// 速度：参考代码中对应 -10.0，控制时间演化
uniform float disturb_speed : hint_range(-50.0, 50.0) = -10.0;
// 偏移幅度：参考代码中对应 0.05
uniform float disturb_strength : hint_range(0.0, 0.2) = 0.05;

/**
 * 扰动带的宽度与延迟
 */
uniform float disturb_width : hint_range(0.01, 0.5) = 0.15;
uniform float disturb_delay : hint_range(0.0, 0.9) = 0.25;


void fragment() {
	vec2 uv = UV;

	// -------- 1. 参考代码中的全局扰动偏移 --------
	// 相位 = TIME * speed + length(UV - 0.5) * frequency
	vec2 centered = uv - vec2(0.5);
	float phase = TIME * disturb_speed + length(centered) * disturb_frequency;

	// sin(相位) * 强度 → 标量偏移量
	float sin_offset = sin(phase) * disturb_strength;

	// 参考代码：xy 同加该标量（沿对角方向整体平移）
	vec2 global_offset = vec2(sin_offset, sin_offset);

	// -------- 2. 扰动权重（带延迟 + 比波纹宽）--------
	float weight = ripple_disturb_weight(
		uv,
		duration,
		min_radius,
		max_radius,
		disturb_delay,
		disturb_width
	);

	// 把全局扰动按权重"局部化"，只在扰动带内生效
	vec2 local_offset = global_offset * weight;

	// -------- 3. 采样被扰动的屏幕纹理 --------
	vec2 screen_uv = SCREEN_UV + local_offset;
	vec3 background = texture(screen_texture, screen_uv).rgb;

	// -------- 4. 波纹本体 --------
	vec4 ripple = create_ripple(
		uv,
		ripple_color,
		duration,
		min_radius,
		max_radius,
		thickness,
		softness
	);

	// -------- 5. 合成：背景透明，只在扰动带 + 波纹处可见 --------
	vec3 final_rgb = mix(background, ripple.rgb, ripple.a);
	float final_alpha = clamp(weight + ripple.a, 0.0, 1.0);

	COLOR = vec4(final_rgb, final_alpha);
}