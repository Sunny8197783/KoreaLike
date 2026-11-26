shader_type canvas_item;
// 잡귀 군중 MultiMesh 셰이더 — 소유: enemies. shaders/enemy_instanced.gdshader(vfx) 의 인스턴스 계약을 그대로 쓰고
// enemies 전용 표현(풀릴 기색 백1px+먹1px·조임 단계·원귀·먹빛 퇴치·등장 솟음)을 더했다.
// INSTANCE_CUSTOM (각 채널 ≤ 2048 정수)
//   x = frame + 8 × dir_row + 32 × flip
//   y = 상태 비트: 1 풀릴 기색(안 먹1px + 바깥 백1px, 박 머리 황, 0/1px 떨림) · 2 먹빛(아이 변형 퇴치: 붉은색 대신 먹)
//       4 원귀(외곽 #c8322d + 바깥 먹 1px) · 512 백 무구 피격(외곽선만 한지)
//       8 퇴치 연출 · 16 비적대(맺힘 복귀 직후: 외곽 먹빛 점선) · 32 국소 정지 · 64 넉백(외곽 jk)
//       128·256 조임 단계 0..3 (매듭 잠금 누적: 2 = 대각 보강, 3 = 1.2Hz 맥동)
//   z = flash_idx + 4 × (dy + 4) + 36 × (dx_s + 2)   flash_idx 0 없음 / 1 한지 / 2 적 / 3 적 밝음
//   w = 해원 디졸브 0..1, 음수 = 등장 솟음(−1 → 0: 발부터 위로 드러남, 먹 가장자리)
// 반투명 없음(ART 3.3): 디졸브·솟음 경계는 단색 픽셀.

uniform float cols = 4.0;
uniform vec2 cell_size = vec2(32.0);
uniform vec2 pivot = vec2(16.0, 29.0);
uniform float hinge_y = 20.0;
uniform float anim_time = 0.0;
uniform int flash_mode = 0;           // 0 단색 / 1 외곽선만 / 2 끔
uniform vec4 baek : source_color = vec4(0.949, 0.925, 0.878, 1.0);
uniform vec4 meok : source_color = vec4(0.0549, 0.0431, 0.0863, 1.0);
uniform vec4 meok2 : source_color = vec4(0.1333, 0.1098, 0.1804, 1.0);
uniform vec4 col_hj : source_color = vec4(0.9137, 0.8627, 0.7529, 1.0);
uniform vec4 col_jk : source_color = vec4(0.7843, 0.1961, 0.1765, 1.0);
uniform vec4 col_jkhi : source_color = vec4(0.8941, 0.3765, 0.3098, 1.0);
uniform vec4 col_jkdk : source_color = vec4(0.5490, 0.1216, 0.1333, 1.0);
uniform vec4 col_outline : source_color = vec4(0.1020, 0.1020, 0.1020, 1.0);
uniform vec4 col_hwang_hi : source_color = vec4(0.9608, 0.8392, 0.4196, 1.0); // 황 밝음 #f5d66b (풀릴 기색 바깥 테 박 맥동)
// 가시성 층(design/18 §1.2): 무리 층. 일반·미니언 머티리얼에만 값이 들어온다(정예+ 는 기본값 = 감광 없음).
uniform float crowd_dim = 0.0;        // 밀도 감광 d 0..1 (vfx/atmosphere.gd 공급)
uniform float crowd_base = 1.0;       // 상시 명도 배율(enemy_manager 공급, 일반·미니언 0.88 / 설정 '끔' 1.0)
uniform float flash_keep = 1.0;       // 군집 타격 감쇠(vfx/hit_feedback.gd 공급): 단색 플래시를 낼 개체 비율 0..1
uniform float pullil_pulse = 0.0;     // 박 머리 1 → 0(atmosphere 가 Events.beat 로 공급). 0.5 이상이면 기색 바깥 테가 황
// bit 512 = 백 무구 피격(플래시를 외곽선에만 — '흰 몸'은 풀릴 기색 하나의 뜻으로만)

varying vec4 v_custom;
varying vec4 v_mod;
varying float v_iid;

bool has_bit(float flags, float bit) {
	return mod(floor(flags / bit), 2.0) >= 1.0;
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_mod = COLOR;
	v_iid = float(INSTANCE_ID);
	if (has_bit(floor(INSTANCE_CUSTOM.y + 0.5), 1.0)) {
		VERTEX.x += step(0.5, fract(anim_time * 3.75 + float(INSTANCE_ID) * 0.37));
	}
}

float inside(vec2 lp) {
	return (lp.x < 0.0 || lp.y < 0.0 || lp.x >= cell_size.x || lp.y >= cell_size.y) ? 0.0 : 1.0;
}

#define CELL_PX(lp) (texelFetch(TEXTURE, ivec2(origin + clamp((lp), vec2(0.0), cell_size - 1.0)), 0) * inside(lp))

void fragment() {
	float xv = floor(v_custom.x + 0.5);
	float frame = mod(xv, 8.0);
	float row = mod(floor(xv / 8.0), 4.0);
	float flip = mod(floor(xv / 32.0), 2.0);
	float bits = floor(v_custom.y + 0.5);
	float zv = floor(v_custom.z + 0.5);
	float fidx = mod(zv, 4.0);
	float dy = mod(floor(zv / 4.0), 9.0) - 4.0;
	float dx = floor(zv / 36.0) - 2.0;
	vec2 origin = vec2(min(frame, cols - 1.0) * cell_size.x, row * cell_size.y);
	vec2 lp = floor(UV * cell_size);
	if (flip > 0.5) {
		lp.x = cell_size.x - 1.0 - lp.x;
	}
	vec2 src = lp;
	if (lp.y <= hinge_y) {
		float sy = lp.y - dy;
		if (dy < 0.0) {
			sy = min(sy, hinge_y);
		}
		src.y = sy;
	}
	if (dx != 0.0 && lp.y < pivot.y - 1.0) {
		if (src.x < pivot.x) {
			src.x = dx > 0.0 ? min(src.x + dx, pivot.x - 1.0) : src.x + dx;
		} else {
			src.x = dx > 0.0 ? max(src.x - dx, pivot.x) : src.x - dx;
		}
	}
	vec4 c = CELL_PX(src);
	bool pullil = has_bit(bits, 1.0);
	bool wongwi = has_bit(bits, 4.0);
	float zoim = mod(floor(bits / 128.0), 4.0);
	bool ring = false;                          // 기색·원귀 테 픽셀(플래시로 덮지 않는다 — 맞는 순간에도 테가 남는다)
	// 무리 층(design/18 §1.2): 상시 ×crowd_base + 밀도 감광(명도 ×(1−0.30d), 채도 ×(1−0.45d)).
	// 풀릴 기색·원귀·외곽선 픽셀은 제외. 플래시·기색 테는 이 뒤에 칠해 맞는 순간 대비가 오히려 커진다.
	if ((crowd_dim > 0.001 || crowd_base < 0.999) && !pullil && !wongwi && c.a > 0.5
			&& distance(c.rgb, col_outline.rgb) >= 0.04) {
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = mix(c.rgb, vec3(lum), 0.45 * crowd_dim) * crowd_base * (1.0 - 0.30 * crowd_dim);
	}
	if (pullil && c.a < 0.5) {
		// 풀릴 기색 2px 테: 몸에 붙은 1px = 먹 #221c2e(창백한 몸·영가와 갈라 놓는다), 그 바깥 1px = 백(박 머리에 순백).
		// 조임 2+ 는 바깥 테를 대각으로 보강, 3 은 1.2Hz 맥동. 맥동 색은 순백(황은 무당 금 테 전용 — design/18 §1.1).
		float a1 = 0.0;
		a1 = max(a1, CELL_PX(src + vec2(1.0, 0.0)).a);
		a1 = max(a1, CELL_PX(src - vec2(1.0, 0.0)).a);
		a1 = max(a1, CELL_PX(src + vec2(0.0, 1.0)).a);
		a1 = max(a1, CELL_PX(src - vec2(0.0, 1.0)).a);
		if (a1 > 0.5) {
			c = vec4(meok2.rgb, 1.0);
			ring = true;
		} else {
			float a2 = 0.0;
			a2 = max(a2, CELL_PX(src + vec2(2.0, 0.0)).a);
			a2 = max(a2, CELL_PX(src - vec2(2.0, 0.0)).a);
			a2 = max(a2, CELL_PX(src + vec2(0.0, 2.0)).a);
			a2 = max(a2, CELL_PX(src - vec2(0.0, 2.0)).a);
			a2 = max(a2, CELL_PX(src + vec2(1.0, 1.0)).a);
			a2 = max(a2, CELL_PX(src + vec2(-1.0, 1.0)).a);
			a2 = max(a2, CELL_PX(src + vec2(1.0, -1.0)).a);
			a2 = max(a2, CELL_PX(src + vec2(-1.0, -1.0)).a);
			if (zoim >= 2.0) {
				a2 = max(a2, CELL_PX(src + vec2(2.0, 1.0)).a);
				a2 = max(a2, CELL_PX(src + vec2(2.0, -1.0)).a);
				a2 = max(a2, CELL_PX(src + vec2(-2.0, 1.0)).a);
				a2 = max(a2, CELL_PX(src + vec2(-2.0, -1.0)).a);
				a2 = max(a2, CELL_PX(src + vec2(1.0, 2.0)).a);
				a2 = max(a2, CELL_PX(src + vec2(-1.0, 2.0)).a);
				a2 = max(a2, CELL_PX(src + vec2(1.0, -2.0)).a);
				a2 = max(a2, CELL_PX(src + vec2(-1.0, -2.0)).a);
			}
			if (a2 > 0.5) {
				bool pulse = pullil_pulse >= 0.5 || (zoim >= 3.0 && fract(anim_time * 1.2) < 0.35);
				// 빽빽한 무리(d→1)에서 기색 테 수십 개가 백·황으로 번쩍이면 무당 금 테·해원 백과 겹친다(weak 19:30 기색 68).
				// 바깥 테만 먹 쪽으로 최대 35% 낮춘다. 몸 옆 먹 1px·맥동 박자는 그대로. 보통 런(d<0.15)은 거의 그대로다.
				c = vec4(mix(pulse ? vec3(1.0) : baek.rgb, meok2.rgb, 0.35 * crowd_dim), 1.0);
				ring = true;
			}
		}
	} else if (wongwi && c.a < 0.5) {
		// 원귀: 위험 테 #c8322d 바깥에 먹 1px — 무리·붉은 바닥 위에서도 갈린다
		float w1 = 0.0;
		w1 = max(w1, CELL_PX(src + vec2(1.0, 0.0)).a);
		w1 = max(w1, CELL_PX(src - vec2(1.0, 0.0)).a);
		w1 = max(w1, CELL_PX(src + vec2(0.0, 1.0)).a);
		w1 = max(w1, CELL_PX(src - vec2(0.0, 1.0)).a);
		if (w1 > 0.5) {
			c = vec4(meok.rgb, 1.0);
			ring = true;
		}
	}
	bool outline_px = c.a > 0.5 && distance(c.rgb, col_outline.rgb) < 0.04;
	if (has_bit(bits, 16.0) && outline_px && mod(lp.x + lp.y + floor(anim_time * 6.0), 2.0) < 1.0) {
		c.rgb = meok2.rgb;                          // 비적대(맺힘 복귀 직후 3초): 외곽 점선 흐림
	}
	if (wongwi && outline_px) {
		c.rgb = col_jk.rgb;                         // 원귀: 외곽 위험색 #c8322d
	}
	if (fidx > 0.5 && flash_mode != 2 && c.a > 0.5 && !ring) {
		bool ink = has_bit(bits, 2.0);
		vec3 fc = fidx < 1.5 ? col_hj.rgb : (fidx < 2.5 ? (ink ? meok2.rgb : col_jk.rgb) : (ink ? meok.rgb : col_jkhi.rgb));
		int fm = has_bit(bits, 512.0) ? 1 : flash_mode;   // 백 무구 피격: 외곽선만 한지
		if (fm == 0 && flash_keep < 0.999) {
			// 인스턴스 번호 + 0.2초 창 해시(플래시 2틱 동안 같은 판정, 창마다 번쩍일 개체가 돌아간다). 게임 난수 아님.
			float hk = fract(sin(v_iid * 12.9898 + floor(anim_time * 5.0) * 7.233 + 4.1414) * 43758.5453);
			if (hk >= flash_keep) {
				fm = 2;
			}
		}
		if ((fm == 0 && !outline_px) || (fm == 1 && outline_px)) {
			c.rgb = fc;
		}
	}
	if (has_bit(bits, 64.0) && flash_mode != 2 && outline_px) {
		c.rgb = col_jk.rgb;
	}
	float w = v_custom.w;
	if (w > 0.0) {
		float noise = fract(sin(dot(src, vec2(12.9898, 78.233))) * 43758.5453) * 0.12;
		float v = lp.y / cell_size.y;
		float cut = 1.0 - w * 1.15;
		if (v + noise > cut + 0.08) {
			discard;
		} else if (v + noise > cut) {
			c.rgb = baek.rgb;
		}
	} else if (w < 0.0) {
		// 등장 솟음: 진행 p = 1 + w (0 → 1). 발(피벗) 아래부터 위로 드러나며 경계는 먹.
		float p = 1.0 + w;
		float noise2 = fract(sin(dot(src, vec2(39.3468, 11.135))) * 24634.6345) * 0.1;
		float v2 = lp.y / max(pivot.y, 1.0);
		float show = 1.0 - p * 1.1;
		if (v2 - noise2 < show) {
			discard;
		} else if (v2 - noise2 < show + 0.1 && c.a > 0.5) {
			c.rgb = meok.rgb;
		}
	}
	if (c.a < 0.5) {
		discard;
	}
	COLOR = vec4(c.rgb, 1.0) * v_mod;
}
