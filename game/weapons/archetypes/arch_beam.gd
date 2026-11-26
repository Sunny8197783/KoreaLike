class_name ArchBeam
extends WeaponBase
## 원형 beam: 공전 거울 + 즉발 광명 빛줄기(명두·일월명두). 소유: combat.
## 거울마다 area(u) 안 가장 가까운 적(어둑시니 최우선)에게 관통 빛줄기. reflect: 마지막 적에서 4u(진화 5u) 안 다음 적으로 연쇄(회당 −reflect_decay).
## 레벨 필드: dmg, mirrors, area(u: 길이·사거리), width(u), reflect, reflect_decay, dark, orbit_r(u), light_r(u)
## 연출: 선딜 = 거울 번쩍(황 1px), 타격 = 정수 빛줄기(한지 코어 + 어두운 가장자리) 홀드, 후딜 = 2f 간격 점멸 소멸.

const SEG_CAP: int = 32
var seg_a: PackedVector2Array = PackedVector2Array()
var seg_b: PackedVector2Array = PackedVector2Array()
var seg_n: int = 0
var _phase: float = 0.0
var _hit_mark: PackedInt32Array = PackedInt32Array()


func _on_setup() -> void:
	seg_a.resize(SEG_CAP)
	seg_b.resize(SEG_CAP)
	_hit_mark.resize(EnemyManager.CAPACITY)
	_hit_mark.fill(-1)


func _mirrors() -> int:
	return clampi(int(s("mirrors", 2)) + sinjang(), 1, 6)


func _mirror_pos(k: int, n: int) -> Vector2:
	return player_pos() + Vector2.from_angle(_phase + TAU * float(k) / float(n)) * s("orbit_r", 2.5) * K.UNIT_PX


func tick(dt: float) -> void:
	_phase += 1.4 * dt


## 거울에서 가장 가까운 대상(어둑시니 등 자동조준 제외 개체를 최우선 — 명두 특효).
func _beam_target(src: Vector2, max_r: float) -> int:
	var em: EnemyManager = enemies()
	var best: int = -1
	var best_d: float = max_r * max_r
	var best_x: int = -1
	var best_xd: float = best_d
	for k in em.active_count:
		var i: int = em.active[k]
		var f: int = em.flags[i]
		if (f & EnemyManager.F_DYING) != 0:
			continue
		var dx: float = em.px[i] - src.x
		var dy: float = em.py[i] - src.y
		var d: float = dx * dx + dy * dy
		if (f & EnemyManager.F_AUTO_TARGET_EXEMPT) != 0:
			if d < best_xd:
				best_xd = d
				best_x = i
			continue
		if d < best_d:
			best_d = d
			best = i
	return best_x if best_x >= 0 else best


func fire() -> void:
	var em: EnemyManager = enemies()
	if em == null:
		return
	seg_n = 0
	var n: int = _mirrors()
	var length: float = s("area", 7.0) * K.UNIT_PX * area_mult()
	var w: float = maxf(s("width", 0.5), 0.3) * K.UNIT_PX * sqrt(area_mult())
	var stamp: int = Game.game_tick
	for k in n:
		var src: Vector2 = _mirror_pos(k, n)
		var t: int = _beam_target(src, length)
		if t < 0:
			continue
		var d: Vector2 = (em.pos_of(t) - src).normalized()
		var last: int = _line(src, d, length, w, s("dmg", 8.0), stamp)
		# 반사 연쇄
		var refl: int = int(s("reflect", 0))
		var m: float = 1.0
		var from: int = last if last >= 0 else t
		for _r in refl:
			m *= 1.0 - s("reflect_decay", 0.1)
			var a: Vector2 = em.pos_of(from)
			var nx: int = _next_target(a, (5.0 if s("reflect", 0) >= 3 else 4.0) * K.UNIT_PX, stamp)
			if nx < 0:
				break
			var d2: Vector2 = (em.pos_of(nx) - a).normalized()
			var l2: int = _line(a, d2, a.distance_to(em.pos_of(nx)) + 4.0, w, s("dmg", 8.0) * m, stamp)
			from = l2 if l2 >= 0 else nx


## 직선 관통 판정 + 연출 선분 기록. 반환: 가장 먼 맞은 적.
func _line(src: Vector2, d: Vector2, length: float, w: float, dmg: float, stamp: int) -> int:
	var em: EnemyManager = enemies()
	var c: int = em.query_circle(src + d * length * 0.5, length * 0.5 + w, _q)
	var far: int = -1
	var far_a: float = -1.0
	for j in c:
		var i: int = _q[j]
		if (em.flags[i] & EnemyManager.F_DYING) != 0:
			continue
		var rel: Vector2 = em.pos_of(i) - src
		var along: float = rel.dot(d)
		if along < 0.0 or along > length or absf(rel.cross(d)) > w * 0.5 + em.radius[i]:
			continue
		if _hit_mark[i] != stamp:
			_hit_mark[i] = stamp
			deal(i, dmg, d, 0.0)
		if along > far_a:
			far_a = along
			far = i
	if seg_n < SEG_CAP:
		seg_a[seg_n] = src
		seg_b[seg_n] = src + d * (far_a + 6.0 if far >= 0 else length)
		seg_n += 1
	return far


func _next_target(a: Vector2, r: float, stamp: int) -> int:
	var em: EnemyManager = enemies()
	var c: int = em.query_circle(a, r, _q)
	var best: int = -1
	var bd: float = r * r
	for j in c:
		var i: int = _q[j]
		if _hit_mark[i] == stamp or (em.flags[i] & EnemyManager.F_DYING) != 0:
			continue
		var d: float = em.pos_of(i).distance_squared_to(a)
		if d < bd:
			bd = d
			best = i
	return best


func draw_ground(ci: CanvasItem) -> void:
	if s("light_r", 0.0) <= 0.0:
		return
	var n: int = _mirrors()
	var rp: Vector2 = render_origin() - player_pos()
	for k in n:
		var p: Vector2 = _mirror_pos(k, n) + rp
		var r: float = s("light_r", 2.0) * K.UNIT_PX
		var seg: int = 24
		for q in seg:
			if q % 3 == 0:
				var a0: float = TAU * float(q) / float(seg) + _phase
				ci.draw_arc(K.rndv(p), roundf(r), a0, a0 + TAU / float(seg), 2, K.COL_HWANG, 1.0)


func draw(ci: CanvasItem) -> void:
	var now: int = Game.anim_tick()
	var n: int = _mirrors()
	var rp: Vector2 = render_origin() - player_pos()
	var wp: float = windup_prog()
	for k in n:
		var p: Vector2 = K.rndv(_mirror_pos(k, n) + rp + Vector2(0, -16))
		if not draw_sheet(ci, fx_name("fx_prop"), p, Game.anim_time() + float(k) * 0.25):
			ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(7, 7)), K.COL_HWANG)
		if wp > 0.4 and (now / 2) % 2 == 0:
			ci.draw_rect(Rect2(p + Vector2(-5, 0), Vector2(11, 1)), K.COL_HWANG)
			ci.draw_rect(Rect2(p + Vector2(0, -5), Vector2(1, 11)), K.COL_HWANG)
	var sf: float = since_fire()
	var hold: float = hold_s()
	var total: float = hold + recovery_s()
	if sf > total or seg_n == 0:
		return
	if sf > hold and (now / 2) % 2 == 1:
		return
	var thick: bool = sf <= hold
	for k2 in seg_n:
		var a: Vector2 = K.rndv(seg_a[k2] + rp + Vector2(0, -14))
		var b: Vector2 = K.rndv(seg_b[k2] + rp + Vector2(0, -10))
		var dv: Vector2 = b - a
		var perp: Vector2 = Vector2(0, 1) if absf(dv.x) >= absf(dv.y) else Vector2(1, 0)
		if thick:
			ci.draw_line(a - perp, b - perp, K.COL_HANJI_DK, 1.0)
			ci.draw_line(a + perp, b + perp, K.COL_HANJI_DK, 1.0)
		ci.draw_line(a, b, K.COL_HANJI if thick else K.COL_HANJI_DK, 1.0)
		if thick:
			ci.draw_rect(Rect2(b - Vector2(2, 2), Vector2(5, 5)), K.COL_HWANG)
