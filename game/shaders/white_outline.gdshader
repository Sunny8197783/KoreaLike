shader_type canvas_item;
// 풀릴 기색 외곽선 (Sprite2D/AnimatedSprite2D 용: 정예·중간보스·보스). 소유: vfx.
// 백 #f2ece0 1px 외곽선 + 0.5px 떨림. 백은 풀릴 기색·길베·영가·해원 전용 예약색.
uniform bool enabled = true;
uniform vec4 outline_color : source_color = vec4(0.949, 0.925, 0.878, 1.0);
uniform float thickness_px = 1.0;
uniform float wobble_px = 0.5;

void vertex() {
	if (enabled) {
		VERTEX.x += sin(TIME * 14.0) * wobble_px;
	}
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (enabled && c.a < 0.5) {
		vec2 o = TEXTURE_PIXEL_SIZE * thickness_px;
		float a = texture(TEXTURE, UV + vec2(o.x, 0.0)).a;
		a = max(a, texture(TEXTURE, UV - vec2(o.x, 0.0)).a);
		a = max(a, texture(TEXTURE, UV + vec2(0.0, o.y)).a);
		a = max(a, texture(TEXTURE, UV - vec2(0.0, o.y)).a);
		if (a > 0.5) {
			c = outline_color;
		}
	}
	COLOR = c * COLOR;
}
