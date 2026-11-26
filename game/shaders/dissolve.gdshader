shader_type canvas_item;
// 디졸브. mode 0 = 해원(수직, 아래→위, 백 가장자리), mode 1 = 퇴치(방사형 파열, 적 가장자리). 소유: vfx.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform int mode = 0;
uniform vec4 edge_haewon : source_color = vec4(0.949, 0.925, 0.878, 1.0);
uniform vec4 edge_toechi : source_color = vec4(0.784, 0.196, 0.176, 1.0);
uniform float edge_width = 0.08;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 cell = floor(UV / TEXTURE_PIXEL_SIZE);
	float n = hash21(cell) * 0.15;
	float v;
	vec4 edge;
	if (mode == 0) {
		v = (1.0 - UV.y) + n;          // 아래(1)부터 먼저 사라진다
		edge = edge_haewon;
	} else {
		v = 1.0 - length(UV - vec2(0.5)) * 1.6 + n;  // 바깥부터 깨진다
		edge = edge_toechi;
	}
	float cut = progress * 1.2;
	if (v < cut - edge_width) {
		discard;
	} else if (v < cut && c.a > 0.0) {
		c.rgb = edge.rgb;
	}
	COLOR = c * COLOR;
}
