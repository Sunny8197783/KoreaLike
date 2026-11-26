shader_type canvas_item;
// 신칼 술 리본(vfx_sinkal_tassel_trail). Line2D 전용: texture = assets/vfx/vfx_sinkal_tassel_trail.png,
// texture_mode = LINE_TEXTURE_TILE, texture_filter = NEAREST, width 6, width_curve 1 -> 0.3 (머리 -> 꼬리),
// gradient: 머리 알파 1 -> 꼬리 알파 0 (Line2D 는 첫 점이 머리). 픽셀 단위로 펄럭이고, 꼬리 알파는 4x4 Bayer 디더로
// 끊어져 한지 조각처럼 사라진다(반투명 금지 — 화면에 수백 개가 겹쳐도 또렷하게). 백 #f2ece0 사용 금지: 텍스처 색 그대로.
// 소유: vfx (G1 red mugu strike).

uniform float flutter_amp : hint_range(0.0, 3.0) = 1.0;   // 텍스처 픽셀 단위 상하 흔들림
uniform float flutter_speed : hint_range(0.0, 20.0) = 9.0;
uniform float tex_px_height = 6.0;                        // 텍스처 높이(px) — 흔들림을 픽셀에 스냅
uniform float tail_tear : hint_range(0.0, 1.0) = 0.35;    // 꼬리 쪽 가장자리를 갉아먹는 정도

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	// UV.x tiles along the line; flutter is a travelling wave snapped to whole texture pixels
	float wave = sin(UV.x * 6.2831 * 0.5 - TIME * flutter_speed) * flutter_amp;
	float dy = floor(wave + 0.5) / tex_px_height;
	vec2 uv = vec2(UV.x, clamp(UV.y + dy, 0.0, 1.0));
	vec4 c = texture(TEXTURE, uv);
	float a = c.a * COLOR.a;
	// tear the ribbon edges as it fades (COLOR.a comes from the Line2D gradient)
	float edge = abs(UV.y - 0.5) * 2.0;
	if (edge > 1.0 - (1.0 - COLOR.a) * tail_tear * 2.0) a = 0.0;
	// crisp dithered alpha: no translucency
	a = a > bayer4(FRAGCOORD.xy) ? 1.0 : 0.0;
	COLOR = vec4(c.rgb * COLOR.rgb, a);
}
