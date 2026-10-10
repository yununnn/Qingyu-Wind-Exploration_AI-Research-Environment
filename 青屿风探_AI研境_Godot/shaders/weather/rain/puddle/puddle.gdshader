shader_type canvas_item;

// -------------------- 积水形状 --------------------

group_uniforms PuddleShape;

/** 使用红通道生成积水形状。 */
uniform sampler2D puddle_noise : repeat_enable, filter_nearest;

/** 形状阈值；越大，保留下来的积水区域越少。 */
uniform float threshold : hint_range(0.0, 1.0) = 0.5;

/** 图片边界限制区域的宽度，单位为 UV。 */
uniform float border_margin : hint_range(0.0, 0.5) = 0.08;

/** 使用噪波改变边界限制区域的宽度，使边界更不规则。 */
uniform float border_irregularity : hint_range(0.0, 0.1) = 0.03;


// -------------------- 积水轮廓 --------------------

group_uniforms PuddleEdge;

/** 内部轮廓使用的噪波阈值差，不是固定的像素宽度。 */
uniform float edge_width : hint_range(0.0, 0.1) = 0.02;

/** 轮廓阈值的动态偏移幅度，使轮廓向水坑内部变化。 */
uniform float edge_noise_strength : hint_range(0.0, 0.1) = 0.02;

/** 轮廓噪波的移动速度，单位为 UV/秒。 */
uniform vec2 edge_noise_speed = vec2(0.05, 0.05);


// -------------------- 水面波纹 --------------------

group_uniforms Ripple;

/** 使用 Alpha 通道控制白色波纹的叠加强度。 */
uniform sampler2D ripple_texture : repeat_disable, filter_nearest;


// -------------------- 倒影与扰动 --------------------

group_uniforms PuddleReflection;

/** 倒影视口输出的纹理。 */
uniform sampler2D reflection_texture : repeat_disable, filter_nearest;

/** 水坑绘制前已经渲染的屏幕画面，用于显示水底。 */
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

/**
 * 水坑内部的倒影占比。
 */
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.95;

/**
 * 倒影从边缘到内部的过渡范围，单位为噪波值差。
 */
uniform float reflection_fade_range : hint_range(0.001, 0.3) = 0.08;

/** 使用灰度噪波生成水平方向和垂直方向的采样偏移。 */
uniform sampler2D distortion_noise : repeat_enable;

/** 扰动噪波的移动速度，单位为 UV/秒。 */
uniform vec2 distortion_speed = vec2(0.1, 0.1);

/** 扰动幅度，单位为水坑自身的 UV。 */
uniform float distortion_strength : hint_range(0.0, 0.05) = 0.01;

/** 水坑左上角在倒影纹理中的归一化坐标。 */
uniform vec2 reflection_uv_origin = vec2(0.0);

/** 水坑宽高占倒影纹理宽高的比例。 */
uniform vec2 reflection_uv_size = vec2(1.0);


// 生成受图片边界限制的形状噪波。
float create_puddle_noise(vec2 uv) {
    float raw_noise = texture(puddle_noise, uv).r;

    // 当前 UV 到图片四条边的最近距离。
    vec2 edge_distance = min(uv, vec2(1.0) - uv);
    float nearest_edge = min(edge_distance.x, edge_distance.y);

    float irregular_margin = max(
        border_margin + (raw_noise * 2.0 - 1.0) * border_irregularity,
        0.001
    );

    float border_mask = smoothstep(
        0.0,
        irregular_margin,
        nearest_edge
    );

    // 同时限制噪波形状和图片边界，避免相乘后过度压低噪波值。
    return min(raw_noise, border_mask);
}


// 使用更高的阈值收缩主体，再取差值得到内部轮廓。
float create_inner_edge(vec2 uv, float noise_value, float shape) {
    float moving_noise = texture(
        puddle_noise,
        uv - TIME * edge_noise_speed
    ).r;

    float inner_shape = step(
        threshold + edge_width + moving_noise * edge_noise_strength,
        noise_value
    );

    return clamp(shape - inner_shape, 0.0, 1.0);
}


// 两次错位采样分别控制 X、Y 偏移，并将偏移范围居中到零。
vec2 create_distortion_offset(vec2 uv) {
    vec2 noise_uv = uv + TIME * distortion_speed;

    vec2 noise_value = vec2(
        texture(distortion_noise, noise_uv).r,
        texture(distortion_noise, noise_uv + vec2(0.37, 0.61)).r
    );

    return (noise_value * 2.0 - 1.0) * distortion_strength;
}


// 将水坑 UV 映射到倒影纹理中的对应区域，并添加扰动。
vec4 sample_reflection(vec2 uv, vec2 offset) {
    vec2 reflection_uv = clamp(
        reflection_uv_origin + (uv + offset) * reflection_uv_size,
        vec2(0.0),
        vec2(1.0)
    );

    return texture(reflection_texture, reflection_uv);
}


// 将水坑 UV 偏移换算为屏幕 UV 偏移，让水底与倒影保持相同位移。
// 此换算适用于当前水坑与屏幕坐标轴对齐、没有旋转的情况。
vec3 sample_ground(vec2 uv, vec2 screen_uv, vec2 offset) {
    vec2 screen_uv_scale = vec2(
        dFdx(screen_uv.x) / dFdx(uv.x),
        dFdy(screen_uv.y) / dFdy(uv.y)
    );

    vec2 ground_uv = clamp(
        screen_uv + offset * screen_uv_scale,
        vec2(0.0),
        vec2(1.0)
    );

    return textureLod(screen_texture, ground_uv, 0.0).rgb;
}


// 根据形状噪波混合水底与倒影，靠近形状阈值的位置显露更多水底。
vec3 create_surface_color(
    vec3 ground,
    vec4 reflection,
    float noise_value
) {
    float depth_mask = smoothstep(
        threshold,
        threshold + reflection_fade_range,
        noise_value
    );

    float reflection_weight =
        depth_mask * reflection_strength * reflection.a;

    return mix(ground, reflection.rgb, reflection_weight);
}


void fragment() {
    // 形状和轮廓共用噪波纹理的像素网格。
    // 倒影、地面和扰动仍使用原始 UV，避免改变原有采样效果。
    vec2 noise_size = vec2(textureSize(puddle_noise, 0));
    vec2 shape_uv = (floor(UV * noise_size) + vec2(0.5)) / noise_size;

    float noise_value = create_puddle_noise(shape_uv);
    float shape = step(threshold, noise_value);
    float edge = create_inner_edge(shape_uv, noise_value, shape);

    vec2 offset = create_distortion_offset(UV);
    vec4 reflection = sample_reflection(UV, offset);
    vec3 ground = sample_ground(UV, SCREEN_UV, offset);
    vec3 water_rgb = create_surface_color(ground, reflection, noise_value);

    // 先用形状遮罩裁切水面，再覆盖 Alpha 为 0.4 的白色轮廓。
    vec4 color = mix(vec4(0.0), vec4(water_rgb, 1.0), shape);
    color = mix(color, vec4(1, 1, 1, 0.679), edge);

    // 最后叠加白色波纹；保持水面已有的 Alpha。
    float ripple_mask = texture(ripple_texture, UV).a * shape;
    color.rgb = mix(color.rgb, vec3(1.0), ripple_mask);

    COLOR = color;
}