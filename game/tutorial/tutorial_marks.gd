extends Node2D
## 연습 굿판 월드 표지(design/17 §5.1.1). 소유: tutorial_run. World 안(카메라 적용) Node2D.
## 색은 황(#e8b931) 점선만 쓴다 — 백(#f2ece0)은 해원 표지 예약색(UiKit.BAEK 주석).
## 디렉터가 상태를 채우고, 이 노드는 그리기만 한다(시뮬 상태를 바꾸지 않는다).

const U: float = 32.0
const COL: Color = Color("e8b931")
const COL_HI: Color = Color("f5d66b")
const COL_DK: Color = Color("a97c1b")
const OUT: Color = Color("1a1a1a")

var arrows: PackedVector2Array = PackedVector2Array()   # 가장 가까운 목표(들) — 무당 곁 화살표 + 목표 위 내림표
var dir4: bool = false                                  # 무당 둘레 4방향 화살표(걷기 L1)
var circle_on: bool = false                             # 황 점선 원
var circle_c: Vector2 = Vector2.ZERO
var circle_r: float = 2.2 * U
var checkpoints: PackedVector2Array = PackedVector2Array()
var cp_lit: PackedByteArray = PackedByteArray()
var demo_on: bool = false                               # 재시연: 흰 점(황 테두리)이 원을 3.8초에 한 바퀴
var demo_period: float = 3.8
var player_circle_r: float = 0.0                        # >0 이면 무당 둘레 점선 원(방울 반경)
var bracket_left: float = 0.0                           # 영가 행렬 괄호 남은 시간(실시간)
var bracket_pts: PackedVector2Array = PackedVector2Array()

var _t: float = 0.0


func _ready() -> void:
	z_index = 40          # 적·무당 위, 화면 HUD 아래
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func clear_all() -> void:
	arrows = PackedVector2Array()
	dir4 = false
	circle_on = false
	checkpoints = PackedVector2Array()
	cp_lit = PackedByteArray()
	demo_on = false
	player_circle_r = 0.0
	bracket_left = 0.0


func _process(delta: float) -> void:
	_t += delta
	if bracket_left > 0.0:
		bracket_left -= delta
	queue_redraw()


func _player_pos() -> Vector2:
	return Game.player.global_position if Game.player != null else Vector2.ZERO


func _draw() -> void:
	var pp: Vector2 = _player_pos()
	var pulse: float = 0.6 + 0.4 * sin(_t * TAU * 1.2)
	if circle_on:
		_dashed_circle(circle_c, circle_r, Color(COL, 0.55 + 0.3 * pulse))
		for k in checkpoints.size():
			var lit: bool = k < cp_lit.size() and cp_lit[k] == 1
			var c: Vector2 = checkpoints[k]
			draw_circle(c, 4.0, OUT)
			draw_circle(c, 3.0, COL_HI if lit else Color(COL_DK, 0.8))
			if lit:
				draw_circle(c, 1.5, Color.WHITE)
	if demo_on:
		var a: float = fmod(_t, demo_period) / demo_period * TAU
		for j in 6:
			var aj: float = a - float(j) * 0.07
			var pj: Vector2 = circle_c + Vector2(cos(aj), sin(aj)) * circle_r
			draw_circle(pj, 2.5 - float(j) * 0.35, Color(1, 1, 1, 0.8 - float(j) * 0.13))
		var pd: Vector2 = circle_c + Vector2(cos(a), sin(a)) * circle_r
		draw_circle(pd, 3.5, COL)
		draw_circle(pd, 2.5, Color.WHITE)
	if player_circle_r > 0.0:
		_dashed_circle(pp, player_circle_r, Color(COL, 0.45 + 0.25 * pulse))
	if dir4:
		for k in 4:
			var d: Vector2 = Vector2.from_angle(float(k) * TAU / 4.0)
			_chevron(pp + d * (1.1 * U + 3.0 * pulse), d, Color(COL, 0.5 + 0.5 * pulse))
	for t: Vector2 in arrows:
		var to: Vector2 = t - pp
		var dist: float = to.length()
		if dist > 1.6 * U:
			var d2: Vector2 = to / dist
			_chevron(pp + d2 * (1.2 * U + 3.0 * pulse), d2, Color(COL, 0.7 + 0.3 * pulse))
		# 목표 위 내림표(통통 튐)
		var top: Vector2 = t + Vector2(0, -26.0 - 3.0 * pulse)
		_chevron(top, Vector2.DOWN, COL_HI)
	if bracket_left > 0.0 and bracket_pts.size() >= 2:
		var al: float = clampf(bracket_left / 0.4, 0.0, 1.0)
		var col: Color = Color(COL, 0.8 * al)
		for k in bracket_pts.size() - 1:
			_dashed_line(bracket_pts[k] + Vector2(0, -22), bracket_pts[k + 1] + Vector2(0, -22), col)
		for e: Vector2 in [bracket_pts[0], bracket_pts[bracket_pts.size() - 1]]:
			draw_line(e + Vector2(0, -26), e + Vector2(0, -18), col, 1.0)


func _chevron(at: Vector2, d: Vector2, col: Color) -> void:
	var n: Vector2 = Vector2(-d.y, d.x)
	var tip: Vector2 = at + d * 4.0
	var a: Vector2 = at - d * 2.0 + n * 4.0
	var b: Vector2 = at - d * 2.0 - n * 4.0
	draw_colored_polygon(PackedVector2Array([tip + d, a + d - n * 0.5, b + d + n * 0.5]), OUT)
	draw_colored_polygon(PackedVector2Array([tip, a, b]), col)


func _dashed_circle(c: Vector2, r: float, col: Color) -> void:
	var segs: int = maxi(16, int(r * TAU / 6.0))
	if segs % 2 == 1:
		segs += 1
	var off: float = _t * 0.6
	for k in range(0, segs, 2):
		var a0: float = off + TAU * float(k) / float(segs)
		var a1: float = off + TAU * float(k + 1) / float(segs)
		draw_line(c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r, col, 1.0)


func _dashed_line(a: Vector2, b: Vector2, col: Color) -> void:
	var len: float = a.distance_to(b)
	if len < 1.0:
		return
	var d: Vector2 = (b - a) / len
	var s: float = 0.0
	while s < len:
		draw_line(a + d * s, a + d * minf(s + 3.0, len), col, 1.0)
		s += 6.0
