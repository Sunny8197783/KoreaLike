shader_type canvas_item;
render_mode unshaded, blend_add;
// vfx_yeongga_spawn_run — 해원 직후 영가가 행렬 꼬리로 종종걸음칠 때 남기는 흰 잔상(2개). L08, add. 소유: vfx (G3 procession).
// 사양: design/13-art-direction.md 6.5 '영가 잔상 2개를 남기며 꼬리로 종종걸음', 4.3 영가 렌더(하단 2px 알파 페이드).
// 사용: 이 머티리얼은 '잔상 스프라이트'용이다(본체는 일반 영가 머티리얼 그대로).
//   합류 런(0.6s) 동안 0.06s 마다 본체의 현재 프레임을 복사한 Sprite2D 를 같은 자리에 남기고(최대 2개 유지),
//   echo_age 0→1 을 0.18s 동안 트윈한 뒤 free. 스프라이트시트 셀이면 cell_rect 에 현재 프레임 UV 사각형.
//   예)  var e := Sprite2D.new(); e.texture = body.sprite_frames.get_frame_texture(body.animation, body.frame)
//        e.material = ECHO_MAT.duplicate(); e.global_position = body.global_position; e.flip_h = body.flip_h
//        add_sibling(e); var tw := e.create_tween(); tw.tween_property(e.material, "shader_parameter/echo_age", 1.0, 0.18); tw.tween_callback(e.queue_free)
//   run_dir: 진행 방향(스크린 x 부호) — 잔상은 진행 반대쪽으로 1px씩 밀리며 가늘어진다.

uniform vec4 baek : source_color = vec4(0.949, 0.925, 0.878, 1.0);   // #f2ece0
uniform vec4 baek_shade : source_color = vec4(0.839, 0.812, 0.757, 1.0); // #d6cfc1
uniform float echo_age : hint_range(0.0, 1.0) = 0.0;
uniform float run_dir = 1.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.8;
uniform vec4 cell_rect = vec4(0.0, 0.0, 1.0, 1.0);

varying vec4 v_mod;

float bayer2(vec2 a) { a = floor(a); return fract(dot(a, vec2(0.5, a.y * 0.75))); }
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }

void vertex() {
	v_mod = COLOR;
	// 나이 들수록 진행 반대쪽으로 1~2px 처짐(정수)
	VERTEX.x -= floor(echo_age * 2.0 + 0.5) * run_dir;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lo_y = cell_rect.y;
	float hi_y = cell_rect.y + cell_rect.w;
	float py = floor((hi_y - UV.y) / TEXTURE_PIXEL_SIZE.y); // 셀 바닥에서 위로 몇 px
	if (c.a < 0.5) {
		discard;
	}
	// 평면 백 실루엣: 위쪽 밝고 아래 그늘 한 단(영가 '위로 가늘어지는 촛불형')
	float v = (UV.y - lo_y) / max(cell_rect.w, 1e-5);
	vec3 col = v < 0.55 ? baek.rgb : baek_shade.rgb;
	float a = max_alpha * (1.0 - echo_age);
	// 하단 2px 알파 페이드(영가 공통)
	if (py < 2.0) a *= 0.5;
	// 반투명은 4x4 베이어 디더로(픽셀 격자 유지): 알파가 떨어질수록 점이 성겨진다
	float th = bayer4(floor(UV / TEXTURE_PIXEL_SIZE)); // 텍셀 격자 기준(화면 확대와 무관)
	if (a < th * 0.9) discard;
	// 잔상은 위에서부터 가늘어짐: 나이가 들면 위쪽 행부터 깎인다
	if (v < echo_age * 0.6) discard;
	// 살아남은 점은 또렷하게(가산이라 어두운 바탕 위에서 흰 점열로 읽힘), 밀도는 디더가 맡는다
	COLOR = vec4(col, 0.9 * v_mod.a);
}
