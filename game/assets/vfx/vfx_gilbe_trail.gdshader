shader_type canvas_item;
render_mode unshaded;
// vfx_gilbe_trail — 길베(영가 행렬 뒤로 깔리는 흰 무명 리본, 6px). L04, 자체 발광, normal. 소유: vfx (G3 procession).
// 사양: design/13-art-direction.md 6.5 — 메시 리본, 알파 0.70↔1.00 박 맥동, 영가 0명이면 50%(캐논 '희미하게'),
//   4초 끝부분 1초 동안 페이드. 재질 패턴 = 무명 결(가로 2px 간격 줄). 기색 테(정지)와 달리 길베는 '맥동'으로 구분.
// 사용(Line2D 권장):
//   width = 6, texture = 1x1 흰 텍스처(또는 아무 텍스처), texture_mode = LINE_TEXTURE_STRETCH,
//   joint_mode = ROUND, antialiased = false. points[0] = 꼬리(가장 오래된 점), 마지막 점 = 머리(행렬 끝).
//   매 프레임 코드에서: length_px = 선 전체 길이(px), beat_phase = 지금 박 진행 0..1(장단 컨덕터),
//   yeongga_count = 행렬 영가 수. (beat_phase 를 안 넘기면 bpm 으로 TIME 에서 계산)
//   UV.x: 0 = 꼬리 → 1 = 머리, UV.y: 리본 폭 0..1.

uniform vec4 baek : source_color = vec4(0.949, 0.925, 0.878, 1.0);   // #f2ece0
uniform vec4 baek_shade : source_color = vec4(0.839, 0.812, 0.757, 1.0); // #d6cfc1
uniform vec4 flash_core : source_color = vec4(1.0, 0.992, 0.965, 1.0);   // #fffdf6 (박 펄스 머리만)
uniform float length_px = 256.0;
uniform float width_px = 6.0;
uniform float beat_phase = -1.0;     // < 0 이면 bpm 으로 계산
uniform float bpm = 90.0;
uniform int yeongga_count = 1;
uniform float tail_fade_frac : hint_range(0.0, 1.0) = 0.25; // 4초 중 끝 1초
uniform float scroll_px_per_sec = 12.0; // 무명 올 마디가 머리→꼬리로 흘러감(행렬이 앞으로 가는 느낌)

void fragment() {
	float ph = beat_phase >= 0.0 ? fract(beat_phase) : fract(TIME * bpm / 60.0);
	// 픽셀 격자로 스냅
	float x = floor(UV.x * length_px);
	float y = floor(clamp(UV.y, 0.0, 0.999) * width_px);
	// 무명 결: 가로 줄 2px 간격, 가장자리 1px 는 그늘
	vec3 col = mod(y, 2.0) < 1.0 ? baek.rgb : baek_shade.rgb;
	if (y < 0.5 || y > width_px - 1.5) col = baek_shade.rgb;
	// 올 마디(slub): 17px 마다 1px 밝은 매듭이 꼬리 쪽으로 흐름
	float s = mod(x + floor(TIME * scroll_px_per_sec), 17.0);
	if (s < 1.0 && y > 0.5 && y < width_px - 1.5) col = baek.rgb;
	// 박 맥동: 박 머리에 1.00 → 다음 박 직전 0.70 (빠르게 차고 천천히 빠짐)
	float pulse = pow(1.0 - ph, 3.0);
	float a = mix(0.70, 1.00, pulse);
	// 박 펄스 물결: 박마다 밝은 띠 하나가 머리에서 꼬리로 달려감(첫 1/3 박)
	float wave_pos = 1.0 - ph * 3.0;
	if (ph < 0.34 && abs(UV.x - wave_pos) * length_px < 2.0) col = ph < 0.08 && UV.x > 0.9 ? flash_core.rgb : baek.rgb;
	if (yeongga_count <= 0) a *= 0.5;
	// 꼬리 페이드: 4단 계단(픽셀아트) — 디더 없이
	float tf = tail_fade_frac > 0.0 ? clamp(UV.x / tail_fade_frac, 0.0, 1.0) : 1.0;
	tf = floor(tf * 4.0 + 0.999) / 4.0;
	a *= tf;
	// 끝 꼬리 1px 는 실 한 가닥(가운데 2줄만)
	if (x < 3.0 && (y < 2.0 || y > width_px - 3.0)) a = 0.0;
	COLOR = vec4(col, a * COLOR.a);
}
