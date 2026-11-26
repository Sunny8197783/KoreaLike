shader_type canvas_item;
render_mode unshaded;
// vfx_pullil_outline — 풀릴 기색 '기색 테' (L11 재출력, 자체 발광, normal). 소유: vfx (G3 judgement).
// 사양: design/13-art-direction.md 2.4 / 2.10.8, data/art_palette.json accessibility_overrides.pullil_outline
//   안 → 밖: 흑 1px #1a1a1a(스프라이트 자체 외곽선 복제) + 백 1px #f2ece0 + 먹 녹아웃 1px #0e0b16 알파 60%.
//   고대비 모드(high_contrast): 백 2px. 지속 중 '맥동 없음'(100%) — 길베는 맥동, 기색 테는 정지(캐논 G11).
//   잔여 3초: blink = 1 → 4Hz 100%↔40% 깜빡임. 미세 흔들림 x ±1px 10Hz(정수 픽셀).
// 사용:
//   Sprite2D/AnimatedSprite2D 에 ShaderMaterial 로 건다. 스프라이트에는 사방 2px(고대비 3px) 투명 여백이 필요(13장 1.3).
//   아틀라스/스프라이트시트 셀이면 cell_rect 에 현재 프레임의 UV 사각형(x, y, w, h)을 넣어 이웃 셀 번짐을 막는다.
//   overlay_only = true: L11 재출력 패스(같은 텍스처를 L11 CanvasLayer 에 한 번 더 그림) — 몸통 내부는 버리고
//   흑 외곽선·백·먹 3겹만 남겨 L10 플레이어 VFX 위에 기색 테를 다시 올린다. false: 몸통 + 테를 한 번에.
//   접근성 opt_pullil_outline_color: baek 를 #f2ece0 / #ffd84a / #4ff0ff 중 하나로 교체.
//   잡귀 MultiMesh 는 res://shaders/enemy_instanced.gdshader 비트 1 이 같은 규칙을 따르도록 이 파일의 ring() 을 이식할 것.

uniform bool enabled = true;
uniform bool overlay_only = false;
uniform bool high_contrast = false;
uniform float blink : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ink_line : source_color = vec4(0.102, 0.102, 0.102, 1.0);   // #1a1a1a 오방 흑
uniform vec4 baek : source_color = vec4(0.949, 0.925, 0.878, 1.0);       // #f2ece0 예약 백
uniform vec4 knockout : source_color = vec4(0.055, 0.043, 0.086, 1.0);   // #0e0b16 먹
uniform float knockout_alpha : hint_range(0.0, 1.0) = 0.6;
uniform vec4 cell_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float wobble_px = 1.0;
uniform float wobble_hz = 10.0;
uniform float phase = 0.0; // 개체별 위상(동시에 300개가 같은 박자로 흔들리지 않게)

// Godot 4 의 fragment COLOR 는 이미 텍스처색이 곱해져 있어서, modulate 는 vertex 에서 따로 받아 둔다
varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
	if (enabled && wobble_px > 0.0) {
		// 정수 픽셀 흔들림: -1, 0, +1 px
		VERTEX.x += floor(sin((TIME * wobble_hz + phase) * 6.2831853) * 1.4 + 0.5) * wobble_px;
	}
}

float occ(sampler2D tex, vec2 uv) {
	vec2 lo = cell_rect.xy, hi = cell_rect.xy + cell_rect.zw;
	if (uv.x < lo.x || uv.y < lo.y || uv.x > hi.x || uv.y > hi.y) return 0.0;
	return step(0.5, texture(tex, uv).a);
}

// 가장 가까운 불투명 픽셀까지의 맨해튼 거리(1..3), 없으면 9
float ring(sampler2D tex, vec2 uv, vec2 px) {
	if (occ(tex, uv + vec2(px.x, 0.0)) + occ(tex, uv - vec2(px.x, 0.0)) + occ(tex, uv + vec2(0.0, px.y)) + occ(tex, uv - vec2(0.0, px.y)) > 0.0) return 1.0;
	float d2 = occ(tex, uv + vec2(2.0 * px.x, 0.0)) + occ(tex, uv - vec2(2.0 * px.x, 0.0)) + occ(tex, uv + vec2(0.0, 2.0 * px.y)) + occ(tex, uv - vec2(0.0, 2.0 * px.y))
		+ occ(tex, uv + px) + occ(tex, uv - px) + occ(tex, uv + vec2(px.x, -px.y)) + occ(tex, uv + vec2(-px.x, px.y));
	if (d2 > 0.0) return 2.0;
	float d3 = occ(tex, uv + vec2(3.0 * px.x, 0.0)) + occ(tex, uv - vec2(3.0 * px.x, 0.0)) + occ(tex, uv + vec2(0.0, 3.0 * px.y)) + occ(tex, uv - vec2(0.0, 3.0 * px.y))
		+ occ(tex, uv + vec2(2.0 * px.x, px.y)) + occ(tex, uv + vec2(2.0 * px.x, -px.y)) + occ(tex, uv + vec2(-2.0 * px.x, px.y)) + occ(tex, uv + vec2(-2.0 * px.x, -px.y))
		+ occ(tex, uv + vec2(px.x, 2.0 * px.y)) + occ(tex, uv + vec2(-px.x, 2.0 * px.y)) + occ(tex, uv + vec2(px.x, -2.0 * px.y)) + occ(tex, uv + vec2(-px.x, -2.0 * px.y));
	if (d3 > 0.0) return 3.0;
	return 9.0;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (!enabled) {
		COLOR = c * v_mod;
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float k = blink > 0.5 ? mix(1.0, 0.4, step(0.5, fract(TIME * 4.0))) : 1.0;
		vec4 outc = vec4(0.0);
		if (c.a >= 0.5) {
			// 몸통 픽셀: 가장자리(이웃이 비어 있음)면 흑 외곽선 복제, 내부면 몸통(overlay 에선 버림)
			float edge = 4.0 - (occ(TEXTURE, UV + vec2(px.x, 0.0)) + occ(TEXTURE, UV - vec2(px.x, 0.0)) + occ(TEXTURE, UV + vec2(0.0, px.y)) + occ(TEXTURE, UV - vec2(0.0, px.y)));
			if (edge > 0.0) outc = ink_line;
			else outc = overlay_only ? vec4(0.0) : c * v_mod;
		} else {
			float d = ring(TEXTURE, UV, px);
			float white_px = high_contrast ? 2.0 : 1.0;
			if (d <= white_px) outc = vec4(baek.rgb, baek.a * k);
			else if (d <= white_px + 1.0) outc = vec4(knockout.rgb, knockout_alpha * k);
		}
		// 바깥 테는 modulate 알파(페이드)만 따르고 색은 예약색 그대로
		if (c.a < 0.5) outc.a *= v_mod.a;
		COLOR = outc;
	}
}
