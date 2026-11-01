shader_type canvas_item;
render_mode unshaded, blend_mix;

/**
 * 暴风区域尺寸，应与承载节点的实际尺寸一致。
 * 用于保持噪声比例和像素块形状，避免横向拉伸。
 */
uniform vec2 band_size = vec2(2200.0, 360.0);

/**
 * 像素块大小，单位为节点局部坐标中的像素。
 * 1：细腻；2：推荐；4～8：更明显的块状效果。
 */
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;

/**
 * 暴风动画速度倍率。
 * 0：静止；1：正常速度；数值越大，流动和翻涌越快。
 * 仅在 wind_time < 0 时生效。
 */
uniform float speed : hint_range(0.0, 3.0, 0.05) = 1.0;

/**
 * 云雾翻涌、扭曲的强度。
 * 0：关闭坐标扭曲，但云雾仍会流动；
 * 数值越大，局部翻卷越明显。
 */
uniform float turbulence : hint_range(0.0, 2.0, 0.05) = 1.0;

/**
 * 整体不透明度倍率。
 * 0：完全透明；1：保留 Shader 计算出的完整透明度。
 * 数值越大，对场景的遮挡越强。
 */
uniform float opacity : hint_range(0.0, 1.0, 0.05) = 0.55;

/**
 * 云雾暗部颜色，用于表现背光和内部阴影。
 * 当前 Shader 只使用 RGB，颜色中的 Alpha 不参与透明度计算。
 */
uniform vec4 shadow_color : source_color = vec4(0.349020, 0.360784, 0.419608, 1.0);

/**
 * 云雾亮部颜色，用于表现受光的翻卷边缘。
 * 当前 Shader 只使用 RGB，颜色中的 Alpha 不参与透明度计算。
 */
uniform vec4 light_color : source_color = vec4(0.552941, 0.572549, 0.600000, 1.0);

/**
 * 手动控制动画时间，单位为秒。
 * 小于 0：自动使用 TIME * speed 播放。
 * 大于或等于 0：直接使用该值，需要由脚本持续更新；
 * 保持数值不变即可暂停，也可用于定位到指定动画时刻。
 */
uniform float wind_time = -1.0;

float hash(vec2 p) {
	uvec2 cell = uvec2(ivec2(p));
	uint h = cell.x * 374761393u + cell.y * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return float(h & 0x00ffffffu) / 16777216.0;
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), w.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), w.x), w.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float weight = 0.52;
	for (int i = 0; i < 5; i++) {
		value += noise(p) * weight;
		p = mat2(vec2(1.92, 0.4), vec2(-0.4, 1.92)) * p + vec2(7.1, 13.7);
		weight *= 0.48;
	}
	return value;
}

void fragment() {
	// Pixel proportions, then a wind direction tilted 12 degrees downwards.
	vec2 pixel_position = (floor(UV * band_size / pixel_size) + vec2(0.5)) * pixel_size;
	vec2 pixel_uv = pixel_position / band_size;
	vec2 p = pixel_position / 360.0;
	vec2 direction = normalize(vec2(1.0, 0.21));
	vec2 across = vec2(-direction.y, direction.x);
	vec2 wind_uv = vec2(dot(p, direction), dot(p, across));
	float t = wind_time < 0.0 ? TIME * speed : wind_time;
	vec2 flow = wind_uv - vec2(t * 2.4, 0.0);

	// Domain warping rolls the cloud masses without drawing streamlines.
	vec2 warp = vec2(
		fbm(flow * vec2(0.62, 1.65) + vec2(4.1, t * 0.15)),
		fbm(flow * vec2(0.73, 1.8) + vec2(19.4, -t * 0.12))
	) - 0.5;
	vec2 cloud_uv = flow * vec2(0.95, 3.0) + warp * turbulence * 2.7;
	float cloud = fbm(cloud_uv);
	float lit_cloud = fbm(cloud_uv + vec2(-0.14, -0.25));
	float middle = fbm((wind_uv - vec2(t * 3.25, 0.0)) * vec2(1.8, 6.5)
		+ warp * turbulence * 3.6 + 31.0);
	float detail = fbm((wind_uv - vec2(t * 4.2, 0.0)) * vec2(3.2, 15.0)
		+ warp * turbulence * 4.2 + 61.0);

	float mass = cloud * 0.63 + middle * 0.27 + detail * 0.1;
	// Broad fronts alternately hide and reveal the background as they pass.
	float front = smoothstep(0.2, 0.78,
		fbm(vec2(flow.x * 0.38, flow.y * 1.2) + 72.0));
	float density = smoothstep(0.23, 0.68, mass) * (0.50 + front * 0.72);
	float alpha = 1.0 - exp(-density * 2.8);

	// Lit folds and darker interiors give the fog volume rather than line edges.
	float folds = clamp((cloud - lit_cloud) * 4.2 + 0.45, 0.0, 1.0);
	float lighting = clamp(folds * 0.40 + smoothstep(0.25, 0.70, mass) * 0.55
		+ (detail - 0.5) * 0.22, 0.0, 1.0);
	lighting = floor(lighting * 3.0 + 0.5) / 3.0;
	vec3 color = mix(shadow_color.rgb, light_color.rgb, lighting);
	float edge = smoothstep(0.0, 0.13, pixel_uv.y)
		* (1.0 - smoothstep(0.87, 1.0, pixel_uv.y))
		* smoothstep(0.0, 0.025, pixel_uv.x)
		* (1.0 - smoothstep(0.975, 1.0, pixel_uv.x));
	alpha = floor(clamp(alpha * edge, 0.0, 1.0) * 4.0 + 0.5) / 4.0;
	COLOR = vec4(color, alpha * opacity);
}
