shader_type canvas_item;
// 잡귀 MultiMesh 공용 셰이더 (design/14 §3.10.3, GAME_FEEL 4.1·4.2·4.4). 소유: vfx (인스턴스 데이터 계약은 enemies 와 공유).
// 텍스처 = SpriteLib.anim_atlas: [S,E,N 3행 × cols 열] 셀(여백 포함). west = east 행 + 좌우 반전.
// 메시 quad = (−pivot) ~ (cell − pivot), UV 0..1 = 셀 1칸. 모든 좌표는 셀 정수 픽셀(리샘플링·회전 없음).
// INSTANCE_CUSTOM (각 채널 ≤ 2048 정수: 반정밀 저장에서도 정확)
//   x = frame + 8 × dir_row + 32 × flip
//   y = 상태 비트: 1 풀릴 기색(2px 테: 안 1px 먹 + 바깥 1px 백↔황 박 맥동, 정수 0/1px 떨림), 2 아이, 4 원귀, 8 퇴치 연출 중,
//       16 유예, 32 국소 정지(디버그), 64 넉백 중(외곽선 jk 틴트), 128×(0..3) 조임 단계,
//       512 백 무구 피격(플래시를 외곽선에만 — '흰 몸'의 뜻은 풀릴 기색 하나로만, 리뷰 vfx#10)
//   z = flash_idx + 4 × (dy + 4) + 36 × (dx_s + 2)   flash_idx 0 없음 / 1 한지 / 2 적 / 3 적 밝음, dy −4..4, dx_s −2..2
//   w = 해원 디졸브 0..1
// 규칙: 피격 플래시는 단색 치환(혼합 아님)·외곽선 #1a1a1a 보존. 백 #f2ece0 은 풀릴 기색 외곽선·해원 가장자리 전용.

uniform float cols = 4.0;
uniform vec2 cell_size = vec2(32.0);
uniform vec2 pivot = vec2(16.0, 29.0);
uniform float hinge_y = 20.0;
uniform float anim_time = 0.0;        // Game.anim_time() (히트스톱·일시정지 정지)
uniform int flash_mode = 0;           // 0 단색 / 1 외곽선만 / 2 끔
uniform vec4 baek : source_color = vec4(0.949, 0.925, 0.878, 1.0);
uniform vec4 col_hj : source_color = vec4(0.9137, 0.8627, 0.7529, 1.0);
uniform vec4 col_jk : source_color = vec4(0.7843, 0.1961, 0.1765, 1.0);
uniform vec4 col_jkhi : source_color = vec4(0.8941, 0.3765, 0.3098, 1.0);
uniform vec4 col_outline : source_color = vec4(0.1020, 0.1020, 0.1020, 1.0);
uniform vec4 col_meok : source_color = vec4(0.1333, 0.1098, 0.1804, 1.0);   // 먹 #221c2e (풀릴 기색 안쪽 테)
uniform vec4 col_hwang_hi : source_color = vec4(0.9608, 0.8392, 0.4196, 1.0); // 황 밝음 #f5d66b (풀릴 기색 바깥 테 맥동)
uniform float pullil_pulse = 0.0;     // 박 머리 1 → 0(atmosphere 가 Events.beat 로 공급). 0.5 이상이면 바깥 테가 황
uniform float flash_keep = 1.0;       // 군집 타격 감쇠(vfx/hit_feedback.gd 가 일반 잡귀 머티리얼에 공급): 단색 플래시를 낼 개체 비율 0..1.
                                      // 나머지는 플래시 없이 스쿼시·넛지로만 반응 — 몰린 곳을 때려도 한지색 덩어리로 뭉치지 않게
uniform float crowd_dim = 0.0;        // 밀도 감광 d(design/13 §2.10.6, vfx/atmosphere.gd 가 일반 잡귀 머티리얼에만 공급). 풀릴 기색 제외

// 주의: Godot 4 canvas fragment 의 COLOR 초깃값은 "정점색 × texture(TEXTURE, UV)" 다. 셀·시프트 샘플을 직접 하므로
// 정점색(모듈레이트)만 varying 으로 받아 곱한다(COLOR 를 곱하면 원래 UV 의 텍셀이 한 번 더 곱해져 형태가 깨진다).
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
		// 풀릴 기색 떨림: 정수 0/1px 토글(약 3.75Hz). 연출 시계라 히트스톱에서 멈춘다.
		VERTEX.x += step(0.5, fract(anim_time * 3.75 + float(INSTANCE_ID) * 0.37));
	}
}

float inside(vec2 lp) {
	return (lp.x < 0.0 || lp.y < 0.0 || lp.x >= cell_size.x || lp.y >= cell_size.y) ? 0.0 : 1.0;
}

// 셀 안 픽셀 lp 의 알파(셀 밖 = 0). TEXTURE 는 단계 함수에서만 쓸 수 있어 매크로로 둔다.
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
	if (crowd_dim > 0.001 && !has_bit(bits, 1.0) && c.a > 0.5 && distance(c.rgb, col_outline.rgb) >= 0.04) {
		// 명도 ×(1−0.22d), 채도 ×(1−0.35d) — 무리가 커질수록 일반 잡귀는 배경으로 물러난다(플래시·기색 테는 이 뒤라 그대로)
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = mix(c.rgb, vec3(lum), 0.35 * crowd_dim) * (1.0 - 0.22 * crowd_dim);
	}
	if (has_bit(bits, 1.0) && c.a < 0.5) {
		// 풀릴 기색 2px 테: 몸에 붙은 1px = 먹(창백한 몸·영가 행렬과 갈라 놓는다), 그 바깥 1px = 백(박 머리에 황 밝음)
		float a1 = 0.0;
		a1 = max(a1, CELL_PX(src + vec2(1.0, 0.0)).a);
		a1 = max(a1, CELL_PX(src - vec2(1.0, 0.0)).a);
		a1 = max(a1, CELL_PX(src + vec2(0.0, 1.0)).a);
		a1 = max(a1, CELL_PX(src - vec2(0.0, 1.0)).a);
		if (a1 > 0.5) {
			c = vec4(col_meok.rgb, 1.0);
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
			if (a2 > 0.5) {
				c = vec4(pullil_pulse >= 0.5 ? vec3(1.0) : baek.rgb, 1.0);   // 맥동은 순백(황은 무당 금 테 전용)
			}
		}
	}
	if (fidx > 0.5 && flash_mode != 2 && c.a > 0.5) {
		vec3 fc = fidx < 1.5 ? col_hj.rgb : (fidx < 2.5 ? col_jk.rgb : col_jkhi.rgb);
		bool outline = distance(c.rgb, col_outline.rgb) < 0.04;
		int fm = has_bit(bits, 512.0) ? 1 : flash_mode;   // 백 무구 피격: 외곽선만 번쩍
		if (fm == 0 && flash_keep < 0.999) {
			// 인스턴스 번호 + 0.2초 창 해시로 고른다(플래시 2틱 동안은 같은 판정, 창마다 번쩍일 개체가 돌아간다)
			float hk = fract(sin(v_iid * 12.9898 + floor(anim_time * 5.0) * 7.233 + 4.1414) * 43758.5453);
			if (hk >= flash_keep) {
				fm = 2;
			}
		}
		if ((fm == 0 && !outline) || (fm == 1 && outline)) {
			c.rgb = fc;
		}
	}
	if (has_bit(bits, 64.0) && flash_mode != 2 && c.a > 0.5 && distance(c.rgb, col_outline.rgb) < 0.04) {
		c.rgb = col_jk.rgb;                       // 넉백 중: 외곽선만 #c8322d (몸 색은 유지)
	}
	float w = v_custom.w;
	if (w > 0.0) {
		// 해원 = 아래→위 디졸브 + 백 가장자리(반투명 없음: 디졸브 경계만)
		float noise = fract(sin(dot(src, vec2(12.9898, 78.233))) * 43758.5453) * 0.12;
		float v = lp.y / cell_size.y;
		float cut = 1.0 - w * 1.15;
		if (v + noise > cut + 0.08) {
			discard;
		} else if (v + noise > cut) {
			c.rgb = baek.rgb;
		}
	}
	if (c.a < 0.5) {
		discard;
	}
	COLOR = vec4(c.rgb, 1.0) * v_mod;
}
