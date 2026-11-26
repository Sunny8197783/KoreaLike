shader_type canvas_item;
// 단일 스프라이트 피격 플래시(GAME_FEEL 4.2). 소유: vfx.
// 혼합이 아니라 단색 치환: 알파 불투명 픽셀 중 외곽선 #1a1a1a 가 아닌 픽셀을 팔레트 색 하나로 바꾼다.
// 색: 0 없음 / 1 한지 #e9dcc0(일반 피격 "흰 플래시") / 2 적 #c8322d(퇴치 일격) / 3 적 밝음 #e4604f. 백 #f2ece0 은 쓰지 않는다(예약).
// flash_mode: 0 단색 / 1 외곽선만 / 2 끔 (접근성).
uniform int flash_idx = 0;
uniform int flash_mode = 0;
uniform vec4 col_hj : source_color = vec4(0.9137, 0.8627, 0.7529, 1.0);
uniform vec4 col_jk : source_color = vec4(0.7843, 0.1961, 0.1765, 1.0);
uniform vec4 col_jkhi : source_color = vec4(0.8941, 0.3765, 0.3098, 1.0);
uniform vec4 col_outline : source_color = vec4(0.1020, 0.1020, 0.1020, 1.0);

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (flash_idx > 0 && flash_mode != 2 && c.a > 0.5) {
		vec3 fc = flash_idx == 1 ? col_hj.rgb : (flash_idx == 2 ? col_jk.rgb : col_jkhi.rgb);
		bool outline = distance(c.rgb, col_outline.rgb) < 0.04;
		if ((flash_mode == 0 && !outline) || (flash_mode == 1 && outline)) {
			c.rgb = fc;
		}
	}
	COLOR = c * v_mod;
}
