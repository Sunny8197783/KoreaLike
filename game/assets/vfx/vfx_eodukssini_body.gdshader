// vfx_eodukssini_body — the eodukssini's boiling meok cloud (KoreaLike, G4 enemy VFX).
// Godot 4 canvas_item shader. Put it on a Sprite2D/ColorRect sized to the body (default 96x96 game px,
// feet at the bottom centre). Metaballs + value noise, snapped to whole game pixels (1 px snap) so it
// sits with the pixel art. Mirrors tools/vendor/pixelfx/src/fx/korean/_g4_eoduk.js; the sprite-sheet
// fallback is vfx_eodukssini_body.png/.json.
// grow: 0..1+ scales the body (eodukssini grows while the player looks up at it).
shader_type canvas_item;
render_mode blend_mix;

uniform vec2 pixel_res = vec2(96.0, 96.0);          // canvas size in game pixels
uniform float grow : hint_range(0.3, 2.0) = 1.0;
uniform float speed : hint_range(0.0, 4.0) = 1.0;
uniform float boil : hint_range(0.0, 1.0) = 0.45;
uniform vec4 ink_lit : source_color = vec4(0.365, 0.318, 0.439, 1.0);   // #5d5170
uniform vec4 ink_mid : source_color = vec4(0.169, 0.137, 0.220, 1.0);   // #2b2338
uniform vec4 ink_dark : source_color = vec4(0.106, 0.082, 0.149, 1.0);  // #1b1526
uniform vec4 ink_core : source_color = vec4(0.055, 0.043, 0.086, 1.0);  // #0e0b16
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i), b = hash(i + vec2(1.0, 0.0)), c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

// local coords: x right from centre, y up from the feet, in game px
float field(vec2 q, float t) {
	float a = t * 6.2831853;
	vec3 balls[13] = vec3[](
		vec3(0.0, 28.0, 15.0), vec3(-10.0 + 2.0 * sin(a), 22.0, 10.0), vec3(11.0 + 2.0 * cos(a), 24.0, 9.5),
		vec3(-4.0 + 3.0 * cos(a + 1.0), 40.0 - 2.0 * sin(a), 9.0), vec3(6.0 + 2.0 * sin(a + 2.0), 38.0, 8.0),
		vec3(-15.0 + 2.0 * cos(a + 3.0), 12.0, 6.0), vec3(14.0 + 2.0 * sin(a + 4.0), 11.0, 6.5), vec3(0.0, 10.0, 10.0),
		vec3(-14.0 + 2.0 * sin(a + 5.0), 36.0, 5.0), vec3(15.0, 34.0 - 2.0 * cos(a + 1.0), 4.5),
		vec3(2.0 + 2.0 * cos(a + 2.0), 50.0, 5.5), vec3(-20.0, 24.0 - 2.0 * sin(a), 4.0), vec3(21.0 + sin(a + 3.0), 20.0, 4.0)
	);
	float v = 0.0;
	for (int i = 0; i < 13; i++) {
		vec3 b = balls[i];
		vec2 d = q - b.xy * grow;
		float r = b.z * grow;
		v += (r * r) / max(0.5, dot(d, d));
	}
	return v + boil * vnoise(q / 6.0 + vec2(cos(a), sin(a)) * 1.5);
}

void fragment() {
	// snap to the game-pixel grid
	vec2 px = floor(UV * pixel_res) + 0.5;
	vec2 q = vec2(px.x - pixel_res.x * 0.5, pixel_res.y - 12.0 - px.y);
	float t = fract(TIME * speed / 1.0);
	float v = field(q, t);
	if (v < 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec4 c = v > 2.4 ? ink_core : (v > 1.5 ? ink_dark : ink_mid);
		if (field(q + vec2(-1.0, 2.0), t) < 1.0) c = ink_lit;          // lit top-left edge
		else if (field(q + vec2(0.0, -2.0), t) < 1.0) c = ink_dark;    // dark underside
		COLOR = vec4(c.rgb, alpha);
	}
}
