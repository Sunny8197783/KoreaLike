extends Node
## 정예 · 중간보스 · 보스(역려 살형/한형) · 저승사자(비적대) · 별상 손님 NPC 제어. 소유: enemies.
## EnemyManager 의 자식 노드 "Bigs". 일반 잡귀와 같은 SoA 슬롯을 쓰고, 슬롯마다 Ctl(데이터 전용 객체) 하나를 붙인다.
## 매 틱 think() 를 부른다(개체 수 ≤ 12, 07 4.1 "정예 이상은 항상 A단계").
## 공격은 모두 enemy_hazards 예고(청·흑)를 거친다: 예고 최소 정예 0.7 / 중간보스·보스 0.8초, 풀릴 기색이면 +0.2초(07 2.7).
## 패턴 스케줄러: 가중 무작위, 같은 패턴 3연속 금지, 페이즈 첫 패턴 고정(07 4.8). 시뮬 난수 = Rng &"ai"/&"mboss".
## EnemyManager 타입을 참조하지 않는다(순환 참조 방지): 이동 모드·플래그 값은 아래 상수로 맞춘다.

const Hz: GDScript = preload("res://enemies/enemy_hazards.gd")

const MV_SEEK: int = 0
const MV_HOLD: int = 1
const MV_VEL: int = 2
const MV_POINT: int = 3
const MV_ORBIT: int = 4
const MV_FLEE: int = 5
const F_PULLIL: int = 2
const F_FLYING: int = 256
const F_INVULN: int = 2048
const F_AUTO_TARGET_EXEMPT: int = 4096
const F_PASS: int = 32768
const F_NONHOSTILE: int = 65536
const F_HIDDEN: int = 262144
const F_NO_PULLIL: int = 2097152

enum Kd { GENERIC, EOD, GEOGU, BULGA, DUEOK, YEOKGWI, DAEGWI, DOKKAEBI, GUMIHO, GANG, BOSS_YEOK, SAJA, SONNIM, HEOSANG }

## 슬롯별 제어 상태(데이터만, 역참조 없음)
class Ctl:
	extends RefCounted
	var slot: int = -1
	var handle: int = -1
	var kd: int = 0
	var sid: StringName = &""
	var tier: StringName = &""
	var phase: int = 1
	var pending_phase: int = 0
	var st: int = 0                 # 0 이동 / 1 예고 / 2 행동 / 3 회복
	var pat: StringName = &""
	var t: float = 0.0              # 상태 남은 시간
	var cd: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var last1: StringName = &""
	var last2: StringName = &""
	var tg: int = -1
	var aim: Vector2 = Vector2.ZERO
	var dir: Vector2 = Vector2.RIGHT
	var n: int = 0
	var form: StringName = &""
	var invuln_t: float = 0.0
	var far_t: float = 0.0
	var size_s: float = 1.0         # 어둑시니 크기 게이지 S
	var big_t: float = 0.0          # 어둑시니 S=3 누적
	var icd: float = 0.0
	var swallowed: int = 0
	var gauge: float = 0.0          # 손님 대접 게이지
	var gauge_hits: int = 0
	var obj: int = -1               # hazards 오브젝트(게이지·매듭·덩어리)
	var knot_k: int = 0             # 한형: 다음 매듭 번호(1..7)
	var segs_left: int = 7
	var seg_floor: float = 0.0
	var open_t: float = 0.0         # 한형 열림 창 남은 초
	var bound: bool = true
	var respawn_t: float = 0.0
	var knots: PackedInt32Array = PackedInt32Array()   # 한형: 지금 떠 있는 매듭(hazards 오브젝트), [0] = 주 매듭
	var seg_n: int = 7              # 한형: 전체 구간 수
	var open_n: int = 1             # 한형: 이번 열림 창이 푼 구간 수(고리로 매듭 n개)
	var open_dur: float = 8.0
	var open_at: float = 0.0        # 열림 시작 게임 초(빠른 딜 보상 판정)
	var guards: PackedInt32Array = PackedInt32Array()
	var route: StringName = &""
	var lumps: PackedInt32Array = PackedInt32Array()   # hazards 오브젝트(살 덩어리)
	var lump_sp: Array[StringName] = []
	var lump_w: PackedInt32Array = PackedInt32Array()  # 덩어리별 깨운 원귀 핸들
	var lump_i: int = 0
	var lump_t: float = 0.0
	var prog_t: float = 0.0
	var parent: int = -1
	var summons: PackedFloat32Array = PackedFloat32Array()   # 보스 분리 소환 문턱(남은 것)
	var ttae_called: bool = false
	var scatter_t: float = 0.0
	var hp_last: float = 1.0
	var leave_t: float = 0.0
	var trail_t: float = 0.0
	var passes: int = 0
	var hanpuri: int = 0
	var kneel: bool = false

var em: Node = null
var _ctl: Array = []               # 활성 Ctl 목록(작음)
var _q: PackedInt32Array = PackedInt32Array()
var _kwanmang: bool = false
var _sonnim: Ctl = null
var _boss: Ctl = null
var _tele_min: Dictionary = {"elite": 0.7, "mboss": 0.8, "boss": 0.8}
var _player_r: float = 9.6
var _yeokgwi_toechi: int = 0
var _yeokgwi_haewon: int = 0
var _gongsu_once: Dictionary = {}
var _haengcha_done: bool = false     # 손님 행차(evt_sonnim_haengcha): 런당 1회
var _sonnim_gauge: float = 0.0       # 행차에서 받은 대접 게이지 → 보스 아레나 손님으로 이월


func _ready() -> void:
	_q.resize(32)
	_player_r = Data.num("enemies", "global_rules.player_hitbox_u", 0.3) * K.UNIT_PX
	var tm: Variant = Data.get_value("enemies", "global_rules.telegraph_min_s", null)
	if tm is Dictionary:
		_tele_min = tm
	Events.trial_start.connect(func(_s: int, _d: StringName) -> void: _kwanmang = true)
	Events.trial_end.connect(func(_s: int, _d: StringName, _w: StringName) -> void: _kwanmang = false)
	Events.enemy_killed.connect(_on_any_killed)
	Events.ring_closed.connect(_on_ring_closed)
	Events.pickup_collected.connect(_on_pickup)


func count() -> int:
	return _ctl.size()


func _hz() -> Node2D:
	return em.get("hazards") as Node2D


func _u(x: float) -> float:
	return x * K.UNIT_PX


func _cm() -> float:
	return 1.0 + Data.num("enemies", "scaling.C_damage.c", 0.06) * Game.time_sec() / 60.0


func _kd_of(sid: String) -> int:
	if sid.begins_with("elite_eodukssini"):
		return Kd.EOD
	match sid:
		"elite_geogu_gwi":
			return Kd.GEOGU
		"elite_bulgasari":
			return Kd.BULGA
		"elite_dueoksini":
			return Kd.DUEOK
		"elite_yeokgwi_ttae":
			return Kd.YEOKGWI
		"mboss_daegwi":
			return Kd.DAEGWI
		"mboss_dokkaebi":
			return Kd.DOKKAEBI
		"mboss_gumiho":
			return Kd.GUMIHO
		"mboss_gangcheori":
			return Kd.GANG
		"boss_yeokryeo":
			return Kd.BOSS_YEOK
		"mboss_dokkaebi__heosang":
			return Kd.HEOSANG
	if sid.begins_with("chaser_jeoseung_saja"):
		return Kd.SAJA
	if sid == "npc_byeolsang_sonnim":
		return Kd.SONNIM
	return Kd.GENERIC


# ─── 수명 ──────────────────────────────────────────────────────────────

func attach(i: int, opts: Dictionary) -> void:
	var c: Ctl = Ctl.new()
	c.slot = i
	c.handle = em.handle_of(i)
	c.sid = em.species_id_of(i)
	c.tier = em.tier_of(i)
	c.kd = _kd_of(String(c.sid))
	c.parent = int(opts.get("parent", -1))
	for k in 8:
		c.cd[k] = Rng.range_s(&"ai", 1.0, 3.0)
	em.set_big(i, c)
	_ctl.append(c)
	match c.kd:
		Kd.EOD:
			c.size_s = 0.6 if String(c.sid).ends_with("__small") else 1.0
			em.set_han(i, 1.0e9, 1.0e9)                       # 한 없음: 크기 게이지로만 결말(07 6.1)
			em.set_flag(i, F_NO_PULLIL, true)
			_apply_eod_size(c)
		Kd.BOSS_YEOK:
			_boss_init(c)
		Kd.SAJA:
			c.route = StringName(String(opts.get("route", "bow" if em.n_ratio() >= 0.5 else "sal_geodum")))
			em.set_flag(i, F_PASS | F_NONHOSTILE | F_INVULN | F_AUTO_TARGET_EXEMPT, true)
			_saja_init(c)
		Kd.SONNIM:
			em.set_flag(i, F_PASS | F_NONHOSTILE | F_INVULN | F_AUTO_TARGET_EXEMPT, true)
			c.obj = int(_hz().call("add_obj", Hz.OKind.GAUGE, em.pos_of(i) + Vector2(0, -52), 0.0))
			c.gauge = float(opts.get("gauge", 0.0))
			c.route = &"haengcha" if bool(opts.get("haengcha", false)) else &"seated"
			c.dir = (opts.get("dir", Vector2.RIGHT) as Vector2).normalized() if opts.get("dir", null) is Vector2 else Vector2.RIGHT
			c.leave_t = 30.0 if c.route == &"haengcha" else 0.0
			_sonnim = c
		Kd.DAEGWI, Kd.DOKKAEBI, Kd.GUMIHO, Kd.GANG:
			c.phase = 1
			c.cd[0] = 0.8        # 페이즈 첫 패턴 고정(학습 가능성)
			if c.kd == Kd.GANG:
				em.set_flag(i, F_FLYING, true)
		Kd.BULGA:
			c.hp_last = em.han_max[i]
		Kd.YEOKGWI:
			_try_haengcha(c)
	_emit_pattern(c, &"arrive", 0.0)


## 손님 행차(07 6.5.2 evt_sonnim_haengcha): 첫 역귀 떼(호위)가 나타날 때 런당 1회, 가마 행렬이 플레이어 앞을
## 1.2u/s 로 30초 가로지른다. 2u 안 공물을 받으면 대접 게이지 +25(보스 아레나로 이월).
func _try_haengcha(c: Ctl) -> void:
	if _haengcha_done or _sonnim != null or Game.player == null:
		return
	_haengcha_done = true
	var pp: Vector2 = Game.player.global_position
	var side: float = 1.0 if Rng.chance(&"ai", 0.5) else -1.0
	var dir: Vector2 = Vector2(side, 0.0)
	var start: Vector2 = pp - dir * _u(9.0) + Vector2(0.0, _u(Rng.range_s(&"ai", -2.5, 2.5)))
	var sh: int = em.spawn(&"npc_byeolsang_sonnim", start, {"haengcha": true, "dir": dir, "intro_s": 0.8})
	if Game.autotest:
		print("[enemies] %s sonnim haengcha h=%d" % [K.fmt_time(Game.time_sec()), sh])
	# 호위: 이 역귀 떼를 가마 뒤로 붙인다(행렬처럼 보이게)
	em.set_pos(c.slot, start - dir * _u(2.0), true)
	if not _gongsu_once.has(&"sonnim_haengcha"):
		_gongsu_once[&"sonnim_haengcha"] = true
		Events.gongsu_spoken.emit(&"", &"sonnim_haengcha", "차린 상이 지나간다. 공물을 바쳐 대접하세요.")


func detach(i: int) -> void:
	for k in _ctl.size():
		var c: Ctl = _ctl[k]
		if c.slot == i:
			_cleanup(c)
			_ctl.remove_at(k)
			return


func _cleanup(c: Ctl) -> void:
	var hz: Node2D = _hz()
	if not c.knots.is_empty():
		_free_knots(c)
	if c.kd == Kd.BOSS_YEOK:
		hz.gop_f = -1.0
	if c.obj >= 0:
		hz.call("free_obj", c.obj)
		c.obj = -1
	for o in c.lumps:
		hz.call("free_obj", o)
	c.lumps.clear()
	if _sonnim == c:
		if c.route == &"haengcha":
			_sonnim_gauge = c.gauge
		_sonnim = null
	if _boss == c:
		_boss = null


func form_of(i: int) -> StringName:
	var c: Variant = em.get("big")[i] if i >= 0 else null
	return (c as Ctl).form if c is Ctl else &""


func _ctl_of(i: int) -> Ctl:
	var c: Variant = em.get("big")[i]
	return c as Ctl if c is Ctl else null


# ─── 틱 ────────────────────────────────────────────────────────────────

func sim_pre(dt: float) -> void:
	for c: Ctl in _ctl:
		for k in 8:
			if c.cd[k] > 0.0:
				c.cd[k] -= dt
		if c.icd > 0.0:
			c.icd -= dt
		if c.invuln_t > 0.0:
			c.invuln_t -= dt
			if c.invuln_t <= 0.0 and c.kd != Kd.SAJA and c.kd != Kd.SONNIM and not (c.kd == Kd.BOSS_YEOK and c.form == &"han" and c.bound):
				em.set_flag(c.slot, F_INVULN, false)


func on_timer(_i: int) -> void:
	pass   # bigs 는 Ctl.t 를 쓴다(ai_t 미사용)


func think(i: int, dt: float, pp: Vector2, d: float) -> void:
	var c: Ctl = _ctl_of(i)
	if c == null:
		return
	if c.t > 0.0:
		c.t -= dt
	match c.kd:
		Kd.EOD:
			_think_eod(c, dt, pp, d)
		Kd.GEOGU:
			_think_geogu(c, dt, pp, d)
		Kd.BULGA:
			_think_bulga(c, dt, pp, d)
		Kd.DUEOK:
			_think_dueok(c, dt, pp, d)
		Kd.YEOKGWI:
			_think_yeokgwi(c, dt, pp, d)
		Kd.DAEGWI:
			_think_daegwi(c, dt, pp, d)
		Kd.DOKKAEBI:
			_think_dokkaebi(c, dt, pp, d)
		Kd.GUMIHO:
			_think_gumiho(c, dt, pp, d)
		Kd.GANG:
			_think_gang(c, dt, pp, d)
		Kd.BOSS_YEOK:
			_think_boss(c, dt, pp, d)
		Kd.SAJA:
			_think_saja(c, dt, pp, d)
		Kd.SONNIM:
			_think_sonnim(c, dt, pp, d)
		_:
			em.set_move(i, MV_SEEK, em.speed[i])
	if c.kd != Kd.SAJA and c.kd != Kd.SONNIM and c.kd != Kd.BOSS_YEOK:
		_recall(c, dt, pp, d)


## 재배치(07 10.5): 정예 22u 5초 → 전방 12u, 중간보스 25u → 예고 0.8초 뒤 전방 10u.
func _recall(c: Ctl, dt: float, pp: Vector2, d: float) -> void:
	var mboss: bool = c.tier == K.TIER_MBOSS
	var lim: float = _u(25.0 if mboss else 22.0)
	if d > lim:
		c.far_t += dt
		if c.far_t >= (0.0 if mboss else 5.0) and c.st == 0:
			var fwd: Vector2 = _player_fwd()
			var to: Vector2 = pp + fwd * _u(10.0 if mboss else 12.0)
			if mboss:
				var tg: int = _hz().call("add_tg", Hz.Shape.MARK, to, Vector2.RIGHT, 24.0, 0.0, 0.8, 0.0, c.handle, Hz.Act.NONE)
				_hz().call("set_callback", tg, c.slot * 16 + 1)
				c.st = 1
				c.t = 0.85
				c.pat = &"teleport"
				c.aim = to
			else:
				em.set_pos(c.slot, to)
			c.far_t = 0.0
	else:
		c.far_t = 0.0


func _player_fwd() -> Vector2:
	var pl: Node2D = Game.player
	if pl == null:
		return Vector2.RIGHT
	var v: Variant = pl.get("last_move_dir")
	return (v as Vector2).normalized() if v is Vector2 and (v as Vector2).length_squared() > 0.0001 else Vector2.DOWN


func _tele(c: Ctl, base: float) -> float:
	var mn: float = float(_tele_min.get(String(c.tier), 0.7))
	var add: float = Data.num("enemies", "global_rules.giseak.elite_plus_telegraph_add_s", 0.2) if (int(em.flags[c.slot]) & F_PULLIL) != 0 else 0.0
	return maxf(base, mn) + add


func _pullil(c: Ctl) -> bool:
	return (int(em.flags[c.slot]) & F_PULLIL) != 0


func _pos(c: Ctl) -> Vector2:
	return Vector2(em.px[c.slot], em.py[c.slot])


func _emit_pattern(c: Ctl, pat: StringName, tele: float) -> void:
	Events.enemy_pattern.emit(c.handle, c.sid, pat, _pos(c), tele)


## 패턴 고르기: 가중 무작위, 같은 패턴 3연속 금지.
func _pick(c: Ctl, ids: Array[StringName], weights: PackedFloat32Array) -> StringName:
	var tot: float = 0.0
	for k in ids.size():
		if ids[k] == c.last1 and ids[k] == c.last2:
			continue
		tot += weights[k]
	if tot <= 0.0:
		return ids[0]
	var r: float = Rng.range_s(&"ai", 0.0, tot)
	for k in ids.size():
		if ids[k] == c.last1 and ids[k] == c.last2:
			continue
		r -= weights[k]
		if r <= 0.0:
			c.last2 = c.last1
			c.last1 = ids[k]
			return ids[k]
	return ids[ids.size() - 1]


## 예고 끝 콜백(hazards → 여기). key = slot × 16 + 코드.
func on_tg(key: int, _tg: int, c0: Vector2) -> void:
	var slot: int = key >> 4
	var code: int = key & 15
	var c: Ctl = _ctl_of(slot) if slot >= 0 and slot < 2560 else null
	if c == null:
		return
	match code:
		1:   # 순간이동 도착
			em.set_pos(c.slot, c0)
			em.add_dust(c0, Vector2.RIGHT)
			c.st = 0
		2:   # 뚝딱 → 고리 파동
			var w: int = _hz().call("add_tg", Hz.Shape.RING, c0, Vector2.RIGHT, _u(1.5), 0.0, 0.05, 12.0, c.handle, Hz.Act.WAVE)
			_hz().call("set_act_wave", w, _u(5.0), 0.6, _u(0.4), 4)
			Juice.screen_shake(0.18)
		3:   # 두억시니 내려찍기 착지
			em.damage_commons(c0, _u(2.2), 25.0 * _cm(), 1.0, 0)
			em.push_commons(c0, _u(2.2), _u(1.0))
			em.add_dust(c0, Vector2.LEFT)
			em.add_dust(c0, Vector2.RIGHT)
			Juice.screen_shake(0.32)
		4:   # 정예 휘두르기 착지(먼지만)
			em.add_dust(c0, c.dir)
		5:   # 대귀 소환점
			em.spawn(&"mboss_daegwi__sogwi", c0, {"parent": c.handle, "intro_s": 0.3})


# ─── 정예 ──────────────────────────────────────────────────────────────

## 어둑시니(07 6.1): 보면 커지고, 등을 돌리면 작아진다. 한 없음, S ≤ 0.3 이면 정적 소멸(= 정예 해원).
func _think_eod(c: Ctl, dt: float, pp: Vector2, d: float) -> void:
	var i: int = c.slot
	var small: bool = String(c.sid).ends_with("__small")
	var p: Vector2 = _pos(c)
	if (Game.game_tick + i) % 6 == 0:
		var fwd: Vector2 = _player_fwd()
		var to: Vector2 = p - pp
		var seen: bool = d <= _u(14.0) and to.normalized().dot(fwd) >= cos(deg_to_rad(45.0))
		var dts: float = dt * 6.0
		if seen:
			c.size_s += Data.num("enemies", "elites.0.growth.cone_grow_per_s", 0.04) * dts
		else:
			c.size_s -= Data.num("enemies", "elites.0.growth.outside_shrink_per_s", 0.08) * dts
		c.size_s = clampf(c.size_s, 0.0, 3.0)
		_apply_eod_size(c)
		var vanish_at: float = 0.4 if small else Data.num("enemies", "elites.0.size_gauge.min_vanish", 0.3)
		if c.size_s <= vanish_at:
			em.kill_now(i, K.KIND_HAEWON, &"white")
			return
	if c.size_s >= 3.0:
		c.big_t += dt
	if c.st == 0:
		var spd: float = clampf(1.4 + 0.4 * (c.size_s - 1.0), 1.0, 2.2)
		em.set_move(i, MV_SEEK, _u(spd))
		if c.big_t >= 10.0 and c.cd[0] <= 0.0 and d < _u(6.0):
			# 삼킴(engulf): 예고 0.8 → 4u 돌진(6u/s), 접촉 30
			c.dir = (pp - p).normalized()
			c.st = 1
			c.t = _tele(c, 0.8)
			c.tg = _hz().call("add_tg", Hz.Shape.LINE, p, c.dir, _u(4.0), _u(1.2 * c.size_s * 0.6), c.t, 0.0, c.handle, Hz.Act.NONE)
			em.set_move(i, MV_HOLD, 0.0)
			_emit_pattern(c, &"eod_engulf", c.t)
	elif c.st == 1 and c.t <= 0.0:
		c.st = 2
		c.t = 4.0 / 6.0
		em.set_vel_dir(i, c.dir)
		em.set_move(i, MV_VEL, _u(6.0))
		em.set_stat(i, &"cmult", 3.0 / maxf(c.size_s, 0.1))      # 10·S × 3/S = 30
		em.set_stat(i, &"contact_cd", 0.0)
	elif c.st == 2 and c.t <= 0.0:
		c.st = 0
		c.cd[0] = 5.0
		em.set_stat(i, &"cmult", 1.0)


func _apply_eod_size(c: Ctl) -> void:
	var s: float = c.size_s
	var sc: int = 1 if s < 1.67 else (2 if s < 2.5 else 3)     # 정수 배율만(ART 1.1)
	em.set_visual(c.slot, sc, 0)
	em.set_stat(c.slot, &"radius", _u(0.6 * maxf(s, 0.3)))
	em.set_stat(c.slot, &"contact", 10.0 * maxf(s, 0.3))


## 거구귀(07 6.2): 흡입 — 원뿔 70°·7u, 예고 1.0초, 2.5초 동안 잡귀를 끌어 삼킴(최대 8), 끝나면 1.2초 경직(받는 피해 ×1.5).
func _think_geogu(c: Ctl, dt: float, pp: Vector2, d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	match c.st:
		0:
			var spd: float = em.speed[i] * (0.8 if c.swallowed >= 5 else 1.0)
			em.set_move(i, MV_SEEK, spd)
			if c.cd[0] <= 0.0 and d < _u(8.0) and _kwan_ok(c):
				c.dir = (pp - p).normalized()
				c.st = 1
				c.t = _tele(c, 1.2 if _pullil(c) else 1.0)
				c.tg = _hz().call("add_tg", Hz.Shape.CONE, p + Vector2(0, -16), c.dir, _u(7.0), deg_to_rad(35.0), c.t, 0.0, c.handle, Hz.Act.NONE, true)
				em.set_move(i, MV_HOLD, 0.0)
				_emit_pattern(c, &"geogu_inhale", c.t)
		1:
			if c.t <= 0.0:
				c.st = 2
				c.t = 2.5
				c.n = 0
		2:
			var mouth: Vector2 = p + c.dir * _u(0.9)
			var m: int = em.pull_commons(mouth, c.dir, deg_to_rad(35.0), _u(7.0), _u(3.0) * dt, _u(0.7), _q)
			for k in m:
				if c.swallowed >= 8:
					break
				em.vanish(_q[k])
				c.swallowed += 1
			# 입 앞 1.2u 안의 무당: 입 피해 15(흡입 한 번에 1회)
			if c.n == 0 and pp.distance_to(mouth) <= _u(1.2) + _player_r:
				Game.player.call("take_hit", 15.0, c.sid)
				c.n = 1
			if (Game.game_tick & 7) == 0:
				_hz().call("add_tg", Hz.Shape.CONE, p + Vector2(0, -16), c.dir, _u(7.0) * (0.4 + 0.6 * c.t / 2.5), deg_to_rad(35.0), 0.12, 0.0, c.handle, Hz.Act.NONE, true)
			if c.t <= 0.0:
				c.st = 3
				c.t = 1.2
				em.set_stat(i, &"dtaken", 1.5)
				em.set_visual(i, 0, 1)
		3:
			if c.t <= 0.0:
				c.st = 0
				c.cd[0] = 10.0 if _pullil(c) else 7.0
				em.set_stat(i, &"dtaken", 1.0)
				em.set_visual(i, 0, 0)


## 불가사리(07 6.3): 휘두르기(원뿔 120°·2.5u, 예고 0.7), 쇠붙이 흡수(filter_damage).
func _think_bulga(c: Ctl, _dt: float, pp: Vector2, d: float) -> void:
	_melee_cone(c, pp, d, &"bulgasari_swipe", _u(3.0), _u(2.5), 60.0, 0.7, 18.0 * _cm(), 5.0 if _pullil(c) else 3.0)


func _melee_cone(c: Ctl, pp: Vector2, d: float, pat: StringName, trig: float, rng: float, half_deg: float, tele: float, dmg: float, cd: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	match c.st:
		0:
			em.set_move(i, MV_SEEK, em.speed[i])
			if c.cd[1] <= 0.0 and d < trig and _kwan_ok(c):
				c.dir = (pp - p).normalized()
				c.st = 1
				c.t = _tele(c, tele)
				c.tg = _hz().call("add_tg", Hz.Shape.CONE, p, c.dir, rng, deg_to_rad(half_deg), c.t, dmg, c.handle, Hz.Act.HIT, true)
				_hz().call("set_callback", c.tg, c.slot * 16 + 4)
				em.set_move(i, MV_HOLD, 0.0)
				_emit_pattern(c, pat, c.t)
		1:
			if c.t <= 0.0:
				c.st = 3
				c.t = 0.35
				em.set_visual(i, 0, 1)
		3:
			if c.t <= 0.0:
				c.st = 0
				c.cd[1] = cd
				em.set_visual(i, 0, 0)


## 두억시니(07 6.4): 내려찍기 원 2.2u(예고 0.9), 한 ≤ 50% 면 0.6초 뒤 3.0u 두 번째(기색이면 없음). 회복 2초 받는 피해 ×1.25.
func _think_dueok(c: Ctl, _dt: float, pp: Vector2, d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	match c.st:
		0:
			em.set_move(i, MV_SEEK, em.speed[i])
			if c.cd[1] <= 0.0 and d < _u(3.0) and _kwan_ok(c):
				c.st = 1
				c.t = _tele(c, 1.1 if _pullil(c) else 0.9)
				c.aim = p
				c.tg = _hz().call("add_tg", Hz.Shape.CIRCLE, p, Vector2.RIGHT, _u(2.2), 0.0, c.t, 25.0 * _cm(), c.handle, Hz.Act.HIT)
				_hz().call("set_callback", c.tg, c.slot * 16 + 3)
				em.set_move(i, MV_HOLD, 0.0)
				em.set_visual(i, 0, -2)
				_emit_pattern(c, &"dueok_slam", c.t)
		1:
			if c.t <= 0.0:
				em.set_visual(i, 0, 2)
				var second: bool = not _pullil(c) and em.han[i] <= em.han_max[i] * 0.5
				if second:
					c.st = 2
					c.t = 0.6
					var t2: float = _tele(c, 0.7)
					var tg2: int = _hz().call("add_tg", Hz.Shape.CIRCLE, c.aim, Vector2.RIGHT, _u(3.0), 0.0, t2 + 0.6, 25.0 * _cm(), c.handle, Hz.Act.HIT)
					_hz().call("set_callback", tg2, c.slot * 16 + 3)
					c.t = t2 + 0.6
				else:
					c.st = 3
					c.t = 2.0
					em.set_stat(i, &"dtaken", 1.25)
		2:
			if c.t <= 0.0:
				c.st = 3
				c.t = 2.0
				em.set_stat(i, &"dtaken", 1.25)
		3:
			if c.t <= 0.0:
				c.st = 0
				c.cd[1] = 4.0
				em.set_stat(i, &"dtaken", 1.0)
				em.set_visual(i, 0, 0)


## 역귀 떼(07 6.5.1): 원거리 띠 5~7u, 5초마다 역병 투척(착지 원 1.8u, 예고 0.8) → 역병 장판 6초. 기색 = 대접(공물 3u 안이면 먹고 해원).
func _think_yeokgwi(c: Ctl, _dt: float, pp: Vector2, d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	if _pullil(c):
		# 대접: 공물 3u 안 → 걸어가 1.5초 먹고 HAEWON_DRAIN
		if c.st == 2:
			em.set_move(i, MV_HOLD, 0.0)
			if c.t <= 0.0:
				em.kill_now(i, K.KIND_HAEWON, &"white")
			return
		var pm: Variant = Game.pickups
		var gi: int = int((pm as Object).call("find_special", &"pick_gongmul", p, _u(3.0))) if pm is Object else -1
		if gi >= 0:
			var gp: Vector2 = (pm as Object).call("special_pos", gi)
			em.set_move(i, MV_POINT, _u(2.5), gp.x, gp.y)
			if gp.distance_to(p) < 14.0 and bool((pm as Object).call("take_special", gi)):
				c.st = 2
				c.t = 1.5
				_emit_pattern(c, &"yeokgwi_daejeop", 1.5)
		else:
			em.set_move(i, MV_SEEK, em.speed[i])
		return
	match c.st:
		0:
			if d > _u(7.0):
				em.set_move(i, MV_SEEK, em.speed[i])
			elif d < _u(5.0):
				em.set_move(i, MV_FLEE, _u(1.6))
			else:
				em.set_move(i, MV_HOLD, 0.0)
			var own: int = int(_hz().call("zones_of", c.handle, Hz.ZKind.YEOKBYEONG))
			if c.cd[0] <= 0.0 and d < _u(8.0) and own < 4 and _kwan_ok(c):
				var pv: Variant = Game.player.get("vel")
				var lead: Vector2 = (pv as Vector2) * 0.5 if pv is Vector2 else Vector2.ZERO
				c.aim = pp + lead
				c.st = 1
				c.t = _tele(c, 0.8)
				var tg: int = _hz().call("add_tg", Hz.Shape.CIRCLE, c.aim, Vector2.RIGHT, _u(1.8), 0.0, c.t, 0.0, c.handle, Hz.Act.ZONE)
				_hz().call("set_act_zone", tg, Hz.ZKind.YEOKBYEONG, _u(1.8), 6.0, 6.0 * _cm())
				em.set_move(i, MV_HOLD, 0.0)
				em.set_visual(i, 0, -1)
				_emit_pattern(c, &"yeokgwi_throw", c.t)
		1:
			if c.t <= 0.0:
				c.st = 0
				c.cd[0] = 5.0
				em.set_visual(i, 0, 0)


## 관망(07 4.7): 시련 중 중간보스는 8u 거리 유지, 공격·소환 정지. 정예는 영향 없음.
func _kwan_ok(c: Ctl) -> bool:
	return not (_kwanmang and c.tier == K.TIER_MBOSS)


# ─── 중간보스 ──────────────────────────────────────────────────────────

func _phase_of(ratio: float) -> int:
	if ratio > 0.6:
		return 1
	if ratio > 0.35:
		return 2
	return 3


func _mboss_common(c: Ctl, pp: Vector2, d: float) -> bool:
	var i: int = c.slot
	if Game.autotest and (Game.game_tick % (15 * K.TICK_HZ)) == 0:
		print("[enemies] %s mboss %s phase=%d han=%.0f/%.0f (%.0f%%) hanpuri=%d d=%.1fu" % [K.fmt_time(Game.time_sec()), String(c.sid), c.phase, em.han[i], em.han_max[i], 100.0 * em.han[i] / maxf(em.han_max[i], 1.0), c.hanpuri, d / K.UNIT_PX])
	if _kwanmang:
		# 관망: 8u 유지 + 엎드림
		if d < _u(8.0):
			em.set_move(i, MV_FLEE, em.speed[i])
		else:
			em.set_move(i, MV_HOLD, 0.0)
		em.set_visual(i, 0, 2)
		return false
	if c.pending_phase > 0:
		_phase_transition(c)
	c.phase = _phase_of(em.han[i] / maxf(em.han_max[i], 1.0))
	return c.invuln_t <= 0.0


## 페이즈 전환: 1.0초 무적 + 포효(밀어내기 파동 3u, 피해 없음). 한은 경계에서 멈춰 있다(filter_damage).
func _phase_transition(c: Ctl) -> void:
	c.pending_phase = 0
	c.invuln_t = 1.0
	em.set_flag(c.slot, F_INVULN, true)
	_hz().call("cancel_owner", c.handle)
	c.st = 0
	c.t = 0.0
	var p: Vector2 = _pos(c)
	em.push_commons(p, _u(3.0), _u(1.5))
	var w: int = _hz().call("add_tg", Hz.Shape.RING, p, Vector2.RIGHT, _u(0.8), 0.0, 0.05, 0.0, c.handle, Hz.Act.WAVE)
	_hz().call("set_act_wave", w, _u(3.0), 0.35, _u(0.3), 0)
	Juice.screen_shake(0.4)
	c.cd[0] = 0.6
	_emit_pattern(c, &"phase", 1.0)


## 대귀(07 7.1): P1 소귀 소환 6(8초)·휘두르기·돌격 명령, P2 소환 8(6초)·돌진·휘두르기, P3 무릎 꿇음·휘두르기만.
func _think_daegwi(c: Ctl, _dt: float, pp: Vector2, d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	if not _mboss_common(c, pp, d):
		return
	match c.st:
		0:
			if c.phase == 3:
				em.set_move(i, MV_SEEK, _u(1.2))
				em.set_visual(i, 0, 1)
				if not c.kneel:
					c.kneel = true
					em.set_minion_smult(c.handle, 0.7)
			else:
				em.set_move(i, MV_SEEK, em.speed[i])
			if d < _u(3.0) and c.cd[1] <= 0.0:
				c.pat = &"daegwi_swing"
				c.dir = (pp - p).normalized()
				c.st = 1
				c.t = _tele(c, 1.0 if c.phase == 3 else 0.8)
				c.tg = _hz().call("add_tg", Hz.Shape.CONE, p, c.dir, _u(3.0), deg_to_rad(45.0), c.t, 20.0, c.handle, Hz.Act.HIT, true)
				_hz().call("set_callback", c.tg, c.slot * 16 + 4)
				em.set_move(i, MV_HOLD, 0.0)
				_emit_pattern(c, c.pat, c.t)
				return
			if c.phase == 3 or c.cd[0] > 0.0:
				return
			var ids: Array[StringName] = [&"daegwi_summon", &"daegwi_dolgyeok"]
			if c.phase != 1:
				ids = [&"daegwi_summon", &"daegwi_charge"]
			var pat: StringName = _pick(c, ids, PackedFloat32Array([2.0, 1.0]))
			c.pat = pat
			match pat:
				&"daegwi_summon":
					var cnt: int = 6 if c.phase == 1 else 8
					var cap: int = 30 if c.phase == 1 else 45
					cnt = mini(cnt, cap - int(em.minions_of(c.handle)))
					c.t = _tele(c, 0.6)
					for k in cnt:
						var a: float = TAU * float(k) / float(maxi(cnt, 1))
						var sp: Vector2 = p + Vector2(cos(a), sin(a)) * _u(3.0)
						var tg: int = _hz().call("add_tg", Hz.Shape.MARK, sp, Vector2.RIGHT, 10.0, 0.0, c.t, 0.0, c.handle, Hz.Act.NONE)
						_hz().call("set_callback", tg, c.slot * 16 + 5)
					c.cd[0] = 8.0 if c.phase == 1 else 6.0
					c.st = 3
					c.t += 0.2
				&"daegwi_dolgyeok":
					c.t = _tele(c, 1.0)
					c.st = 1
					em.set_visual(i, 0, -2)
					c.cd[0] = 12.0
				&"daegwi_charge":
					c.dir = (pp - p).normalized()
					c.t = _tele(c, 1.0)
					c.st = 1
					c.tg = _hz().call("add_tg", Hz.Shape.LINE, p, c.dir, _u(7.0), _u(1.5), c.t, 0.0, c.handle, Hz.Act.NONE)
					c.cd[0] = 7.0
			if c.st == 1:
				em.set_move(i, MV_HOLD, 0.0)
			_emit_pattern(c, pat, c.t)
		1:
			if c.t > 0.0:
				return
			match c.pat:
				&"daegwi_swing":
					c.st = 3
					c.t = 0.4
					c.cd[1] = 5.0 if c.phase == 3 else 4.0
				&"daegwi_dolgyeok":
					em.set_minion_smult(c.handle, 5.0 / 3.0)    # 소귀 5u/s 1.5초
					c.st = 2
					c.t = 1.5
					em.set_visual(i, 0, 0)
				&"daegwi_charge":
					em.set_vel_dir(i, c.dir)
					em.set_move(i, MV_VEL, _u(4.5))
					em.set_stat(i, &"cmult", 25.0 / maxf(em.contact[i], 1.0))
					em.set_stat(i, &"contact_cd", 0.0)
					c.st = 2
					c.t = 1.5
		2:
			if c.t <= 0.0:
				if c.pat == &"daegwi_dolgyeok":
					em.set_minion_smult(c.handle, 1.0)
				em.set_stat(i, &"cmult", 1.0)
				c.st = 3
				c.t = 0.6
				em.set_move(i, MV_HOLD, 0.0)
		3:
			if c.t <= 0.0:
				c.st = 0
				em.set_visual(i, 0, 1 if c.phase == 3 else 0)


## 도깨비(07 7.2): P1 뚝딱(3연타 원 1.5u + 고리 파동 4틈)·가짜 엽전, P2 허상 2·씨름 청하기·뚝딱, P3 도망·순간이동·가짜 엽전.
func _think_dokkaebi(c: Ctl, _dt: float, pp: Vector2, d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	if not _mboss_common(c, pp, d):
		return
	match c.st:
		0:
			if c.phase == 3:
				# P3 도망(리뷰 critical: 3.6u/s·5초 순간이동이면 4.0u/s 무당이 못 따라잡아 11:30 미해결 퇴장 반복) → 2.8u/s(한풀이 2회+ 2.2), 8초, 무당 기준 4u
				em.set_move(i, MV_FLEE, _u(2.2 if c.hanpuri >= 2 else 2.8))
				if c.cd[2] <= 0.0:
					# 순간이동(예고 0.5초)
					var a: float = Rng.range_s(&"ai", 0.0, TAU)
					var to: Vector2 = pp + Vector2(cos(a), sin(a)) * _u(4.0)
					var tg: int = _hz().call("add_tg", Hz.Shape.MARK, to, Vector2.RIGHT, 20.0, 0.0, 0.5, 0.0, c.handle, Hz.Act.NONE)
					_hz().call("set_callback", tg, c.slot * 16 + 1)
					c.cd[2] = 8.0
					_emit_pattern(c, &"dok_flee", 0.5)
				if c.cd[0] <= 0.0 and c.hanpuri < 2:
					_dok_fake_coin(c, p)
					c.cd[0] = 20.0
				return
			em.set_move(i, MV_SEEK, em.speed[i])
			if c.cd[0] > 0.0:
				return
			var ids: Array[StringName] = [&"dok_ttukttak", &"dok_fake_coin"]
			if c.phase != 1:
				ids = [&"dok_ttukttak", &"dok_ssireum", &"dok_heosang"]
			var w: PackedFloat32Array = PackedFloat32Array([2.0, 1.0]) if c.phase == 1 else PackedFloat32Array([2.0, 1.5, 1.0])
			var pat: StringName = _pick(c, ids, w)
			if pat == &"dok_fake_coin" and c.hanpuri >= 2:
				pat = &"dok_ttukttak"
			if pat == &"dok_heosang" and c.n > 0:
				pat = &"dok_ttukttak"
			c.pat = pat
			match pat:
				&"dok_ttukttak":
					c.st = 1
					c.n = 3
					_dok_hit(c, pp)
					c.cd[0] = 4.0
				&"dok_fake_coin":
					_dok_fake_coin(c, p)
					c.cd[0] = 5.0
				&"dok_heosang":
					c.t = _tele(c, 0.8)
					for k in 2:
						var a2: float = PI * float(k) + Rng.range_s(&"ai", -0.5, 0.5)
						em.spawn(&"mboss_dokkaebi__heosang", p + Vector2(cos(a2), sin(a2)) * _u(2.0), {"parent": c.handle, "intro_s": c.t})
					c.n = 1
					c.cd[0] = 6.0
					_emit_pattern(c, pat, c.t)
				&"dok_ssireum":
					# 씨름 청하기: 창 4초, 반지름 2u. 왼쪽 90° 부채꼴(도깨비가 무당을 볼 때 왼다리)로 들어가면 성공.
					c.st = 2
					c.t = 4.0
					c.dir = (pp - p).normalized()
					c.tg = _hz().call("add_tg", Hz.Shape.RING, p, c.dir, _u(2.0), 0.0, 4.0, 0.0, c.handle, Hz.Act.NONE, true)
					var left: Vector2 = Vector2(c.dir.y, -c.dir.x)
					_hz().call("add_tg", Hz.Shape.MARK, p + left * _u(1.4), left, 8.0, 0.0, 4.0, 0.0, c.handle, Hz.Act.NONE)
					em.set_move(i, MV_HOLD, 0.0)
					c.cd[0] = 15.0
					_emit_pattern(c, pat, 4.0)
					if not _gongsu_once.has(&"dok_ssireum"):
						_gongsu_once[&"dok_ssireum"] = true
						Events.gongsu_spoken.emit(&"", &"dok_ssireum", "왼다리를 걸어라.")
		1:
			# 뚝딱 3연타: 예고가 끝날 때마다 다시 겨눈다
			if c.t <= 0.0:
				c.n -= 1
				if c.n > 0:
					_dok_hit(c, pp)
				else:
					c.st = 3
					c.t = 0.6
		2:
			# 씨름 창
			if d <= _u(2.0) + _player_r:
				var rel: Vector2 = (pp - p).normalized()
				var left2: Vector2 = Vector2(c.dir.y, -c.dir.x)
				if rel.dot(left2) >= cos(deg_to_rad(45.0)):
					em.freeze(i, 300)
					em.set_stat(i, &"dtaken", 1.5)
					em.set_han(i, maxf(1.0, em.han[i] - em.han_max[i] * 0.1))
					c.hanpuri += 1
					c.st = 3
					c.t = 5.0
					_hz().call("cancel_owner", c.handle)
					_emit_pattern(c, &"dok_ssireum_win", 0.0)
				else:
					Game.player.call("take_hit", 10.0, c.sid)
					c.st = 3
					c.t = 0.8
					_hz().call("cancel_owner", c.handle)
			elif c.t <= 0.0:
				c.st = 3
				c.t = 0.4
		3:
			if c.t <= 0.0:
				c.st = 0
				em.set_stat(i, &"dtaken", 1.0)


func _dok_hit(c: Ctl, pp: Vector2) -> void:
	var add: float = 0.3 if c.hanpuri >= 2 else 0.0
	c.t = _tele(c, 0.8 + add)
	c.tg = _hz().call("add_tg", Hz.Shape.CIRCLE, pp, Vector2.RIGHT, _u(1.5), 0.0, c.t, 22.0, c.handle, Hz.Act.HIT)
	_hz().call("set_callback", c.tg, c.slot * 16 + 2)
	em.set_move(c.slot, MV_HOLD, 0.0)
	_emit_pattern(c, &"dok_ttukttak", c.t)


func _dok_fake_coin(c: Ctl, p: Vector2) -> void:
	var pm: Variant = Game.pickups
	if not (pm is Object):
		return
	for k in 12:
		var a: float = TAU * float(k) / 12.0 + Rng.range_s(&"ai", -0.2, 0.2)
		var r: float = Rng.range_s(&"ai", _u(2.0), _u(5.0))
		(pm as Object).call("spawn_special", &"pick_gajja_yeopjeon", p + Vector2(cos(a), sin(a)) * r, 8.0)
	_emit_pattern(c, &"dok_fake_coin", 0.5)


## 구미호(07 7.3): 여우불(방사탄)·꼬리 휘두르기(270°)·가짜 공물, P3 여우구슬(8초 안에 주우면 한풀이).
func _think_gumiho(c: Ctl, _dt: float, pp: Vector2, d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	if not _mboss_common(c, pp, d):
		return
	match c.st:
		0:
			em.set_move(i, MV_SEEK, em.speed[i] * (0.8 if c.phase == 3 else 1.0))
			if d < _u(3.5) and c.cd[1] <= 0.0:
				c.pat = &"gumiho_tailsweep"
				c.dir = (pp - p).normalized()
				c.st = 1
				c.t = _tele(c, 0.8)
				c.tg = _hz().call("add_tg", Hz.Shape.CONE, p, -c.dir, _u(3.5), deg_to_rad(135.0), c.t, 18.0, c.handle, Hz.Act.HIT, true)
				em.set_move(i, MV_HOLD, 0.0)
				c.cd[1] = 5.0
				_emit_pattern(c, c.pat, c.t)
				return
			if c.cd[0] > 0.0:
				return
			if c.phase == 3 and c.n == 0:
				c.n = 1
				var a: float = Rng.range_s(&"ai", 0.0, TAU)
				Game.pickups.call("spawn_special", &"pick_yeou_guseul", p + Vector2(cos(a), sin(a)) * _u(4.0), 8.0)
				_emit_pattern(c, &"gumiho_bead", 0.0)
			var ids: Array[StringName] = [&"gumiho_foxfire", &"gumiho_fake_offering"]
			var pat: StringName = _pick(c, ids, PackedFloat32Array([2.0, 1.0]))
			c.pat = pat
			if pat == &"gumiho_foxfire":
				var cnt: int = 18 if c.phase == 2 else 9
				c.t = _tele(c, 1.0 if c.phase == 3 else 0.8)
				var tg: int = _hz().call("add_tg", Hz.Shape.RAYS, p + Vector2(0, -20), Vector2.RIGHT, 0.0, 0.0, c.t, 10.0, c.handle, Hz.Act.BULLETS)
				_hz().call("set_act_bullets", tg, cnt, _u(2.5), Rng.range_s(&"ai", 0.0, TAU), 5.0)
				c.cd[0] = 12.0 if c.phase == 3 else 8.0
			else:
				for k in 6:
					var a2: float = TAU * float(k) / 6.0
					Game.pickups.call("spawn_special", &"pick_gajja_gongmul", p + Vector2(cos(a2), sin(a2)) * Rng.range_s(&"ai", _u(3.0), _u(6.0)), 10.0)
				c.t = 0.5
				c.cd[0] = 6.0
			c.st = 3
			_emit_pattern(c, pat, c.t)
		1:
			if c.t <= 0.0:
				c.st = 3
				c.t = 0.4
		3:
			if c.t <= 0.0:
				c.st = 0


## 강철이(07 7.4): 비행 통과(선 1.5u, 예고 1.2) + 가뭄 장판, 맴돌기·숨결(원뿔 60°·6u), P2 가뭄 고리, P3 착지.
func _think_gang(c: Ctl, dt: float, pp: Vector2, d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	if not _mboss_common(c, pp, d):
		return
	match c.st:
		0:
			if c.phase == 3:
				em.set_move(i, MV_SEEK, _u(1.4))
			else:
				em.set_move(i, MV_ORBIT, _u(2.0), _u(6.0))
			if c.cd[0] > 0.0:
				return
			var ids: Array[StringName] = [&"gang_flyover", &"gang_breath", &"gang_drought_ring"]
			if c.phase == 3:
				ids = [&"gang_breath"]
			elif c.phase == 1:
				ids = [&"gang_flyover", &"gang_breath"]
			var pat: StringName = _pick(c, ids, PackedFloat32Array([1.5, 1.0, 1.0]))
			c.pat = pat
			match pat:
				&"gang_flyover":
					c.dir = (pp - p).normalized()
					c.aim = pp - c.dir * _u(8.0)
					c.t = _tele(c, 1.2)
					c.tg = _hz().call("add_tg", Hz.Shape.LINE, c.aim, c.dir, _u(16.0), _u(1.5), c.t, 0.0, c.handle, Hz.Act.NONE)
					c.st = 1
					em.set_move(i, MV_POINT, _u(7.0), c.aim.x, c.aim.y)
					c.cd[0] = 2.5
				&"gang_breath":
					c.dir = (pp - p).normalized()
					c.t = _tele(c, 1.1 if c.phase == 3 else 0.9)
					c.tg = _hz().call("add_tg", Hz.Shape.CONE, p, c.dir, _u(6.0), deg_to_rad(30.0), c.t, 12.0, c.handle, Hz.Act.HIT, true)
					c.st = 3
					em.set_move(i, MV_HOLD, 0.0)
					c.cd[0] = 4.0
				&"gang_drought_ring":
					c.t = _tele(c, 1.5)
					for k in 14:
						var a: float = TAU * float(k) / 14.0
						var zp: Vector2 = pp + Vector2(cos(a), sin(a)) * _u(7.0)
						var tg: int = _hz().call("add_tg", Hz.Shape.CIRCLE, zp, Vector2.RIGHT, _u(0.6), 0.0, c.t, 0.0, c.handle, Hz.Act.ZONE)
						_hz().call("set_act_zone", tg, Hz.ZKind.GAMUM, _u(0.6), 12.0, 0.0)
					c.st = 3
					c.cd[0] = 6.0
			_emit_pattern(c, pat, c.t)
		1:
			if c.t <= 0.0:
				# 통과: 선을 따라 7u/s, 접촉 20, 1.5u마다 가뭄 장판
				em.set_pos(c.slot, c.aim, false)
				em.set_vel_dir(i, c.dir)
				em.set_move(i, MV_VEL, _u(7.0))
				em.set_stat(i, &"cmult", 1.0)
				em.set_stat(i, &"contact_cd", 0.0)
				c.st = 2
				c.t = 16.0 / 7.0
				c.trail_t = 0.0
		2:
			c.trail_t -= dt
			if c.trail_t <= 0.0:
				c.trail_t = 1.5 / 7.0
				_hz().call("add_zone", Hz.ZKind.GAMUM, p, _u(0.75), 15.0, 0.0, c.handle, 0.0)
			if c.t <= 0.0:
				c.passes += 1
				c.st = 3
				c.t = 0.5
				c.cd[0] = 6.0 if c.passes % 3 == 0 else 0.6
		3:
			if c.t <= 0.0:
				c.st = 0


# ─── 보스: 역려(07 8.1) ────────────────────────────────────────────────

func _boss_init(c: Ctl) -> void:
	var i: int = c.slot
	var n: float = em.n_ratio()
	var hi: float = Data.num("enemies", "boss_common.form_rule.han_if_N_gte", 0.55)
	var lo: float = Data.num("enemies", "boss_common.form_rule.sal_if_N_lte", 0.45)
	if n >= hi:
		c.form = &"han"
	elif n <= lo:
		c.form = &"sal"
	else:
		c.form = &"sal" if Game.salgi >= 50.0 else &"han"
	var forced: String = DebugTools.arg("boss-form")
	if forced == "han" or forced == "sal":
		c.form = StringName(forced)
	var s_mult: float = 1.0 + Data.num("enemies", "scaling.S_salgi.k", 0.002) * Game.salgi
	_yeokgwi_haewon = int(em.haewon_count_of(&"elite_yeokgwi_ttae"))
	_yeokgwi_toechi = int(em.toechi_count_of(&"elite_yeokgwi_ttae"))
	if c.form == &"sal":
		var hm: float = minf(Data.num("enemies", "boss_common.sal.han_fixed", 130000.0) * s_mult, Data.num("enemies", "boss_common.sal.han_cap", 1.0e9))
		em.set_han(i, hm, hm)
		em.set_stat(i, &"speed", _u(Data.num("enemies", "bosses.0.form_sal.speed_u", 1.6)))
		em.set_stat(i, &"contact", Data.num("enemies", "bosses.0.form_sal.contact_dmg", 26.0))
		c.summons = PackedFloat32Array([1.0, 0.85, 0.7, 0.5, 0.35])
	else:
		var hm2: float = minf(Data.num("enemies", "boss_common.han.han_fixed", 85000.0) * s_mult, Data.num("enemies", "boss_common.han.han_cap", 1.0e9))
		var segs: int = int(Data.num("enemies", "boss_common.han.gopuri.segments", 7))
		var start: int = segs - mini(2, _yeokgwi_haewon)
		em.set_han(i, hm2 * float(start) / float(segs), hm2)
		em.set_stat(i, &"speed", _u(Data.num("enemies", "bosses.0.form_han.speed_u", 1.0)))
		em.set_stat(i, &"contact", Data.num("enemies", "bosses.0.form_han.contact_dmg", 12.0))
		em.set_flag(i, F_NO_PULLIL | F_INVULN, true)
		c.seg_n = segs
		c.segs_left = start
		c.knot_k = segs - start + 1
		c.bound = true
		c.respawn_t = 2.5
	c.phase = 1
	c.cd[0] = 2.5
	_boss = c
	# 손님 NPC: 아레나 가장자리(보스 뒤 6u)에 앉아 대접을 받는다(07 6.5.2). 이미 있으면(행차) 그대로.
	if _sonnim == null and Game.player != null:
		var p: Vector2 = _pos(c)
		var away: Vector2 = (p - Game.player.global_position).normalized()
		em.spawn(&"npc_byeolsang_sonnim", p + away * _u(6.0), {"intro_s": 1.0, "gauge": _sonnim_gauge})


func _think_boss(c: Ctl, dt: float, pp: Vector2, d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	var age: int = Game.game_tick - int(em.spawn_tick[i])
	if age < int(Data.num("enemies", "boss_common.intro_s", 2.0) * K.TICK_HZ):
		em.set_move(i, MV_HOLD, 0.0)
		return
	if c.scatter_t > 0.0:
		# 흩어짐(손님 흡족): 정지, 공격 없음, 받는 백 피해 ×1.5(filter_damage)
		c.scatter_t -= dt
		em.set_move(i, MV_HOLD, 0.0)
		em.set_visual(i, 0, 2)
		if c.scatter_t <= 0.0:
			em.set_visual(i, 0, 0)
		return
	if c.form == &"han":
		_think_boss_han(c, dt, pp, d)
		return
	if c.pending_phase > 0:
		_phase_transition(c)
	var ratio: float = em.han[i] / maxf(em.han_max[i], 1.0)
	c.phase = 1 if ratio > 0.7 else (2 if ratio > 0.35 else 3)
	if c.invuln_t > 0.0:
		return
	# 분리 소환(문턱): 퇴치 상위 종
	if c.summons.size() > 0 and ratio <= c.summons[0] + 0.0001 and c.st == 0:
		var th: float = c.summons[0]
		c.summons.remove_at(0)
		var k_sp: int = 0 if th >= 0.85 else (1 if th >= 0.5 else 2)
		var per: int = 12 if th >= 0.85 else (10 if th >= 0.5 else 8)
		c.t = _tele(c, 1.0)
		c.st = 3
		em.set_visual(i, 0, -3)
		for kk in k_sp + 1:
			var sp: StringName = em.top_toechi_species(kk)
			for n in per:
				var a: float = TAU * float(n) / float(per) + float(kk) * 0.3
				em.spawn(sp, p + Vector2(cos(a), sin(a)) * _u(2.2), {"intro_s": c.t, "no_variant": true})
		_emit_pattern(c, &"yeok_split_summon", c.t)
		return
	if not c.ttae_called and ratio <= 0.6:
		c.ttae_called = true
		var cnt: int = 2 + mini(2, _yeokgwi_toechi)
		for n2 in cnt:
			var a2: float = TAU * float(n2) / float(cnt)
			em.spawn(&"elite_yeokgwi_ttae", p + Vector2(cos(a2), sin(a2)) * _u(4.0), {"intro_s": 1.0})
		_emit_pattern(c, &"yeok_ttae_call", 1.0)
	match c.st:
		0:
			em.set_move(i, MV_SEEK, em.speed[i])
			if c.cd[0] > 0.0:
				return
			var ids: Array[StringName] = []
			var w: PackedFloat32Array = PackedFloat32Array()
			if c.phase == 1:
				ids = [&"yeok_pox_spray", &"yeok_plague_lob"]
				w = PackedFloat32Array([1.2, 1.0])
			elif c.phase == 2:
				ids = [&"yeok_mob_charge", &"yeok_pox_ring", &"yeok_plague_lob"]
				w = PackedFloat32Array([1.0, 1.0, 0.6])
			else:
				ids = [&"yeok_pox_spray", &"yeok_plague_lob"]
				w = PackedFloat32Array([1.0, 0.7])
			var pat: StringName = _pick(c, ids, w)
			c.pat = pat
			var weak: bool = c.phase == 3
			match pat:
				&"yeok_pox_spray":
					c.t = _tele(c, 1.0 if weak else 0.8)
					c.n = 2 if weak else 3
					c.aim = Vector2(Rng.range_s(&"ai", 0.0, TAU), 0)
					var tg: int = _hz().call("add_tg", Hz.Shape.RAYS, p + Vector2(0, -40), Vector2.RIGHT, 0.0, 0.0, c.t, 14.0, c.handle, Hz.Act.BULLETS)
					_hz().call("set_act_bullets", tg, 12, _u(3.2), c.aim.x, 6.0)
					c.st = 2
					c.trail_t = c.t + 0.3
					c.cd[0] = 8.0 if weak else 6.0
				&"yeok_plague_lob":
					var pv: Variant = Game.player.get("vel")
					var lead: Vector2 = (pv as Vector2) * 0.5 if pv is Vector2 else Vector2.ZERO
					var tgt: Vector2 = pp + lead
					var side: Vector2 = Vector2(-(tgt - p).y, (tgt - p).x).normalized() * _u(2.0)
					c.t = _tele(c, 1.0 if weak else 0.8)
					var r: float = _u(1.5 if weak else 2.0)
					for k in 3:
						var zp: Vector2 = tgt + side * float(k - 1)
						var tg2: int = _hz().call("add_tg", Hz.Shape.CIRCLE, zp, Vector2.RIGHT, r, 0.0, c.t, 0.0, c.handle, Hz.Act.ZONE)
						_hz().call("set_act_zone", tg2, Hz.ZKind.PLAGUE, r, 8.0, 10.0)
					c.st = 3
					c.cd[0] = 12.0 if weak else 9.0
				&"yeok_mob_charge":
					c.dir = (pp - p).normalized()
					c.t = _tele(c, 1.0)
					c.tg = _hz().call("add_tg", Hz.Shape.LINE, p, c.dir, _u(8.0), _u(2.0), c.t, 0.0, c.handle, Hz.Act.NONE)
					c.st = 1
					em.set_move(i, MV_HOLD, 0.0)
					c.cd[0] = 6.0
				&"yeok_pox_ring":
					c.t = _tele(c, 0.8)
					var a0: float = Rng.range_s(&"ai", 0.0, TAU)
					var tg3: int = _hz().call("add_tg", Hz.Shape.RAYS, p + Vector2(0, -40), Vector2.RIGHT, 0.0, 0.0, c.t, 14.0, c.handle, Hz.Act.BULLETS)
					_hz().call("set_act_bullets", tg3, 16, _u(2.6), a0, 6.0)
					var tg4: int = _hz().call("add_tg", Hz.Shape.RAYS, p + Vector2(0, -40), Vector2.RIGHT, 0.0, 0.0, c.t + 0.05, 14.0, c.handle, Hz.Act.BULLETS)
					_hz().call("set_act_bullets", tg4, 16, _u(3.6), a0 + PI / 16.0, 6.0)
					c.st = 3
					c.cd[0] = 7.0
			_emit_pattern(c, pat, c.t)
		1:
			if c.t <= 0.0 and c.pat == &"yeok_mob_charge":
				em.set_vel_dir(i, c.dir)
				em.set_move(i, MV_VEL, _u(10.0))
				em.set_stat(i, &"cmult", 30.0 / maxf(em.contact[i], 1.0))
				em.set_stat(i, &"contact_cd", 0.0)
				c.st = 2
				c.t = 0.8
				c.trail_t = 0.0
		2:
			if c.pat == &"yeok_mob_charge":
				c.trail_t -= dt
				if c.trail_t <= 0.0:
					c.trail_t = 0.12
					_hz().call("add_zone", Hz.ZKind.YEOKBYEONG, p, _u(0.5), 6.0, 10.0, c.handle, 0.0)
				if c.t <= 0.0:
					em.set_stat(i, &"cmult", 1.0)
					em.set_move(i, MV_HOLD, 0.0)
					em.add_dust(p, c.dir)
					c.st = 3
					c.t = 0.8
			elif c.pat == &"yeok_pox_spray":
				em.set_move(i, MV_HOLD, 0.0)
				c.trail_t -= dt
				if c.trail_t <= 0.0 and c.n > 1:
					c.n -= 1
					c.aim.x += deg_to_rad(15.0)
					var tg5: int = _hz().call("add_tg", Hz.Shape.RAYS, p + Vector2(0, -40), Vector2.RIGHT, 0.0, 0.0, 0.3, 14.0, c.handle, Hz.Act.BULLETS)
					_hz().call("set_act_bullets", tg5, 12, _u(3.2), c.aim.x, 6.0)
					c.trail_t = 0.3
				if c.n <= 1 and c.trail_t <= 0.0:
					c.st = 3
					c.t = 0.4
		3:
			if c.t <= 0.0:
				c.st = 0
				em.set_visual(i, 0, 0)


## 한형 고풀이(07 8.0.3): 묶임(무적) ⇄ 열림 창. 매듭을 만지거나 고리 안에 넣으면 풀린다.
func _think_boss_han(c: Ctl, dt: float, pp: Vector2, _d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	var hz: Node2D = _hz()
	em.set_move(i, MV_SEEK, em.speed[i] * (0.5 if not c.bound else 1.0))
	if c.bound:
		hz.gop_x = p.x
		hz.gop_y = p.y
		hz.gop_f = -1.0
		if c.knots.is_empty():
			c.respawn_t -= dt
			if c.respawn_t <= 0.0:
				_spawn_knot(c, pp, false)
		else:
			var touched: bool = false
			for kk in c.knots.size():
				var o: int = c.knots[kk]
				hz.o_lx[o] = p.x
				hz.o_ly[o] = p.y - 40.0
				if Vector2(hz.o_x[o], hz.o_y[o]).distance_to(pp) <= float(hz.o_r[o]) + _player_r:
					touched = true
			if touched:
				_untie(c, 1)     # 밟기 = 1구간. 여러 매듭을 고리로 함께 묶으면 n구간·긴 창(_on_ring_closed)
			else:
				# 호위 수비(매듭 4~7): 주 매듭 주위 1.5u 를 돈다
				var kp: Vector2 = Vector2(hz.o_x[c.knots[0]], hz.o_y[c.knots[0]])
				for k in c.guards.size():
					var gs: int = em.slot_of(c.guards[k])
					if gs >= 0:
						var a: float = Game.time_sec() * 1.6 + TAU * float(k) / 4.0
						em.set_move(gs, MV_POINT, _u(3.0), kp.x + cos(a) * _u(1.5), kp.y + sin(a) * _u(1.5))
		# 묶임 중 압박: 꽃 반점 탄 8발(5초)
		if c.cd[0] <= 0.0:
			var t: float = _tele(c, 0.8)
			var tg: int = hz.call("add_tg", Hz.Shape.RAYS, p + Vector2(0, -40), Vector2.RIGHT, 0.0, 0.0, t, 6.0, c.handle, Hz.Act.BULLETS)
			hz.call("set_act_bullets", tg, 8, _u(2.2), Rng.range_s(&"ai", 0.0, TAU), 6.0)
			c.cd[0] = 5.0
			_emit_pattern(c, &"yeok_flower_tear", t)
	else:
		c.open_t -= dt
		hz.gop_x = p.x
		hz.gop_y = p.y
		hz.gop_f = clampf(c.open_t / maxf(c.open_dur, 0.1), 0.0, 1.0)
		if em.han[i] <= c.seg_floor + 0.5:
			_segment_done(c)
		elif c.open_t <= 0.0:
			# 창 종료: 묶임 복귀, 같은 번호 매듭이 '반쯤 풀린 매듭'으로 2초 뒤 다른 자리에(구간 경계는 그대로 — 깎은 한은 남는다)
			c.bound = true
			em.set_flag(i, F_INVULN, true)
			em.set_flag(i, F_PULLIL, false)
			c.respawn_t = 2.0
			hz.gop_f = -1.0
			_emit_pattern(c, &"gopuri_rebind", 0.0)
			if Game.autotest:
				print("[enemies] %s gopuri rebind (window expired) han=%.0f floor=%.0f" % [K.fmt_time(Game.time_sec()), em.han[i], c.seg_floor])
			_say_once(&"gopuri_rebind", "다시 묶였다. 새 매듭을 밟아라.")


## 매듭 생성(한형). 무당 화면 안(무당에게서 3.5~5u, 화면 세로 절반 5.6u)·보스와 3.5u 이상 떨어진 곳 — 처음 하는 사람도 바로 보이게.
## 매듭 4번부터 2~3개가 함께 생긴다(덧매듭은 반쯤 풀린 표지 o_v=1): 밟으면 1구간, 고리로 n개를 함께 묶으면 n구간·창 8+4(n−1)초.
## near = 직전 창을 빨리 끝냄(화력 보상) → 2.5~3u 가까이.
func _spawn_knot(c: Ctl, pp: Vector2, near: bool = false) -> void:
	var p: Vector2 = _pos(c)
	var away: Vector2 = (pp - p).normalized() if pp.distance_squared_to(p) > 1.0 else Vector2.RIGHT
	var best: Vector2 = pp + away.rotated(Rng.range_s(&"ai", -0.8, 0.8)) * _u(3.0 if near else 4.0)
	var r0: float = _u(2.5 if near else 3.5)
	var r1: float = _u(3.0 if near else 5.0)
	for tries in 12:
		var a: float = Rng.range_s(&"ai", 0.0, TAU)
		var cand: Vector2 = pp + Vector2(cos(a), sin(a)) * Rng.range_s(&"ai", r0, r1)
		if cand.distance_to(p) < _u(3.5):
			continue
		if c.n != 0 and absf(wrapf(a - c.aim.x, -PI, PI)) < PI * 0.33:
			continue
		best = cand
		c.aim.x = a
		c.n = 1
		break
	var hz: Node2D = _hz()
	var cnt: int = 1
	if c.knot_k >= 4:
		cnt = mini(2 if c.knot_k < 6 else 3, c.segs_left)
	c.knots.clear()
	var a0: float = Rng.range_s(&"ai", 0.0, TAU)
	for e in cnt:
		var kp: Vector2 = best
		if e > 0:
			var ae: float = a0 + (PI if cnt == 2 else TAU * float(e - 1) / 2.0 + PI / 3.0)
			kp = best + Vector2(cos(ae), sin(ae)) * _u(2.2)
		var o: int = int(hz.call("add_obj", Hz.OKind.KNOT, kp, _u(0.8), c.knot_k + e))
		if o < 0:
			continue
		hz.o_v[o] = 1.0 if e > 0 else 0.0
		hz.o_lx[o] = p.x
		hz.o_ly[o] = p.y - 40.0
		c.knots.append(o)
		Events.boss_knot.emit(kp, c.knot_k + e, true)
	c.obj = c.knots[0] if not c.knots.is_empty() else -1
	c.guards.clear()
	if c.knot_k >= 4:
		for k in 4:
			var h: int = em.spawn(&"enm_subi", best + Vector2(cos(TAU * k / 4.0), sin(TAU * k / 4.0)) * _u(1.5), {"intro_s": 0.6, "no_recycle": true})
			if h >= 0:
				c.guards.append(h)
	_emit_pattern(c, &"gopuri_knot", 0.0)
	if Game.autotest:
		print("[enemies] %s gopuri knot k=%d n=%d near=%s segs_left=%d d_player=%.1fu" % [K.fmt_time(Game.time_sec()), c.knot_k, c.knots.size(), str(near), c.segs_left, best.distance_to(pp) / K.UNIT_PX])
	_say_once(&"gopuri_knot", "보스가 묶여 있다. 흰 매듭을 밟아 풀어라 — 풀린 동안만 한이 깎인다.")
	if cnt >= 2:
		_say_once(&"gopuri_knot_multi", "매듭이 여럿이다. 고리로 함께 묶으면 더 오래 풀린다.")


## 공수 자막 1회(런당). HUD 공수 레인이 받는다(deity_id 비움 = 굿판의 소리).
func _say_once(key: StringName, text: String) -> void:
	if _gongsu_once.has(key):
		return
	_gongsu_once[key] = true
	Events.gongsu_spoken.emit(&"", key, text)


func _free_knots(c: Ctl) -> void:
	var hz: Node2D = _hz()
	for o in c.knots:
		if o >= 0 and o < hz.o_alive.size() and hz.o_alive[o] == 1:
			Events.boss_knot.emit(Vector2(hz.o_x[o], hz.o_y[o]), hz.o_label[o], false)
			hz.call("free_obj", o)
	c.knots.clear()
	c.obj = -1


## 매듭 풀림: 보스 경직 1초 → 열림 창 8초(+4초/추가 매듭). 창 안 받는 피해 상한 = 풀린 구간(n개) 남은 한.
func _untie(c: Ctl, nknots: int) -> void:
	if not c.bound or c.knots.is_empty():
		return
	var i: int = c.slot
	var n: int = clampi(nknots, 1, maxi(1, c.segs_left))
	_free_knots(c)
	c.bound = false
	c.open_n = n
	c.open_dur = 8.0 + 4.0 * float(n - 1)
	c.open_t = c.open_dur
	c.open_at = Game.time_sec()
	var seg: float = em.han_max[i] / float(maxi(c.seg_n, 1))
	c.seg_floor = maxf(0.0, seg * float(c.segs_left - n))
	em.set_flag(i, F_INVULN, false)
	em.set_flag(i, F_PULLIL, true)          # 사람 얼굴(백 외곽선) + 백 ×3(stat_puri)
	em.set_stat(i, &"pullil_t", 9999.0)
	em.freeze(i, 60)
	for g in c.guards:
		var gs: int = em.slot_of(g)
		if gs >= 0:
			em.enter_pullil_now(gs)
	c.guards.clear()
	_emit_pattern(c, &"gopuri_untie", 0.0)
	if Game.autotest:
		print("[enemies] %s gopuri untie n=%d window=%.0fs floor=%.0f han=%.0f" % [K.fmt_time(Game.time_sec()), n, c.open_dur, c.seg_floor, em.han[i]])
	Juice.screen_shake(0.2 + 0.1 * float(n - 1))
	if n >= 2:
		_say_once(&"gopuri_multi_done", "매듭 %d개가 함께 풀렸다 — 길게 쳐라!" % n)


func _segment_done(c: Ctl) -> void:
	var i: int = c.slot
	var quick: bool = Game.time_sec() - c.open_at <= 3.0 + 2.0 * float(c.open_n - 1)
	if Game.autotest:
		print("[enemies] %s gopuri segment done n=%d in %.1fs quick=%s left=%d" % [K.fmt_time(Game.time_sec()), c.open_n, Game.time_sec() - c.open_at, str(quick), c.segs_left - c.open_n])
	c.segs_left -= c.open_n
	c.knot_k += c.open_n
	if c.segs_left <= 0:
		return
	c.bound = true
	em.set_flag(i, F_INVULN, true)
	em.set_flag(i, F_PULLIL, false)
	c.respawn_t = 0.0
	_hz().gop_f = -1.0
	# 화력 보상: 창을 빨리 채우면 다음 매듭이 곧바로 가까이(강한 빌드 90~110초 목표)
	_spawn_knot(c, Game.player.global_position, quick)


## 공개 조회(EnemyManager.boss_knots 경유): 떠 있는 한형 매듭 위치를 out 에 채운다. 반환 개수.
func knot_positions(out: PackedVector2Array) -> int:
	if _boss == null or _boss.form != &"han":
		return 0
	var hz: Node2D = _hz()
	var n: int = 0
	for o in _boss.knots:
		if n >= out.size():
			break
		out[n] = Vector2(hz.o_x[o], hz.o_y[o])
		n += 1
	return n


## 공개 조회(--autotest 봇용, 읽기 전용): 지금 붙어 싸울 큰 적의 (x, y) = 중심, z = 돌 반지름(u, 0 = 그 점으로 간다).
## 없으면 Vector3.INF. 한형 보스: 열림 창일 때만(묶임 중엔 매듭이 우선). 중간보스: 관망(시련) 중에는 없음.
## 도깨비 씨름 창: 왼다리 표식 점(z = 0). 사람 플레이의 '붙어서 친다'를 흉내 내 해결 시간을 재기 위한 것이다.
func bot_engage(pp: Vector2) -> Vector3:
	if _boss != null and em.is_alive(_boss.slot):
		var bp: Vector2 = _pos(_boss)
		if _boss.form == &"han":
			return Vector3(bp.x, bp.y, 2.2) if not _boss.bound else Vector3.INF
		return Vector3(bp.x, bp.y, 4.0)
	if _kwanmang:
		return Vector3.INF
	var best: Ctl = null
	var bd: float = INF
	for c: Ctl in _ctl:
		if c.tier != K.TIER_MBOSS or not em.is_alive(c.slot):
			continue
		var dd: float = pp.distance_squared_to(_pos(c))
		if dd < bd:
			bd = dd
			best = c
	if best == null:
		return Vector3.INF
	var p: Vector2 = _pos(best)
	if best.kd == Kd.DOKKAEBI and best.st == 2 and best.pat == &"dok_ssireum":
		# 씨름 창: 고리 밖(3u)을 돌아 왼쪽 부채꼴에 서면 표식으로 들어간다(오른쪽으로 들어가면 실패)
		var left: Vector2 = Vector2(best.dir.y, -best.dir.x)
		if (pp - p).normalized().dot(left) < cos(deg_to_rad(35.0)):
			return Vector3(p.x, p.y, 3.0)
		var mk: Vector2 = p + left * _u(1.4)
		return Vector3(mk.x, mk.y, 0.0)
	return Vector3(p.x, p.y, 3.0 if best.kd == Kd.DOKKAEBI else 3.5)


## 공개 조회: x = 1 묶임 / 0 열림 / −1 한형 보스 없음, y = 열림 창 남은 초, z = 남은 구간 수(0..7).
func gopuri_state() -> Vector3:
	if _boss == null or _boss.form != &"han" or not em.is_alive(_boss.slot):
		return Vector3(-1.0, 0.0, 0.0)
	return Vector3(1.0 if _boss.bound else 0.0, maxf(0.0, _boss.open_t) if not _boss.bound else 0.0, float(_boss.segs_left))


# ─── 저승사자(07 9장, v1.2 비적대) ─────────────────────────────────────

func _saja_init(c: Ctl) -> void:
	if c.route == &"sal_geodum" and Game.player != null:
		var pp: Vector2 = Game.player.global_position
		var ring: float = _u(9.0)
		var a0: float = Rng.range_s(&"ai", 0.0, TAU)
		for k in 3:
			var a: float = a0 + TAU * float(k) / 3.0
			var o: int = int(_hz().call("add_obj", Hz.OKind.LUMP, pp + Vector2(cos(a), sin(a)) * ring, _u(0.7)))
			c.lumps.append(o)
			c.lump_sp.append(em.top_toechi_species(k))
			c.lump_w.append(-1)
		Events.settlement_started.emit(&"sal_geodum", {"lumps": 3, "total_s": 90.0})
	elif c.route == &"bow":
		Events.settlement_started.emit(&"saja_bow", {})
	else:
		Events.settlement_started.emit(&"timeout", {})


func _think_saja(c: Ctl, dt: float, pp: Vector2, d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	if c.leave_t > 0.0:
		c.leave_t -= dt
		em.set_move(i, MV_FLEE, _u(1.5))
		if c.leave_t <= 0.0:
			em.vanish(i)
		return
	match c.route:
		&"bow":
			if c.st == 0:
				if d > _u(1.5):
					em.set_move(i, MV_SEEK, _u(1.5))
				else:
					c.st = 1
					c.t = 1.5
					em.set_move(i, MV_HOLD, 0.0)
					em.set_visual(i, 0, 2)
					_emit_pattern(c, &"saja_bow", 1.5)
			elif c.st == 1 and c.t <= 0.0:
				em.set_visual(i, 0, 0)
				Events.vfx_request.emit(&"vfx_saja_begareugi", pp, 0.0)
				Events.settlement_progress.emit(&"saja_bow", 1, 1, 1.0)
				c.leave_t = 3.0
		&"sal_geodum":
			c.prog_t += dt
			var hz: Node2D = _hz()
			if c.lump_i >= c.lumps.size():
				if c.st != 9:
					c.st = 9
					c.t = 1.5
					em.set_visual(i, 0, 2)
					Events.settlement_progress.emit(&"sal_geodum", 3, 3, 1.0)
				elif c.t <= 0.0:
					em.set_visual(i, 0, 0)
					c.leave_t = 3.0
				em.set_move(i, MV_HOLD, 0.0)
				return
			var o: int = c.lumps[c.lump_i]
			var lp: Vector2 = Vector2(hz.o_x[o], hz.o_y[o])
			if c.st == 0:
				em.set_move(i, MV_POINT, _u(2.5), lp.x, lp.y + _u(0.8))
				if p.distance_to(lp) < _u(1.2):
					# 거두기 시작: 원귀 1 + 호위 8 깨움
					c.st = 1
					c.lump_t = 0.0
					var sp: StringName = c.lump_sp[c.lump_i]
					var h: int = em.spawn(sp, lp + Vector2(0, -6), {"wongwi": true, "no_variant": true, "intro_s": 1.5})
					c.lump_w[c.lump_i] = h
					for k in 8:
						var a: float = TAU * float(k) / 8.0
						em.spawn(sp, lp + Vector2(cos(a), sin(a)) * _u(1.6), {"no_variant": true, "intro_s": 1.0})
					_emit_pattern(c, &"saja_collect", 30.0)
			elif c.st == 1:
				em.set_move(i, MV_HOLD, 0.0)
				c.lump_t += dt
				hz.o_v[o] = clampf(c.lump_t / 30.0, 0.0, 1.0)
				var w: int = c.lump_w[c.lump_i]
				var wd: bool = w >= 0 and em.slot_of(w) < 0
				if c.lump_t >= 30.0 or wd:
					hz.call("free_obj", o)
					c.lump_i += 1
					c.st = 0
			if (Game.game_tick % 60) == 0:
				var prog: float = maxf(c.prog_t / 90.0, float(c.lump_i) / 3.0)
				Events.settlement_progress.emit(&"sal_geodum", c.lump_i, 3, clampf(prog, 0.0, 1.0))
		_:
			em.set_move(i, MV_HOLD, 0.0)
			if c.st == 0:
				c.st = 1
				c.t = 3.0
				Events.vfx_request.emit(&"vfx_saja_begareugi", p, 0.0)
			elif c.st == 1 and c.t <= 0.0:
				c.st = 2
				Events.settlement_progress.emit(&"timeout", 1, 1, 1.0)


# ─── 별상 손님 NPC(07 6.5.2) ───────────────────────────────────────────

func _think_sonnim(c: Ctl, dt: float, _pp: Vector2, _d: float) -> void:
	var i: int = c.slot
	var p: Vector2 = _pos(c)
	var hz: Node2D = _hz()
	if c.obj >= 0:
		hz.o_x[c.obj] = p.x
		hz.o_y[c.obj] = p.y - float(em.body_h_of(i)) - 8.0
		hz.o_v[c.obj] = c.gauge
	if c.st == 9:
		# 배송(sm_sonnim_baesong): 2초 동안 싸리말 타고 떠남
		em.set_vel_dir(i, Vector2(0.6, -1.0))
		em.set_move(i, MV_VEL, _u(2.5))
		if c.t <= 0.0:
			em.vanish(i)
		return
	if c.route == &"haengcha":
		em.set_vel_dir(i, c.dir)
		em.set_move(i, MV_VEL, _u(1.2))
		c.leave_t -= dt
		if c.leave_t <= 0.0:
			em.vanish(i)
	else:
		em.set_move(i, MV_HOLD, 0.0)
	# 대접: 2u 안 공물 +25(소모)
	if (Game.game_tick + i) % 6 == 0:
		var pm: Variant = Game.pickups
		if pm is Object:
			var gi: int = int((pm as Object).call("find_special", &"pick_gongmul", p, _u(2.0)))
			if gi >= 0 and bool((pm as Object).call("take_special", gi)):
				_daejeop(c, 25.0)


func _daejeop(c: Ctl, add: float) -> void:
	var before: float = c.gauge
	c.gauge = minf(100.0, c.gauge + add)
	_emit_pattern(c, &"sonnim_daejeop", 0.0)
	for th: float in [50.0, 100.0]:
		if before < th and c.gauge >= th and c.gauge_hits < 2:
			c.gauge_hits += 1
			if _boss != null:
				if _boss.form == &"sal":
					_boss.scatter_t = 3.0
					_hz().call("cancel_owner", _boss.handle)
					_emit_pattern(_boss, &"yeok_scatter", 3.0)
				else:
					_untie(_boss, 1)


func _baesong() -> void:
	if _sonnim != null:
		_sonnim.st = 9
		_sonnim.t = 2.0
		_emit_pattern(_sonnim, &"sonnim_baesong", 2.0)


# ─── 피해 필터·결말 훅(EnemyManager 가 부름) ──────────────────────────

func filter_damage(i: int, dmg: float, white: bool, src: int) -> float:
	var c: Ctl = _ctl_of(i)
	if c == null:
		return dmg
	if c.invuln_t > 0.0:
		return 0.0
	match c.kd:
		Kd.EOD:
			# 크기 게이지만 움직인다: 적 무구 +0.03(0.25초 간격), 백 −0.02
			if c.icd <= 0.0 or white:
				c.size_s += -0.02 if white else Data.num("enemies", "elites.0.growth.red_hit_grow", 0.03)
				c.size_s = clampf(c.size_s, 0.0, 3.0)
				c.icd = 0.25
				_apply_eod_size(c)
			return 0.0
		Kd.BULGA:
			var tags: Array = _weapon_tags(src)
			if tags.has("fire"):
				return dmg * 2.0
			if tags.has("metal") and not white:
				# 쇠붙이 흡수: 피해 0, 최대 한 +1.5%(누적 상한 +100%)
				var base: float = c.hp_last
				if c.n < 66:
					c.n += 1
					em.set_han(i, em.han[i] + base * 0.015, em.han_max[i] + base * 0.015)
				if (Game.game_tick & 7) == 0:
					Events.vfx_request.emit(&"vfx_bulgasari_iron_absorb", _pos(c) + Vector2(0, -30), 0.0)
				return 0.0
		Kd.BOSS_YEOK:
			if c.form == &"han":
				if c.bound:
					return 0.0
				if not white:
					dmg *= 0.5
				return minf(dmg, maxf(0.0, em.han[i] - c.seg_floor))
			if c.scatter_t > 0.0 and white:
				dmg *= 1.5
	# 페이즈 경계 멈춤(중간보스 0.6/0.35, 보스 살형 0.7/0.35)
	if c.tier == K.TIER_MBOSS or (c.kd == Kd.BOSS_YEOK and c.form == &"sal"):
		var hm: float = em.han_max[i]
		var b1: float = 0.7 if c.kd == Kd.BOSS_YEOK else 0.6
		var cur: float = em.han[i]
		var bound_v: float = -1.0
		if cur > b1 * hm:
			bound_v = b1 * hm
		elif cur > 0.35 * hm:
			bound_v = 0.35 * hm
		if bound_v > 0.0 and cur - dmg < bound_v:
			dmg = cur - bound_v + 0.01
			c.pending_phase = 1
	return dmg


func _weapon_tags(src: int) -> Array:
	var wm: Variant = Game.weapons
	if src < 0 or not (wm is Object):
		return []
	var w: Variant = (wm as Object).call("weapon_at", src)
	if w is Object:
		var def: Variant = (w as Object).get("def")
		if def is Dictionary:
			var tg: Variant = (def as Dictionary).get("tags", [])
			if tg is Array:
				return tg
	return []


func after_hit(i: int, _dmg: float, _white: bool) -> void:
	var c: Ctl = _ctl_of(i)
	if c == null:
		return
	if c.kd == Kd.BOSS_YEOK and c.form == &"han" and not c.bound and em.han[i] <= c.seg_floor + 0.5 and c.segs_left <= 1:
		pass   # 마지막 구간: 한 0 → 마지막 피해 색으로 결말(EnemyManager)


func on_pullil(i: int) -> void:
	var c: Ctl = _ctl_of(i)
	if c == null:
		return
	if c.kd == Kd.DAEGWI:
		em.set_minion_smult(c.handle, 0.7)


## 외부 확정(고리·사자) 허용 여부. 어둑시니: 고리는 크기 −0.2. 보스·사자·손님: 거부.
func allow_force(i: int, cause: StringName) -> bool:
	var c: Ctl = _ctl_of(i)
	if c == null:
		return true
	match c.kd:
		Kd.EOD:
			if cause == &"ring":
				c.size_s -= Data.num("enemies", "elites.0.growth.ring_shrink", 0.2)
				_apply_eod_size(c)
				return false
		Kd.BOSS_YEOK, Kd.SAJA, Kd.SONNIM:
			return false
	return c.tier != K.TIER_MBOSS or _pullil(c)


func on_kill(i: int, kind: StringName) -> void:
	var c: Ctl = _ctl_of(i)
	if c == null:
		return
	var p: Vector2 = _pos(c)
	var hz: Node2D = _hz()
	match c.kd:
		Kd.GEOGU:
			if kind == K.KIND_TOECHI:
				Game.cur_neok += c.swallowed           # 삼킨 것들: 각자 천도, 넋 +1
		Kd.YEOKGWI:
			if kind == K.KIND_TOECHI:
				hz.call("add_zone", Hz.ZKind.YEOKBYEONG, p, _u(1.8), 6.0, 6.0 * _cm(), -1, 0.0)
			else:
				hz.call("convert_owner_zones", c.handle, -1)
		Kd.BULGA:
			if kind == K.KIND_HAEWON and Game.pickups != null:
				for k in 2:
					Game.pickups.call("spawn_special", &"pick_gongmul", p + Vector2(-12.0 + 24.0 * k, 0))
		Kd.DUEOK:
			if kind == K.KIND_HAEWON:
				em.damage_commons(p, _u(6.0), 0.0, 1.0e9, 60)    # 잡귀 기절 1초(피해 없음)
		Kd.DAEGWI:
			if kind == K.KIND_HAEWON:
				for kk in em.active_count:
					var j: int = em.active[kk]
					if int(em.ai_link[j]) == c.handle and em.is_alive(j):
						em.force_haewon(j, &"white")
			else:
				em.set_minion_smult(c.handle, 1.3)
		Kd.DOKKAEBI:
			if kind == K.KIND_HAEWON and Game.pickups != null:
				var tot: float = Data.num("meta_economy", "income.yeopjeon_sources.mboss_dokkaebi_haewon_rain", 400.0)
				Game.pickups.call("spawn_coins", p, tot, 20, _u(4.0))
				Game.pickups.call("spawn_box", &"box_gilhyung", p + Vector2(0, 18), Data.num("meta_economy", "income.yeopjeon_sources.box_gilhyung_mboss", 1000.0))
			for kk in em.active_count:
				var j2: int = em.active[kk]
				if em.species_id_of(j2) == &"mboss_dokkaebi__heosang" and em.is_alive(j2):
					em.vanish(j2)
		Kd.BOSS_YEOK:
			_baesong()
		Kd.EOD:
			pass
	_hz().call("cancel_owner", c.handle)


## 대귀 한풀이: 소귀 해원마다 최대 한 −1%(상한 −30%).
func _on_any_killed(_h: int, sp: StringName, _pos: Vector2, kind: StringName, _cause: StringName, _tier: StringName) -> void:
	if sp == &"mboss_daegwi__sogwi" and kind == K.KIND_HAEWON:
		for c: Ctl in _ctl:
			if c.kd == Kd.DAEGWI and c.hanpuri < 30:
				c.hanpuri += 1
				var hm: float = em.han_max[c.slot]
				em.set_han(c.slot, minf(em.han[c.slot], hm * 0.99), hm * 0.99)


## 고리 닫힘: 한형 매듭이 고리 안이면 풀림(여러 개 동시 가능), 어둑시니 크기 −0.2.
func _on_ring_closed(area_tiles: int, _n: int, centroid: Vector2) -> void:
	var rr: float = sqrt(float(area_tiles) / PI) * K.UNIT_PX
	var ring: Object = null
	if Game.run_root != null:
		var rv: Variant = Game.run_root.get("ring")
		if rv is Object and (rv as Object).has_method("contains"):
			ring = rv as Object
	for c: Ctl in _ctl:
		if c.kd == Kd.BOSS_YEOK and c.form == &"han" and c.bound and not c.knots.is_empty():
			var hz: Node2D = _hz()
			var inside: int = 0
			for o in c.knots:
				var kp: Vector2 = Vector2(hz.o_x[o], hz.o_y[o])
				var hit: bool = bool(ring.call("contains", kp)) if ring != null else kp.distance_to(centroid) <= rr
				if hit:
					inside += 1
			if inside > 0:
				_untie(c, inside)
		elif c.kd == Kd.EOD and _pos(c).distance_to(centroid) <= rr:
			c.size_s -= Data.num("enemies", "elites.0.growth.ring_shrink", 0.2)
			_apply_eod_size(c)


func _on_pickup(kind: StringName, _v: float, _p: Vector2) -> void:
	if kind == &"pick_yeou_guseul":
		for c: Ctl in _ctl:
			if c.kd == Kd.GUMIHO:
				c.hanpuri = 1
				em.set_stat(c.slot, &"pullil_t", 9999.0)     # 이번 싸움 맺힘 없음
				_emit_pattern(c, &"gumiho_hanpuri", 0.0)
