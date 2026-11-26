shader_type canvas_item;
// 보스 붉은 달(월드 층, 카메라 고정). 소유: vfx. 구동: vfx/red_moon.gd.
// 2026-11-24 리뷰 vfx#12: 후처리에서 화면 픽셀을 덮어쓰던 달을 지면(z −10) 위·소품(−6)·행위자(0~3) 아래(z −8)로 옮겼다.
// 적·적탄·예고는 달 위에 그려진다(가리지 않음). 크레이터는 가로 막대 대신 불규칙한 얼룩 3개(jk 램프), 구름 띠 없음.
// 반투명 없음: 떠오름은 4×4 Bayer 디더 문턱(reveal), 헤일로도 디더 점.
uniform float reveal = 0.0;        // 0..1
uniform float beat_pulse = 0.0;    // 박 머리 계단 0..1(헤일로 맥동)
uniform float tex_px = 96.0;       // 스프라이트 한 변(px)
uniform float moon_r = 22.0;

const vec3 JK_HI = vec3(0.894, 0.376, 0.310);   // #e4604f
const vec3 JK = vec3(0.784, 0.196, 0.176);      // #c8322d
const vec3 JK_DK = vec3(0.549, 0.122, 0.133);   // #8c1f22
const vec3 JK_DKK = vec3(0.337, 0.075, 0.094);  // #561318

float bayer4(vec2 p) {
	vec2 q = mod(floor(p), 4.0);
	float i = q.x + q.y * 4.0;
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

// 불규칙한 크레이터: 중심 c, 반경 rc, 가장자리 1px 들쭉날쭉(정수 격자 해시)
float crater(vec2 lp, vec2 c, float rc) {
	vec2 d = lp - c;
	float wob = (hash12(floor(lp) + c * 3.1) - 0.5) * 1.6;
	return length(d * vec2(1.0, 1.25)) < rc + wob ? 1.0 : 0.0;
}

void fragment() {
	vec2 px = floor(UV * tex_px);
	vec2 lp = px - vec2(tex_px * 0.5) + 0.5;
	float th = bayer4(px);
	if (th >= reveal) {
		discard;
	}
	float r = length(lp);
	vec3 c;
	if (r > moon_r) {
		float halo = clamp(1.0 - (r - moon_r) / (moon_r * (1.0 + 0.25 * beat_pulse)), 0.0, 1.0);
		float h2 = halo * halo;
		if (h2 * 0.75 <= th) {
			discard;
		}
		c = h2 > 0.45 ? JK_DK : JK_DKK;
	} else {
		c = JK;
		float lim = dot(normalize(lp + vec2(0.001)), normalize(vec2(-1.0, -1.0))) * (r / moon_r);
		if (lim > 0.62 + (th - 0.5) * 0.2) {
			c = JK_HI;
		} else if (lim < -0.45 + (th - 0.5) * 0.3) {
			c = JK_DK;
		}
		// 얼룩 3개(바다 자리): 어두운 면 #8c1f22, 왼쪽 위 빛을 받는 아래·오른쪽 안벽 1px #e4604f
		float k = max(crater(lp, vec2(-5.0, 4.0), 6.5), max(crater(lp, vec2(8.0, -4.0), 3.0), crater(lp, vec2(1.0, -9.0), 2.0)));
		if (k > 0.5 && r < moon_r - 2.0) {
			float k2 = max(crater(lp + vec2(1.0, 1.0), vec2(-5.0, 4.0), 6.5),
				max(crater(lp + vec2(1.0, 1.0), vec2(8.0, -4.0), 3.0), crater(lp + vec2(1.0, 1.0), vec2(1.0, -9.0), 2.0)));
			c = k2 > 0.5 ? JK_DK : JK_HI;
		}
		if (r > moon_r - 1.0) {
			c = JK_DKK;                               // 1px 먹빛 가장자리(지면과 분리)
		}
	}
	COLOR = vec4(c, 1.0);
}
