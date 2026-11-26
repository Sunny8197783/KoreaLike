extends RefCounted
## 가호(加護) 의례 과제 6종 시뮬레이션(06 §5.x.3). 소유: deities.
## 반환 단위: 진척 % 포인트(0..100). TrialDirector 가 위치 계수·무당 배율을 곱해 가호 게이지에 더한다.
##  산신 grm_hold    : 산길 쉼터(반경 4) 안에 서면 3.2%/s × 남은 영가/10. 호식 원혼이 영가를 1.5초 붙들면 잃는다.
##  용왕 grm_escort  : 물에 든 넋 5(반경 7~9 고리)을 1.5유닛 안에서 건져 용왕상(반경 2)으로. 1넋 17%. 물귀신에게 맞으면 떨어뜨림.
##  칠성 grm_connect : 별 7개를 순서대로 밟는다(반경 1). 별당 6.5%, 한 바퀴 4.5%, 두 바퀴(둘째는 51.4° 회전 ×1.15).
##  장군 grm_install : 오방기 자리 5곳(중앙 + 사방 6)에 0.8초 서서 세운다. 첫 세움 16%, 모두 서 있으면 2%/s. 잡귀가 2초 닿으면 쓰러짐.
##  바리 grm_escort  : 원혼 떼 12를 몰아(무당 3유닛 안이면 달아남) 저승 문(반경 2.5)으로. 1넋 8.5%.
##  제석 grm_ring+hold: 굿상 공물 60에서 시작. 마당 안 길닦음 1회 = 공물 +20·진척 16%. 공물 ≥ 50이면 1.5%/s. 아귀가 공물을 빤다.
## 할당: 오브젝트는 고정 용량 Packed 배열(최대 16). 스폰·이벤트 시점에만 Dictionary 를 읽는다.

const Defs := preload("res://deities/deity_defs.gd")
const OBJ_CAP: int = 16
const EMPTY: Dictionary = {}   # 읽기 전용 기본값(틱 경로에서 빈 사전 할당 방지)

enum Kind { NONE, HOLD, ESCORT_WATER, CONNECT, INSTALL, HERD, GUTSANG }

var kind: int = Kind.NONE
var deity: StringName = &""
var n: int = 1
var anchor: Vector2 = Vector2.ZERO
var zone: Vector2 = Vector2.ZERO        # 쉼터·용왕상·저승 문·굿상 중심
var zone_r: float = 0.0
var progress_total: float = 0.0         # 이 과제가 낸 진척 합(디버그·로그)
var done: bool = false

# 오브젝트(영가·넋·별·기·원혼) SoA
var ox: PackedFloat32Array = PackedFloat32Array()
var oy: PackedFloat32Array = PackedFloat32Array()
var ovx: PackedFloat32Array = PackedFloat32Array()
var ovy: PackedFloat32Array = PackedFloat32Array()
var ot: PackedFloat32Array = PackedFloat32Array()     # 타이머(붙들림·세움·쓰러짐)
var ost: PackedInt32Array = PackedInt32Array()        # 상태 0 없음 1 있음 2 들림/세워짐 3 사라짐(연출) 4 완료
var ofx: PackedFloat32Array = PackedFloat32Array()    # 상태 전환 연출 시각(게임 초)
var o_count: int = 0

# 과제별 수치
var rate_in_zone: float = 3.2
var hold_remaining: int = 10
var carry: int = 0
var carry_cap: int = 2
var star_next: int = 0
var star_round: int = 0
var star_last_t: float = -100.0
var star_timeout: float = 6.0
var offering: float = 60.0
var side_pct: float = 0.0
var side_cap: float = 20.0
var threat_species: StringName = &""
var threat_iv: float = 5.0
var threat_count: int = 3
var _threat_next: float = 0.0
var _now: float = 0.0
var _rng: RandomNumberGenerator
var _q: PackedInt32Array = PackedInt32Array()
var _def: Dictionary = {}
var last_event: StringName = &""        # 연출용(방금 일어난 일): &"deliver" &"star" &"flag" &"lost" &"gate" &"ring" …
var last_event_pos: Vector2 = Vector2.ZERO
var last_event_t: float = -10.0


func _init() -> void:
	ox.resize(OBJ_CAP)
	oy.resize(OBJ_CAP)
	ovx.resize(OBJ_CAP)
	ovy.resize(OBJ_CAP)
	ot.resize(OBJ_CAP)
	ost.resize(OBJ_CAP)
	ofx.resize(OBJ_CAP)
	_q.resize(64)
	_rng = Rng.stream(&"trial")


func setup(p_deity: StringName, p_n: int, p_anchor: Vector2, player_pos: Vector2, now: float) -> void:
	deity = p_deity
	n = p_n
	anchor = p_anchor
	_now = now
	done = false
	progress_total = 0.0
	side_pct = 0.0
	carry = 0
	star_next = 0
	star_round = 0
	ost.fill(0)
	ot.fill(0.0)
	ofx.fill(-10.0)
	o_count = 0
	var d: Dictionary = Data.deity(String(deity))
	_def = d.get("gaho_task", EMPTY)
	var th: Dictionary = _def.get("threats", EMPTY)
	threat_species = StringName(String(th.get("enemy", "")))
	threat_iv = float(th.get("interval_s", 5.0))
	threat_count = _count_formula(String(th.get("count_formula", "3+n")))
	_threat_next = now + 2.0
	var away: Vector2 = (anchor - player_pos).normalized() if anchor.distance_squared_to(player_pos) > 4.0 else Vector2.RIGHT
	match String(deity):
		"deity_sansin":
			kind = Kind.HOLD
			var ob: Dictionary = _obj(0)
			zone = anchor + away * float(ob.get("offset_from_anchor", 5)) * K.UNIT_PX
			zone_r = float(ob.get("radius", 4)) * K.UNIT_PX
			rate_in_zone = float(_def.get("progress", EMPTY).get("in_zone_pct_per_s", 3.2))
			hold_remaining = int(_obj(1).get("count", 10))
			for i in hold_remaining:
				var a: float = TAU * float(i) / float(hold_remaining) + _rng.randf() * 0.4
				_put(i, zone + Vector2.from_angle(a) * _rng.randf_range(0.8, 2.6) * K.UNIT_PX, 1)
			o_count = hold_remaining
		"deity_yongwang":
			kind = Kind.ESCORT_WATER
			zone = anchor
			zone_r = float(_obj(0).get("radius", 2)) * K.UNIT_PX
			var cnt: int = int(_obj(1).get("count", 5))
			var yc: int = 0
			if Game.run_root != null:
				var yt: Variant = Game.run_root.get("yeongga")
				if yt is Object:
					yc = int((yt as Object).get("count"))
			carry_cap = mini(int(_def.get("carry_capacity_max", 4)), 2 + int(floor(float(yc) / 10.0)))
			for i in cnt:
				_respawn_soul(i)
			o_count = cnt
		"deity_chilseong":
			kind = Kind.CONNECT
			zone = anchor
			zone_r = 0.0
			star_timeout = Game.stat(&"stat_gilbe", 4.0) * 1.5
			_place_stars(0.0, 1.0)
			o_count = 7
		"deity_janggun":
			kind = Kind.INSTALL
			zone = anchor
			var off: float = 6.0 * K.UNIT_PX
			var dirs: PackedVector2Array = [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
			for i in 5:
				_put(i, anchor + dirs[i] * off, 1)
			o_count = 5
		"deity_barigongju":
			kind = Kind.HERD
			var gate_off: float = float(_obj(0).get("offset_from_anchor", 8)) * K.UNIT_PX
			zone = anchor + away * gate_off
			zone_r = float(_obj(0).get("entry_radius", 2.5)) * K.UNIT_PX
			var cnt2: int = int(_obj(1).get("count", 12))
			var herd_c: Vector2 = anchor - away * 1.5 * K.UNIT_PX
			for i in cnt2:
				_put(i, herd_c + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.3, 2.4) * K.UNIT_PX, 1)
			o_count = cnt2
		"deity_jeseok_daegam":
			kind = Kind.GUTSANG
			zone = anchor
			zone_r = 1.5 * K.UNIT_PX
			var om: Dictionary = _obj(0).get("offering_meter", EMPTY)
			offering = float(om.get("start", 60))
			side_cap = float(_def.get("progress_side", EMPTY).get("cap_pct", 20))
		_:
			kind = Kind.NONE
	if kind == Kind.ESCORT_WATER:
		side_cap = float(_def.get("progress", EMPTY).get("mulgwisin_cap_pct", 20))


func _obj(i: int) -> Dictionary:
	var arr: Variant = _def.get("objects", [])
	if arr is Array and i < (arr as Array).size() and arr[i] is Dictionary:
		return arr[i]
	return {}


func _count_formula(f: String) -> int:
	# "3+n" / "2+n" 꼴만
	var parts: PackedStringArray = f.replace(" ", "").split("+")
	var v: int = 0
	for p: String in parts:
		if p == "n":
			v += n
		elif p.is_valid_int():
			v += int(p)
	return maxi(1, v)


func _put(i: int, p: Vector2, st: int) -> void:
	ox[i] = p.x
	oy[i] = p.y
	ovx[i] = 0.0
	ovy[i] = 0.0
	ot[i] = 0.0
	ost[i] = st
	ofx[i] = _now


func _respawn_soul(i: int) -> void:
	var ring: Variant = _obj(1).get("ring", [7, 9])
	var r0: float = float(ring[0]) if ring is Array else 7.0
	var r1: float = float(ring[1]) if ring is Array else 9.0
	_put(i, anchor + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(r0, r1) * K.UNIT_PX, 1)


func _place_stars(rot: float, scl: float) -> void:
	# 북두칠성(탐랑→파군): 국자 4 + 자루 3. 너비 약 14유닛(span).
	var pts: PackedVector2Array = [Vector2(-1.0, -0.25), Vector2(-0.62, -0.5), Vector2(-0.2, -0.2), Vector2(-0.3, 0.3), Vector2(0.2, 0.35), Vector2(0.6, 0.15), Vector2(1.0, 0.42)]
	var span: float = 7.0 * K.UNIT_PX * scl
	for i in 7:
		_put(i, anchor + pts[i].rotated(rot) * span, 1)
	star_next = 0


# ─── 틱 ────────────────────────────────────────────────────────────────

## 반환: 이번 틱 진척 %p(위치 계수·배율 적용 전).
func sim_step(dt: float, now: float, pp: Vector2) -> float:
	_now = now
	if kind == Kind.NONE or done:
		return 0.0
	var gain: float = 0.0
	_tick_threats(now)
	match kind:
		Kind.HOLD:
			gain += _tick_hold(dt, pp)
		Kind.ESCORT_WATER:
			gain += _tick_escort(dt, pp)
		Kind.CONNECT:
			gain += _tick_connect(pp)
		Kind.INSTALL:
			gain += _tick_install(dt, pp)
		Kind.HERD:
			gain += _tick_herd(dt, pp)
		Kind.GUTSANG:
			gain += _tick_gutsang(dt)
	progress_total += gain
	return gain


func _em() -> EnemyManager:
	return Game.enemies as EnemyManager


func _tick_threats(now: float) -> void:
	if threat_species == &"" or now < _threat_next:
		return
	_threat_next = now + threat_iv
	var em: EnemyManager = _em()
	if em == null:
		return
	var c: Vector2 = zone if zone_r > 0.0 else anchor
	for k in threat_count:
		var a: float = _rng.randf() * TAU
		em.spawn(threat_species, c + Vector2.from_angle(a) * _rng.randf_range(7.5, 9.5) * K.UNIT_PX)


func _hostile_near(p: Vector2, r: float) -> int:
	var em: EnemyManager = _em()
	if em == null:
		return 0
	var cnt: int = em.query_circle(p, r, _q, 8)
	var hostile: int = 0
	for k in cnt:
		if em.is_hostile(_q[k]):
			hostile += 1
	return hostile


func _event(e: StringName, p: Vector2) -> void:
	last_event = e
	last_event_pos = p
	last_event_t = _now


func _tick_hold(dt: float, pp: Vector2) -> float:
	var g: float = 0.0
	if pp.distance_to(zone) <= zone_r and hold_remaining > 0:
		g = rate_in_zone * dt * float(hold_remaining) / 10.0
	for i in o_count:
		if ost[i] != 1:
			continue
		# 영가는 쉼터 안을 천천히 맴돈다
		var a: float = _now * 0.35 + float(i)
		ox[i] += cos(a) * 3.0 * dt
		oy[i] += sin(a * 1.3) * 2.0 * dt
		var near: int = _hostile_near(Vector2(ox[i], oy[i]), 0.9 * K.UNIT_PX)
		if near > 0:
			ot[i] += dt
			if ot[i] >= float(_def.get("threats", EMPTY).get("abduct_contact_s", 1.5)):
				ost[i] = 3
				ofx[i] = _now
				hold_remaining -= 1
				_event(&"lost", Vector2(ox[i], oy[i]))
		else:
			ot[i] = maxf(0.0, ot[i] - dt * 0.5)
	return g


func _tick_escort(dt: float, pp: Vector2) -> float:
	var g: float = 0.0
	var pr: float = float(_def.get("pickup_radius", 1.5)) * K.UNIT_PX
	var per: float = float(_def.get("progress", EMPTY).get("per_delivery_pct", 17))
	for i in o_count:
		match ost[i]:
			1:
				# 물결 따라 표류(고리 위를 천천히 돈다)
				var rel: Vector2 = Vector2(ox[i], oy[i]) - anchor
				var tang: Vector2 = Vector2(-rel.y, rel.x).normalized()
				ox[i] += tang.x * K.UNIT_PX * dt
				oy[i] += tang.y * K.UNIT_PX * dt
				if carry < carry_cap and pp.distance_to(Vector2(ox[i], oy[i])) <= pr:
					ost[i] = 2
					ofx[i] = _now
					carry += 1
					_event(&"pickup", Vector2(ox[i], oy[i]))
			2:
				# 무당 뒤를 따른다(줄)
				var k: float = float(i % 4 + 1)
				var tgt: Vector2 = pp + Vector2(0, -6.0) - (Game.player as Player).last_move_dir * 14.0 * k if Game.player != null else pp
				ox[i] = lerpf(ox[i], tgt.x, minf(1.0, dt * 8.0))
				oy[i] = lerpf(oy[i], tgt.y, minf(1.0, dt * 8.0))
				if pp.distance_to(zone) <= zone_r + 0.5 * K.UNIT_PX:
					carry -= 1
					g += per
					_event(&"deliver", zone)
					ost[i] = 3
					ofx[i] = _now
			3:
				if _now - ofx[i] >= 1.2:
					_respawn_soul(i)
	return g


func _tick_connect(pp: Vector2) -> float:
	var g: float = 0.0
	var pr: float = float(_def.get("touch_radius", 1.0)) * K.UNIT_PX + 6.0
	var prog: Dictionary = _def.get("progress", EMPTY)
	if star_next > 0 and _now - star_last_t > star_timeout:
		# 끊김: 이번 바퀴 처음부터
		for i in 7:
			if ost[i] == 2:
				ost[i] = 1
				ofx[i] = _now
		star_next = 0
		_event(&"break", pp)
	if star_next < 7 and pp.distance_to(Vector2(ox[star_next], oy[star_next])) <= pr:
		ost[star_next] = 2
		ofx[star_next] = _now
		star_last_t = _now
		_event(&"star", Vector2(ox[star_next], oy[star_next]))
		star_next += 1
		g += float(prog.get("per_star_pct", 6.5))
		if star_next >= 7:
			g += float(prog.get("round_bonus_pct", 4.5))
			star_round += 1
			_event(&"round", anchor)
			if star_round < int(prog.get("rounds_for_full", 2)):
				var rd: Dictionary = _def.get("round", EMPTY)
				_place_stars(deg_to_rad(float(rd.get("rotate_deg", 51.4))) * float(star_round), pow(float(rd.get("scale", 1.15)), float(star_round)))
			else:
				done = true
	return g


func _tick_install(dt: float, pp: Vector2) -> float:
	var g: float = 0.0
	var prog: Dictionary = _def.get("progress", EMPTY)
	var ir: float = float(_def.get("install_radius", 1.2)) * K.UNIT_PX
	var need: float = float(_def.get("install_accum_s", 0.8))
	var topple_s: float = float(_def.get("topple", EMPTY).get("enemy_contact_s", 2.0))
	var standing: int = 0
	for i in 5:
		var p: Vector2 = Vector2(ox[i], oy[i])
		if ost[i] == 1 or ost[i] == 3:
			if pp.distance_to(p) <= ir:
				ot[i] += dt
				if ot[i] >= need:
					var first: bool = ost[i] == 1
					ost[i] = 2
					ofx[i] = _now
					ot[i] = 0.0
					_event(&"flag", p)
					if first:
						g += float(prog.get("per_flag_first_pct", 16))
			else:
				ot[i] = maxf(0.0, ot[i] - dt)
		elif ost[i] == 2:
			standing += 1
			if _hostile_near(p, 0.8 * K.UNIT_PX) > 0:
				ot[i] += dt
				if ot[i] >= topple_s:
					ost[i] = 3       # 쓰러짐(다시 세우면 진척 없음)
					ofx[i] = _now
					ot[i] = 0.0
					_event(&"topple", p)
			else:
				ot[i] = maxf(0.0, ot[i] - dt)
	if standing >= 5:
		g += float(prog.get("all_standing_pct_per_s", 2.0)) * dt
	return g


func _tick_herd(dt: float, pp: Vector2) -> float:
	var g: float = 0.0
	var hd: Dictionary = _def.get("herding", EMPTY)
	var flee_r: float = float(hd.get("flee_radius", EMPTY).get("player", 3.0)) * K.UNIT_PX
	var flee_v: float = float(hd.get("flee_speed", 2.6)) * K.UNIT_PX
	var idle_v: float = float(hd.get("idle_speed", 0.4)) * K.UNIT_PX
	var coh_w: float = float(hd.get("cohesion_weight", 0.3))
	var per: float = float(_def.get("progress", EMPTY).get("per_soul_pct", 8.5))
	var ground_r: float = 12.0 * K.UNIT_PX
	var cx: float = 0.0
	var cy: float = 0.0
	var alive: int = 0
	for i in o_count:
		if ost[i] == 1:
			cx += ox[i]
			cy += oy[i]
			alive += 1
	if alive > 0:
		cx /= float(alive)
		cy /= float(alive)
	for i in o_count:
		if ost[i] != 1:
			continue
		var p: Vector2 = Vector2(ox[i], oy[i])
		var v: Vector2 = Vector2.ZERO
		var dp: Vector2 = p - pp
		var dl: float = dp.length()
		if dl < flee_r and dl > 0.01:
			v += dp / dl * flee_v * (1.0 - dl / flee_r * 0.5)
		else:
			v += Vector2.from_angle(_now * 0.7 + float(i) * 1.7) * idle_v
		if alive > 1:
			v += (Vector2(cx, cy) - p) * coh_w
		if p.distance_to(anchor) > ground_r:
			v += (anchor - p).normalized() * flee_v
		ovx[i] = lerpf(ovx[i], v.x, minf(1.0, dt * 6.0))
		ovy[i] = lerpf(ovy[i], v.y, minf(1.0, dt * 6.0))
		ox[i] += ovx[i] * dt
		oy[i] += ovy[i] * dt
		if Vector2(ox[i], oy[i]).distance_to(zone) <= zone_r:
			ost[i] = 4
			ofx[i] = _now
			g += per
			_event(&"gate", Vector2(ox[i], oy[i]))
	return g


func _tick_gutsang(dt: float) -> float:
	var g: float = 0.0
	var hold: Dictionary = _def.get("hold", EMPTY)
	var th: Dictionary = _def.get("threats", EMPTY)
	var drain: float = float(th.get("drain_per_agwi_per_s", 5)) * maxf(0.3, 1.0 - 0.07 * float(n - 1))
	var near: int = _hostile_near(zone, float(th.get("drain_radius", 1.5)) * K.UNIT_PX)
	if near > 0:
		offering = maxf(0.0, offering - drain * float(near) * dt)
	if offering >= float(hold.get("threshold", 50)):
		g += float(hold.get("pct_per_s", 1.5)) * dt
	return g


# ─── 이벤트 ────────────────────────────────────────────────────────────

## 반환: 진척 %p.
func on_enemy_killed(species: StringName, pos: Vector2, kind_k: StringName) -> float:
	if done:
		return 0.0
	var prog: Dictionary = _def.get("progress", EMPTY)
	match kind:
		Kind.HOLD:
			if species == threat_species and pos.distance_to(zone) <= float(prog.get("credit_radius", 6)) * K.UNIT_PX:
				return float(prog.get("haewon_hosik_pct", 4.0)) if kind_k == K.KIND_HAEWON else float(prog.get("toechi_hosik_pct", 1.5))
		Kind.ESCORT_WATER:
			if species == threat_species and kind_k == K.KIND_HAEWON and side_pct < side_cap:
				var v: float = minf(float(prog.get("mulgwisin_haewon_pct", 2.5)), side_cap - side_pct)
				side_pct += v
				return v
		Kind.GUTSANG:
			var ps: Dictionary = _def.get("progress_side", EMPTY)
			if species == threat_species and kind_k == K.KIND_HAEWON and pos.distance_to(zone) <= float(ps.get("radius", 5)) * K.UNIT_PX and side_pct < side_cap:
				var v2: float = minf(float(ps.get("agwi_haewon_pct", 2.5)), side_cap - side_pct)
				side_pct += v2
				return v2
	return 0.0


## 길닦음(고리) — 제석 과제 본 경로. 반환: 진척 %p.
func on_ring_closed(area: int, centroid: Vector2) -> float:
	if kind != Kind.GUTSANG or done or centroid.distance_to(anchor) > 12.0 * K.UNIT_PX:
		return 0.0
	var rg: Dictionary = _def.get("ring", EMPTY)
	if area < int(rg.get("min_area", 9)):
		return 0.0
	offering = minf(100.0, offering + float(rg.get("offering_add", 20)))
	_event(&"ring", centroid)
	return float(rg.get("progress_pct", 16)) + minf(float(rg.get("area_bonus_cap_pct", 6)), float(area) * float(rg.get("area_bonus_pct_per_tile", 0.1)))


## 물귀신 접촉 → 든 넋을 그 자리에 떨어뜨림(용왕).
func on_player_damaged(source: StringName, pp: Vector2) -> void:
	if kind != Kind.ESCORT_WATER or carry <= 0:
		return
	if source != threat_species and not String(source).ends_with("_avatar"):
		return
	for i in o_count:
		if ost[i] == 2:
			_put(i, pp + Vector2.from_angle(_rng.randf() * TAU) * 1.2 * K.UNIT_PX, 1)
	carry = 0
	_event(&"drop", pp)


## 과제 안내 표식(HUD 화살표 대상): 다음으로 가야 할 곳.
func guide_point(pp: Vector2) -> Vector2:
	match kind:
		Kind.HOLD, Kind.GUTSANG:
			return zone
		Kind.ESCORT_WATER:
			if carry > 0:
				return zone
			var best: Vector2 = zone
			var bd: float = INF
			for i in o_count:
				if ost[i] == 1:
					var d: float = pp.distance_squared_to(Vector2(ox[i], oy[i]))
					if d < bd:
						bd = d
						best = Vector2(ox[i], oy[i])
			return best
		Kind.CONNECT:
			if star_next < 7:
				return Vector2(ox[star_next], oy[star_next])
		Kind.INSTALL:
			var bi: Vector2 = anchor
			var bdi: float = INF
			for i in 5:
				if ost[i] != 2:
					var d2: float = pp.distance_squared_to(Vector2(ox[i], oy[i]))
					if d2 < bdi:
						bdi = d2
						bi = Vector2(ox[i], oy[i])
			return bi
		Kind.HERD:
			# 떼 뒤편(문 반대쪽)으로 가서 밀어야 한다
			var cx: Vector2 = Vector2.ZERO
			var c: int = 0
			for i in o_count:
				if ost[i] == 1:
					cx += Vector2(ox[i], oy[i])
					c += 1
			if c > 0:
				cx /= float(c)
				return cx + (cx - zone).normalized() * 2.5 * K.UNIT_PX
	return anchor
