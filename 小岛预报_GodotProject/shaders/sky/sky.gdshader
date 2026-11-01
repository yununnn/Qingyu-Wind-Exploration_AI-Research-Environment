shader_type canvas_item;
render_mode unshaded;

group_uniforms Sky;
/**
 * 天空颜色
 */
uniform vec4 sky_color : source_color = vec4(0.133333, 0.152941, 0.247059, 1.0);
/**
 * 云底颜色
 */
uniform vec4 cloud_shadow_color : source_color = vec4(0.349020, 0.360784, 0.419608, 1.0);
/**
 * 云面颜色
 */
uniform vec4 cloud_color : source_color = vec4(0.552941, 0.572549, 0.600000, 1.0);

group_uniforms Clouds;
/**
 * 使用灰度噪波生成云层的形状。
 */
uniform sampler2D cloud_noise : repeat_enable, filter_linear;
/**
 * 云层缩放比例，数值越小，云块越大。
 */
uniform vec2 cloud_scale = vec2(1.2, 0.8);
/**
 * 云层移动速度，单位为 UV/秒。
 */
uniform vec2 cloud_speed = vec2(0.008, 0.003);
/**
 * 云层阈值，阈值越低，云层覆盖越多。
 */
uniform float cloud_threshold : hint_range(0.2, 0.8, 0.01) = 0.55;

group_uniforms Pixel;
/**
 * 与天空的逻辑绘制尺寸对应；默认适配 640×360。
 */
uniform vec2 canvas_size = vec2(640.0, 360.0);
/**
 * 像素化的尺寸，单位为像素；数值越大，像素化效果越明显。
 */
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 1.0;
group_uniforms;

void fragment() {
	vec2 grid = canvas_size / pixel_size;
	vec2 uv = (floor(UV * grid) + vec2(0.5)) / grid;
	vec2 cloud_uv = uv * cloud_scale - TIME * cloud_speed;
	float cloud_value = texture(cloud_noise, cloud_uv).r;
	// 上方云层更厚，下方留出较大的深蓝灰天空。
	cloud_value += (0.5 - uv.y) * 0.5;
	// 两道硬阈值形成平涂色块和像素阶梯轮廓。
	float shadow = step(cloud_threshold - 0.1, cloud_value);
	float highlight = step(cloud_threshold, cloud_value);
	vec3 color = mix(sky_color.rgb, cloud_shadow_color.rgb, shadow);
	color = mix(color, cloud_color.rgb, highlight);
	COLOR = vec4(color, 1.0);
}
