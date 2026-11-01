shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 ripple_color : source_color = vec4(0.9, 0.95, 1.0, 0.85);

varying float particle_progress;
varying vec4 particle_tint;

void vertex() {
	particle_progress = INSTANCE_CUSTOM.y;
	particle_tint = COLOR;
}

float ellipse_fill(vec2 point, vec2 radii) {
	vec2 normalized_point = point / radii;
	return 1.0 - step(1.0, dot(normalized_point, normalized_point));
}

void fragment() {
	float progress = clamp(particle_progress, 0.0, 1.0);
	float frame = min(floor(progress * 8.0), 7.0);
	float radius = 2.0 + frame * 2.0;
	vec2 radii = vec2(radius, radius * 0.5);
	// 在固定的 32×32 画布上重画椭圆，不缩放粒子纹理。
	vec2 point = floor(UV * 32.0) + vec2(0.5) - vec2(16.0);
	float filled = ellipse_fill(point, radii);
	// 对实心椭圆做四邻域内缩，保留连通的单像素边界。
	float inside = min(
		min(ellipse_fill(point + vec2(1.0, 0.0), radii),
			ellipse_fill(point - vec2(1.0, 0.0), radii)),
		min(ellipse_fill(point + vec2(0.0, 1.0), radii),
			ellipse_fill(point - vec2(0.0, 1.0), radii))
	);
	float ring = filled * (1.0 - inside);
	float fade = 1.0 - smoothstep(0.35, 1.0, progress);
	COLOR = vec4(ripple_color.rgb * particle_tint.rgb,
		ripple_color.a * particle_tint.a * ring * fade);
}
