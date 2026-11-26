shader_type canvas_item;
// 원혼 구슬 MultiMesh 셰이더 — 소유: enemies(pickups).
// INSTANCE_CUSTOM: x = 프레임 번호(시트 행 우선), z = 1 이면 병합·착지 번쩍(한지 단색 #e9dcc0).
// 반투명 없음(ART 3.3): 알파 0.5 미만은 버린다.

uniform float cols = 4.0;
uniform float rows = 1.0;
uniform vec4 col_hj : source_color = vec4(0.9137, 0.8627, 0.7529, 1.0);

varying vec2 v_cell;
varying float v_flash;

void vertex() {
	float f = floor(INSTANCE_CUSTOM.x + 0.5);
	v_cell = vec2(mod(f, cols), floor(f / cols));
	v_flash = INSTANCE_CUSTOM.z;
}

void fragment() {
	vec4 c = texture(TEXTURE, (v_cell + UV) / vec2(cols, rows));
	if (c.a < 0.5) {
		discard;
	}
	if (v_flash > 0.5) {
		c.rgb = col_hj.rgb;
	}
	COLOR = vec4(c.rgb, 1.0);
}
