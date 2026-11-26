class_name ArchMeleeArc
extends WeaponBase
## 원형 melee_arc: 360° 회전 베기(spin) / 전방 부채꼴(cone) / 3갈래 찌르기(prong) / 이동 방향 연타(thrust). 소유: combat.
## params: shape(spin|cone|prong|thrust), pull_pullil(부채: 풀릴 기색은 끌어옴), fan_deg(갈래 전체각, 기본 30)
##   crescents(만월도: 마지막 회전 뒤 반달 검기 waves개) · quake(벽력편곤: 착지 고리 + 정기 비례 피해) · whirls(일월선풍: 회오리 공전 + 끌어오기 돌진)
##   lunge(파진창: 이동 중 창기 잔상 투사체)
## 레벨 필드: dmg, area(u 반경/길이), angle(deg), width(u), kb(u), spins, spin_time, prongs, thrusts, thrust_iv, mark, gusts, back …
## 연출(GAME_FEEL 3.1): 선딜 = 판정 범위 예고(어두운 팔레트 1px) + 손 반짝, 타격 = 시트(4방향, 90° 회전·좌우 반전) + 정수 스미어, 후딜 = 시트 소멸.

const C_SWING: int = 1
const C_CRESCENT: int = 2
const C_BACK: int = 3
const C_THRUST: int = 4
const C_PRONG: int = 5
const C_GUST: int = 6
const C_QUAKE: int = 7

const SW_CAP: int = 12
var sw_tick: PackedInt32Array = PackedInt32Array()
var sw_dir: PackedVector2Array = PackedVector2Array()
var sw_org: PackedVector2Array = PackedVector2Array()
var sw_len: PackedFloat32Array = PackedFloat32Array()
var sw_kind: PackedInt32Array = PackedInt32Array()
var sw_flip: PackedByteArray = PackedByteArray()
var _sw_head: int = 0
var _dir_cnt: PackedInt32Array = PackedInt32Array()
var _whirl_phase: float = 0.0
var _whirl_hit_t: float = 0.0
var _dash_t: float = 0.0
var _dash_from: Vector2 = Vector2.ZERO
var _dash_to: Vector2 = Vector2.ZERO
var _dash_tick: int = -100000
var _spin_n: int = 0


func _on_setup() -> void:
	sw_tick.resize(SW_CAP)
	sw_tick.fill(-100000)
	sw_dir.resize(SW_CAP)
	sw_org.resize(SW_CAP)
	sw_len.resize(SW_CAP)
	sw_kind.resize(SW_CAP)
	sw_flip.resize(SW_CAP)
	_dir_cnt.resize(8)


func _shape() -> String:
	return String(params.get("shape", "cone"))


func _radius() -> float:
	return s("area", 2.0) * K.UNIT_PX * area_mult()


func _dmg() -> float:
	var d: float = s("dmg", 8.0)
	if bool(params.get("quake", false)):
		d += s("hp_scale", 0.0) * Game.hp_max
	if bool(params.get("lunge", false)):
		# 도무 100% 초과분 1%당 +1%(상한 domu_cap)
		d *= 1.0 + clampf((Game.stat(&"stat_domu", 1.0) - 1.0) * s("domu_scale", 1.0), 0.0, s("domu_cap", 0.6))
	return d


func _attack_dir() -> Vector2:
	match _shape():
		"spin":
			return Vector2.RIGHT
		"prong":
			return _best_octant(player_pos(), s("area", 4.0) + 0.5, -1)
	return move_dir()


## 반경 안 8방위 중 적이 가장 많은 방위(삼지창). skip: 제외할 방위(-1 없음).
func _best_octant(o: Vector2, r_u: float, skip: int) -> Vector2:
	var em: EnemyManager = enemies()
	if em == null:
		return move_dir()
	_dir_cnt.fill(0)
	var n: int = em.query_circle(o, r_u * K.UNIT_PX, _q)
	for k in n:
		var i: int = _q[k]
		if (em.flags[i] & EnemyManager.F_DYING) != 0:
			continue
		var d: Vector2 = em.pos_of(i) - o
		var oc: int = int(roundf(atan2(d.y, d.x) / (PI / 4.0))) & 7
		_dir_cnt[oc] += 1
	var best: int = -1
	var bc: int = 0
	for k2 in 8:
		if k2 != skip and _dir_cnt[k2] > bc:
			bc = _dir_cnt[k2]
			best = k2
	if best < 0:
		return move_dir() if skip < 0 else Vector2.ZERO
	return Vector2.from_angle(float(best) * PI / 4.0)


func fire() -> void:
	var dir: Vector2 = _attack_dir()
	fire_dir = dir
	match _shape():
		"spin":
			var spins: int = maxi(1, int(s("spins", 1)))
			var extra: int = mini(sinjang(), int(limit("amt_cap", 4)))
			_spin_n = 0
			_swing(C_SWING, dir, 1.0)
			for k in range(1, spins + extra):
				schedule_action(0.15 * float(k), C_SWING, dir, 1.0 if k < spins else 0.6)
			if bool(params.get("crescents", false)):
				schedule_action(0.15 * float(spins + extra - 1) + 0.1, C_CRESCENT, dir, 1.0)
		"prong":
			var th: int = maxi(1, int(s("thrusts", 1)))
			_prong_set(dir, 1.0)
			for k in range(1, th):
				schedule_action(0.2 * float(k), C_PRONG, dir, 1.0)
			# 신장 수 1당 다음으로 적이 많은 방위에 찌르기 1세트(상한 +4)
			var skip: int = int(roundf(atan2(dir.y, dir.x) / (PI / 4.0))) & 7
			for k2 in mini(sinjang(), 4):
				var d2: Vector2 = _best_octant(player_pos(), s("area", 4.0) + 0.5, skip)
				if d2 == Vector2.ZERO:
					break
				schedule_action(0.05 * float(k2 + 1), C_PRONG, d2, 1.0)
		"thrust":
			var th2: int = maxi(1, int(s("thrusts", 3)))
			var iv: float = maxf(0.05, s("thrust_iv", 0.1))
			for k in th2:
				if k == 0:
					_thrust(dir, 1.0)
				else:
					schedule_action(iv * float(k), C_THRUST, Vector2.ZERO, 1.0)
		_:
			var gusts: int = maxi(1, int(s("gusts", 1)))
			_swing(C_SWING, dir, 1.0)
			for k in range(1, gusts):
				schedule_action(0.25 * float(k), C_GUST, dir, 1.0)
			if s("back", 0.0) > 0.0:
				schedule_action(0.12, C_BACK, -dir, 0.7)
			if bool(params.get("quake", false)):
				schedule_action(0.08, C_QUAKE, dir, 1.0)
			# 편곤: 신장 수 1당 0.2초 뒤 같은 방향 재타격(50%, 상한 +3)
			if not bool(params.get("pull_pullil", false)):
				for k3 in mini(sinjang(), int(limit("amt_cap", 3))):
					schedule_action(0.2 * float(k3 + 1), C_GUST, dir, 0.5)


func _action(code: int, dir: Vector2, mult: float) -> void:
	match code:
		C_SWING, C_GUST, C_BACK:
			_swing(code, dir if dir != Vector2.ZERO else _attack_dir(), mult)
		C_CRESCENT:
			_crescents()
		C_THRUST:
			_thrust(move_dir(), mult)
		C_PRONG:
			_prong_set(dir, mult)
		C_QUAKE:
			var c: Vector2 = player_pos() + dir * s("ring_offset", 2.0) * K.UNIT_PX
			var r: float = s("ring_r", 2.0) * K.UNIT_PX * area_mult()
			var em: EnemyManager = enemies()
			if em != null:
				var n: int = em.query_circle(c, r, _q)
				for k in n:
					apply_status(_q[k], &"st_gyeongjik", s("ring_stun", 0.6))
			deal_circle(c, r, _dmg() * s("ring_mult", 0.5), 0.6)
			play_fx(fx_name("fx_ring"), c)
			Juice.add_trauma(0.15)


func _record(kind_v: int, o: Vector2, dir: Vector2, ln: float, flip: bool) -> void:
	var k: int = _sw_head % SW_CAP
	_sw_head += 1
	sw_tick[k] = Game.game_tick
	sw_dir[k] = dir
	sw_org[k] = o
	sw_len[k] = ln
	sw_kind[k] = kind_v
	sw_flip[k] = 1 if flip else 0


## 회전·부채꼴 베기 1회.
func _swing(code: int, dir: Vector2, mult: float) -> void:
	var em: EnemyManager = enemies()
	if em == null:
		return
	var origin: Vector2 = player_pos()
	var spin: bool = _shape() == "spin"
	var r: float = _radius()
	var ang: float = s("angle", 90.0)
	if bool(params.get("pull_pullil", false)):
		ang = minf(ang + 15.0 * float(sinjang()), ang + 45.0)
	var half: float = deg_to_rad(ang) * 0.5
	var kb: float = s("kb", 0.0)
	var pull: bool = bool(params.get("pull_pullil", false))
	var n: int = em.query_circle(origin, r, _q)
	var hits: int = 0
	for k in n:
		var i: int = _q[k]
		if (em.flags[i] & EnemyManager.F_DYING) != 0:
			continue
		var d: Vector2 = em.pos_of(i) - origin
		if not spin and absf(dir.angle_to(d)) > half and d.length() >= 12.0:
			continue
		if not can_hit(i, 0.0):
			continue
		var kd: Vector2 = d.normalized() if d.length_squared() > 0.01 else dir
		if pull and (em.flags[i] & EnemyManager.F_PULLIL) != 0:
			# 백 무구는 풀릴 기색을 밀지 않는다 — 부채는 0.5u 끌어온다
			deal(i, _dmg(), -kd, minf(0.5, d.length() / K.UNIT_PX), mult, F_PULL)
		else:
			deal(i, _dmg(), kd, kb, mult)
		hits += 1
	_spin_n += 1
	_record(code, origin, dir, r, spin and (_spin_n % 2 == 0))
	if code != C_SWING:
		Audio.play_sfx(StringName("sfx_wpn_" + stem), &"SFX", -9.0, 0.08)


## 만월도: 반달 검기 waves개 사방 발사.
func _crescents() -> void:
	var pp: ProjectilePool = pool()
	if pp == null:
		return
	var n: int = maxi(1, int(s("waves", 8)))
	var spd: float = s("wave_spd", 9.0) * K.UNIT_PX * speed_mult()
	for k in n:
		var d: Vector2 = Vector2.from_angle(TAU * float(k) / float(n))
		pp.spawn_player(slot, player_pos(), d * spd, s("wave_range", 6.0) * K.UNIT_PX / spd, s("wave_width", 1.0) * 0.5 * K.UNIT_PX, s("wave_dmg", 18.0), int(s("wave_pierce", 2)), false, 1, true)


## 장창 직선 찌르기(관통). 신장 수 1당 ±20° 창 추가(상한 +4).
func _thrust(dir: Vector2, mult: float) -> void:
	var extra: int = mini(sinjang(), 4)
	_line_hit(dir, s("area", 4.0) * K.UNIT_PX * area_mult(), s("width", 0.4) * K.UNIT_PX, mult, false)
	for k in extra:
		var sgn: float = 1.0 if k % 2 == 0 else -1.0
		var d2: Vector2 = dir.rotated(deg_to_rad(20.0 * float(k / 2 + 1)) * sgn)
		_line_hit(d2, s("area", 4.0) * K.UNIT_PX * area_mult(), s("width", 0.4) * K.UNIT_PX, mult, false)
	if bool(params.get("lunge", false)) and moving_speed() >= s("run_threshold", 3.5) * K.UNIT_PX * 0.98:
		var pp: ProjectilePool = pool()
		if pp != null:
			var spd: float = s("lunge_spd", 16.0) * K.UNIT_PX * speed_mult()
			pp.spawn_player(slot, player_pos(), dir * spd, s("lunge_range", 8.0) * K.UNIT_PX / spd, 0.4 * K.UNIT_PX, s("lunge_dmg", 10.0), -1, false, 1, true)
	if fires_total > 0:
		Audio.play_sfx(StringName("sfx_wpn_" + stem), &"SFX", -10.0, 0.1)


## 삼지창 3갈래(진화 5갈래) 동시 찌르기 + 정예 표식.
func _prong_set(dir: Vector2, mult: float) -> void:
	var n: int = maxi(1, int(s("prongs", 3)))
	var fan: float = deg_to_rad(float(params.get("fan_deg", 30.0)))
	var ln: float = s("area", 3.5) * K.UNIT_PX * area_mult()
	for k in n:
		var t: float = 0.0 if n == 1 else (float(k) / float(n - 1) - 0.5)
		_line_hit(dir.rotated(fan * t), ln, s("width", 0.5) * K.UNIT_PX, mult, true)


func _line_hit(dir: Vector2, ln: float, width: float, mult: float, mark: bool) -> void:
	var em: EnemyManager = enemies()
	if em == null:
		return
	var origin: Vector2 = player_pos()
	var n: int = em.query_circle(origin + dir * ln * 0.5, ln * 0.5 + width, _q)
	var wm: WeaponManager = mgr as WeaponManager
	for k in n:
		var i: int = _q[k]
		if (em.flags[i] & EnemyManager.F_DYING) != 0:
			continue
		var d: Vector2 = em.pos_of(i) - origin
		var along: float = d.dot(dir)
		if along < -8.0 or along > ln or absf(d.cross(dir)) > width * 0.5 + em.radius[i]:
			continue
		if not can_hit(i, 0.0):
			continue
		deal(i, _dmg(), dir, s("kb", 0.0), mult)
		if mark and (em.flags[i] & EnemyManager.F_ELITE_PLUS) != 0 and s("mark", 0.0) > 0.0:
			if not wm.is_marked(i):
				play_fx(fx_name("fx_mark"), em.pos_of(i) + Vector2(0, -float(em.body_h_of(i)) - 4.0))
			wm.set_mark(i, 5.0 * dur_mult(), s("mark", 0.15))
	_record(C_THRUST, origin, dir, ln, false)


func tick(dt: float) -> void:
	if not bool(params.get("whirls", false)):
		return
	# 일월선풍: 일·월 회오리 공전 + 4초마다 풀릴 기색 무리 끌어오기
	_whirl_phase += 2.2 * dt
	_whirl_hit_t -= dt
	if _whirl_hit_t <= 0.0:
		_whirl_hit_t = maxf(0.1, s("whirl_tick", 0.25))
		var nw: int = maxi(1, int(s("whirl", 2)))
		for k in nw:
			deal_circle(_whirl_pos(k, nw), s("whirl_r", 1.2) * K.UNIT_PX * area_mult(), s("whirl_dmg", 8.0), 0.0, s("whirl_tick", 0.25) * 0.9)
	_dash_t -= dt
	if _dash_t <= 0.0:
		_dash_t = s("dash_every", 4.0)
		_pull_cluster()


func _whirl_pos(k: int, n: int) -> Vector2:
	return player_pos() + Vector2.from_angle(_whirl_phase + TAU * float(k) / float(n)) * s("orbit_r", 3.0) * K.UNIT_PX


func _pull_cluster() -> void:
	var em: EnemyManager = enemies()
	if em == null:
		return
	var o: Vector2 = player_pos()
	var n: int = em.query_circle(o, 8.0 * K.UNIT_PX, _q)
	var best: int = -1
	var best_c: int = 0
	var step: int = maxi(1, n / 12)
	for k in range(0, n, step):
		var i: int = _q[k]
		if (em.flags[i] & EnemyManager.F_PULLIL) == 0:
			continue
		var c: int = 0
		var p: Vector2 = em.pos_of(i)
		for k2 in n:
			var j: int = _q[k2]
			if (em.flags[j] & EnemyManager.F_PULLIL) != 0 and em.pos_of(j).distance_squared_to(p) <= 9.0 * K.UNIT_PX * K.UNIT_PX:
				c += 1
		if c > best_c:
			best_c = c
			best = i
	if best < 0:
		return
	var center: Vector2 = em.pos_of(best)
	var pr: float = s("pull_r", 3.0) * K.UNIT_PX
	for k3 in n:
		var j2: int = _q[k3]
		if (em.flags[j2] & EnemyManager.F_PULLIL) == 0 or em.pos_of(j2).distance_to(center) > pr:
			continue
		var to: Vector2 = o - em.pos_of(j2)
		deal(j2, 1.0, to.normalized(), minf(2.5, to.length() / K.UNIT_PX * 0.7), 1.0, F_PULL | F_NO_SFX)
	_dash_from = o
	_dash_to = center
	_dash_tick = Game.game_tick


# ─── 연출 ────────────────────────────────────────────────────────────

## 보조탄(tag 1): 만월도 반달 검기(시트) / 파진창 창기 잔상(절차적 창날).
func proj_visual(tag: int) -> Dictionary:
	if tag == 1 and fx_name("fx_wave") != &"":
		return {"fx": fx_name("fx_wave"), "orient": &"dir4"}
	if tag == 1:
		return {"orient": &"dir4"}
	return super.proj_visual(tag)


func projectile_texture() -> Texture2D:
	if _proc_tex == null:
		_proc_tex = make_blade_texture(20, 5)
	return _proc_tex


func draw(ci: CanvasItem) -> void:
	var now: int = Game.anim_tick()
	var o: Vector2 = render_origin()
	var body: Vector2 = o + Vector2(0, -14)
	# 선딜: 판정 범위 예고(어두운 팔레트, 2틱 점멸) + 손 반짝
	var wp: float = windup_prog()
	if wp >= 0.0:
		var pd: Vector2 = _attack_dir()
		draw_windup_hand(ci, -pd if _shape() == "spin" else pd)
		var c: Color = col_dk()
		if (now / 2) % 2 == 0 or wp > 0.6:
			var r: float = _radius()
			match _shape():
				"spin":
					draw_ring(ci, o, r * (0.6 + 0.4 * wp), c)
				"cone":
					var half: float = deg_to_rad(s("angle", 90.0)) * 0.5
					var a: float = pd.angle()
					ci.draw_arc(K.rndv(o), roundf(r), a - half, a + half, 16, c, 1.0)
				_:
					var ln: float = s("area", 4.0) * K.UNIT_PX * area_mult() * wp
					_stroke(ci, o, pd, ln, c, K.COL_HEUK, 1)
	# 타격·후딜 기록
	for k in SW_CAP:
		var age: float = float(now - sw_tick[k]) / K.TICK_HZ
		if age < 0.0 or age > 0.6:
			continue
		var d: Vector2 = sw_dir[k]
		var org: Vector2 = o if _shape() != "thrust" else K.rndv(sw_org[k] - player_pos() + o)
		match sw_kind[k]:
			C_THRUST:
				_draw_thrust(ci, org, d, sw_len[k], age)
			_:
				_draw_swing(ci, body, d, sw_len[k], age, sw_flip[k] == 1, sw_kind[k] == C_BACK)
	# 일월선풍 회오리·끌어오기
	if bool(params.get("whirls", false)):
		var nw: int = maxi(1, int(s("whirl", 2)))
		for k2 in nw:
			var wp2: Vector2 = _whirl_pos(k2, nw) - player_pos() + o + Vector2(0, -8)
			if not draw_sheet(ci, fx_name("fx_whirl"), wp2, Game.anim_time() + float(k2) * 0.2):
				draw_ring(ci, wp2, 8.0, K.COL_HANJI)
		if now - _dash_tick < 10:
			_stroke(ci, _dash_to, (_dash_from - _dash_to).normalized(), _dash_from.distance_to(_dash_to), K.COL_HANJI, K.COL_HANJI_DK, 1)


func _draw_swing(ci: CanvasItem, body: Vector2, d: Vector2, r: float, age: float, flip: bool, back: bool) -> void:
	var hold: float = hold_s()
	var fx: StringName = fx_name("fx_cast")
	var d4: int = dir4_of(d)
	if _shape() == "spin":
		if not draw_sheet(ci, fx, body, age, 2 if flip else 0):
			if age < hold + recovery_s():
				draw_ring(ci, body, r, col_main(), 2.0)
		# 판정 원: 타격 홀드 동안 정수 1px 테(실제 반경)
		if age < hold:
			draw_ring(ci, body + Vector2(0, 14), r, col_hi())
		return
	if not draw_sheet(ci, fx, body + K.rndv(K.dir8(d) * 6.0), age, d4):
		if age < hold + recovery_s():
			var half: float = deg_to_rad(s("angle", 90.0)) * 0.5
			var a: float = d.angle()
			ci.draw_arc(K.rndv(body), roundf(r), a - half, a + half, 18, col_main(), 3.0)
	# 정수 스미어(타격 1f): 실제 판정 호
	if age < 0.05 and not back:
		var half2: float = deg_to_rad(s("angle", 90.0)) * 0.5
		var a2: float = d.angle()
		ci.draw_arc(K.rndv(body), roundf(r * 0.85), a2 - half2, a2 + half2, 18, col_hi(), 1.0)
		ci.draw_arc(K.rndv(body), roundf(r), a2 - half2, a2 + half2, 18, K.COL_HANJI if is_red() else K.COL_HANJI_DK, 1.0)


func _draw_thrust(ci: CanvasItem, org: Vector2, d: Vector2, ln: float, age: float) -> void:
	var hold: float = hold_s()
	var total: float = hold + recovery_s()
	if age > total:
		return
	var hand: Vector2 = org + Vector2(0, -14)
	# 축 정렬(±12°)이면 시트, 아니면 정수 획
	var a: float = rad_to_deg(d.angle())
	var off: float = absf(wrapf(a, -45.0, 45.0))
	var drew: bool = false
	if off < 12.0:
		drew = draw_sheet(ci, fx_name("fx_cast"), hand, age, dir4_of(d))
	if not drew:
		var ext: float = clampf(age / 0.05, 0.0, 1.0) if age < hold else clampf(1.0 - (age - hold) / maxf(0.01, recovery_s()), 0.0, 1.0)
		_stroke(ci, hand, d, roundf(ln * ext), col_main(), col_dk(), 2)
		if age < hold:
			var tip: Vector2 = K.rndv(hand + d * ln * ext)
			ci.draw_rect(Rect2(tip - Vector2(1, 1), Vector2(3, 3)), K.COL_HANJI)


## 정수 픽셀 획(Bresenham 대신 반올림 스텝): 코어 c, 가장자리 edge, 굵기 w(1|2).
func _stroke(ci: CanvasItem, from: Vector2, d: Vector2, ln: float, c: Color, edge: Color, w: int) -> void:
	if ln < 1.0:
		return
	var perp: Vector2 = Vector2(0, 1) if absf(d.x) >= absf(d.y) else Vector2(1, 0)
	var a: Vector2 = K.rndv(from)
	var e: Vector2 = K.rndv(from + d * ln)
	if w >= 2:
		ci.draw_line(a + perp, e + perp, edge, 1.0)
		ci.draw_line(a - perp, e - perp, edge, 1.0)
	ci.draw_line(a, e, c, 1.0)
	ci.draw_rect(Rect2(e, Vector2(1, 1)), K.COL_HANJI)
