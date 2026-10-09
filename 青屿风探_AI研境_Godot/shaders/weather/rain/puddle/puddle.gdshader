shader_type canvas_item;

/**
 * 积水形状
 */
group_uniforms PuddleShape;
/**
 * 积水形状纹理
 * 使用噪波纹理来生成积水的形状。
 */
uniform sampler2D puddle_noise : repeat_enable, filter_nearest;
/**
 * 形状阈值
 * 数值越大，积水形状越小。
 */
uniform float threshold : hint_range(0.0, 1.0) = 0.5;
/**
 * 水坑与图片边缘的安全距离
 * 数值越大，水坑越不会靠近 Sprite2D 的边界
 */
uniform float border_margin : hint_range(0.0, 0.5) = 0.08;

/**
 * 图片边缘的不规则程度
 */
uniform float border_irregularity : hint_range(0.0, 0.1) = 0.03;

/**
 * 积水边缘
 */
group_uniforms PuddleEdge;
/**
 * 边缘宽度
 */
uniform float edge_width : hint_range(0.0, 0.1) = 0.02;
/**
 * 边缘噪波强度
 * 越大，边缘的移动噪波越明显
 */
uniform float edge_noise_strength : hint_range(0.0, 0.1) = 0.02;
/**
 * 边缘噪波速度
 * 控制边缘噪波移动的快慢
 */
uniform vec2 edge_noise_speed = vec2(0.05, 0.05);

/**
 * 水面波纹
 */
group_uniforms Ripple;
/**
 * 波纹纹理
 */
uniform sampler2D ripple_texture : repeat_disable, filter_nearest;

/**
 * 水面反射
 */
group_uniforms PuddleReflection;
/**
 * 屏幕纹理
 */
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
/**
 * 反射颜色
 */
uniform vec4 puddle_color : source_color;
/**
 * 噪波增强
 * 用于加深水面的深度
 */
uniform float noise_boost : hint_range(0.0, 10) = 0.0;
/**
 * 水面扰动噪波纹理
 */
uniform sampler2D distortion_noise : repeat_enable;
/**
 * 扰动速度
 */
uniform vec2 distortion_speed = vec2(0.1, 0.1);
/**
 * 扰动强度
 */
uniform float distortion_strength : hint_range(0.0, 0.05) = 0.01;

/**
 * 生成水坑噪波
 */
float create_puddle_noise(
    vec2 uv,
    sampler2D cps_puddle_noise,
    float cps_border_margin,
    float cps_border_irregularity
) {
    // 获取原始噪波
    float raw_noise = texture(cps_puddle_noise, uv).r;


    // ------------------------------------------------
    // 计算当前 UV 到 Sprite2D 四条边的最近距离
    // ------------------------------------------------

    // 左右边缘距离
    float edge_x = min(uv.x, 1.0 - uv.x);

    // 上下边缘距离
    float edge_y = min(uv.y, 1.0 - uv.y);

    // 当前像素距离图片最近边缘的距离
    float edge_distance = min(edge_x, edge_y);


    // ------------------------------------------------
    // 让边界宽度产生不规则变化
    // ------------------------------------------------

    // 将噪波从 0~1 转换成 -1~1
    float edge_noise = raw_noise * 2.0 - 1.0;

    // 每个位置拥有不同的边缘宽度
    float irregular_margin =
        cps_border_margin
        + edge_noise * cps_border_irregularity;

    // 防止出现 0 或负数
    irregular_margin = max(irregular_margin, 0.001);


    // ------------------------------------------------
    // 生成边缘遮罩
    // 图片最边缘 = 0
    // 向内部逐渐变成 = 1
    // ------------------------------------------------

    float border_mask = smoothstep(
        0.0,
        irregular_margin,
        edge_distance
    );


    // ------------------------------------------------
    // 修改最终用于生成水坑的噪波
    // ------------------------------------------------

    // 分别保留噪波形状和图片边界的限制。
    // 避免边界衰减再次压低原始噪波，生成额外的大块轮廓区域。
    float noise_value = min(raw_noise, border_mask);


    return noise_value;
}


void fragment() {
    // 获取水坑噪波纹理的像素尺寸
    vec2 noise_size = vec2(textureSize(puddle_noise, 0));

    // 所有形状、边界距离和轮廓计算，共用同一像素网格。
    // 每个格子统一使用对应噪波像素中心的 UV。
    vec2 uv = (floor(UV * noise_size) + vec2(0.5)) / noise_size;

    // 生成积水形状
    float noise_value = create_puddle_noise(
        uv,
        puddle_noise,
        border_margin,
        border_irregularity
    );
    // 通过step生成积水形状
    float shape = step(threshold, noise_value);

	// 采样随时间移动的噪波，范围为 0~1
    float moving_noise = texture(
        puddle_noise,
        uv - TIME * edge_noise_speed
    ).r;

    // 非负偏移量，使轮廓只向水坑内部延伸
    float inward_offset = moving_noise * edge_noise_strength;

    // 提高阈值，得到向内收缩后的水坑主体
    float inner_shape = step(
        threshold + edge_width + inward_offset,
        noise_value
    );

    // 原始水坑减去收缩后的主体，得到内部轮廓
    float edge = clamp(shape - inner_shape, 0.0, 1.0);
    

    // // 配合噪波与TIME计算扰动纹理
    // vec4 distortion_texture = texture(distortion_noise, uv + TIME * distortion_speed);
    //     // 扰动强度控制
    // distortion_texture = distortion_texture * distortion_strength;
    // // 处理后的地面扰动纹理
    // vec3 ground_texture = texture(screen_texture, SCREEN_UV + distortion_texture.xy).rgb;
    
    // 用遮罩权重直接混合
    // 积水主体：不透明黑
    vec4 puddle_col = vec4(0.0, 0.0, 0.0, 1.0);
    // 边缘：不透明白
    vec4 edge_col = vec4(1.0, 1.0, 1.0, 1.0);
    // 透明背景
    vec4 transparent_col = vec4(0.0, 0.0, 0.0, 0.0);

    // 先画积水主体，再覆盖内部轮廓
    vec4 col = mix(transparent_col, puddle_col, shape);
    col = mix(col, edge_col, edge);

    // 使用原始 UV，避免波纹被水坑噪波网格再次像素化。
    vec4 ripple = texture(ripple_texture, UV);

    // 图中的浅色波纹：用波纹透明度控制白色的叠加。
    // shape 是你已有的积水遮罩。
    float ripple_mask = ripple.a * shape;

    col.rgb = mix(col.rgb, vec3(1.0), ripple_mask);


    COLOR = col;


}
