class_name ArchOrbit
extends WeaponBase
## 원형 orbit: 공전체 N개(넋전 종이 인형). 소유: combat.
## params: permanent(넋꽃비·결합 부속: 상시 공전), petals(넋꽃비: petal_every_beats 박마다 넋전마다 꽃잎 낙하)
## 레벨 필드: dmg, amt, area(u: 공전 반경), omega(deg/s), dur(s: 유지), hit_iv(s), hitbox(u), petal_dmg, petal_r
## 연출: 생성 2f(아래에서 떠오름) → 공전(시트 4f) → 소멸 2f(위로 흩어짐), 접촉 시 한지 스파크 1f.

var _active_t: float = 0.0
var _phase: float = 0.0
var _spawn_tick: int = -100000
var _contact_tick: PackedInt32Array = PackedInt32Array()
var _last_beat: int = -1
var _beats: int = 0


func _on_setup() -> void:
	_contact_tick.resize(16)
	_contact_tick.fill(-100000)
	if _permanent():
		_active_t = 1e9
		_spawn_tick = Game.game_tick


func _permanent() -> bool:
	return bool(params.get("permanent", false)) or s("permanent", 0.0) > 0.0


func uses_fire() -> bool:
	return not _permanent()


func _count() -> int:
	return clampi(int(s("amt", 2)) + (0 if is_sub else sinjang()), 1, mini(int(limit("amt_cap", 10)), 16))


func fire() -> void:
	var dur: float = s("dur", 0.0) * dur_mult()
	_active_t = dur if dur > 0.0 else 1e9
	_spawn_tick = Game.game_tick


func _orbit_pos(k: int, n: int) -> Vector2:
	var r: float = s("area", 1.6) * K.UNIT_PX * area_mult()
	return player_pos() + Vector2.from_angle(_phase + TAU * float(k) / float(n)) * r


func tick(dt: float) -> void:
	if _active_t <= 0.0:
		return
	_active_t -= dt
	_phase += deg_to_rad(s("omega", 180.0)) * dt * (1.0 + (speed_mult() - 1.0) * 0.5)
	var em: EnemyManager = enemies()
	if em == null:
		return
	var n: int = _count()
	var hr: float = maxf(s("hitbox", 0.35), 0.25) * K.UNIT_PX * sqrt(area_mult())
	var iv: float = maxf(s("hit_iv", 0.5), 0.1)
	for k in n:
		var p: Vector2 = _orbit_pos(k, n)
		var c: int = em.query_circle(p, hr, _q)
		for j in c:
			var i: int = _q[j]
			if (em.flags[i] & EnemyManager.F_DYING) != 0:
				continue
			if can_hit(i, iv):
				deal(i, s("dmg", 5.0), (em.pos_of(i) - player_pos()).normalized(), 0.3)
				_contact_tick[k] = Game.game_tick
	if bool(params.get("petals", false)) and Beat.is_beat_tick and Beat.beat_index != _last_beat:
		_last_beat = Beat.beat_index
		_beats += 1
		if _beats % maxi(1, int(s("petal_every_beats", 2))) == 0:
			for k2 in n:
				var src: Vector2 = _orbit_pos(k2, n)
				var t: int = find_target(src, 6.0 * K.UNIT_PX)
				if t >= 0:
					schedule_strike(em.pos_of(t), 0.35, s("petal_r", 1.0) * K.UNIT_PX * area_mult(), s("petal_dmg", 10.0), 0.0, fx_name("fx_petal"))


func draw(ci: CanvasItem) -> void:
	var now: int = Game.anim_tick()
	var wp: float = windup_prog()
	if wp >= 0.0 and _active_t <= 0.0:
		draw_windup_hand(ci, move_dir())
	if _active_t <= -recovery_s():
		return
	var n: int = _count()
	var age: float = float(now - _spawn_tick) / K.TICK_HZ
	var rise: float = clampf(1.0 - age / maxf(0.05, hold_s()), 0.0, 1.0)      # 생성: 6px 아래에서 떠오름
	var vanish: float = clampf(-_active_t / maxf(0.05, recovery_s()), 0.0, 1.0) if _active_t <= 0.0 else 0.0
	var rp: Vector2 = render_origin() - player_pos()
	for k in n:
		var p: Vector2 = K.rndv(_orbit_pos(k, n) + rp + Vector2(0, -12.0 + 6.0 * rise - 8.0 * vanish))
		if vanish > 0.0 and (now / 2) % 2 == 0:
			continue
		if not draw_sheet(ci, fx_name("fx_prop"), p, Game.anim_time() + float(k) * 0.13, 0, Color.WHITE, true):
			var r: Rect2 = Rect2(p - Vector2(3, 5), Vector2(6, 10))
			ci.draw_rect(r, K.COL_HANJI)
			ci.draw_rect(r, K.COL_HEUK, false, 1.0)
		if now - _contact_tick[k] < 3:
			ci.draw_rect(Rect2(p + Vector2(-4, 0), Vector2(9, 1)), K.COL_HANJI)
			ci.draw_rect(Rect2(p + Vector2(0, -4), Vector2(1, 9)), K.COL_HANJI)
