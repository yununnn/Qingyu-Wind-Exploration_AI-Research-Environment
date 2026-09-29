// NOTE: Shader automatically converted from Godot Engine 4.7.2.stable's CanvasItemMaterial.

shader_type canvas_item;
// 渲染模式：添加
render_mode blend_add;
// 粒子动画水平帧数
uniform int particles_anim_h_frames;
// 粒子动画垂直帧数
uniform int particles_anim_v_frames;
// 粒子动画循环
uniform bool particles_anim_loop;

void vertex() {
	// 转换后生成的代码
	float h_frames = float(particles_anim_h_frames);
	float v_frames = float(particles_anim_v_frames);
	VERTEX.xy /= vec2(h_frames, v_frames);
	float particle_total_frames = float(particles_anim_h_frames * particles_anim_v_frames);
	float particle_frame = floor(INSTANCE_CUSTOM.z * float(particle_total_frames));
	if (!particles_anim_loop) {
		particle_frame = clamp(particle_frame, 0.0, particle_total_frames - 1.0);
	} else {
		particle_frame = mod(particle_frame, particle_total_frames);
	}	UV /= vec2(h_frames, v_frames);
	UV += vec2(mod(particle_frame, h_frames) / h_frames, floor((particle_frame + 0.5) / h_frames) / v_frames);
}
