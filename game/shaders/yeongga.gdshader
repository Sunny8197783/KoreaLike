shader_type canvas_item;
// 영가(해원된 넋) 실루엣. 소유: vfx.
// 2026-11-24 리뷰 vfx#10: 백 #f2ece0 은 풀릴 기색 테 전용 → 영가는 백을 쓰지 않는다.
// 2026-11-25 마감 리뷰(튜토리얼 newcomer·bugs_flow): 청회색 영가가 창백한 귀신 무리(회청·흰 계열)와 같은 색으로 읽혀
// '무엇이 아군인지' 갈리지 않았다 → 따뜻한 넋불빛(한지·황토 기미, 무당 금 #f5d66b 보다 채도·명도를 낮춤) + 반투명(α0.72).
// 적은 불투명·차가운 색, 영가는 반투명·따뜻한 색 — 색상과 투명도 두 갈래로 가른다. 원래 명암 2단은 남기고 아래쪽은 흐리게(발 없는 넋).
uniform vec4 ghost_hi : source_color = vec4(0.851, 0.788, 0.639, 1.0);   // #d9c9a3 넋불 밝은 면
uniform vec4 ghost_lo : source_color = vec4(0.549, 0.478, 0.369, 1.0);   // #8c7a5e 넋불 어두운 면
uniform vec4 ghost_warm : source_color = vec4(0.910, 0.784, 0.541, 1.0); // #e8c88a 넋불 기미
uniform float tint = 0.78;
uniform float ghost_alpha = 0.72;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 g = l > 0.42 ? ghost_hi.rgb : ghost_lo.rgb;
	g = mix(g, ghost_warm.rgb, 0.25);   // 따뜻한 전면(design/18 §1.1 영가 층): 차가운 귀신 무리와 색상으로 갈린다
	vec3 col = mix(c.rgb, g, clamp(tint + 0.25, 0.0, 1.0));
	float fade_bottom = smoothstep(0.95, 0.45, UV.y);
	COLOR = vec4(col, c.a * fade_bottom * ghost_alpha) * COLOR;
}
