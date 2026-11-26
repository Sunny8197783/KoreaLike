shader_type canvas_item;
// 오컬트 후처리(화면 전체, PostLayer ColorRect). 소유: vfx. 구동: vfx/screen_fx.gd.
// 640×360 게임 픽셀 격자에서 계산한다(뷰포트 스트레치 = viewport). 모든 경계는 4×4 Bayer 디더로 계단을 낸다(부드러운 그라데이션 금지 — 픽셀 톤).
//  1 저채도        desaturate (파일럿 값 0.08 유지, 살기 문턱 뒤에만 상승)
//  2 촛불 조명     밝기 = max(ambient, Σ 광원 강도 × (1 − (d/반경)²)) (design/08 §4.1). 어둠은 먹-청으로 눌러 주고 난색 광원은 데운다.
//                  lights[i] = (화면 px x, y, 반경 px, 강도), light_tone[i] = 0 난색(촛불) / 1 백(해원·영가) / 2 황(신명)
//                  깜빡임(반경·강도 10Hz 계단)은 스크립트가 값에 실어 보낸다.
//  3 거리 색조     tint (거리마다 다른 밤 색)
//  4 먹 비네트     vignette + 신령 시련색 aura_col×aura + 보스 붉은 달 red_moon + 신명 색동 saekdong(가장자리 오방 줄무늬)
//  5 한지 그레인   종이 섬유결(가로 결 + 점) — 6fps 로만 흔들린다
//  6 붉은 달       red_moon 은 비네트 적빛만(원반은 월드 층 vfx/red_moon.gd)
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float vignette = 0.5;
uniform float grain = 0.035;
uniform float desaturate = 0.08;
uniform vec4 meok : source_color = vec4(0.055, 0.043, 0.086, 1.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float ambient = 1.0;                 // 0..1 (1 = 어둠 없음)
uniform float dark_strength = 0.5;           // 어둠이 화면을 누르는 정도(가독성 하한: 0.5 → 가장 어두운 곳도 약 0.6배)
uniform vec4 dark_col : source_color = vec4(0.42, 0.46, 0.70, 1.0);   // 어둠 곱 색(먹-청)
uniform vec4 warm_col : source_color = vec4(1.0, 0.70, 0.35, 1.0);    // 촛불 #ffb35a
uniform vec4 cool_col : source_color = vec4(0.949, 0.925, 0.878, 1.0); // 백 #f2ece0 (해원 빛)
uniform vec4 gold_col : source_color = vec4(0.91, 0.725, 0.19, 1.0);  // 황 #e8b931 (신명)
uniform int light_count = 0;
uniform vec4 lights[24];
uniform float light_tone[24];

uniform vec4 aura_col : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float aura = 0.0;                    // 신령 시련 중 0..1
uniform float saekdong = 0.0;                // 신명 오름 0..1
uniform float red_moon = 0.0;                // 보스 0..1
uniform vec2 moon_px = vec2(548.0, 40.0);    // 달 중심(화면 px)
uniform float moon_r = 22.0;
uniform float beat_pulse = 0.0;              // 박 머리 0..1 (색동·달 헤일로 맥동)
uniform float fx_time = 0.0;                 // 실시간 초(스크립트 공급 — TIME 은 편집기·일시정지와 어긋난다)

const vec3 SD0 = vec3(0.784, 0.196, 0.176);  // 적 #c8322d
const vec3 SD1 = vec3(0.961, 0.839, 0.420);  // 황 #f5d66b
const vec3 SD2 = vec3(0.333, 0.722, 0.667);  // 청록 #55b8aa
const vec3 SD3 = vec3(0.373, 0.576, 0.871);  // 청 #5f93de
const vec3 SD4 = vec3(0.914, 0.863, 0.753);  // 한지 #e9dcc0 (색동의 흰 줄 — 예약 백 대신)

float bayer4(vec2 p) {
	vec2 q = mod(floor(p), 4.0);
	float i = q.x + q.y * 4.0;
	// 4×4 Bayer (0..15)/16
	float v = 0.0;
	if (i < 0.5) v = 0.0; else if (i < 1.5) v = 8.0; else if (i < 2.5) v = 2.0; else if (i < 3.5) v = 10.0;
	else if (i < 4.5) v = 12.0; else if (i < 5.5) v = 4.0; else if (i < 6.5) v = 14.0; else if (i < 7.5) v = 6.0;
	else if (i < 8.5) v = 3.0; else if (i < 9.5) v = 11.0; else if (i < 10.5) v = 1.0; else if (i < 11.5) v = 9.0;
	else if (i < 12.5) v = 15.0; else if (i < 13.5) v = 7.0; else if (i < 14.5) v = 13.0; else v = 5.0;
	return (v + 0.5) / 16.0;
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// 값 v(0..1)를 n 단계로 양자화(디더 문턱).
float band(float v, float n, float th) {
	return clamp(floor(v * n + th) / n, 0.0, 1.0);
}

vec3 saek(float k) {
	float i = mod(floor(k), 5.0);
	if (i < 0.5) return SD0;
	if (i < 1.5) return SD1;
	if (i < 2.5) return SD2;
	if (i < 3.5) return SD3;
	return SD4;
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = floor(SCREEN_UV * res);              // 왼쪽 위 원점 게임 픽셀(FRAGCOORD 는 렌더러마다 y 방향이 달라 쓰지 않는다)
	float th = bayer4(px);
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;

	// 1 저채도
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desaturate);

	// 2 촛불 조명
	float lit = 0.0;
	vec3 glow = vec3(0.0);
	for (int i = 0; i < light_count; i++) {
		vec4 L = lights[i];
		vec2 dv = px - L.xy;
		dv.y *= 1.25;                              // 지면 원근: 빛 웅덩이는 가로로 긴 타원
		float q = dot(dv, dv) / (L.z * L.z);
		if (q < 1.0) {
			float k = L.w * (1.0 - q);
			lit += k;
			float tn = light_tone[i];
			vec3 lc = tn < 0.5 ? warm_col.rgb : (tn < 1.5 ? cool_col.rgb : gold_col.rgb);
			glow += lc * k;
		}
	}
	float bright = clamp(max(ambient, lit), 0.0, 1.0);
	float bq = band(bright, 6.0, th);              // 6단 계단 + 디더 = 픽셀 톤 빛 웅덩이
	vec3 shade = mix(vec3(1.0), dark_col.rgb, dark_strength);
	c *= mix(shade, vec3(1.0), bq);
	float gq = band(clamp(lit, 0.0, 1.0), 5.0, th);
	vec3 gcol = glow / max(lit, 0.001);
	c += c * gcol * gq * 0.22;                     // 광원 색으로 살짝 데운다(곱 가산 — 어두운 곳을 띄우지 않는다)

	// 3 거리 색조
	c *= tint.rgb;

	// 4 먹 비네트(+ 시련 신령색, 붉은 달, 색동)
	vec2 d = SCREEN_UV - vec2(0.5);
	d.x *= 1.6;
	float vig = smoothstep(0.35, 0.95, length(d));
	float vq = band(vig, 7.0, th);
	vec3 vcol = meok.rgb;
	vcol = mix(vcol, aura_col.rgb * 0.30, aura * 0.75);
	vcol = mix(vcol, vec3(0.337, 0.075, 0.094), red_moon * 0.8);     // 적 가장 어둠 #561318
	c = mix(c, vcol, vq * vignette);
	if (aura > 0.001) {
		float rim = band(smoothstep(0.30, 0.55, vig) * (1.0 - smoothstep(0.55, 0.95, vig)), 3.0, th);
		c += aura_col.rgb * rim * aura * 0.07;      // 시련: 가장자리 안쪽에 신령색 테
	}
	if (saekdong > 0.001) {
		// 색동: 가장자리에서 안쪽으로 6px 폭 5색 줄무늬(대각 45°), 박마다 한 칸씩 밀린다.
		float edge = min(min(px.x, res.x - 1.0 - px.x), min(px.y, res.y - 1.0 - px.y));
		float reach = 10.0 + 6.0 * beat_pulse;
		float e = clamp(1.0 - edge / reach, 0.0, 1.0);
		float eq = band(e, 4.0, th);
		float stripe = floor((px.x + px.y) / 6.0 + floor(fx_time * 2.0));
		c = mix(c, saek(stripe), eq * saekdong * 0.62);
		c *= mix(vec3(1.0), vec3(1.06, 1.0, 0.90), saekdong);
	}

	// 5 한지 그레인: 가로 섬유결(길이 3~9px) + 낱알
	float ft = floor(fx_time * 6.0);
	float row = px.y + ft * 7.0;
	float seg = floor((px.x + hash12(vec2(row, 3.0)) * 40.0) / (3.0 + floor(hash12(vec2(row, 9.0)) * 7.0)));
	float fibre = hash12(vec2(seg, row));
	float speck = hash12(px + ft * 13.0);
	c += ((fibre - 0.5) * 0.7 + (speck - 0.5) * 0.6) * grain;

	// 6 붉은 달: 원반·헤일로는 월드 층(shaders/red_moon.gdshader, z −8)으로 옮겼다(2026-11-24 — 후처리 원반이 적·적탄을 덮었다).
	//   여기서는 비네트 적빛(위 4)만 red_moon 을 쓴다.
	COLOR = vec4(c, 1.0);
}
