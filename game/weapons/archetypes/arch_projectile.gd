class_name ArchProjectile
extends WeaponBase
## 원형 projectile: 조준 탄/산탄/부메랑/직선 관통 검기 + 진화·결합 변형. 소유: combat.
## params:
##   return(bool 신칼) · spread_deg(기본 12) · fan_field("angle" → 레벨 angle 이 부채 전체각) · aim(nearest|distinct|elite|move)
##   amt_sinjang(신장 수 1당 +sinjang_per) · blade(절차적 검기 그림) · elite_bonus(정예 이상 ×elite)
##   catch(신장칼: 귀환 순간 catch_r 원형 참격) · blast(마지막 관통/사거리 끝 폭발 blast_r/blast_dmg) · burn(화상 burn_dps·burn_dur)
##   chain(노잣돈: 해원 시 chain_r 내 풀릴 기색 1체 연쇄 해원) · stars(이십팔수: 3u마다 별 → 0.5초 뒤 낙뢰, 28번째 검기 일제 낙뢰)
##   petals(넋신칼: 칼 경로 백 꽃잎) · sub_orbit(넋전 공전 부속) · sub_barrier(약화 결계 부속) · mirrors(칠성: 공전 거울 반사 검기 + 낙뢰)
## 레벨 필드: dmg, amt, spd(u/s), area(u: 사거리), pierce(-1 무한), hitbox(u), width(u, 검기 폭), kb(u), crit, elite

const NEAR_HIT_PX: float = 24.0        # 발사 지점에서 이 안에서 발사 틱에 맞으면 스미어 + 접촉점 칼
const SMEAR_TICKS: int = 1
const CONTACT_TICKS: int = 2
const WINDUP_REACH: float = 13.0       # 선딜 칼은 로브(적색) 밖에 — 같은 적색 위에서 사라지지 않게
const TAG_MAIN: int = 0
const TAG_REFLECT: int = 1

var _near_tick: int = -100000
var _near_to: Vector2 = Vector2.ZERO
var _near_from: Vector2 = Vector2.ZERO
var _targets: PackedInt32Array = PackedInt32Array()
var _trav: PackedFloat32Array = PackedFloat32Array()      # 풀 인덱스별 마지막 표식 이후 이동 거리
var _lastp: PackedVector2Array = PackedVector2Array()
var _marks: PackedByteArray = PackedByteArray()            # 풀 인덱스별 표식/반사 횟수
var _waves: int = 0
var _catch_tick: int = -100000
var _mirror_phase: float = 0.0
var _flash_t: float = -1.0


func _on_setup() -> void:
	_targets.resize(16)
	if _tracks():
		_trav.resize(ProjectilePool.CAPACITY)
		_lastp.resize(ProjectilePool.CAPACITY)
		_marks.resize(ProjectilePool.CAPACITY)
	if bool(params.get("sub_orbit", false)):
		add_sub(&"orbit", {"permanent": true}, {"dmg": s("orbit_dmg", 12.0), "amt": s("orbit", 3.0), "area": 2.2, "omega": 216, "hit_iv": 0.5, "cd": 4}, "white")
	if bool(params.get("sub_barrier", false)):
		add_sub(&"drop_zone", {"place": "follow", "push": true, "base": "wpn_sogeum"}, {"dmg": s("aura_dmg", 8.0), "area": s("aura_r", 2.6), "push": 0.8, "tick": 0.5, "dur": 1.0, "cd": 1.0}, "white")


func _tracks() -> bool:
	return bool(params.get("stars", false)) or bool(params.get("petals", false)) or bool(params.get("mirrors", false))


func _count() -> int:
	var n: int = maxi(1, int(s("amt", 1)))
	if bool(params.get("amt_sinjang", false)):
		n += sinjang() * int(params.get("sinjang_per", 1))
		n = mini(n, int(limit("amt_cap", 10)))
	return mini(n, int(Data.num("weapons", "globals.amount_cap_global", 10)) + 5)


func fire() -> void:
	var pp: ProjectilePool = pool()
	if pp == null:
		return
	var n: int = _count()
	var o: Vector2 = player_pos()
	var aim: String = String(params.get("aim", "nearest"))
	var range_u: float = s("area", 6.0)
	var base: Vector2
	if aim == "move":
		base = move_dir()
	elif aim == "elite":
		base = aim_dir(maxf(range_u, 10.0), true)
	else:
		base = aim_dir(range_u + 2.0)
	fire_dir = base
	var fan: float
	if String(params.get("fan_field", "")) == "angle":
		fan = deg_to_rad(s("angle", 30.0))
	else:
		fan = deg_to_rad(float(params.get("spread_deg", 12.0))) * float(n - 1)
	var spd: float = s("spd", 10.0) * K.UNIT_PX * speed_mult()
	var range_px: float = range_u * K.UNIT_PX
	var hit_r: float = maxf(s("hitbox", 0.3), s("width", 0.0) * 0.5) * K.UNIT_PX * sqrt(area_mult())
	var ret: bool = bool(params.get("return", false))
	var red: bool = is_red()
	var track: bool = _tracks()
	var nt: int = 0
	if aim == "distinct":
		nt = nearest_n(o, range_px, n, _targets)
	for k in n:
		var dir: Vector2
		if k < nt:
			dir = (enemies().pos_of(_targets[k]) - o).normalized()
		else:
			var t: float = 0.0 if n == 1 else (float(k) / float(n - 1) - 0.5)
			dir = base.rotated(fan * t)
		var i: int = pp.spawn_player(slot, o, dir * spd, range_px / maxf(spd, 1.0), hit_r, s("dmg", 5.0), int(s("pierce", 1)), ret, TAG_MAIN, red, track)
		if track and i >= 0:
			_trav[i] = 0.0
			_lastp[i] = o
			_marks[i] = 0
	_waves += 1
	if bool(params.get("stars", false)) and _waves % maxi(1, int(s("grand_every", 28))) == 0:
		_grand_bolts()
	_flash_t = 0.0


## 이십팔수: 화면 안 적 28체 일제 낙뢰.
func _grand_bolts() -> void:
	var em: EnemyManager = enemies()
	if em == null:
		return
	var n: int = em.query_circle(player_pos(), 11.0 * K.UNIT_PX, _q)
	var cnt: int = mini(n, int(s("grand_bolts", 28)))
	for k in cnt:
		var i: int = _q[k]
		schedule_strike(em.pos_of(i), 0.1 + 0.02 * float(k), s("bolt_r", 1.2) * K.UNIT_PX, s("grand_dmg", 60.0), 0.0, fx_name("fx_bolt"))
	play_fx(fx_name("fx_grand"), player_pos())
	Juice.add_trauma(0.35)


func on_projectile_hit(enemy_slot: int, dmg: float, dir: Vector2, tag: int = 0, proj_index: int = -1) -> void:
	var em: EnemyManager = enemies()
	if em == null:
		return
	var f: int = em.flags[enemy_slot]
	var pull: bool = (f & EnemyManager.F_PULLIL) != 0
	var han_before: float = em.han[enemy_slot]
	deal(enemy_slot, dmg * (s("reflect_mult", 0.7) if tag == TAG_REFLECT else 1.0), dir, s("kb", 0.0))
	if bool(params.get("burn", false)):
		add_dot(enemy_slot, s("burn_dps", 6.0), s("burn_dur", 3.0) * dur_mult())
	if bool(params.get("chain", false)) and pull and (f & EnemyManager.F_ELITE_PLUS) == 0:
		var puri: float = minf(Game.stat(&"stat_puri", 3.0), 6.0)
		if dmg * puri * Game.stat(&"stat_sinppal", 1.0) >= han_before:
			_chain_from(enemy_slot)
	if tag == TAG_MAIN and Game.game_tick - fire_anim_tick <= 1:
		var ep: Vector2 = em.pos_of(enemy_slot)
		if ep.distance_to(fire_pos) <= NEAR_HIT_PX:
			var bh: int = em.body_h_of(enemy_slot)
			_near_tick = Game.game_tick
			_near_from = hand_point(dir)
			_near_to = K.rndv(ep + Vector2(0, -roundf(bh * 0.5)) - dir * 3.0)
	if proj_index >= 0 and not bool(params.get("return", false)) and fx_name("fx_hit") != &"":
		play_fx(fx_name("fx_hit"), em.pos_of(enemy_slot) + Vector2(0, -8))


## 노잣돈 연쇄 해원: chain_r 안 다른 풀릴 기색 일반 잡귀 1체(연쇄의 연쇄 없음).
func _chain_from(src: int) -> void:
	var em: EnemyManager = enemies()
	var c: Vector2 = em.pos_of(src)
	var n: int = em.query_circle(c, s("chain_r", 3.0) * K.UNIT_PX, _q)
	for k in n:
		var i: int = _q[k]
		if i == src:
			continue
		var f: int = em.flags[i]
		if (f & EnemyManager.F_PULLIL) != 0 and (f & (EnemyManager.F_ELITE_PLUS | EnemyManager.F_DYING)) == 0:
			em.force_haewon(i, &"white")
			_chain_a = c
			_chain_b = em.pos_of(i)
			_chain_tick = Game.game_tick
			return


var _chain_a: Vector2 = Vector2.ZERO
var _chain_b: Vector2 = Vector2.ZERO
var _chain_tick: int = -100000


func on_projectile_end(_tag: int, pos: Vector2, _vel: Vector2, reason: int) -> void:
	if reason == ProjectilePool.END_RETURNED:
		if bool(params.get("catch", false)):
			deal_circle(player_pos(), s("catch_r", 1.5) * K.UNIT_PX * area_mult(), s("dmg", 20.0), 0.3)
			_catch_tick = Game.game_tick
		if stem == "sinkal":
			Audio.play_sfx(&"sfx_wpn_sinkal__return", &"SFX", -14.0, 0.05)
	elif bool(params.get("blast", false)):
		schedule_strike(pos, 0.0, s("blast_r", 1.5) * K.UNIT_PX * area_mult(), s("blast_dmg", 14.0), 0.2, fx_name("fx_blast"))


func on_projectile_step(tag: int, i: int, pos: Vector2) -> void:
	if i < 0 or i >= _trav.size():
		return
	_trav[i] += pos.distance_to(_lastp[i])
	_lastp[i] = pos
	if bool(params.get("stars", false)) and tag == TAG_MAIN:
		if _trav[i] >= 3.0 * K.UNIT_PX and int(_marks[i]) < int(s("bolts_per_wave", 3)):
			_trav[i] = 0.0
			_marks[i] += 1
			schedule_strike(pos, 0.5, s("bolt_r", 1.2) * K.UNIT_PX * area_mult(), s("bolt_dmg", 24.0), 0.0, fx_name("fx_bolt"))
	if bool(params.get("petals", false)):
		if _trav[i] >= 1.5 * K.UNIT_PX and int(_marks[i]) < 8:
			_trav[i] = 0.0
			_marks[i] += 1
			schedule_strike(pos, 0.3, s("petal_r", 1.0) * K.UNIT_PX * area_mult(), s("petal_dmg", 10.0), 0.0, fx_name("fx_petal"), 1)
	if bool(params.get("mirrors", false)) and tag == TAG_MAIN and _marks[i] == 0:
		var nm: int = maxi(1, int(s("mirrors", 4)))
		for k in nm:
			var mp: Vector2 = _mirror_pos(k, nm)
			if mp.distance_squared_to(pos) <= 196.0:
				_marks[i] = 1
				var pp: ProjectilePool = pool()
				var t: int = find_target(mp, 9.0 * K.UNIT_PX)
				var d: Vector2 = (enemies().pos_of(t) - mp).normalized() if t >= 0 else (mp - player_pos()).normalized()
				var spd: float = s("spd", 14.0) * K.UNIT_PX * speed_mult()
				pp.spawn_player(slot, mp, d * spd, s("area", 8.0) * K.UNIT_PX / spd, maxf(s("width", 1.0) * 0.5, 0.3) * K.UNIT_PX, s("dmg", 30.0), -1, false, TAG_REFLECT, false, false)
				if t >= 0:
					schedule_strike(enemies().pos_of(t), 0.25, s("bolt_r", 1.3) * K.UNIT_PX, s("bolt_dmg", 28.0), 0.0, fx_name("fx_bolt"))
				break


## 넋신칼 꽃잎(code 1): 백 꽃잎 — 결합이라도 꽃잎은 백.
func _strike(code: int, p: Vector2, r_px: float, dmg: float, kb_u: float) -> void:
	if code == 1:
		var save: int = color
		color = K.DmgColor.WHITE
		deal_circle(p, r_px, dmg, 0.0)
		color = save
	else:
		deal_circle(p, r_px, dmg, kb_u)


func _mirror_pos(k: int, n: int) -> Vector2:
	return player_pos() + Vector2.from_angle(_mirror_phase + TAU * float(k) / float(n)) * 2.5 * K.UNIT_PX


func tick(dt: float) -> void:
	_mirror_phase += 1.6 * dt


# ─── 렌더 전용 연출(파일럿 r3: GAME_FEEL 3.1·3.2) — 시뮬을 바꾸지 않는다 ─────────────

func proj_visual(tag: int) -> Dictionary:
	var out: Dictionary = super.proj_visual(tag)
	if bool(params.get("blade", false)) and not out.has("fx"):
		out["orient"] = &"dir4"
	return out


func projectile_texture() -> Texture2D:
	if _proc_tex == null:
		if bool(params.get("blade", false)):
			_proc_tex = make_blade_texture(clampi(int(s("width", 0.8) * 24.0), 16, 28), 5)
		else:
			_proc_tex = make_blade_texture(10, 3)
	return _proc_tex


func draw(ci: CanvasItem) -> void:
	var now: int = Game.anim_tick()
	# 선딜: 신칼 시트(파일럿) 또는 공통 손 반짝
	if wu_target >= 0.0:
		var d: Vector2 = aim_dir(s("area", 8.0) + 2.0, String(params.get("aim", "")) == "elite")
		var drew: bool = false
		if stem == "sinkal":
			var fx: Dictionary = VfxLib.get_fx(&"vfx_sinkal_windup")
			var regions: Array = fx.get("regions", [])
			if not bool(fx.get("placeholder", true)) and not regions.is_empty():
				var fi: int = mini(int((Game.anim_time() - wu_anim_t0) * float(fx["fps"])), regions.size() - 1)
				var r: Rect2 = regions[maxi(fi, 0)]
				var hp: Vector2 = hand_point(d) + K.rndv(K.dir8(d) * (WINDUP_REACH - 6.0))
				var flip: bool = d.x < 0.0
				ci.draw_set_transform(hp, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
				ci.draw_texture_rect_region(fx["texture"], Rect2(-K.rndv(fx["pivot"]), r.size), r)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				drew = true
		if not drew:
			draw_windup_hand(ci, d)
			if bool(params.get("blade", false)):
				# 칼날 기 모음: 손 앞 검기 예고선(진행에 따라 길어짐)
				var wp: float = windup_prog()
				var hp2: Vector2 = hand_point(d, 8.0)
				var ln: float = roundf(6.0 + 10.0 * wp)
				ci.draw_line(hp2, hp2 + K.rndv(K.dir8(d) * ln), col_dk(), 1.0)
	# 발사 섬광(손 16px 1f) + 검기 시전 시트
	var sf: float = since_fire()
	if sf < 0.05 and fx_name("fx_cast") == &"":
		var hp3: Vector2 = hand_point(fire_dir, 8.0)
		ci.draw_rect(Rect2(hp3 - Vector2(2, 2), Vector2(5, 5)), col_hi())
		ci.draw_rect(Rect2(hp3 - Vector2(0, 4), Vector2(1, 9)), K.COL_HANJI)
		ci.draw_rect(Rect2(hp3 - Vector2(4, 0), Vector2(9, 1)), K.COL_HANJI)
	if fx_name("fx_cast") != &"" and sf < 0.6 and not bool(params.get("catch", false)):
		draw_sheet(ci, fx_name("fx_cast"), hand_point(fire_dir, 4.0), sf, dir4_of(fire_dir))
	# 신장칼 귀환 참격
	if bool(params.get("catch", false)):
		var ct: float = float(now - _catch_tick) / K.TICK_HZ
		if ct >= 0.0 and ct < 0.4:
			if not draw_sheet(ci, fx_name("fx_cast"), render_origin() + Vector2(0, -12), ct):
				draw_ring(ci, render_origin(), s("catch_r", 1.5) * K.UNIT_PX * area_mult(), col_hi())
	# 노잣돈 연쇄선(종이돈 줄)
	if now - _chain_tick < 12:
		var a: Vector2 = K.rndv(_chain_a + Vector2(0, -10))
		var b: Vector2 = K.rndv(_chain_b + Vector2(0, -10))
		var steps: int = maxi(1, int(a.distance_to(b) / 4.0))
		for k in steps + 1:
			var q: Vector2 = K.rndv(a.lerp(b, float(k) / float(steps)))
			ci.draw_rect(Rect2(q, Vector2(2, 1)), K.COL_HANJI if k % 2 == 0 else K.COL_HWANG)
	# 칠성 거울
	if bool(params.get("mirrors", false)):
		var nm: int = maxi(1, int(s("mirrors", 4)))
		for k2 in nm:
			var mp: Vector2 = _mirror_pos(k2, nm) + Vector2(0, -14)
			if not draw_sheet(ci, &"vfx_myeongdu_mirror", mp, Game.anim_time() + float(k2) * 0.1):
				ci.draw_rect(Rect2(K.rndv(mp) - Vector2(3, 3), Vector2(7, 7)), K.COL_HWANG)
	# 근접 적중: 발사 틱 1f 스미어(3px, 무구 팔레트) + 접촉점 칼 2틱 (신칼 계열)
	if stem != "sinkal":
		return
	var e: int = now - _near_tick
	if e >= 0 and e < CONTACT_TICKS:
		var dv: Vector2 = _near_to - _near_from
		if e < SMEAR_TICKS:
			var n: int = maxi(1, int(maxf(absf(dv.x), absf(dv.y))))
			for k3 in n + 1:
				var q2: Vector2 = K.rndv(_near_from + dv * (float(k3) / float(n)))
				ci.draw_rect(Rect2(q2 - Vector2(1, 1), Vector2(3, 3)), K.COL_JEOK)
			for k4 in n + 1:
				var q3: Vector2 = K.rndv(_near_from + dv * (float(k4) / float(n)))
				ci.draw_rect(Rect2(q3, Vector2(1, 1)), K.COL_JEOK_HI)
		var sfx: Dictionary = VfxLib.get_fx(&"vfx_sinkal_proj")
		var sr: Array = sfx.get("regions", [])
		if sr.size() == 8 and not bool(sfx.get("placeholder", true)):
			var k8: int = int(roundf(atan2(dv.y, dv.x) / (PI / 4.0))) & 7
			var rr: Rect2 = sr[k8]
			ci.draw_texture_rect_region(sfx["texture"], Rect2(_near_to - K.rndv(sfx["pivot"]), rr.size), rr)
