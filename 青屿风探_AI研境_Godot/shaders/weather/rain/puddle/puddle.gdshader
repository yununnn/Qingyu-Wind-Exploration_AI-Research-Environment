shader_type canvas_item;

/**
 * 积水形状
 */
group_uniforms PuddleShape;
/**
 * 积水形状纹理
 * 使用噪波纹理来生成积水的形状。
 */
uniform sampler2D puddle_noise : repeat_disable, filter_nearest;
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


void fragment() {
    // uv坐标
    vec2 uv = UV;

    // 获取噪波值
    // float noise_value = texture(puddle_noise, uv).r;
    // 获取原始噪波
    float raw_noise = texture(puddle_noise, uv).r;


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
        border_margin
        + edge_noise * border_irregularity;

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

    float noise_value = raw_noise * border_mask;
    
    // 通过step生成积水形状
    float shape = step(threshold, noise_value);
    // 内切一层轮廓，此为边缘
    float edge = step(threshold - edge_width, noise_value);
    
    // 配合噪波与TIME计算扰动纹理
    vec4 distortion_texture = texture(distortion_noise, uv + TIME * distortion_speed);
        // 扰动强度控制
    distortion_texture = distortion_texture * distortion_strength;
    // 处理后的地面扰动纹理
    vec3 ground_texture = texture(screen_texture, SCREEN_UV + distortion_texture.xy).rgb;
    
    float edge_uv = uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y) * 100.0;

    // 积水纹理
    if (shape == 1.0) {
        COLOR = vec4(ground_texture + puddle_color.rgb, 1.0);
    } 
    // 边缘纹理
    else if (edge == 1.0) {
        COLOR = vec4(1, 1, 1, puddle_color.a);
    }
    // 其他区域透明
    else {
        COLOR = vec4(0, 0, 0, 0);
    }


}
