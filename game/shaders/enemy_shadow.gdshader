shader_type canvas_item;
// 발밑 픽셀 타원 그림자(MultiMesh 1개로 전 적). GAME_FEEL 2.3. 소유: vfx.
// 메시 quad 는 (−quad/2) ~ (quad/2), 발 원점 = quad 중심(행 0 = 발끝 행). INSTANCE_CUSTOM.x = 폭 px(짝수), .y = 높이 px.
// 색 = 먹 #0e0b16 불투명 픽셀, 반투명은 COLOR(modulate) 로만(ART_STYLE 3.3 블렌드 예외 — GAME_FEEL 10장 결정 ①).

uniform vec2 quad = vec2(64.0, 12.0);
uniform vec4 meok : source_color = vec4(0.0549, 0.0431, 0.0863, 1.0);

varying vec2 v_wh;
varying vec4 v_mod;

void vertex() {
	v_wh = INSTANCE_CUSTOM.xy;
	v_mod = COLOR;
}

void fragment() {
	vec2 lp = floor(UV * quad) - floor(quad * 0.5);
	float w = floor(v_wh.x + 0.5);
	float h = floor(v_wh.y + 0.5);
	if (w < 2.0 || h < 1.0) {
		discard;
	}
	float cy = mod(h, 2.0) > 0.5 ? 0.5 : 0.0;
	float dx = (lp.x + 0.5) / (w * 0.5);
	float dy = (lp.y + 0.5 - cy) / (h * 0.5);
	if (dx * dx + dy * dy > 1.0) {
		discard;
	}
	COLOR = vec4(meok.rgb, 1.0) * v_mod;
}
