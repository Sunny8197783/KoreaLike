shader_type canvas_item;
render_mode blend_add, unshaded;
// vfx_screen_flash — 길닦음 등 해원 순간의 순백 화면 플래시 (L17, add).
// 2프레임 @24fps: 프레임0 intensity 0.30, 프레임1 0.15 (screen_post_fx.gd 가 구동).
// 백 예약: 해원 순간 연출 전용. 코어색은 팔레트의 '플래시 코어 전용' #fffdf6.
// 광과민 가이드: 알파 ≤ 30%, 초당 ≤ 3회 (13-art-direction 2.11). 상한은 여기서도 clamp 한다.

uniform vec4 flash_color : source_color = vec4(1.0, 0.992, 0.965, 1.0); // #fffdf6
uniform float intensity : hint_range(0.0, 0.3) = 0.0;
// 길닦음 고리 중심(화면 UV). 중심 쪽이 조금 더 밝고 가장자리는 70%까지 — 빛이 '터져 나오는' 방향을 준다.
uniform vec2 center_uv = vec2(0.5, 0.5);
uniform float edge_falloff : hint_range(0.0, 1.0) = 0.3;
// 저해상도 격자(640x360)로 감쇠 단계를 끊어 픽셀아트 화면과 맞춘다.
uniform vec2 pixel_grid = vec2(640.0, 360.0);
uniform float bands = 4.0;

void fragment() {
	vec2 uv = (floor(SCREEN_UV * pixel_grid) + 0.5) / pixel_grid;
	vec2 d = (uv - center_uv) * vec2(pixel_grid.x / pixel_grid.y, 1.0);
	float r = clamp(length(d) / 1.0, 0.0, 1.0);
	float k = 1.0 - edge_falloff * floor(r * bands) / bands;
	COLOR = vec4(flash_color.rgb, min(intensity, 0.3) * k);
}
