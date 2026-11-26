shader_type canvas_item;
// vfx_bingui_pattern_sweep — 빙의 무복 문양 투영 + 스윕 (L09, normal). 소유: vfx (G5 deity/bingui).
// 사양: design/13-art-direction.md §5.4 문양 투영, §5.5 타임라인(0.60s 스윕 0.3초), §5.6 신령별 문양.
//   의복 마스크 구역 0 = 없음, 1 = 몸판(Z2), 2 = 소매(Z1), 3 = 치맛단(Z3). 빙의 순서 → 구역 배정은 게임 코드(FIFO).
//   문양 타일(16x16, res://assets/vfx/vfx_bingui_pattern_tiles.png, 12장 가로) 픽셀이 칠해진 곳만
//   '같은 명도 단계의 신령색'으로 치환한다(밝음/기본/그림자 3단계 → 베이크 셰이딩 유지).
//   투영 좌표 = 스프라이트 로컬 픽셀 mod 16 (걸어도 문양이 몸에 붙음). 64px 셀이면 아틀라스 픽셀 mod 16 과 같다.
//   스윕: zone_progress[i] 0→1 (0.3초, 아래→위). 앞머리 1~2px 은 황백 #fff1b8 섬광(백 #f2ece0 예약 회피).
//   미완 빙의(D-01, 효과 70%): zone_incomplete[i] = true → 50% 체커 디더로만 표시.
// 사용:
//   무당 몸 레이어(Sprite2D/AnimatedSprite2D)에 ShaderMaterial. zone_mask 는 몸 시트와 1:1 같은 배치의 마스크 시트
//   (R 채널 = 구역*64, 0/64/128/192). 시트/아틀라스면 cell_rect 에 현재 프레임 UV 사각형(x, y, w, h).
//   zone_tile[i] = 타일 번호 + 1 (타일 = 신령*2 + 면: 산신0 용왕1 칠성2 장군3 바리4 제석·대감5 / 위엄0 가호1), 0 = 비어 있음.
//   (Godot 4 는 uniform 배열 기본값을 지원하지 않으므로 0 = 비어 있음으로 인코딩)
//   ramp_*[i] = 해당 구역 신령 램프(밝음·기본·그림자), secondary[i] = 2번째 색(호랑이 먹줄, 칠성 군청 등).
//   신령 램프 기본값 표는 res://assets/vfx/vfx_bingui_pattern_tiles.json 의 deity_colors / saekdong.

uniform sampler2D zone_mask : filter_nearest;
uniform sampler2D pattern_atlas : filter_nearest, repeat_disable;
uniform vec4 cell_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform int zone_tile[3];          // index by zone-1: [Z1 소매, Z2 몸판, Z3 치맛단]; value = tile+1, 0 = empty
uniform float zone_progress[3];    // 0..1 sweep (bottom -> top); 1 = fully shown
uniform bool zone_incomplete[3];
uniform vec4 ramp_light[3] : source_color;
uniform vec4 ramp_base[3] : source_color;
uniform vec4 ramp_shadow[3] : source_color;
uniform vec4 secondary[3] : source_color;
uniform vec4 saekdong[6] : source_color;
uniform vec4 sweep_edge : source_color = vec4(1.0, 0.945, 0.722, 1.0); // #fff1b8 황백
uniform float lum_light : hint_range(0.0, 1.0) = 0.62;
uniform float lum_shadow : hint_range(0.0, 1.0) = 0.34;

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	COLOR = base;
	if (base.a > 0.5) {
		ivec2 tex_size = textureSize(TEXTURE, 0);
		ivec2 px = ivec2(floor(UV * vec2(tex_size)));
		int zone = int(floor(texture(zone_mask, UV).r * 255.0 / 64.0 + 0.5)); // 0..3
		if (zone >= 1 && zone <= 3) {
			int zi = zone - 1;
			int tile = zone_tile[zi] - 1;
			if (tile >= 0) {
				// frame-local vertical position (0 = bottom of the cell, 1 = top) for the sweep
				float v_local = clamp((UV.y - cell_rect.y) / max(cell_rect.w, 1e-6), 0.0, 1.0);
				float up = 1.0 - v_local;
				float prog = zone_progress[zi];
				float cell_h = cell_rect.w * float(tex_size.y);
				float edge_band = 2.0 / max(cell_h, 1.0);
				if (up <= prog) {
					ivec2 tp = ivec2(tile * 16 + (px.x % 16), px.y % 16);
					vec4 m = texelFetch(pattern_atlas, tp, 0);
					bool dither_ok = !zone_incomplete[zi] || ((px.x + px.y) % 2 == 0);
					if (m.a > 0.5 && dither_ok) {
						float l = luma(base.rgb);
						vec3 c;
						if (m.b > 0.05) {
							int si = clamp(int(floor((m.b * 255.0 - 20.0) / 40.0 + 0.5)), 0, 5);
							c = saekdong[si].rgb * (l > lum_light ? 1.0 : (l > lum_shadow ? 0.85 : 0.62));
						} else if (m.g > 0.5) {
							c = secondary[zi].rgb * (l > lum_light ? 1.15 : (l > lum_shadow ? 1.0 : 0.8));
						} else {
							c = l > lum_light ? ramp_light[zi].rgb : (l > lum_shadow ? ramp_base[zi].rgb : ramp_shadow[zi].rgb);
						}
						COLOR = vec4(c, base.a);
					}
					// the sweep front: a 2px pale-gold line riding up the cloth while prog < 1
					if (prog < 1.0 && up > prog - edge_band) {
						COLOR = vec4(sweep_edge.rgb, base.a);
					}
				}
			}
		}
	}
}
