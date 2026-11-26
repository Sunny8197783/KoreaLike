class_name GilbeTrail
extends Node2D
## 길베: 무당 뒤로 남는 흰 무명 리본(기본 4초, stat_gilbe, 신명 오름 ×2). 소유: haewon.
## 데이터: combat_core.gilbe (min_step_u 0.1, duration_base 4, sinmyeong_mult 2, width_px 6, alpha 0.35/0.7, fade_last_sec 0.5, break_jump_u 0.5)
## 링 버퍼(오래된 것 → 최신). 고리 닫힘 판정(ring_closure.gd)이 point()/time_at()/area2()/len_between() 로 읽는다.
## 누적 외적(cs)·누적 길이(ls)를 샘플과 함께 저장 → 임의 구간 [a..b] 를 닫은 폴리곤의 넓이(신발끈)를 O(1)로 구한다
##   (래스터 전 조기 탈출: 넓이 0·되돌아가기·제자리 걸음에서 래스터·플러드필을 돌지 않는다).
## 그리기: Line2D + shaders/vfx_gilbe_trail(vfx 소유 셰이더) — 무명 결 6px, 박 맥동 0.70↔1.00, 박 머리 물결, 꼬리 계단 페이드.
## 색: 백 #f2ece0 (예약색 — 길베 전용 용도 중 하나).

const CAP: int = 1024

var xs: PackedFloat32Array = PackedFloat32Array()
var ys: PackedFloat32Array = PackedFloat32Array()
var ts: PackedFloat32Array = PackedFloat32Array()
var cs: PackedFloat64Array = PackedFloat64Array()   # 누적 외적 Σ cross(p_j, p_j+1) (이 샘플까지)
var ls: PackedFloat64Array = PackedFloat64Array()   # 누적 길이(px)
var head: int = 0          # 다음 쓰기 위치
var count: int = 0

var _min_step: float = 0.1 * 32.0
var _break_jump: float = 0.5 * 32.0
var _width: float = 6.0
var _alpha0: float = 0.35
var _alpha1: float = 0.7
var _fade: float = 0.5
var _dur_base: float = 4.0
var _dur_mult: float = 2.0
var _dur_max: float = 8.0

var _line: Line2D = null
var _mat: ShaderMaterial = null
var _draw_step: float = 3.0
const P_LEN: StringName = &"length_px"
const P_PHASE: StringName = &"beat_phase"
const P_BPM: StringName = &"bpm"
const P_YG: StringName = &"yeongga_count"
const P_WIDTH: StringName = &"width_px"


func _ready() -> void:
	xs.resize(CAP)
	ys.resize(CAP)
	ts.resize(CAP)
	cs.resize(CAP)
	ls.resize(CAP)
	_min_step = Data.num("combat_core", "gilbe.min_step_u", 0.1) * K.UNIT_PX
	_break_jump = Data.num("combat_core", "gilbe.break_jump_u", 0.5) * K.UNIT_PX
	_width = Data.num("combat_core", "gilbe.width_px", 6.0)
	_alpha0 = Data.num("combat_core", "gilbe.alpha_no_yeongga", 0.35)
	_alpha1 = Data.num("combat_core", "gilbe.alpha_with_yeongga", 0.7)
	_fade = Data.num("combat_core", "gilbe.fade_last_sec", 0.5)
	_dur_base = Data.num("combat_core", "gilbe.duration_base", 4.0)
	_dur_mult = Data.num("combat_core", "gilbe.sinmyeong_mult", 2.0)
	_dur_max = Data.num("combat_core", "gilbe.duration_max", 8.0)
	z_index = -1
	_line = Line2D.new()
	_line.width = _width
	_line.antialiased = false
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_NONE
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	var img: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_line.texture = ImageTexture.create_from_image(img)
	_line.default_color = Color.WHITE
	var sh: Shader = load("res://assets/vfx/vfx_gilbe_trail.gdshader") as Shader
	if sh != null:
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter(P_WIDTH, _width)
		_line.material = _mat
	else:
		_line.default_color = Color(K.COL_BAEK, 0.6)
	add_child(_line)


func duration() -> float:
	var d: float = Game.stat(&"stat_gilbe", _dur_base)
	if Game.sinmyeong_oreum:
		d *= _dur_mult
	return minf(d, _dur_max * 2.0)


func _idx(k: int) -> int:
	return (head - count + k + CAP * 2) % CAP


func point(k: int) -> Vector2:
	var i: int = _idx(k)
	return Vector2(xs[i], ys[i])


func time_at(k: int) -> float:
	return ts[_idx(k)]


## 구간 [a..b] 를 직선으로 닫은 폴리곤의 부호 있는 넓이 ×2 (px²). O(1).
func area2(a: int, b: int) -> float:
	var ia: int = _idx(a)
	var ib: int = _idx(b)
	var closing: float = float(xs[ib]) * float(ys[ia]) - float(xs[ia]) * float(ys[ib])
	return (cs[ib] - cs[ia]) + closing


## 구간 [a..b] 의 경로 길이(px). O(1).
func len_between(a: int, b: int) -> float:
	return ls[_idx(b)] - ls[_idx(a)]


## 누적 길이(px, 단조 증가).
func len_at(k: int) -> float:
	return ls[_idx(k)]


## [lo..hi] 에서 누적 길이 ≥ target 인 첫 k (없으면 hi + 1). 이분 탐색 O(log n).
func first_len_at_least(target: float, lo: int, hi: int) -> int:
	var a: int = lo
	var b: int = hi + 1
	while a < b:
		var m: int = (a + b) >> 1
		if ls[_idx(m)] >= target:
			b = m
		else:
			a = m + 1
	return a


func clear() -> void:
	count = 0


## 가장 최신 keep 개만 남기고 지운다(고리 닫힘 후 소비).
func consume_keep_last(keep: int) -> void:
	count = mini(count, keep)


## 틱 4: 샘플 기록.
func sim_record(_dt: float) -> void:
	if Game.player == null:
		return
	var p: Vector2 = Game.player.global_position
	var t: float = Game.time_sec()
	var c_prev: float = 0.0
	var l_prev: float = 0.0
	if count > 0:
		var li: int = _idx(count - 1)
		var last: Vector2 = Vector2(xs[li], ys[li])
		var d: float = last.distance_to(p)
		if d > _break_jump * 4.0:
			clear()  # 순간이동 등 — 궤적 끊김
		elif d < _min_step:
			_expire(t)
			return
		else:
			c_prev = cs[li] + (float(last.x) * float(p.y) - float(p.x) * float(last.y))
			l_prev = ls[li] + d
	xs[head] = p.x
	ys[head] = p.y
	ts[head] = t
	cs[head] = c_prev
	ls[head] = l_prev
	head = (head + 1) % CAP
	count = mini(count + 1, CAP)
	_expire(t)


func _expire(t: float) -> void:
	var dur: float = duration()
	while count > 0 and t - time_at(0) > dur:
		count -= 1


## 렌더: 샘플을 3px 간격으로 솎아 Line2D 점을 제자리 갱신(할당 없음), 머리는 플레이어 렌더 발 좌표.
func _process(_delta: float) -> void:
	var pl: Player = Game.player as Player
	var m: int = 0
	var length: float = 0.0
	if count >= 2 and pl != null:
		var prev: Vector2 = point(0)
		_set_pt(m, prev)
		m += 1
		for k in range(1, count):
			var p: Vector2 = point(k)
			var d: float = p.distance_to(prev)
			if d >= _draw_step or k == count - 1:
				length += d
				_set_pt(m, p.round())
				m += 1
				prev = p
		var hp: Vector2 = pl.render_pos
		if hp == Vector2.ZERO or hp.distance_squared_to(prev) > 4096.0:
			hp = point(count - 1)   # 첫 렌더 전·순간이동: 마지막 샘플
		length += hp.distance_to(prev)
		_set_pt(m, hp)
		m += 1
	while _line.get_point_count() > m:
		_line.remove_point(_line.get_point_count() - 1)
	_line.visible = m >= 2
	if _mat != null and m >= 2:
		var yc: int = 0
		var yt: YeonggaTrain = _yeongga()
		if yt != null:
			yc = yt.count
		_mat.set_shader_parameter(P_LEN, maxf(length, 1.0))
		_mat.set_shader_parameter(P_PHASE, Beat.beat_phase())
		_mat.set_shader_parameter(P_BPM, Beat.bpm)
		# 영가 0명 50% 는 셰이더가 처리(캐논 '희미하게'). 닫을 수 있는 고리가 생기면(가이드) 길베를 온전히 밝혀 '이 흰 길을 묶어라'를 보인다.
		var guide: bool = _ring != null and _ring.guide_on
		_mat.set_shader_parameter(P_YG, maxi(yc, 1) if guide else yc)
		_line.default_color = Color.WHITE


func _set_pt(i: int, p: Vector2) -> void:
	if i < _line.get_point_count():
		_line.set_point_position(i, p)
	else:
		_line.add_point(p)


var _ring: RingClosure = null


func _yeongga() -> YeonggaTrain:
	if _ring == null and Game.run_root != null:
		_ring = Game.run_root.get("ring") as RingClosure
	if Game.run_root == null:
		return null
	return Game.run_root.get("yeongga") as YeonggaTrain
