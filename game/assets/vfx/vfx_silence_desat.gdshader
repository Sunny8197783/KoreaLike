shader_type canvas_item;
render_mode unshaded;
// vfx_silence_desat — 정적(어둑시니 등장·보스 직전): 0.8초 동안 채도 −60% + 먹 비네트 (L17, normal).
// strength 0→1 을 0.8s 트윈(screen_post_fx.gd). 비네트는 먹 #0e0b16, 640x360 격자로 끊고 단계(bands)로
// 양자화해 픽셀아트 화면 위에서도 '먹이 번지는' 단단한 가장자리가 된다. 가장자리는 느리게 일렁인다(먹 번짐).

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float desat_max : hint_range(0.0, 1.0) = 0.6;     // 채도 −60% (6.8 표)
uniform float darken_max : hint_range(0.0, 1.0) = 0.12;   // 전체 명도 살짝 하강
uniform vec4 ink : source_color = vec4(0.0549, 0.0431, 0.0863, 1.0); // 먹 #0e0b16
uniform float vignette_inner : hint_range(0.0, 1.5) = 0.45;
uniform float vignette_outer : hint_range(0.0, 1.5) = 1.05;
uniform float vignette_max : hint_range(0.0, 1.0) = 0.7;
uniform float bleed_amp : hint_range(0.0, 0.2) = 0.045;   // 먹 번짐 일렁임 폭
uniform vec2 pixel_grid = vec2(640.0, 360.0);
uniform float bands = 5.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float s = clamp(strength, 0.0, 1.0);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat_max * s);
	c *= 1.0 - darken_max * s;

	vec2 uv = (floor(SCREEN_UV * pixel_grid) + 0.5) / pixel_grid;
	vec2 d = (uv - 0.5) * 2.0;
	d.x *= pixel_grid.x / pixel_grid.y * 0.75;
	float ang = atan(d.y, d.x);
	float r = length(d) + bleed_amp * s * (sin(ang * 7.0 + TIME * 0.7) * 0.6 + sin(ang * 13.0 - TIME * 1.1) * 0.4);
	float v = smoothstep(vignette_inner, vignette_outer, r);
	v = floor(v * bands + 0.5) / bands;
	c = mix(c, ink.rgb, v * vignette_max * s);
	COLOR = vec4(c, 1.0);
}
