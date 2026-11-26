extends RefCounted
## 화신(化身) 시뮬레이션: 이동·패턴·바닥 텔레그래프·화신 탄. 소유: deities.
## 규칙(06 §3.6): 접촉 피해 없음 · 텔레그래프 공격만 피해 · **비치명**(정기 1 미만 불가) · 발동 시각은 장단 그리드에 스냅 ·
##   P1 0~10s / P2 t≥10 또는 위엄≥40% / P3 t≥20 또는 위엄≥75% · 패턴 뒤 '숨 고르기'(받는 시험 ×1.5).
## 화신은 EnemyManager 개체가 아니다 → 무구로 죽일 수 없다("신령은 적으로 죽이지 않는다"). 위엄 시험 타격은
##   TrialDirector 가 무구 발사(Events.weapon_fired) 사거리 판정으로 계산한다.
## 할당: 텔레그래프·탄은 고정 용량 Packed 배열. 패턴 시작(이벤트 시점)에서만 Dictionary 를 읽는다.

const Defs := preload("res://deities/deity_defs.gd")

enum Shape { CIRCLE, RECT, RING, SWEEP }
enum St { IDLE, MOVE, CAST, DASH, VULN, HIDDEN, SMILE }

const F_FIRED: int = 1
const F_HIT_DONE: int = 2
const F_NO_DMG: int = 4
const F_SLOW: int = 8
const F_DASH: int = 16
const F_PULL: int = 32
const F_EXPAND: int = 64       # RING 반경이 시간에 따라 변함(퍼짐/좁힘)
const F_SNAP_PLAYER: int = 128 # 발동 시 플레이어 위치 고정(이미 고정)

const TG_CAP: int = 48
const B_CAP: int = 320
const PLAYER_R_U: float = 0.35

var deity: StringName = &""
var n: int = 1
var pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO
var anchor: Vector2 = Vector2.ZERO
var state: int = St.IDLE
var anim: StringName = &"idle"
var anim_t0: float = 0.0           # 연출 시계 기준 애니 시작
var face_x: float = 1.0
var phase: int = 1
var vuln_until: float = -1.0
var hidden_until: float = -1.0
var busy_until: float = 0.0
var flash_until: float = -1.0      # 피격 플래시(게임 초)
var nod_until: float = -1.0        # 무당 적중 시 끄덕임
var alpha: float = 1.0             # 잠수·순간이동 페이드
var body_r_px: float = 28.0
var size_px: int = 128
var keep_min: float = 4.0 * 32.0
var keep_max: float = 7.0 * 32.0
var speed_px: float = 2.6 * 32.0
var leash_px: float = 11.0 * 32.0
var dmg_scale: float = 1.0
var period_scale: float = 1.0
var speed_scale: float = 1.0
var hits_on_player: int = 0
var tether_until: float = -1.0
var tether_max_px: float = 320.0
var tether_dmg: float = 10.0
var _tether_next: float = 0.0
var orbit_a: float = 0.0           # 장군 4신장 공전 각
var slow_until: float = -1.0       # 포효·시루 둔화(무당)
var slow_pct: float = 0.0

# 패턴 표
var pats: Array[Dictionary] = []
var pat_timer: PackedFloat32Array = PackedFloat32Array()
var pat_enabled: PackedByteArray = PackedByteArray()
var _queue: Array[Dictionary] = []    # 연속 발동(겹돌진·세 갈래·순차 강타) 예약 {at, kind, ...} — 이벤트 시점 할당
var _now: float = 0.0
var _rng: RandomNumberGenerator

# 돌진
var dash_from: Vector2 = Vector2.ZERO
var dash_to: Vector2 = Vector2.ZERO
var dash_t0: float = 0.0
var dash_t1: float = 0.0
var dash_w_px: float = 19.0
var dash_dmg: float = 0.0
var dash_hit: bool = false

# 텔레그래프 SoA
var tg_on: PackedByteArray = PackedByteArray()
var tg_shape: PackedByteArray = PackedByteArray()
var tg_flags: PackedInt32Array = PackedInt32Array()
var tg_x: PackedFloat32Array = PackedFloat32Array()
var tg_y: PackedFloat32Array = PackedFloat32Array()
var tg_dx: PackedFloat32Array = PackedFloat32Array()
var tg_dy: PackedFloat32Array = PackedFloat32Array()
var tg_a: PackedFloat32Array = PackedFloat32Array()      # 원 반경 / 사각 길이 / 고리 바깥 반경 / 쓸기 반폭
var tg_b: PackedFloat32Array = PackedFloat32Array()      # 사각 폭 / 고리 두께 / 쓸기 두께
var tg_c: PackedFloat32Array = PackedFloat32Array()      # 고리·쓸기 틈 각(rad) 또는 틈 오프셋
var tg_v: PackedFloat32Array = PackedFloat32Array()      # 반경 변화 속도(px/s) 또는 쓸기 속도
var tg_t0: PackedFloat32Array = PackedFloat32Array()
var tg_t1: PackedFloat32Array = PackedFloat32Array()     # 발동 시각
var tg_life: PackedFloat32Array = PackedFloat32Array()   # 발동 후 지속(0 = 순간)
var tg_tick: PackedFloat32Array = PackedFloat32Array()
var tg_next: PackedFloat32Array = PackedFloat32Array()
var tg_dmg: PackedFloat32Array = PackedFloat32Array()    # 최대 정기 % (n 배율 전)
var tg_count: int = 0                                     # 표시용 활성 수

# 화신 탄 SoA(청 테두리·흑 코어)
var b_on: PackedByteArray = PackedByteArray()
var bx: PackedFloat32Array = PackedFloat32Array()
var by: PackedFloat32Array = PackedFloat32Array()
var bvx: PackedFloat32Array = PackedFloat32Array()
var bvy: PackedFloat32Array = PackedFloat32Array()
var blife: PackedFloat32Array = PackedFloat32Array()
var brad: PackedFloat32Array = PackedFloat32Array()
var bdmg: PackedFloat32Array = PackedFloat32Array()
var b_count: int = 0

# 이벤트(연출용, 시뮬이 채우고 view/director 가 읽는다): 이번 틱 발동 지점
var fired_ev: Array[Vector3] = []     # (x, y, radius_px) — 이벤트 시점만 append
var player_hit_ev: int = 0


func _init() -> void:
	# Packed 배열은 값 타입 → 하나씩 resize(루프 변수로 하면 사본만 바뀐다)
	tg_x.resize(TG_CAP)
	tg_y.resize(TG_CAP)
	tg_dx.resize(TG_CAP)
	tg_dy.resize(TG_CAP)
	tg_a.resize(TG_CAP)
	tg_b.resize(TG_CAP)
	tg_c.resize(TG_CAP)
	tg_v.resize(TG_CAP)
	tg_t0.resize(TG_CAP)
	tg_t1.resize(TG_CAP)
	tg_life.resize(TG_CAP)
	tg_tick.resize(TG_CAP)
	tg_next.resize(TG_CAP)
	tg_dmg.resize(TG_CAP)
	tg_on.resize(TG_CAP)
	tg_shape.resize(TG_CAP)
	tg_flags.resize(TG_CAP)
	bx.resize(B_CAP)
	by.resize(B_CAP)
	bvx.resize(B_CAP)
	bvy.resize(B_CAP)
	blife.resize(B_CAP)
	brad.resize(B_CAP)
	bdmg.resize(B_CAP)
	b_on.resize(B_CAP)
	_rng = Rng.stream(&"trial")


func setup(p_deity: StringName, p_n: int, p_anchor: Vector2, start_pos: Vector2, now: float) -> void:
	deity = p_deity
	n = p_n
	anchor = p_anchor
	pos = start_pos
	prev_pos = start_pos
	_now = now
	var d: Dictionary = Data.deity(String(deity))
	var av: Dictionary = d.get("avatar", {})
	var c: Dictionary = Data.get_value("deities", "constants", {})
	size_px = int(av.get("size_px", 128))
	body_r_px = clampf(float(size_px) * 0.2, 14.0, 34.0)
	var kd: Variant = av.get("keep_distance", null)
	if kd is Array and (kd as Array).size() >= 2:
		keep_min = float(kd[0]) * K.UNIT_PX
		keep_max = float(kd[1]) * K.UNIT_PX
	speed_scale = 1.0 + float(c.get("avatar_speed_scale_per_n", 0.07)) * float(n - 1)
	speed_px = float(av.get("move_speed", 2.6)) * K.UNIT_PX * speed_scale
	leash_px = float(c.get("avatar_leash", 11)) * K.UNIT_PX
	dmg_scale = 1.0 + float(c.get("avatar_damage_scale_per_n", 0.2)) * float(n - 1)
	period_scale = maxf(0.5, 1.0 + float(c.get("pattern_period_scale_per_n", -0.08)) * float(n - 1))
	pats.clear()
	var arr: Variant = av.get("patterns", [])
	if arr is Array:
		for p: Variant in arr:
			if p is Dictionary:
				pats.append(p)
	# 슬롯 3·4: 탄막·돌진을 덧붙여 시련 후반을 위협적으로(data constants.avatar_extra_patterns, 2026-11-24 리뷰)
	var ex: Dictionary = c.get("avatar_extra_patterns", {})
	if not ex.is_empty() and n >= int(ex.get("min_n", 3)):
		var rd: Dictionary = ex.get("radial", {})
		if not rd.is_empty():
			pats.append({"id": "extra_radial", "phase_min": 1, "period_s": float(rd.get("period_s", 7.5)), "tg_s": float(rd.get("tg_s", 0.9)),
				"damage_pct_max_jeonggi": float(rd.get("damage_pct_max_jeonggi", 6)),
				"hit": {"shape": "spiral_bullets", "ways": int(rd.get("ways", 12)), "waves": int(rd.get("waves", 2)) + (1 if n >= 4 else 0), "speed": float(rd.get("speed", 4.2))}})
		var dd: Dictionary = ex.get("dash", {})
		if not dd.is_empty():
			pats.append({"id": "extra_dash", "phase_min": 1, "period_s": float(dd.get("period_s", 6.5)), "tg_s": float(dd.get("tg_s", 0.8)),
				"damage_pct_max_jeonggi": float(dd.get("damage_pct_max_jeonggi", 8)),
				"hit": {"shape": "line", "length": float(dd.get("length", 9)), "width": float(dd.get("width", 1.4)), "speed": float(dd.get("speed", 15))}})
	pat_timer.resize(pats.size())
	pat_enabled.resize(pats.size())
	for i in pats.size():
		# 첫 발동을 엇갈리게: 주기의 35~70%
		pat_timer[i] = float(pats[i].get("period_s", 6.0)) * period_scale * _rng.randf_range(0.35, 0.7)
	_set_phase(1)
	clear_attacks()
	state = St.IDLE
	alpha = 1.0
	hits_on_player = 0
	tether_until = -1.0


func clear_attacks() -> void:
	tg_on.fill(0)
	b_on.fill(0)
	tg_count = 0
	b_count = 0
	_queue.clear()
	if state == St.DASH:
		state = St.IDLE


func _set_phase(p: int) -> void:
	phase = p
	var replaced: Dictionary = {}
	for i in pats.size():
		var pm: int = int(pats[i].get("phase_min", 1))
		var hit: Dictionary = pats[i].get("hit", {})
		if pm <= phase and hit.has("replaces"):
			replaced[String(hit["replaces"])] = true
	for i in pats.size():
		var pm: int = int(pats[i].get("phase_min", 1))
		pat_enabled[i] = 1 if (pm <= phase and not replaced.has(String(pats[i].get("id", "")))) else 0


func set_phase(p: int) -> void:
	if p == phase:
		return
	_set_phase(p)
	# P2 진입 트리거 패턴(칠성 명실 시험)
	for i in pats.size():
		var hit: Dictionary = pats[i].get("hit", {})
		if pat_enabled[i] == 1 and String(hit.get("trigger", "")) == "on_phase2_enter" and p == 2:
			_start_pattern(i)


func targetable() -> bool:
	return state != St.HIDDEN and state != St.SMILE and _now >= hidden_until


func is_vulnerable() -> bool:
	return _now < vuln_until


## 시련 해결: 공격 정리 + 미소(위엄 웃음 / 가호 읍).
func smile() -> void:
	clear_attacks()
	state = St.SMILE
	anim = &"idle"
	alpha = 1.0
	tether_until = -1.0


# ─── 틱 ────────────────────────────────────────────────────────────────

func sim_step(dt: float, now: float, player_pos: Vector2) -> void:
	_now = now
	prev_pos = pos
	fired_ev.clear()
	player_hit_ev = 0
	orbit_a = wrapf(orbit_a + dt * 0.9, 0.0, TAU)
	if state == St.SMILE:
		return
	# 예약 발동
	var qi: int = 0
	while qi < _queue.size():
		var q: Dictionary = _queue[qi]
		if now >= float(q["at"]):
			_queue.remove_at(qi)
			_run_queued(q, player_pos)
		else:
			qi += 1
	# 상태
	match state:
		St.DASH:
			var k: float = clampf((now - dash_t0) / maxf(0.001, dash_t1 - dash_t0), 0.0, 1.0)
			pos = dash_from.lerp(dash_to, k)
			if not dash_hit and dash_dmg > 0.0 and _seg_dist(player_pos, prev_pos, pos) <= dash_w_px * 0.5 + PLAYER_R_U * K.UNIT_PX:
				dash_hit = true
				_hurt_player(dash_dmg, player_pos)
			if k >= 1.0:
				state = St.IDLE
		St.HIDDEN:
			alpha = maxf(0.0, alpha - dt * 3.0)
			if now >= hidden_until:
				state = St.IDLE
				alpha = 0.0
		_:
			if alpha < 1.0:
				alpha = minf(1.0, alpha + dt * 2.5)
			if now >= busy_until and state == St.CAST:
				state = St.IDLE
			if state != St.CAST:
				_move(dt, player_pos)
				_tick_patterns(dt)
	_tick_tgs(dt, now, player_pos)
	_tick_bullets(dt, player_pos)
	if tether_until > now and state != St.SMILE:
		if pos.distance_to(player_pos) > tether_max_px and now >= _tether_next:
			_tether_next = now + 1.0
			_hurt_player(tether_dmg, player_pos)
	if now >= vuln_until and state == St.VULN:
		state = St.IDLE


func _move(dt: float, pp: Vector2) -> void:
	var to_p: Vector2 = pp - pos
	var d: float = to_p.length()
	var want: Vector2 = Vector2.ZERO
	if d > keep_max:
		want = to_p / maxf(d, 1.0)
	elif d < keep_min:
		want = -to_p / maxf(d, 1.0)
	# 느린 공전(잡귀처럼 쫓지 않고 '맞서 선다')
	if d > 1.0:
		var tang: Vector2 = Vector2(-to_p.y, to_p.x) / d
		want += tang * 0.35
	var from_a: Vector2 = pos - anchor
	if from_a.length() > leash_px:
		want = -from_a.normalized()
	if want.length_squared() > 0.0001:
		want = want.normalized()
		pos += want * speed_px * dt
		if absf(want.x) > 0.2:
			face_x = signf(want.x)
		if state == St.IDLE:
			state = St.MOVE
	elif state == St.MOVE:
		state = St.IDLE
	if state == St.MOVE or state == St.IDLE:
		anim = &"move" if state == St.MOVE else &"idle"
	if absf(to_p.x) > 8.0 and state != St.MOVE:
		face_x = signf(to_p.x)


func _tick_patterns(dt: float) -> void:
	for i in pats.size():
		if pat_enabled[i] == 0:
			continue
		var per: float = float(pats[i].get("period_s", 6.0))
		if per <= 0.0:
			continue
		pat_timer[i] -= dt
		if pat_timer[i] <= 0.0 and _now >= busy_until:
			pat_timer[i] = per * period_scale
			_start_pattern(i)
			return


# ─── 패턴 ──────────────────────────────────────────────────────────────

func _pp() -> Vector2:
	return Game.player.global_position if Game.player != null else pos


## 텔레그래프 지연을 장단 그리드에 스냅(06 §3.6: 표 값 이상, 최대 +1그리드).
func _snap(delay: float) -> float:
	var bnow: float = Game.beat_sec()
	var t: float = Beat.next_grid_time(bnow + delay)
	return clampf(t - bnow, delay, delay + Beat.grid_sec() + 0.001)


func _start_pattern(i: int) -> void:
	var p: Dictionary = pats[i]
	var hit: Dictionary = p.get("hit", {})
	var tg: float = _snap(float(p.get("tg_s", 0.8)))
	var dmg: float = float(p.get("damage_pct_max_jeonggi", 10))
	var vul: float = float(p.get("vulnerable_s", 0.0))
	var shape: String = String(hit.get("shape", "circle"))
	var pp: Vector2 = _pp()
	var dirp: Vector2 = (pp - pos).normalized() if pp.distance_squared_to(pos) > 1.0 else Vector2(face_x, 0)
	var busy: float = tg + 0.3
	anim = &"attack"
	anim_t0 = Game.anim_time()
	Audio.play_sfx(&"sfx_trl_avatar_telegraph", &"SFX", -6.0, 0.05)
	match shape:
		"line":
			_q_dash(dirp, float(hit.get("length", 10)), float(hit.get("width", 1.2)), float(hit.get("speed", 14)), tg, dmg, 0.0)
			busy = tg + float(hit.get("length", 10)) / maxf(1.0, float(hit.get("speed", 14))) + 0.1
		"line_x2":
			var base: Dictionary = _pat_by_id("sansin_p_dolgin")
			var bh: Dictionary = base.get("hit", hit)
			var ln: float = float(bh.get("length", 10))
			var sp: float = float(bh.get("speed", 14)) + 1.3 * float(n - 1)
			_q_dash(dirp, ln, float(bh.get("width", 1.2)), sp, tg, dmg, 0.0)
			var t2: float = tg + ln / sp + _snap(float(hit.get("second_tg_s", 0.5)))
			_queue.append({"at": _now + tg + ln / sp + 0.02, "kind": "dash", "len": ln, "w": float(bh.get("width", 1.2)), "spd": sp, "tg": t2 - tg - ln / sp, "dmg": dmg})
			busy = t2 + ln / sp + 0.1
		"triangle_x3":
			var ln3: float = 7.0
			var sp3: float = 14.0 + 1.3 * float(n - 1)
			var leg: float = _snap(float(hit.get("leg_s", 0.45)))
			_q_dash(dirp, ln3, 1.2, sp3, tg, dmg, 0.0)
			var t_acc: float = tg + ln3 / sp3
			for k in 2:
				_queue.append({"at": _now + t_acc + 0.02, "kind": "dash", "len": ln3, "w": 1.2, "spd": sp3, "tg": leg, "dmg": dmg, "rot": 2.094 * float(k + 1)})
				t_acc += leg + ln3 / sp3
			busy = t_acc + 0.1
			anim = &"charge"
		"circle":
			var r: float = float(hit.get("radius", 5)) * K.UNIT_PX
			var flags: int = F_NO_DMG if dmg <= 0.0 else 0
			var st: Variant = hit.get("player_status", null)
			if st is Dictionary:
				flags |= F_SLOW
				slow_pct = absf(float((st as Dictionary).get("domu_pct", -40))) / 100.0
			_add_tg(Shape.CIRCLE, pos, Vector2.ZERO, r, 0.0, 0.0, 0.0, tg, 0.0, 0.0, dmg, flags)
			anim = &"roar"
		"circles":
			var cnt: int = int(hit.get("count", 3))
			var rr: float = float(hit.get("radius", 1.2)) * K.UNIT_PX
			var sc: float = float(hit.get("scatter_radius", 4)) * K.UNIT_PX
			for k in cnt:
				var off: Vector2 = Vector2.ZERO if k == 0 else Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.4, 1.0) * sc
				_add_tg(Shape.CIRCLE, pp + off, Vector2.ZERO, rr, 0.0, 0.0, 0.0, tg, 0.0, 0.0, dmg, 0)
		"fan_bullets":
			var ways: int = int(hit.get("bullets", hit.get("ways", 9)))
			var ang: float = deg_to_rad(float(hit.get("angle_deg", 60)))
			_queue.append({"at": _now + tg, "kind": "fan", "ways": ways, "ang": ang, "spd": float(hit.get("speed", 5)), "dmg": dmg, "r": float(hit.get("bullet_radius", 0.25))})
			_add_tg(Shape.RECT, pos, dirp, 3.0 * K.UNIT_PX, 0.6 * K.UNIT_PX, 0.0, 0.0, tg, 0.0, 0.0, 0.0, F_NO_DMG)
		"spiral_bullets", "rotating_radial", "spin_push_ring":
			var total: int = int(hit.get("bullets", hit.get("ring_bullets", int(hit.get("ways", 7)) * int(hit.get("waves", 2)))))
			if shape == "rotating_radial" and n >= 4:
				total = int(hit.get("ways", 7)) * int(hit.get("waves_n4plus", 3))
			_queue.append({"at": _now + tg, "kind": "radial", "total": total, "ways": int(hit.get("ways", 8)), "spd": float(hit.get("speed", 4)), "dmg": dmg, "spiral": shape != "spin_push_ring"})
			_add_tg(Shape.RING, pos, Vector2.ZERO, body_r_px + 18.0, 6.0, 0.0, 0.0, tg, 0.0, 0.0, 0.0, F_NO_DMG)
			busy = tg + 1.0
		"wall":
			var wd: float = float(hit.get("width", 8)) * K.UNIT_PX * 0.5
			var gap: float = float(hit.get("gap", 2.0)) * K.UNIT_PX
			var gap_off: float = _rng.randf_range(-wd * 0.6, wd * 0.6)
			_add_tg(Shape.SWEEP, pos, dirp, wd, 0.5 * K.UNIT_PX, gap_off, float(hit.get("speed", 3)) * K.UNIT_PX, tg, 4.0, 0.0, dmg, 0, gap)
		"rolling_logs":
			var lanes: int = int(hit.get("lanes", 3))
			var sp_l: float = float(hit.get("lane_spacing", 2)) * K.UNIT_PX
			var perp: Vector2 = Vector2(-dirp.y, dirp.x)
			for k in lanes:
				var o: Vector2 = pos + perp * (float(k) - float(lanes - 1) * 0.5) * sp_l
				_add_tg(Shape.RECT, o, dirp, 12.0 * K.UNIT_PX, float(hit.get("lane_width", 1.2)) * K.UNIT_PX, 0.0, 0.0, tg, 0.0, 0.0, 0.0, F_NO_DMG)
			_queue.append({"at": _now + tg, "kind": "logs", "lanes": lanes, "sp": sp_l, "dir": dirp, "spd": float(hit.get("speed", 6)), "dmg": dmg, "w": float(hit.get("lane_width", 1.2))})
		"teleport_spring":
			state = St.HIDDEN
			hidden_until = _now + float(hit.get("untargetable_s", 2.0))
			_queue.append({"at": hidden_until, "kind": "reappear"})
			busy = hidden_until - _now + 0.2
		"whirlpools", "embers":
			var cntw: int = int(hit.get("count", 3))
			var rw: float = float(hit.get("radius", 1.5)) * K.UNIT_PX
			var dur: float = float(hit.get("dur_s", 4.0))
			for k in cntw:
				var offw: Vector2 = Vector2.from_angle(TAU * float(k) / float(cntw) + _rng.randf() * 0.8) * _rng.randf_range(1.5, 3.5) * K.UNIT_PX
				_add_tg(Shape.CIRCLE, pp + offw, Vector2.ZERO, rw, 0.0, 0.0, 0.0, tg, dur, float(hit.get("tick_s", 0.5)), dmg * 0.5, F_PULL if shape == "whirlpools" else 0)
		"dipper_circles", "dipper_circles_x2":
			var cntd: int = int(hit.get("count", 7))
			var rd: float = float(hit.get("radius", 1.0)) * K.UNIT_PX
			_dipper(pp, rd, tg, dmg, 0.0, cntd)
			if shape == "dipper_circles_x2":
				_dipper(pp, rd, tg + _snap(float(hit.get("second_tg_s", 0.6))), dmg, deg_to_rad(float(hit.get("rotate_deg", 51.4))), cntd)
				busy = tg + 1.0
		"tether":
			tether_until = _now + float(hit.get("dur_s", 10))
			tether_max_px = float(hit.get("max_dist", 10)) * K.UNIT_PX
			tether_dmg = dmg
			_tether_next = _now + 1.0
			busy = 0.4
		"4_lines_sequential":
			var order: Array = hit.get("order", ["east", "south", "west", "north"])
			var lnl: float = float(hit.get("length_n3plus", hit.get("length", 6))) if n >= 3 else float(hit.get("length", 6))
			var off_l: float = float(hit.get("offset", 7)) * K.UNIT_PX
			var step: float = float(hit.get("interval_beats", 0.5)) * Beat.beat_len_sec()
			for k in order.size():
				var dv: Vector2 = _dir_named(String(order[k]))
				_add_tg(Shape.RECT, pp + dv * off_l, -dv, lnl * K.UNIT_PX, float(hit.get("width", 1)) * K.UNIT_PX, 0.0, 0.0, tg + step * float(k), 0.0, 0.0, dmg, 0)
			busy = tg + step * float(order.size()) + 0.2
		"closing_square":
			var r_from: float = float(hit.get("side_from", 14)) * 0.5 * K.UNIT_PX
			var r_to: float = float(hit.get("side_to", 6)) * 0.5 * K.UNIT_PX
			var dur_c: float = float(hit.get("dur_s", 3.0))
			var gap_a: float = float(hit.get("gap", 2.0)) / maxf(1.0, r_to / K.UNIT_PX)
			_add_tg(Shape.RING, pp, Vector2.from_angle(_rng.randf() * TAU), r_from, 0.5 * K.UNIT_PX, gap_a, -(r_from - r_to) / dur_c, tg, dur_c, float(hit.get("tick_s", 0.5)), dmg, F_EXPAND)
		"arc":
			var dash_d: float = float(hit.get("dash", 2))
			_q_dash(dirp, dash_d, 1.0, 10.0, tg * 0.5, 0.0, 0.0)
			_add_tg(Shape.CIRCLE, pos + dirp * dash_d * K.UNIT_PX, Vector2.ZERO, float(hit.get("radius", 3)) * K.UNIT_PX, 0.0, 0.0, 0.0, tg, 0.0, 0.0, dmg, 0)
		"sequential_slams":
			var ordr: Array = hit.get("order", ["east", "south", "center", "west", "north"])
			var rs: float = float(hit.get("radius", 2.5)) * K.UNIT_PX
			var stp: float = float(hit.get("interval_beats", 1)) * Beat.beat_len_sec()
			for k in ordr.size():
				var dvs: Vector2 = _dir_named(String(ordr[k]))
				_add_tg(Shape.CIRCLE, anchor + dvs * 5.0 * K.UNIT_PX, Vector2.ZERO, rs, 0.0, 0.0, 0.0, tg + stp * float(k), 0.0, 0.0, dmg, 0)
			busy = tg + stp * float(ordr.size())
		"ripple_rings":
			var cr: int = int(hit.get("count", 3))
			var gapr: float = deg_to_rad(float(hit.get("gap_deg", 60)))
			for k in cr:
				_add_tg(Shape.RING, pos, Vector2.from_angle(_rng.randf() * TAU), body_r_px, 0.45 * K.UNIT_PX, gapr, float(hit.get("expand_speed", 2.5)) * K.UNIT_PX, tg + 0.7 * float(k), 4.0, 0.0, dmg, F_EXPAND)
			busy = tg + 0.7 * float(cr)
		"3_lines":
			var l3: float = float(hit.get("length", 5)) * K.UNIT_PX
			for k in 3:
				_add_tg(Shape.RECT, pos, dirp.rotated(deg_to_rad(-22.0 + 22.0 * float(k))), l3, 0.9 * K.UNIT_PX, 0.0, 0.0, tg, 0.0, 0.0, dmg, 0)
		"circle_zone":
			slow_pct = absf(float(hit.get("player_domu_pct", -35))) / 100.0
			_add_tg(Shape.CIRCLE, pp, Vector2.ZERO, float(hit.get("radius", 2.5)) * K.UNIT_PX, 0.0, 0.0, 0.0, tg, float(hit.get("dur_s", 4.0)), 0.25, 0.0, F_NO_DMG | F_SLOW)
		"orb_vacuum":
			_add_tg(Shape.RING, pos, Vector2.ZERO, float(hit.get("radius", 6)) * K.UNIT_PX, 0.3 * K.UNIT_PX, 0.0, -float(hit.get("radius", 6)) * K.UNIT_PX / maxf(0.5, float(hit.get("dur_s", 3.0))), tg, float(hit.get("dur_s", 3.0)), 0.0, 0.0, F_NO_DMG | F_EXPAND)
			vul = maxf(vul, float(hit.get("dur_s", 3.0)))   # 삼키는 동안 맞히면 토해 낸다 → 숨 고르기 창으로 취급
		"combo":
			var parts: Dictionary = hit.get("parts", {})
			var t_c: float = 0.0
			for pid: Variant in parts.keys():
				var cnt_c: int = int(parts[pid])
				for k in cnt_c:
					_queue.append({"at": _now + t_c, "kind": "pattern", "id": String(pid)})
					t_c += 1.3
			busy = t_c + 0.3
		_:
			_add_tg(Shape.CIRCLE, pp, Vector2.ZERO, 1.5 * K.UNIT_PX, 0.0, 0.0, 0.0, tg, 0.0, 0.0, dmg, 0)
	if state != St.HIDDEN and state != St.DASH:
		state = St.CAST
	busy_until = _now + busy
	if vul > 0.0:
		_queue.append({"at": _now + busy, "kind": "vuln", "dur": vul})


func _pat_by_id(id: String) -> Dictionary:
	for p: Dictionary in pats:
		if String(p.get("id", "")) == id:
			return p
	return {}


func _dir_named(s: String) -> Vector2:
	match s:
		"east":
			return Vector2.RIGHT
		"west":
			return Vector2.LEFT
		"north":
			return Vector2.UP
		"south":
			return Vector2.DOWN
	return Vector2.ZERO


## 북두칠성 7점(국자 4 + 자루 3). 플레이어 중심, 너비 약 7유닛.
func _dipper(c: Vector2, r: float, delay: float, dmg: float, rot: float, cnt: int) -> void:
	var pts: PackedVector2Array = [Vector2(-3.2, -0.6), Vector2(-1.9, -1.2), Vector2(-0.6, -0.5), Vector2(-0.9, 0.8), Vector2(0.8, 0.9), Vector2(2.1, 0.4), Vector2(3.4, 1.0)]
	for k in mini(cnt, pts.size()):
		var p: Vector2 = pts[k].rotated(rot) * K.UNIT_PX * 1.05
		_add_tg(Shape.CIRCLE, c + p, Vector2.ZERO, r, 0.0, 0.0, 0.0, delay + 0.06 * float(k), 0.0, 0.0, dmg, 0)


func _q_dash(dirv: Vector2, len_u: float, w_u: float, spd_u: float, tg: float, dmg: float, _rot: float) -> void:
	var L: float = len_u * K.UNIT_PX
	_add_tg(Shape.RECT, pos, dirv, L + body_r_px, w_u * K.UNIT_PX, 0.0, 0.0, tg, 0.0, 0.0, 0.0, F_NO_DMG | F_DASH)
	_queue.append({"at": _now + tg, "kind": "dash_go", "dir": dirv, "len": L, "spd": spd_u * K.UNIT_PX, "w": w_u * K.UNIT_PX, "dmg": dmg})
	anim = &"charge"


func _run_queued(q: Dictionary, pp: Vector2) -> void:
	match String(q["kind"]):
		"dash_go":
			var dv: Vector2 = q["dir"]
			var L: float = float(q["len"])
			dash_from = pos
			dash_to = pos + dv * L
			var a2: Vector2 = dash_to - anchor
			if a2.length() > leash_px + 2.0 * K.UNIT_PX:
				dash_to = anchor + a2.normalized() * (leash_px + 2.0 * K.UNIT_PX)
			dash_t0 = _now
			dash_t1 = _now + dash_from.distance_to(dash_to) / maxf(1.0, float(q["spd"]))
			dash_w_px = float(q["w"])
			dash_dmg = float(q["dmg"])
			dash_hit = false
			state = St.DASH
			if absf(dv.x) > 0.1:
				face_x = signf(dv.x)
			anim = &"run"
			fired_ev.append(Vector3(pos.x, pos.y, 20.0))
		"dash":
			var dirp: Vector2 = (pp - pos).normalized() if pp.distance_squared_to(pos) > 1.0 else Vector2(face_x, 0)
			if q.has("rot"):
				dirp = dirp.rotated(float(q["rot"]) * 0.35)
			_q_dash(dirp, float(q["len"]), float(q["w"]), float(q["spd"]), float(q["tg"]), float(q["dmg"]), 0.0)
		"fan":
			var dirf: Vector2 = (pp - pos).normalized() if pp.distance_squared_to(pos) > 1.0 else Vector2(face_x, 0)
			var ways: int = int(q["ways"])
			var ang: float = float(q["ang"])
			for k in ways:
				var a: float = -ang * 0.5 + ang * (float(k) / maxf(1.0, float(ways - 1)))
				_spawn_bullet(pos, dirf.rotated(a) * float(q["spd"]) * K.UNIT_PX, 4.0, float(q["r"]) * K.UNIT_PX, float(q["dmg"]))
			fired_ev.append(Vector3(pos.x, pos.y, 24.0))
		"radial":
			var total: int = int(q["total"])
			var ways2: int = maxi(1, int(q["ways"]))
			var base_a: float = _rng.randf() * TAU
			for k in total:
				var a2r: float = base_a + TAU * float(k) / float(ways2) + (0.25 * float(k / ways2) if bool(q["spiral"]) else 0.0)
				var spd: float = float(q["spd"]) * K.UNIT_PX * (1.0 + 0.08 * float(k / ways2))
				_spawn_bullet(pos, Vector2.from_angle(a2r) * spd, 4.5, 0.22 * K.UNIT_PX, float(q["dmg"]))
			fired_ev.append(Vector3(pos.x, pos.y, 30.0))
		"logs":
			var dvl: Vector2 = q["dir"]
			var perp: Vector2 = Vector2(-dvl.y, dvl.x)
			var lanes: int = int(q["lanes"])
			for k in lanes:
				var o: Vector2 = pos + perp * (float(k) - float(lanes - 1) * 0.5) * float(q["sp"])
				_spawn_bullet(o, dvl * float(q["spd"]) * K.UNIT_PX, 2.2, float(q["w"]) * 0.5 * K.UNIT_PX, float(q["dmg"]))
		"reappear":
			var a: float = _rng.randf() * TAU
			pos = anchor + Vector2.from_angle(a) * _rng.randf_range(3.0, 7.0) * K.UNIT_PX
			prev_pos = pos
			state = St.IDLE
			alpha = 0.0
			fired_ev.append(Vector3(pos.x, pos.y, 40.0))
		"vuln":
			vuln_until = _now + float(q["dur"])
			if state != St.DASH and state != St.HIDDEN:
				state = St.VULN
				anim = &"idle"
		"pattern":
			var id: String = String(q["id"])
			for i in pats.size():
				if String(pats[i].get("id", "")) == id:
					var saved_busy: float = busy_until
					_start_pattern(i)
					busy_until = maxf(saved_busy, busy_until)
					break


# ─── 텔레그래프 ─────────────────────────────────────────────────────────

func _add_tg(shape: int, p: Vector2, d: Vector2, a: float, b: float, c: float, v: float, delay: float, life: float, tick: float, dmg: float, flags: int, extra_gap: float = 0.0) -> int:
	for i in TG_CAP:
		if tg_on[i] == 0:
			tg_on[i] = 1
			tg_shape[i] = shape
			tg_flags[i] = flags
			tg_x[i] = p.x
			tg_y[i] = p.y
			tg_dx[i] = d.x
			tg_dy[i] = d.y
			tg_a[i] = a
			tg_b[i] = b
			tg_c[i] = c if shape != Shape.SWEEP else c
			tg_v[i] = v
			tg_t0[i] = _now
			tg_t1[i] = _now + delay
			tg_life[i] = life
			tg_tick[i] = tick
			tg_next[i] = _now + delay
			tg_dmg[i] = dmg
			if shape == Shape.SWEEP:
				tg_tick[i] = extra_gap     # 쓸기: tick 칸에 틈 크기(px)를 둔다
			tg_count += 1
			return i
	return -1


func _tick_tgs(_dt: float, now: float, pp: Vector2) -> void:
	var pr: float = PLAYER_R_U * K.UNIT_PX
	var slowed: bool = false
	for i in TG_CAP:
		if tg_on[i] == 0:
			continue
		var f: int = tg_flags[i]
		if now < tg_t1[i]:
			if (f & F_DASH) != 0:
				# 돌진 텔레그래프는 화신을 따라 원점 갱신
				tg_x[i] = pos.x
				tg_y[i] = pos.y
			continue
		var age: float = now - tg_t1[i]
		if (f & F_FIRED) == 0:
			tg_flags[i] |= F_FIRED
			f = tg_flags[i]
			if (f & F_DASH) == 0:
				fired_ev.append(Vector3(tg_x[i], tg_y[i], tg_a[i] if tg_shape[i] == Shape.CIRCLE else 0.0))
			if (f & F_NO_DMG) == 0 and (f & F_DASH) == 0 and tg_life[i] <= 0.0 and tg_shape[i] != Shape.SWEEP:
				if _inside(i, pp, pr, 0.0):
					_hurt_player(tg_dmg[i], pp)
		# 지속형(장판·쓸기·고리)
		if tg_life[i] > 0.0:
			if (f & F_SLOW) != 0 and _inside(i, pp, pr, age):
				slowed = true
			if (f & F_NO_DMG) == 0:
				if tg_shape[i] == Shape.SWEEP or tg_shape[i] == Shape.RING:
					if (f & F_HIT_DONE) == 0 and _inside(i, pp, pr, age):
						tg_flags[i] |= F_HIT_DONE
						_hurt_player(tg_dmg[i], pp)
				elif now >= tg_next[i] and _inside(i, pp, pr, age):
					tg_next[i] = now + maxf(0.1, tg_tick[i])
					_hurt_player(tg_dmg[i], pp)
			if age >= tg_life[i]:
				tg_on[i] = 0
				tg_count -= 1
		elif (f & F_SLOW) != 0:
			if _inside(i, pp, pr, 0.0):
				slowed = true
				slow_until = now + 1.0
			tg_on[i] = 0
			tg_count -= 1
		elif age >= 0.22:
			tg_on[i] = 0
			tg_count -= 1
	if slowed:
		slow_until = maxf(slow_until, now + 0.15)


## 판정: 플레이어 원(pr)이 도형과 겹치는가.
func _inside(i: int, p: Vector2, pr: float, age: float) -> bool:
	var c: Vector2 = Vector2(tg_x[i], tg_y[i])
	match tg_shape[i]:
		Shape.CIRCLE:
			return p.distance_to(c) <= tg_a[i] + pr
		Shape.RECT:
			var d: Vector2 = Vector2(tg_dx[i], tg_dy[i])
			var rel: Vector2 = p - c
			var along: float = rel.dot(d)
			var side: float = absf(rel.dot(Vector2(-d.y, d.x)))
			return along >= -pr and along <= tg_a[i] + pr and side <= tg_b[i] * 0.5 + pr
		Shape.RING:
			var r: float = ring_r(i, age)
			var dist: float = p.distance_to(c)
			if absf(dist - r) > tg_b[i] * 0.5 + pr:
				return false
			if tg_c[i] > 0.0:
				var gd: Vector2 = Vector2(tg_dx[i], tg_dy[i])
				var ang: float = absf(wrapf((p - c).angle() - gd.angle(), -PI, PI))
				if ang < tg_c[i] * 0.5:
					return false
			return true
		Shape.SWEEP:
			var dsw: Vector2 = Vector2(tg_dx[i], tg_dy[i])
			var front: float = tg_v[i] * age
			var rel2: Vector2 = p - c
			var al: float = rel2.dot(dsw)
			if absf(al - front) > tg_b[i] * 0.5 + pr:
				return false
			var sd: float = rel2.dot(Vector2(-dsw.y, dsw.x))
			if absf(sd) > tg_a[i]:
				return false
			return absf(sd - tg_c[i]) > tg_tick[i] * 0.5 - pr
	return false


func ring_r(i: int, age: float) -> float:
	if (tg_flags[i] & F_EXPAND) != 0:
		return maxf(4.0, tg_a[i] + tg_v[i] * maxf(0.0, age))
	return tg_a[i]


# ─── 탄 ────────────────────────────────────────────────────────────────

func _spawn_bullet(p: Vector2, v: Vector2, life: float, r: float, dmg: float) -> void:
	for i in B_CAP:
		if b_on[i] == 0:
			b_on[i] = 1
			bx[i] = p.x
			by[i] = p.y
			bvx[i] = v.x
			bvy[i] = v.y
			blife[i] = life
			brad[i] = maxf(3.0, r)
			bdmg[i] = dmg
			b_count += 1
			return


func _tick_bullets(dt: float, pp: Vector2) -> void:
	if b_count <= 0:
		return
	var pr: float = PLAYER_R_U * K.UNIT_PX
	for i in B_CAP:
		if b_on[i] == 0:
			continue
		bx[i] += bvx[i] * dt
		by[i] += bvy[i] * dt
		blife[i] -= dt
		var dx: float = bx[i] - pp.x
		var dy: float = by[i] - pp.y
		var rr: float = brad[i] + pr
		if dx * dx + dy * dy <= rr * rr:
			_hurt_player(bdmg[i], pp)
			b_on[i] = 0
			b_count -= 1
			continue
		if blife[i] <= 0.0:
			b_on[i] = 0
			b_count -= 1


# ─── 피해(비치명) ───────────────────────────────────────────────────────

## 피해 = 기준% × 최대 정기 × (1 + 0.20(n−1)). 정기를 1 미만으로 깎지 못한다(sys_sinryeong_bulsal).
func _hurt_player(pct: float, _pp2: Vector2) -> void:
	if pct <= 0.0 or Game.player == null or not Game.run_active:
		return
	var pl: Player = Game.player as Player
	if pl == null or pl.hit == null or pl.hit.iframe_left > 0.0 or Game.debug_invuln:
		return
	var raw: float = pct * 0.01 * Game.hp_max * dmg_scale
	var cap: float = Game.hp - 1.0
	if cap <= 0.0:
		# 정기 1: 화신은 더 깎지 않는다(무적 깜빡임만 주어 연속 판정 방지)
		pl.hit.iframe_left = 0.4
		nod_until = _now + 0.25
		player_hit_ev += 1
		return
	pl.take_hit(minf(raw, cap), StringName(String(deity) + "_avatar"))
	hits_on_player += 1
	player_hit_ev += 1
	nod_until = _now + 0.25          # 고개 끄덕임(조롱 금지, 존중)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
