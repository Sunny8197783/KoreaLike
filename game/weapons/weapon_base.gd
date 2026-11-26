class_name WeaponBase
extends RefCounted
## 무구 행동 원형(archetype)의 기반. 소유: combat.
## 하나의 무구 = WeaponBase 하위 원형 스크립트 + weapons.json 레벨 테이블(진화·결합은 stats) + 원형 파라미터(archetype_registry.gd).
## 하위 원형이 구현하는 것: fire() / tick(dt) / draw(ci) (+선택: on_projectile_hit / on_projectile_end / on_projectile_step / proj_visual / _action / _strike)
## 발사 시각은 Beat.try_fire 가 정한다(장단 박 양자화 phase_carry, 판정 없음). 하위 클래스는 박을 직접 보지 않는다.
##
## 피해 파이프라인: deal() → (결합 색 결정 · 표식/공포 증폭 · 정예 배율) → DamageCalc.roll(신빨·결단) → EnemyManager.queue_hit
##   (틱 13 resolve_hits 가 풀이 배율·매듭 잠금·결단타·넉백 거리 해석). 붉은 무구는 풀릴 기색 일반 잡귀를 조준하지 않는다(02 5.2).
## 연출(GAME_FEEL 3.1·3.2): feel.windup_f 선딜은 박 앞당김으로 재생, 타격 = 박 틱, impact_hold_f 홀드 + recovery_f 후딜. 전부 렌더 전용.
##   좌표는 정수(K.rndv), 회전은 90° 단위(픽셀 정확)만, 배율 1.

const KIND_WEAPON: StringName = &"weapon"
const KIND_EVO: StringName = &"evo"
const KIND_UNION: StringName = &"union"
const F_PULL: int = 1                # deal opts: 백 무구지만 풀릴 기색을 끌어온다(부채)
const F_NO_CRIT: int = 2             # 지속 피해 등: 결단 판정 없음
const F_NO_SFX: int = 4

var id: StringName = &""
var base_id: StringName = &""        # 원본 무구 id(진화·결합은 대표 무구) — SFX·feel 기준
var stem: String = ""                # "sinkal" (sfx_wpn_<stem>)
var kind: StringName = KIND_WEAPON
var def: Dictionary = {}
var params: Dictionary = {}          # archetype_registry 파라미터
var feel: Dictionary = {}            # weapons.json feel(진화·결합은 원본 feel 위에 덮어씀)
var level: int = 1
var max_level: int = 8
var slot: int = 0
var color: int = K.DmgColor.RED
var downbeat: bool = false
var beat_key: StringName = &""
var mgr: Node2D = null               # WeaponManager
var lv: Dictionary = {}              # 현재 레벨 행(진화·결합: 원본 Lv8 행 + stats)
var is_sub: bool = false             # 결합 무구의 부속(넋전 공전 등): weapon_fired 를 내지 않는다
var subs: Array[WeaponBase] = []
var _hit_last: PackedInt32Array = PackedInt32Array()   # 적 슬롯별 마지막 타격 game_tick (같은 무구 재타격 간격)
var _q: PackedInt32Array = PackedInt32Array()          # 공용 쿼리 버퍼
var fires_total: int = 0
var hits_total: int = 0              # 디버그 집계(봇 리포트): 적중 수 · 요청 피해 합
var dmg_total: float = 0.0


func setup(p_def: Dictionary, p_slot: int, p_mgr: Node2D, p_params: Dictionary, p_kind: StringName = KIND_WEAPON) -> void:
	def = p_def
	kind = p_kind
	id = StringName(String(def.get("id", "")))
	params = p_params
	slot = p_slot
	mgr = p_mgr
	base_id = StringName(String(params.get("base", id)))
	stem = String(base_id).trim_prefix("wpn_")
	var c: String = String(def.get("color", "red"))
	color = K.DmgColor.WHITE if c == "white" else (K.DmgColor.UNION if c == "dual" else K.DmgColor.RED)
	downbeat = bool(params.get("downbeat", false))
	beat_key = StringName("w:%s%s" % [id, String(params.get("sub_key", ""))])
	_hit_last.resize(EnemyManager.CAPACITY)
	_hit_last.fill(-100000)
	_q.resize(512)
	_strike_alloc()
	_build_feel()
	if kind == KIND_WEAPON:
		max_level = int(def.get("max_level", 8))
	else:
		max_level = 1
	set_level(1)
	_on_setup()


func _build_feel() -> void:
	feel = {}
	var bd: Dictionary = Data.weapon(String(base_id))
	var bf: Variant = bd.get("feel", null)
	if bf is Dictionary:
		feel = (bf as Dictionary).duplicate()
	if kind != KIND_WEAPON:
		var own: Variant = def.get("feel", null)
		if own is Dictionary:
			for k: String in own:
				feel[k] = own[k]
	var pf: Variant = params.get("feel", null)
	if pf is Dictionary:
		for k2: String in pf:
			feel[k2] = pf[k2]


func set_level(p_level: int) -> void:
	level = clampi(p_level, 1, max_level)
	if kind == KIND_WEAPON:
		var levels: Variant = def.get("levels", [])
		if levels is Array and not levels.is_empty():
			lv = levels[mini(level, levels.size()) - 1]
	else:
		# 진화·결합: 원본 무구 Lv8 행을 바탕으로 stats 를 덮는다(빠진 필드 — spd 등 — 는 원본값)
		lv = {}
		var bd: Dictionary = Data.weapon(String(base_id))
		var bl: Variant = bd.get("levels", [])
		if bl is Array and not bl.is_empty():
			lv = (bl[bl.size() - 1] as Dictionary).duplicate()
		var st: Variant = def.get("stats", {})
		if st is Dictionary:
			for k: String in st:
				lv[k] = st[k]
		var ov: Variant = params.get("stats", null)
		if ov is Dictionary:
			for k2: String in ov:
				lv[k2] = ov[k2]
	_on_level()
	for sw in subs:
		sw._on_level()


## 현재 레벨 수치(없으면 default).
func s(field: String, default: float = 0.0) -> float:
	var v: Variant = lv.get(field, default)
	return float(v) if (v is float or v is int) else default


func has_field(field: String) -> bool:
	return lv.has(field)


func limit(field: String, default: float) -> float:
	var l: Variant = def.get("limits", null)
	if l is Dictionary and (l as Dictionary).has(field):
		return float(l[field])
	var bd: Dictionary = Data.weapon(String(base_id))
	var bl: Variant = bd.get("limits", null)
	if bl is Dictionary and (bl as Dictionary).has(field):
		return float(bl[field])
	return default


## 쿨다운(05 3.2.2a): P = max(min_period, cd × max(floor, 장단)) — 그리드 하한·신명 하한은 Beat 가 적용.
func cooldown() -> float:
	var jd: float = maxf(Data.num("weapons", "globals.cooldown.floor", 0.4), Game.stat(&"stat_jangdan", 1.0))
	if Game.sinmyeong_oreum:
		# 신명 오름: 장단 −15%p(HaewonSystem.jangdan_bonus), 하한 0.25 (core 통합, haewon 요청)
		jd = maxf(Data.num("weapons", "globals.cooldown.floor_sinmyeong_oreum", 0.25), Game.stat(&"stat_jangdan", 1.0) + HaewonSystem.jangdan_bonus())
	var mp: float = s("min_period", limit("min_period", 0.05))
	return maxf(mp, s("cd", 1.0) * jd)


func area_mult() -> float:
	return Game.stat(&"stat_doryang", 1.0)


func dur_mult() -> float:
	return Game.stat(&"stat_yeongheom", 1.0)


func speed_mult() -> float:
	return Game.stat(&"stat_gise", 1.0)


## 신장 수(Amount): 원형마다 해석이 다르다(amount_rule). 상한 limits.amt_cap.
func sinjang() -> int:
	return clampi(int(Game.stat(&"stat_sinjang", 0.0)), 0, 10)


## 개수 필드 + 신장 수(상한 amt_cap).
func amount(field: String = "amt", default: float = 1.0) -> int:
	var cap: int = int(limit("amt_cap", 10))
	return clampi(int(s(field, default)) + sinjang(), 1, maxi(cap, int(s(field, default))))


func is_white() -> bool:
	return color == K.DmgColor.WHITE


func is_red() -> bool:
	return color == K.DmgColor.RED


## 이 무구 연출의 주색(팔레트). 적 = jk 계열, 백·결합 = 한지 계열(순백 #f2ece0 금지).
func col_main() -> Color:
	return K.COL_JEOK if is_red() else K.COL_HANJI


func col_hi() -> Color:
	return K.COL_JEOK_HI if is_red() else K.COL_HANJI


func col_dk() -> Color:
	return K.COL_JEOK_DK if is_red() else K.COL_HANJI_DK


func player_pos() -> Vector2:
	return Game.player.global_position if Game.player != null else Vector2.ZERO


func move_dir() -> Vector2:
	var p: Player = Game.player as Player
	return p.last_move_dir if p != null else Vector2.DOWN


func moving_speed() -> float:
	var p: Player = Game.player as Player
	return p.vel.length() if p != null else 0.0


func enemies() -> EnemyManager:
	return Game.enemies as EnemyManager


func pool() -> ProjectilePool:
	return Game.projectiles as ProjectilePool


# ─── 조준 ────────────────────────────────────────────────────────────

## 조준 대상 슬롯. 붉은 무구: 풀릴 기색 일반 잡귀·자동조준 제외·소멸 중 제외(02 5.2).
## 백 무구: 풀릴 기색을 거리 ×0.6 으로 우대(지전 "풀릴 기색 우선"). elite_first: 정예 이상 우선(사인참사검).
func find_target(origin: Vector2, max_r: float, elite_first: bool = false) -> int:
	var em: EnemyManager = enemies()
	if em == null:
		return -1
	var best: int = -1
	var best_d: float = max_r * max_r
	var best_e: int = -1
	var best_ed: float = best_d
	var red: bool = is_red()
	for k in em.active_count:
		var i: int = em.active[k]
		var f: int = em.flags[i]
		if (f & (EnemyManager.F_DYING | EnemyManager.F_AUTO_TARGET_EXEMPT)) != 0:
			continue
		var pull: bool = (f & EnemyManager.F_PULLIL) != 0
		var elite: bool = (f & EnemyManager.F_ELITE_PLUS) != 0
		if red and pull and not elite:
			continue
		var dx: float = em.px[i] - origin.x
		var dy: float = em.py[i] - origin.y
		var d: float = dx * dx + dy * dy
		if not red and pull:
			d *= 0.36
		if d < best_d:
			best_d = d
			best = i
		if elite_first and elite and d < best_ed:
			best_ed = d
			best_e = i
	return best_e if best_e >= 0 else best


## 가장 가까운 적 방향(없으면 마지막 이동 방향).
func aim_dir(max_range_u: float = 14.0, elite_first: bool = false) -> Vector2:
	var em: EnemyManager = enemies()
	if em != null:
		var o: Vector2 = player_pos()
		var i: int = find_target(o, max_range_u * K.UNIT_PX, elite_first)
		if i >= 0:
			var d: Vector2 = em.pos_of(i) - o
			if d.length_squared() > 1.0:
				return d.normalized()
	return move_dir()


var _nn_d: PackedFloat32Array = PackedFloat32Array()


## 가장 가까운 서로 다른 n체(각궁). out 에 슬롯, 반환 개수.
func nearest_n(origin: Vector2, max_r: float, n: int, out: PackedInt32Array) -> int:
	var em: EnemyManager = enemies()
	if em == null or n <= 0:
		return 0
	if _nn_d.size() < out.size():
		_nn_d.resize(out.size())
	n = mini(n, out.size())
	var cnt: int = 0
	var lim: float = max_r * max_r
	var red: bool = is_red()
	for k in em.active_count:
		var i: int = em.active[k]
		var f: int = em.flags[i]
		if (f & (EnemyManager.F_DYING | EnemyManager.F_AUTO_TARGET_EXEMPT)) != 0:
			continue
		if red and (f & EnemyManager.F_PULLIL) != 0 and (f & EnemyManager.F_ELITE_PLUS) == 0:
			continue
		var dx: float = em.px[i] - origin.x
		var dy: float = em.py[i] - origin.y
		var d: float = dx * dx + dy * dy
		if d >= lim:
			continue
		if cnt < n:
			out[cnt] = i
			_nn_d[cnt] = d
			cnt += 1
		else:
			var worst: int = 0
			for j in range(1, cnt):
				if _nn_d[j] > _nn_d[worst]:
					worst = j
			if d < _nn_d[worst]:
				out[worst] = i
				_nn_d[worst] = d
	return cnt


## 4방향 인덱스(0 E, 1 S, 2 W, 3 N).
static func dir4_of(v: Vector2) -> int:
	if absf(v.x) >= absf(v.y):
		return 0 if v.x >= 0.0 else 2
	return 1 if v.y > 0.0 else 3


static func dir4_vec(d4: int) -> Vector2:
	match d4:
		1:
			return Vector2.DOWN
		2:
			return Vector2.LEFT
		3:
			return Vector2.UP
	return Vector2.RIGHT


# ─── 피해 파이프라인 ────────────────────────────────────────────────

## 재타격 간격 확인 + 기록. interval_s <= 0 이면 같은 틱 중복만 막는다.
func can_hit(enemy_slot: int, interval_s: float) -> bool:
	var t: int = Game.game_tick
	var iv: int = maxi(1, int(interval_s * K.TICK_HZ))
	if t - _hit_last[enemy_slot] < iv:
		return false
	_hit_last[enemy_slot] = t
	return true


## 적에게 피해 요청(이번 틱 resolve_hits 에서 일괄 해석).
## level_dmg: 레벨 피해(적 기준). 결합(양면) 무구는 대상이 풀릴 기색이면 백 모드로 white_dmg 비율을 쓴다.
## kb_u: 넉백 거리(u). 백 무구는 풀릴 기색을 밀지 않는다(globals.knockback_vs_pullil.white = 0) — F_PULL 이면 끌어온다.
func deal(enemy_slot: int, level_dmg: float, kb_dir: Vector2 = Vector2.ZERO, kb_u: float = 0.0, special_mult: float = 1.0, opts: int = 0) -> void:
	var em: EnemyManager = enemies()
	if em == null or not em.is_alive(enemy_slot):
		return
	var f: int = em.flags[enemy_slot]
	var pull: bool = (f & EnemyManager.F_PULLIL) != 0
	var elite: bool = (f & EnemyManager.F_ELITE_PLUS) != 0
	var col: int = color
	var dmg: float = level_dmg
	if col == K.DmgColor.UNION:
		if pull:
			col = K.DmgColor.WHITE
			var rd: float = s("dmg", 1.0)
			dmg = level_dmg * (s("white_dmg", rd * 0.4) / maxf(rd, 1.0))
		else:
			col = K.DmgColor.RED
	var white: bool = col == K.DmgColor.WHITE
	if white and pull and (opts & F_PULL) == 0:
		kb_u = 0.0
	var mult: float = special_mult * (mgr as WeaponManager).target_mult(enemy_slot)
	if elite and bool(params.get("elite_bonus", false)):
		mult *= maxf(1.0, s("elite", 1.0))
	var extra_crit: float = s("crit", 0.0) if (opts & F_NO_CRIT) == 0 else -1.0
	var r: Vector2 = DamageCalc.roll(dmg, white, extra_crit, mult)
	em.queue_hit(enemy_slot, r.x, col, r.y > 0.5, kb_dir, kb_u, slot)
	hits_total += 1
	dmg_total += r.x
	if (opts & F_NO_SFX) == 0:
		(mgr as WeaponManager).note_hit(self, enemy_slot)


## 원형 범위 피해(장판·파동·폭발). 반환: 맞힌 수.
func deal_circle(center: Vector2, r_px: float, level_dmg: float, kb_u: float = 0.0, interval_s: float = 0.0, special_mult: float = 1.0, opts: int = 0) -> int:
	var em: EnemyManager = enemies()
	if em == null:
		return 0
	var n: int = em.query_circle(center, r_px, _q)
	var hit: int = 0
	for k in n:
		var i: int = _q[k]
		if (em.flags[i] & EnemyManager.F_DYING) != 0:
			continue
		if not can_hit(i, interval_s):
			continue
		var d: Vector2 = em.pos_of(i) - center
		deal(i, level_dmg, d.normalized() if d.length_squared() > 0.01 else Vector2.RIGHT, kb_u, special_mult, opts)
		hit += 1
	return hit


## 상태이상 요청(enemies 소유 API, 있으면 호출). id: st_bongbak 봉박 · st_gyeongak 경악(공포) · st_gyeongjik 경직 · st_dunhwa 둔화.
func apply_status(enemy_slot: int, st: StringName, dur_s: float, strength: float = 1.0) -> void:
	var em: EnemyManager = enemies()
	if em == null or not em.is_alive(enemy_slot):
		return
	if em.has_method(&"apply_status"):
		em.call(&"apply_status", enemy_slot, st, dur_s, strength)
		return
	# TODO(enemies): apply_status(slot, st, dur_s, strength) 공개 API(둔화·경악 포함). 그때까지 봉박·경직만 freeze 로 대체(일반 잡귀 한정).
	if (st == &"st_bongbak" or st == &"st_gyeongjik") and (em.flags[enemy_slot] & EnemyManager.F_ELITE_PLUS) == 0:
		em.freeze(enemy_slot, maxi(1, int(dur_s * K.TICK_HZ)))


# ─── 지연 타격(낙뢰·꽃잎·후속 충격파) ──────────────────────────────

const STRIKE_CAP: int = 64
var st_t: PackedFloat32Array = PackedFloat32Array()      # 남은 시간(s), <= -1 비어 있음
var st_x: PackedFloat32Array = PackedFloat32Array()
var st_y: PackedFloat32Array = PackedFloat32Array()
var st_r: PackedFloat32Array = PackedFloat32Array()
var st_dmg: PackedFloat32Array = PackedFloat32Array()
var st_kb: PackedFloat32Array = PackedFloat32Array()
var st_code: PackedInt32Array = PackedInt32Array()
var st_fx: Array[StringName] = []
var st_live: int = 0


func _strike_alloc() -> void:
	st_t.resize(STRIKE_CAP)
	st_t.fill(-1.0)
	st_x.resize(STRIKE_CAP)
	st_y.resize(STRIKE_CAP)
	st_r.resize(STRIKE_CAP)
	st_dmg.resize(STRIKE_CAP)
	st_kb.resize(STRIKE_CAP)
	st_code.resize(STRIKE_CAP)
	st_fx.resize(STRIKE_CAP)
	ac_t.resize(ACT_CAP)
	ac_t.fill(-1.0)
	ac_code.resize(ACT_CAP)
	ac_x.resize(ACT_CAP)
	ac_y.resize(ACT_CAP)
	ac_m.resize(ACT_CAP)
	dot_h.resize(DOT_CAP)
	dot_h.fill(-1)
	dot_t.resize(DOT_CAP)
	dot_dps.resize(DOT_CAP)
	dot_acc.resize(DOT_CAP)


## delay_s 뒤 pos 에 반경 r_px 원형 피해(code: 하위 _strike 훅 구분, 0 = 기본 원형 피해).
func schedule_strike(pos: Vector2, delay_s: float, r_px: float, dmg: float, kb_u: float = 0.0, fx: StringName = &"", code: int = 0) -> void:
	var best: int = -1
	for k in STRIKE_CAP:
		if st_t[k] < -0.5:
			best = k
			break
	if best < 0:
		return
	st_t[best] = maxf(0.0, delay_s)
	st_x[best] = pos.x
	st_y[best] = pos.y
	st_r[best] = r_px
	st_dmg[best] = dmg
	st_kb[best] = kb_u
	st_code[best] = code
	st_fx[best] = fx
	st_live += 1


func _tick_strikes(dt: float) -> void:
	if st_live <= 0:
		return
	for k in STRIKE_CAP:
		if st_t[k] < -0.5:
			continue
		st_t[k] -= dt
		if st_t[k] <= 0.0:
			st_t[k] = -1.0
			st_live -= 1
			var p: Vector2 = Vector2(st_x[k], st_y[k])
			if st_code[k] == 0:
				deal_circle(p, st_r[k], st_dmg[k], st_kb[k])
			else:
				_strike(st_code[k], p, st_r[k], st_dmg[k], st_kb[k])
			if st_fx[k] != &"":
				play_fx(st_fx[k], p)


## 하위 원형: 특수 지연 타격(code > 0).
func _strike(_code: int, p: Vector2, r_px: float, dmg: float, kb_u: float) -> void:
	deal_circle(p, r_px, dmg, kb_u)


## 대기 중인 지연 타격 표시(작은 별 표식, 발동 직전 깜빡임). 하위 원형이 원할 때 draw() 에서 호출.
func draw_pending_strikes(ci: CanvasItem, c: Color) -> void:
	if st_live <= 0:
		return
	var blink: bool = (Game.anim_tick() / 3) % 2 == 0
	for k in STRIKE_CAP:
		if st_t[k] < -0.5 or st_t[k] > 0.6:
			continue
		var p: Vector2 = K.rndv(Vector2(st_x[k], st_y[k]))
		var cc: Color = c if (st_t[k] > 0.15 or blink) else K.COL_HWANG
		ci.draw_rect(Rect2(p + Vector2(-1, -3), Vector2(3, 7)), cc)
		ci.draw_rect(Rect2(p + Vector2(-3, -1), Vector2(7, 3)), cc)
		ci.draw_rect(Rect2(p, Vector2(1, 1)), K.COL_HANJI)


# ─── 예약 동작(연속 찌르기·2회전·후속 고리) ───────────────────────

const ACT_CAP: int = 24
var ac_t: PackedFloat32Array = PackedFloat32Array()
var ac_code: PackedInt32Array = PackedInt32Array()
var ac_x: PackedFloat32Array = PackedFloat32Array()
var ac_y: PackedFloat32Array = PackedFloat32Array()
var ac_m: PackedFloat32Array = PackedFloat32Array()


func schedule_action(delay_s: float, code: int, dir: Vector2 = Vector2.ZERO, mult: float = 1.0) -> void:
	for k in ACT_CAP:
		if ac_t[k] < -0.5:
			ac_t[k] = maxf(0.0, delay_s)
			ac_code[k] = code
			ac_x[k] = dir.x
			ac_y[k] = dir.y
			ac_m[k] = mult
			return


func _tick_actions(dt: float) -> void:
	for k in ACT_CAP:
		if ac_t[k] < -0.5:
			continue
		ac_t[k] -= dt
		if ac_t[k] <= 0.0:
			ac_t[k] = -1.0
			_action(ac_code[k], Vector2(ac_x[k], ac_y[k]), ac_m[k])


func _action(_code: int, _dir: Vector2, _mult: float) -> void:
	pass


# ─── 지속 피해(화상: 적, 결단 없음) ────────────────────────────────

const DOT_CAP: int = 128
var dot_h: PackedInt32Array = PackedInt32Array()
var dot_t: PackedFloat32Array = PackedFloat32Array()
var dot_dps: PackedFloat32Array = PackedFloat32Array()
var dot_acc: PackedFloat32Array = PackedFloat32Array()
var dot_live: int = 0


## 갱신형 지속 피해(같은 대상이면 시간 갱신, 더 강한 값 유지).
func add_dot(enemy_slot: int, dps: float, dur_s: float) -> void:
	var em: EnemyManager = enemies()
	if em == null:
		return
	var h: int = em.handle_of(enemy_slot)
	var free: int = -1
	for k in DOT_CAP:
		if dot_h[k] == h:
			dot_t[k] = maxf(dot_t[k], dur_s)
			dot_dps[k] = maxf(dot_dps[k], dps)
			return
		if free < 0 and dot_h[k] < 0:
			free = k
	if free < 0:
		return
	dot_h[free] = h
	dot_t[free] = dur_s
	dot_dps[free] = dps
	dot_acc[free] = 0.0
	dot_live += 1


func _tick_dots(dt: float) -> void:
	if dot_live <= 0:
		return
	var em: EnemyManager = enemies()
	for k in DOT_CAP:
		if dot_h[k] < 0:
			continue
		var i: int = em.slot_of(dot_h[k]) if em != null else -1
		dot_t[k] -= dt
		if i < 0 or not em.is_alive(i) or dot_t[k] <= 0.0:
			dot_h[k] = -1
			dot_live -= 1
			continue
		dot_acc[k] += dt
		if dot_acc[k] >= 0.5:
			dot_acc[k] -= 0.5
			deal(i, dot_dps[k] * 0.5, Vector2.ZERO, 0.0, 1.0, F_NO_CRIT | F_NO_SFX)


# ─── 선딜·타격·후딜 (GAME_FEEL 3.1·3.2, 렌더 전용) ────────────────

var wu_target: float = -1.0          # 선딜 중인 발사 박 시각(박 시계 초), -1 없음
var wu_anim_t0: float = 0.0          # 선딜 시작 연출 시각(Game.anim_time 단위)
var wu_len: float = 0.0
var fire_anim_tick: int = -100000    # 마지막 발사 틱(game_tick)
var fire_pos: Vector2 = Vector2.ZERO
var fire_dir: Vector2 = Vector2.RIGHT


func _feel_f(key: String, default: float) -> float:
	var v: Variant = feel.get(key, default)
	return float(v) if (v is float or v is int) else default


## 선딜 길이(초). feel.windup_f(20fps 프레임). 규칙: 선딜 + 타격 홀드 ≤ 그리드 간격의 80% → 넘으면 1f씩 줄임(최소 1f).
func windup_s() -> float:
	var wf: float = _feel_f("windup_f", 2.0 if id == &"wpn_sinkal" else 0.0)
	if wf <= 0.0:
		return 0.0
	var hold: float = _feel_f("impact_hold_f", 2.0)
	var step: float = Beat.beat_len_sec() if downbeat else Beat.grid_sec()
	var lim: float = step * 0.8 / 0.05
	while wf > 1.0 and wf + hold > lim:
		wf -= 1.0
	return wf * 0.05


func hold_s() -> float:
	return _feel_f("impact_hold_f", 2.0) * 0.05


func recovery_s() -> float:
	return _feel_f("recovery_f", 3.0) * 0.05


## 발사 후 경과(연출 시계, 초). 발사 전이면 큰 값.
func since_fire() -> float:
	return maxf(0.0, Game.anim_time() - float(fire_anim_tick) / K.TICK_HZ)


## 선딜 진행(0..1), 선딜 중이 아니면 -1.
func windup_prog() -> float:
	if wu_target < 0.0 or wu_len <= 0.0:
		return -1.0
	return clampf((Game.anim_time() - wu_anim_t0) / wu_len, 0.0, 1.0)


## 손 무기 동작 단계(design/19 §6.1, 렌더 전용). phase: idle | windup | hit | recover, t: 그 단계 진행 0..1.
## 선딜 진행값은 draw_windup_hand 가 쓰는 windup_prog() 그대로다. 타격 틱 = Events.weapon_fired.
func held_phase() -> Dictionary:
	var wp: float = windup_prog()
	if wp >= 0.0:
		return {"phase": &"windup", "t": wp}
	if fire_anim_tick < 0:
		return {"phase": &"idle", "t": 0.0}
	var sf: float = since_fire()
	var h: float = maxf(hold_s(), 0.05)
	if sf < h:
		return {"phase": &"hit", "t": sf / h}
	var r: float = maxf(recovery_s(), 0.05)
	if sf < h + r:
		return {"phase": &"recover", "t": (sf - h) / r}
	return {"phase": &"idle", "t": 0.0}


## 던진 무구가 아직 손에 돌아오지 않았는가(신칼 등 귀환형: 손 무기를 숨긴다). 기본 false.
func held_out() -> bool:
	return false


## 군중(화면 일반 잡귀 ≥40, 숫자 군중 모드 이력 — design/19 §5.1): 잔상·원판 끔, 고리 1px. 첫 프레임은 남긴다.
static func fx_crowd() -> bool:
	if Juice.number_crowd:
		return true
	var v: VfxPlayer = Game.vfx as VfxPlayer
	return v != null and v.atmosphere != null and v.atmosphere.crowd_n >= 40


## 새 타격 멈춤(J2: 작두 첫 적중·다중 처치, design/19 §5.0)을 쓰는가. 디버그 빌드의 --no-new-hitstop 은 전후 캡처를
## 같은 시뮬로 맞출 때만 쓴다(히트스톱은 프레임↔틱 묶음을 바꿔 봇 입력 시점이 달라진다).
static func new_hitstop_on() -> bool:
	return not (OS.is_debug_build() and DebugTools.arg("no-new-hitstop") != "")


## 하위 원형이 상시형(발사 없이 tick 만)일 때 false.
func uses_fire() -> bool:
	return true


## WeaponManager.sim_step 이 틱마다 호출.
func sim_step(dt: float) -> void:
	tick(dt)
	_tick_actions(dt)
	_tick_strikes(dt)
	_tick_dots(dt)
	for sw in subs:
		sw.sim_step(dt)
	if not uses_fire():
		return
	var ws: float = windup_s()
	if ws > 0.0 and wu_target < 0.0:
		var tf: float = Beat.request_fire(beat_key, cooldown(), downbeat)
		if tf - Game.beat_sec() <= ws + 0.0005:
			wu_target = tf
			wu_len = ws
			wu_anim_t0 = float(Game.game_tick) / K.TICK_HZ
			_windup_start()
	if Beat.try_fire(beat_key, cooldown(), downbeat):
		wu_target = -1.0
		fire_anim_tick = Game.game_tick
		fire_pos = player_pos()
		fires_total += 1
		fire()
		if not is_sub:
			_fire_sfx()
			Events.weapon_fired.emit(id, slot, player_pos())
	elif wu_target >= 0.0 and Game.beat_sec() > wu_target + 0.05:
		wu_target = -1.0                     # 박을 건너뜀(히트스톱) → 선딜 취소, 중립 복귀


func _fire_sfx() -> void:
	Audio.play_sfx(StringName("sfx_wpn_" + stem), &"SFX", -5.0, 0.05)


func _windup_start() -> void:
	pass


# ─── 연출 도우미(정수 좌표·90° 회전·배율 1) ──────────────────────

func play_fx(fx_id: StringName, pos: Vector2, flip: int = 0) -> void:
	var v: VfxPlayer = Game.vfx as VfxPlayer
	if v == null or fx_id == &"":
		return
	var fx: Dictionary = VfxLib.get_fx(fx_id)
	if bool(fx.get("loop", false)) or bool(fx.get("placeholder", true)):
		return                                   # 원샷 재생기에 루프 시트를 넣으면 끝나지 않는다
	v.play(fx_id, pos, 0.0, 1.0, {"flip": flip})


func fx_name(key: String) -> StringName:
	return StringName(String(feel.get(key, "")))


## 손 앵커(렌더 좌표): 플레이어 보간 위치 + 손 높이 16 + 방향 reach px.
func hand_point(dir: Vector2, reach: float = 6.0) -> Vector2:
	var p: Player = Game.player as Player
	var base: Vector2 = p.render_pos if p != null else player_pos()
	return K.rndv(base + Vector2(0, -16) + K.dir8(dir) * reach)


func render_origin() -> Vector2:
	var p: Player = Game.player as Player
	return p.render_pos if p != null else player_pos()


## 시트 한 프레임 그리기. d4: 0 E(원본), 1 S(+90°), 2 W(좌우 반전), 3 N(−90°). t: 재생 시각(초).
## 반환 false = 비루프 시트가 끝났거나 시트 없음.
func draw_sheet(ci: CanvasItem, fx_id: StringName, pos: Vector2, t: float, d4: int = 0, tint: Color = Color.WHITE, force_loop: bool = false) -> bool:
	if fx_id == &"":
		return false
	var fx: Dictionary = VfxLib.get_fx(fx_id)
	if bool(fx.get("placeholder", true)):
		return false
	var regions: Array = fx["regions"]
	if regions.is_empty():
		return false
	var n: int = regions.size()
	var fi: int = int(maxf(t, 0.0) * float(fx["fps"]))
	if bool(fx["loop"]) or force_loop:
		fi = fi % n
	elif fi >= n:
		return false
	var r: Rect2 = regions[fi]
	var ang: float = 0.0
	var sx: float = 1.0
	if d4 == 1:
		ang = PI * 0.5
	elif d4 == 2:
		sx = -1.0
	elif d4 == 3:
		ang = -PI * 0.5
	# 가산 지정(art_vfx_list add) 시트도 본체는 일반 블렌드로 그린다 — 붉은 시트의 먹 테두리가 무리 위에서 선을 지켜 준다(11-26 전후 비교).
	# 대신 첫 1~2f 를 add_overlay 로 가산 층(_add_ci)에 한 번 더 얹어 '강한 첫 프레임'을 낸다(design/19 §5.0 ②).
	ci.draw_set_transform(K.rndv(pos), ang, Vector2(sx, 1.0))
	ci.draw_texture_rect_region(fx["texture"], Rect2(-K.rndv(fx["pivot"]), r.size), r, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## 첫 프레임 겹침(design/19 §5.0 ② '강한 한 장'): 시트의 frame 번째 그림을 한지 단색 가산으로 한 번 더(배율 정수).
## 본 층(_draw) 안에서만 부른다. alpha 0.6 기본. 붉은 시트는 어두워서(평균 L≈0.1) 한지 쪽으로 1.3배 물들여 더한다.
func add_overlay(fx_id: StringName, pos: Vector2, frame: int = 0, d4: int = 0, alpha: float = 0.6, scl: int = 1, hole: Rect2 = Rect2()) -> void:
	var wm: WeaponManager = mgr as WeaponManager
	if wm == null or fx_id == &"":
		return
	var fx: Dictionary = VfxLib.get_fx(fx_id)
	if bool(fx.get("placeholder", true)):
		return
	var regions: Array = fx["regions"]
	if regions.is_empty():
		return
	var r: Rect2 = regions[clampi(frame, 0, regions.size() - 1)]
	if hole.has_area() and d4 == 0 and scl == 1:
		# 무당 몸 상자(design/19 §5.1: 내 VFX 채움 α ≤0.15)를 비우고 위·아래·좌·우 네 조각으로 나눠 더한다
		var dst: Rect2 = Rect2(K.rndv(pos) - K.rndv(fx["pivot"]), r.size)
		var hc: Rect2 = dst.intersection(hole)
		if hc.has_area():
			var parts: Array[Rect2] = [
				Rect2(dst.position, Vector2(dst.size.x, hc.position.y - dst.position.y)),
				Rect2(Vector2(dst.position.x, hc.end.y), Vector2(dst.size.x, dst.end.y - hc.end.y)),
				Rect2(Vector2(dst.position.x, hc.position.y), Vector2(hc.position.x - dst.position.x, hc.size.y)),
				Rect2(Vector2(hc.end.x, hc.position.y), Vector2(dst.end.x - hc.end.x, hc.size.y))]
			for pr: Rect2 in parts:
				if pr.size.x >= 1.0 and pr.size.y >= 1.0:
					wm.push_add(fx["texture"], pr, Rect2(r.position + (pr.position - dst.position), pr.size),
						Transform2D.IDENTITY, Color(1.3, 1.2, 1.0, alpha))
			return
	var ang: float = 0.0
	var sx: float = float(scl)
	if d4 == 1:
		ang = PI * 0.5
	elif d4 == 2:
		sx = -sx
	elif d4 == 3:
		ang = -PI * 0.5
	wm.push_add(fx["texture"], Rect2(-K.rndv(fx["pivot"]), r.size), r,
		Transform2D(ang, Vector2(sx, float(scl)), 0.0, K.rndv(pos)), Color(1.3, 1.2, 1.0, alpha))


## 시트 한 프레임을 정수 배율로(꽂힘 1f scale 2 등). 일반 블렌드.
func draw_sheet_frame(ci: CanvasItem, fx_id: StringName, pos: Vector2, frame: int, scl: int = 1, tint: Color = Color.WHITE) -> void:
	var fx: Dictionary = VfxLib.get_fx(fx_id)
	if bool(fx.get("placeholder", true)):
		return
	var regions: Array = fx["regions"]
	if regions.is_empty():
		return
	var r: Rect2 = regions[clampi(frame, 0, regions.size() - 1)]
	ci.draw_set_transform(K.rndv(pos), 0.0, Vector2(scl, scl))
	ci.draw_texture_rect_region(fx["texture"], Rect2(-K.rndv(fx["pivot"]), r.size), r, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 시트 길이(초). 시트 없으면 0.
func sheet_len(fx_id: StringName) -> float:
	if fx_id == &"":
		return 0.0
	var fx: Dictionary = VfxLib.get_fx(fx_id)
	if bool(fx.get("placeholder", true)):
		return 0.0
	return float((fx["regions"] as Array).size()) / maxf(1.0, float(fx["fps"]))


## 고리 밑 먹 받침(design/18 §1.6): 흰·회색 무리 위에서도 내 고리 선이 끊겨 보이지 않게 바깥 1px 먹. 어두운 색 선은 생략.
## 실선 고리(draw_ring)만 받친다. 점선 고리는 조각마다 호가 하나씩 늘어 묶음(draw call)이 크게 늘어서 뺐다(측정: 14:00 +55).
const COL_RING_INK: Color = Color(0.0549, 0.0431, 0.0863)    # 먹 #0e0b16


static func _ring_needs_ink(col: Color) -> bool:
	return col.a > 0.5 and (0.299 * col.r + 0.587 * col.g + 0.114 * col.b) > 0.3


## 1px 점선 원(장판 경계: 불투명 팔레트색, 반투명 금지). every: 몇 조각마다 하나 그릴지.
func draw_dotted_ring(ci: CanvasItem, c: Vector2, r: float, col: Color, every: int = 2, phase: float = 0.0) -> void:
	var seg: int = clampi(int(r / 3.0), 12, 72)
	for k in seg:
		if k % every == 0:
			var a0: float = TAU * float(k) / float(seg) + phase
			ci.draw_arc(K.rndv(c), roundf(r), a0, a0 + TAU / float(seg), 2, col, 1.0)


## 정수 1px 원(점선 없이). 선딜 예고·판정 원.
func draw_ring(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float = 1.0) -> void:
	var seg: int = clampi(int(r * 0.5), 12, 64)
	if r >= 3.0 and _ring_needs_ink(col):
		ci.draw_arc(K.rndv(c), roundf(r) + (w + 1.0) * 0.5, 0.0, TAU, seg, COL_RING_INK, 1.0)
	ci.draw_arc(K.rndv(c), roundf(r), 0.0, TAU, seg, col, w)


## 선딜 공통 표시: 손 앵커 반짝(#f5d66b 대신 팔레트 황) + 진행 중 예고선. 하위 원형이 draw() 첫머리에서 호출.
func draw_windup_hand(ci: CanvasItem, dir: Vector2) -> void:
	var wp: float = windup_prog()
	if wp < 0.0:
		return
	var hp: Vector2 = hand_point(dir, 6.0 + roundf(wp * 3.0))
	var c: Color = K.COL_HWANG if wp > 0.5 else col_hi()
	ci.draw_rect(Rect2(hp - Vector2(1, 1), Vector2(3, 3)), c)
	if wp > 0.5:
		ci.draw_rect(Rect2(hp + Vector2(-3, 0), Vector2(7, 1)), K.COL_HWANG)
		ci.draw_rect(Rect2(hp + Vector2(0, -3), Vector2(1, 7)), K.COL_HWANG)


# ─── 하위 원형이 덮어쓰는 훅 ───────────────────────────────────────

func _on_setup() -> void:
	pass


func _on_level() -> void:
	pass


func fire() -> void:
	pass


func tick(_dt: float) -> void:
	pass


func draw(_ci: CanvasItem) -> void:
	pass


## 바닥 층(지면 위·적 아래, z −2): 장판·마름쇠·예고 원.
func draw_ground(_ci: CanvasItem) -> void:
	pass


## WeaponManager._draw 가 호출: 본 무구 + 부속 + 대기 타격.
func draw_all(ci: CanvasItem) -> void:
	draw(ci)
	for sw in subs:
		sw.draw(ci)
	draw_pending_strikes(ci, col_main())


func draw_ground_all(ci: CanvasItem) -> void:
	draw_ground(ci)
	for sw in subs:
		sw.draw_ground(ci)


## 슬롯에서 빠질 때(진화·결합 교체). 신호 연결 해제 등.
func dispose() -> void:
	for sw in subs:
		sw.dispose()
	_on_dispose()


func _on_dispose() -> void:
	pass


## 부속 무구 생성(결합: 넋전 공전·약화 결계·길베 트레일 등). 같은 슬롯·자기 박 키.
func add_sub(arch_key: StringName, sub_params: Dictionary, sub_stats: Dictionary, sub_color: String) -> WeaponBase:
	var script: GDScript = ArchetypeRegistry.script_for(arch_key)
	var w: WeaponBase = script.new() as WeaponBase
	var d: Dictionary = {"id": String(id), "color": sub_color, "stats": sub_stats}
	var p: Dictionary = sub_params.duplicate()
	p["base"] = String(sub_params.get("base", base_id))
	p["sub_key"] = ":" + String(arch_key)
	w.is_sub = true
	w.setup(d, slot, mgr, p, KIND_UNION)
	subs.append(w)
	return w


## ProjectilePool 이 이 무구의 투사체가 적에 닿았을 때 호출.
## tag: spawn_player 의 tag(0 본탄, 1.. 보조탄). proj_index: 풀 인덱스(콜백 안에서 ProjectilePool.kill 로 소모 가능).
func on_projectile_hit(enemy_slot: int, dmg: float, dir: Vector2, _tag: int = 0, _proj_index: int = -1) -> void:
	deal(enemy_slot, dmg, dir, s("kb", 0.0))


## ProjectilePool 이 이 무구의 투사체가 사라질 때 호출. reason: ProjectilePool.END_RANGE/END_RETURNED/END_PIERCE.
func on_projectile_end(_tag: int, _pos: Vector2, _vel: Vector2, _reason: int) -> void:
	pass


## track=true 로 쏜 투사체가 틱마다(이동 후) 호출.
func on_projectile_step(_tag: int, _proj_index: int, _pos: Vector2) -> void:
	pass


## 투사체 표시 계약(GAME_FEEL 3.3): {fx, trail, orient: none|spin|dir4|dir8|dir16, fps, scale(1|2), lift_px, spark, recoil_px}.
## 원본은 feel(있으면 그대로), 없으면 projectile_texture() 를 그린다. 하위 원형이 덮어써도 된다.
func proj_visual(_tag: int) -> Dictionary:
	var out: Dictionary = {}
	for k: String in ["fx", "trail", "orient", "spark"]:
		if feel.has(k):
			out[k] = StringName(String(feel[k]))
	for k: String in ["fps", "scale", "lift_px", "recoil_px"]:
		if feel.has(k):
			out[k] = int(feel[k])
	if id == &"wpn_sinkal" and not out.has("fx"):
		# 파일럿 P3: 신칼 spin 8f @16fps(사전 렌더, 회전 금지), 16×16
		out["fx"] = &"vfx_sinkal_proj"
		out["orient"] = &"spin"
		out["fps"] = 16
		# r3: 나갈 때 dir8(칼끝 = 진행 방향, 술이 뒤로 → '던진 칼'), 정점(사거리 70% 이후)·귀환은 spin
		out["orient_out"] = &"dir8"
		out["orient_apex"] = &"spin"
		out["orient_ret"] = &"spin"
		out["apex_frac"] = 0.7
	return out


var _proc_tex: Texture2D = null


## 투사체 텍스처(플레이스홀더). assets/sprites/<weapon_id>/proj.png 가 있으면 그걸 쓴다.
func projectile_texture() -> Texture2D:
	var t: Texture2D = SpriteLib.tex("res://assets/sprites/%s/proj.png" % id)
	if t != null:
		return t
	if _proc_tex == null:
		_proc_tex = make_blade_texture(10, 3)
	return _proc_tex


## 절차적 칼날/검기 텍스처(팔레트 색만, 동쪽 향함). 무구 설정 시 1회 생성.
func make_blade_texture(w: int, h: int) -> Texture2D:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid: int = h / 2
	for x in w:
		var tip: bool = x >= w - 2
		for y in h:
			var dy: int = absi(y - mid)
			var half: int = 0 if tip else (mid if x > 1 else maxi(0, mid - 1))
			if dy > half:
				continue
			var c: Color = col_dk()
			if dy == 0:
				c = K.COL_HANJI if x >= w - 4 else col_hi()
			elif dy == 1:
				c = col_main()
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
