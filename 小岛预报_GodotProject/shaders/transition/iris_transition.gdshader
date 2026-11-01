shader_type canvas_item;
render_mode unshaded;

// 读取当前屏幕已经绘制的场景
uniform sampler2D screen_texture
    : hint_screen_texture, repeat_disable, filter_nearest;

// 圆形中心，采用屏幕归一化坐标
uniform vec2 center = vec2(0.5, 0.5);

// 遮罩颜色，默认为纯黑
uniform vec4 mask_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// 0：完整显示场景
// 1：完全显示遮罩颜色
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// 圆形边缘柔化宽度，单位为屏幕像素
uniform float edge_softness_px
    : hint_range(0.0, 16.0) = 1.5;


void fragment() {
    // 进度达到 1 时，整个画面显示遮罩颜色
    if (progress >= 1.0) {
        COLOR = vec4(mask_color.rgb, 1.0);
    } else {
        // 将 UV 坐标差转换为屏幕像素距离，保持圆形不变形
        vec2 delta_px =
            (SCREEN_UV - center) / SCREEN_PIXEL_SIZE;

        float distance_px = length(delta_px);

        // 计算中心到屏幕最远角落的距离
        vec2 farthest_uv = max(
            center,
            vec2(1.0) - center
        );

        float max_radius = length(
            farthest_uv / SCREEN_PIXEL_SIZE
        );

        // 避免 smoothstep 的边界区间为零
        float feather = max(edge_softness_px, 0.001);

        // progress 越大，圆形窗口越小
        float radius =
            max_radius * (1.0 - progress)
            + feather * 0.5;

        // 圆内为 1，圆外逐渐过渡为 0
        float mask = 1.0 - smoothstep(
            radius - feather * 0.5,
            radius + feather * 0.5,
            distance_px
        );

        // 获取当前场景颜色
        vec3 scene_color = textureLod(
            screen_texture,
            SCREEN_UV,
            0.0
        ).rgb;

        // 圆内显示场景，圆外显示自定义遮罩颜色
        vec3 final_color = mix(
            mask_color.rgb,
            scene_color,
            mask
        );

        COLOR = vec4(final_color, 1.0);
    }
}