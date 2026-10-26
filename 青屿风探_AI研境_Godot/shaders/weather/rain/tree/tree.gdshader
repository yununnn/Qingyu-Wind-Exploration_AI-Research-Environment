shader_type canvas_item;

// 裁剪后单棵树的高度，不是整张精灵图的高度。
uniform float tree_height : hint_range(1.0, 1024.0, 1.0) = 128.0;

// 树根在 Sprite2D 本地坐标中的 Y。
// Centered 开启、Offset 为 0 时，通常填 tree_height / 2。
uniform float root_y = 64.0;

// 树顶向右偏移的最大距离，单位为本地像素。
uniform float right_bend : hint_range(0.0, 100.0, 0.5) = 18.0;

// 回弹幅度占最大偏移的比例。
uniform float rebound_ratio : hint_range(0.0, 0.5, 0.01) = 0.15;

// 一个循环的时长，单位为秒。
uniform float cycle_seconds : hint_range(0.2, 5.0, 0.05) = 1.4;

// 风力强度：0 = 完全不动，1 = 全幅摆动。风起时由脚本渐变到这个值。
uniform float wind_strength : hint_range(0.0, 1.0) = 0.0;

// 每棵树独立的水深，单位为素材局部像素。
instance uniform float submerge_depth = 0.0;
// x：局部振幅；y：世界空间频率；z：共享时间相位；w：水域范围遮罩。
instance uniform vec4 water_wave = vec4(0.0);
varying vec2 water_world_position;
// 当前裁剪区域在整张图集中的归一化矩形。
instance uniform vec4 atlas_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

// 横向折射最大偏移，单位为素材像素。
uniform float refraction_pixels = 1.0;
// 接触水线宽度，单位为素材像素。
uniform float waterline_width = 1.0;
uniform vec4 waterline_color : source_color = vec4(0.72, 0.79, 0.67, 1.0);
uniform vec4 underwater_color : source_color = vec4(0.42, 0.60, 0.62, 1.0);
uniform float underwater_tint = 0.16;

varying float height_above_root;
varying vec4 sprite_tint;

void vertex() {
	height_above_root = root_y - VERTEX.y;
	sprite_tint = COLOR;
	// 开始时从直立状态逐渐向右倾斜。
	float initial_push = smoothstep(0.0, cycle_seconds, TIME);

	float phase = fract(
		max(TIME - cycle_seconds, 0.0) / cycle_seconds
	);

	// 短时间轻微回弹，然后用更长时间继续向右摆。
	float rebound;
	if (phase < 0.22) {
		rebound = smoothstep(0.0, 0.22, phase);
	} else {
		rebound = 1.0 - smoothstep(0.22, 1.0, phase);
	}

	float displacement = right_bend
		* (1.0 - rebound_ratio * rebound)
		* initial_push
		* wind_strength;

	// 树根处位移为零，越靠上，向右偏移越大。
	float height_weight = (root_y - VERTEX.y) / tree_height;
	VERTEX.x += displacement * height_weight;
	water_world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    // 水位按素材像素取整，形成清晰的像素水线。
    float wave = sin(water_world_position.x * water_wave.y + water_wave.z) * water_wave.x;
    float depth = floor(submerge_depth + wave + 0.5);
    vec2 sample_uv = UV;
    float below_line = depth - height_above_root;
    bool submerged = water_wave.w > 0.5 && depth > 0.0 && below_line >= 0.0;

    if (submerged && below_line >= waterline_width) {
        // 每三行共享一个偏移量，形成分段的横向折射。
        float row = floor(below_line / 3.0);
        float shift = round(sin(row * 0.8 + TIME * 1.8) * refraction_pixels);
        sample_uv.x += shift * TEXTURE_PIXEL_SIZE.x;
    }

    // 偏移超出当前图集区域时透明，禁止采到相邻素材。
    if (any(lessThan(sample_uv, atlas_uv_rect.xy)) ||
        any(greaterThanEqual(sample_uv, atlas_uv_rect.xy + atlas_uv_rect.zw))) {
        COLOR = vec4(0.0);
    } else {
        vec2 pixel = TEXTURE_PIXEL_SIZE;
        sample_uv = clamp(sample_uv,
            atlas_uv_rect.xy + pixel * 0.5,
            atlas_uv_rect.xy + atlas_uv_rect.zw - pixel * 0.5);
        vec4 color = texture(TEXTURE, sample_uv) * sprite_tint;
        if (submerged) {
            color.rgb = mix(color.rgb, underwater_color.rgb, underwater_tint);
            // 水线只画在实际不透明的树图上，不填满 Sprite 的矩形。
            if (below_line < waterline_width) {
                color.rgb = mix(color.rgb, waterline_color.rgb * sprite_tint.rgb, 0.55);
            }
        }
        // 保留水下部分的透明度和轮廓，不再按水深裁掉树干。
        COLOR = color;
    }
}

