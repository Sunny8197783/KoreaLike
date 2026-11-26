shader_type canvas_item;
// 행위자 공통 픽셀 셰이더(플레이어 Sprite2D). GAME_FEEL 1.4·1.5. 소유: vfx.
// 리샘플링·회전 없음: 모든 변형은 정수 픽셀 시프트(힌지 스쿼시·밴드 기울기)와 단색 치환(플래시)뿐이다.
// Sprite2D 는 region_enabled + region_rect = 아틀라스 셀, flip_h = west(east 반전). 셰이더 좌표는 텍스처 공간 셀 픽셀.
//   cell_origin  셀 왼쪽 위(아틀라스 px)       cell_size  셀 크기(px, 여백 포함)
//   pivot        발 피벗(셀 px)                hinge_y    허리 행(셀 px). 이 행 위만 스쿼시·기울기
//   sq_dy        + 눌림(위가 내려옴) / − 늘어남   sq_dx      + 한쪽 면 확장 / − 수축 (피벗 x 기준 대칭)
//   shear        허리 위 행당 가로 시프트(텍스처 공간, 반전 시 부호 반대로 넘김). |시프트| ≤ shear_max
//   flash_idx    0 없음 / 1 한지 #e9dcc0 / 2 적 #c8322d / 3 적 밝음 #e4604f — 외곽선 #1a1a1a 는 보존
//   flash_mode   0 단색 / 1 외곽선만 / 2 끔 (접근성)
//   rim_mode     0 일반 / 1 테만(몸 밖 rim_w px 금 + 그 밖 1px 먹, 몸은 버림) / 2 실루엣(몸 먹 + 테 금 + 먹) — design/18 §1.1·1.4
//                무당 금 테(Rim, z7)와 무적 점멸 숨김 틱이 쓴다. 스쿼시·기울기는 같은 경로(map_src)로 따른다.

uniform vec2 cell_origin = vec2(0.0);
uniform vec2 cell_size = vec2(64.0);
uniform vec2 pivot = vec2(32.0, 58.0);
uniform float hinge_y = 37.0;
uniform float sq_dy = 0.0;
uniform float sq_dx = 0.0;
uniform float shear = 0.0;
uniform float shear_max = 2.0;
uniform int flash_idx = 0;
uniform int flash_mode = 0;
uniform vec4 col_hj : source_color = vec4(0.9137, 0.8627, 0.7529, 1.0);
uniform vec4 col_jk : source_color = vec4(0.7843, 0.1961, 0.1765, 1.0);
uniform vec4 col_jkhi : source_color = vec4(0.8941, 0.3765, 0.3098, 1.0);
uniform vec4 col_outline : source_color = vec4(0.1020, 0.1020, 0.1020, 1.0);
uniform int rim_mode = 0;
uniform int rim_w = 1;
uniform vec4 col_rim : source_color = vec4(0.9608, 0.8392, 0.4196, 1.0);   // 금 #f5d66b
uniform vec4 col_ink : source_color = vec4(0.0549, 0.0431, 0.0863, 1.0);   // 먹 #0e0b16

// 주의: Godot 4 canvas fragment 의 COLOR 초깃값은 "정점색 × texture(TEXTURE, UV)" 다. 셀·시프트 샘플을 직접 하므로
// 정점색(모듈레이트)만 varying 으로 받아 곱한다(COLOR 를 곱하면 원래 UV 의 텍셀이 한 번 더 곱해져 형태가 깨진다).
varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

float inside(vec2 lp) {
	return (lp.x < 0.0 || lp.y < 0.0 || lp.x >= cell_size.x || lp.y >= cell_size.y) ? 0.0 : 1.0;
}

vec2 map_src(vec2 lp) {
	vec2 src = lp;
	if (lp.y <= hinge_y) {
		float sh = clamp(floor((hinge_y - lp.y) * shear + 0.5), -shear_max, shear_max);
		src.x -= sh;
		float sy = lp.y - sq_dy;
		if (sq_dy < 0.0) {
			sy = min(sy, hinge_y);
		}
		src.y = sy;
	}
	if (sq_dx != 0.0 && lp.y < pivot.y - 2.0) {
		if (src.x < pivot.x) {
			src.x = sq_dx > 0.0 ? min(src.x + sq_dx, pivot.x - 1.0) : src.x + sq_dx;
		} else {
			src.x = sq_dx > 0.0 ? max(src.x - sq_dx, pivot.x) : src.x - sq_dx;
		}
	}
	return src;
}

void fragment() {
	vec2 lp = floor(UV / TEXTURE_PIXEL_SIZE) - cell_origin;
	// TEXTURE 는 함수 인자로 못 넘긴다(canvas 셰이더 제약) — 샘플은 여기서 직접 한다.
	vec2 src0 = map_src(lp);
	vec4 c = texture(TEXTURE, (cell_origin + src0 + 0.5) * TEXTURE_PIXEL_SIZE) * inside(src0);
	if (rim_mode != 0) {
		if (c.a > 0.5) {
			if (rim_mode == 1) {
				discard;
			}
			COLOR = vec4(col_ink.rgb, 1.0) * v_mod;
		} else {
			// 몸까지 맨해튼 거리(≤ rim_w + 1)
			int lim = rim_w + 1;
			int md = 99;
			for (int dy = -3; dy <= 3; dy++) {
				for (int dx = -3; dx <= 3; dx++) {
					int m = abs(dx) + abs(dy);
					if (m == 0 || m > lim || m >= md) {
						continue;
					}
					vec2 sn = map_src(lp + vec2(float(dx), float(dy)));
					if (textureLod(TEXTURE, (cell_origin + sn + 0.5) * TEXTURE_PIXEL_SIZE, 0.0).a * inside(sn) > 0.5) {
						md = m;
					}
				}
			}
			if (md <= rim_w) {
				COLOR = vec4(col_rim.rgb, 1.0) * v_mod;
			} else if (md == lim) {
				COLOR = vec4(col_ink.rgb, 1.0) * v_mod;
			} else {
				discard;
			}
		}
	} else {
		if (flash_idx > 0 && flash_mode != 2 && c.a > 0.5) {
			vec3 fc = flash_idx == 1 ? col_hj.rgb : (flash_idx == 2 ? col_jk.rgb : col_jkhi.rgb);
			bool outline = distance(c.rgb, col_outline.rgb) < 0.04;
			if ((flash_mode == 0 && !outline) || (flash_mode == 1 && outline)) {
				c.rgb = fc;
			}
		}
		COLOR = c * v_mod;
	}
}
