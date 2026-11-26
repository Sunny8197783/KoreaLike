shader_type canvas_item;
render_mode unshaded;
// vfx_last_procession_ghost — 18:20 마지막 행렬(sm_jakdu_last_procession)의 귀환 영가. L08, normal. 소유: vfx (G3 procession).
// 사양: design/13-art-direction.md 4.3 '마지막 행렬 알파 45% + 1px 백 외곽만', 6.5 vfx_last_procession_ghost.
//   몸 = 원래 영가 색 그대로 알파 45%, 검은 외곽선(#1a1a1a)은 지우고 그 자리(밖 1px)를 백 #f2ece0 선으로.
//   하단 2px 알파 페이드, 1박에 1px 위로 떴다 내려오는 부유(정수 픽셀), 촛불처럼 머리 쪽이 살짝 일렁임.
// 사용: 영가 AnimatedSprite2D 에 ShaderMaterial. 시트 셀이면 cell_rect 갱신. 스프라이트에 2px 투명 여백 필요.

uniform vec4 baek : source_color = vec4(0.949, 0.925, 0.878, 1.0);   // #f2ece0
uniform float body_alpha : hint_range(0.0, 1.0) = 0.45;
uniform float outline_alpha : hint_range(0.0, 1.0) = 0.9;
uniform float beat_phase = -1.0;   // 장단 컨덕터 박 위상 0..1 (없으면 bpm 으로)
uniform float bpm = 60.0;
uniform float phase = 0.0;         // 개체별 위상
uniform vec4 cell_rect = vec4(0.0, 0.0, 1.0, 1.0);

varying vec4 v_mod; // modulate (fragment COLOR 엔 텍스처색이 이미 곱해져 있음)

float occ(sampler2D tex, vec2 uv) {
	vec2 lo = cell_rect.xy, hi = cell_rect.xy + cell_rect.zw;
	if (uv.x < lo.x || uv.y < lo.y || uv.x > hi.x || uv.y > hi.y) return 0.0;
	vec4 s = texture(tex, uv);
	// 원래의 검은 외곽선 픽셀은 '몸'으로 치지 않는다 → 백 선이 그 자리에 들어간다
	float is_ink = step(s.a, 0.5) + step(max(max(s.r, s.g), s.b), 0.13);
	return is_ink > 0.0 ? 0.0 : 1.0;
}

void vertex() {
	v_mod = COLOR;
	float ph = beat_phase >= 0.0 ? beat_phase : TIME * bpm / 60.0;
	VERTEX.y -= step(0.5, fract(ph + phase)); // 1박에 1px 떠오름
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, UV);
	float body = occ(TEXTURE, UV);
	float py = floor((cell_rect.y + cell_rect.w - UV.y) / px.y);
	float fade = py < 2.0 ? 0.5 : 1.0;
	if (body > 0.5) {
		COLOR = vec4(c.rgb, body_alpha * fade * v_mod.a);
	} else {
		float n = occ(TEXTURE, UV + vec2(px.x, 0.0)) + occ(TEXTURE, UV - vec2(px.x, 0.0)) + occ(TEXTURE, UV + vec2(0.0, px.y)) + occ(TEXTURE, UV - vec2(0.0, px.y));
		if (n > 0.0) {
			// 머리 쪽(셀 위 40%) 외곽선은 촛불처럼 1프레임씩 일렁임
			float v = (UV.y - cell_rect.y) / max(cell_rect.w, 1e-5);
			float flick = v < 0.4 ? step(0.25, fract(sin(dot(floor(UV / px), vec2(12.9898, 78.233)) + floor(TIME * 8.0)) * 43758.5453)) : 1.0;
			COLOR = vec4(baek.rgb, outline_alpha * fade * mix(0.55, 1.0, flick) * v_mod.a);
		} else {
			COLOR = vec4(0.0);
		}
	}
}
