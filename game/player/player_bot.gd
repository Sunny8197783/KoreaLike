class_name PlayerBot
extends RefCounted
## --autotest 봇 입력. 소유: core(리드).
## 16초 주기: 10초 고리 그리기 → 6초 원혼 구슬 줍기. 항상 가까운 적 회피를 섞는다.
## 고리: 풀릴 기색 잡귀가 근처에 있으면 그 둘레를 돈다(길닦음 해원 경로 시험), 없으면 제자리 원.
## 시각은 게임 시각(Game.time_sec) 기준 — --speed 배속에서도 같은 궤적.
## 시련(deities): 강림 원이 뜨면 (슬롯 짝/홀로) 왼쪽/오른쪽 원에 들어가 고르고, 시련 중에는 화신 둘레(사거리 6.5u 안)를 돈다.
## 중간보스·보스: 매듭이 없으면 bot_engage(enemies) 가 준 큰 적 둘레(2.2~4u)를 돈다(해결 시간 측정, 11-24 waves 요청).
## 큰 고리: 3번째 고리 주기마다 길베 길이가 허락하는 가장 큰 원(최대 4.5u)을 그린다(만다라 도량·넓이 회귀 검증).

const ORBIT_R_U: float = 2.4          # 한 바퀴 ≈ 3.8초 < 길베 4초 → 고리가 닫힌다
const ORBIT_SEEK_U: float = 7.0       # 이 안의 풀릴 기색 잡귀를 고리 중심으로 삼는다
const BIG_R_MAX_U: float = 4.5
const TRIAL_ORBIT_U: float = 4.0      # 화신 사거리(reach 6.5u) 안쪽

var _t: float = 0.0
var _q: PackedInt32Array = PackedInt32Array()
var _orbit_center: Vector2 = Vector2.INF
var _orbit_dir: float = 1.0


func _init() -> void:
	_q.resize(64)


func input(p: Node2D) -> Vector2:
	_t = Game.time_sec()
	var pos: Vector2 = p.global_position
	var desire: Vector2
	var cycle: float = fmod(_t, 16.0)
	var orbiting: bool = false
	var trial_goal: Vector2 = _trial_goal(pos)
	var big: bool = int(_t / 16.0) % 3 == 2
	var obj_goal: Vector2 = _nearest_obj(pos, 40.0 * K.UNIT_PX) if trial_goal == Vector2.INF else Vector2.INF
	var eng: Vector3 = _engage_goal(pos) if trial_goal == Vector2.INF and obj_goal == Vector2.INF else Vector3.INF
	# 정예·중간보스 상자: 첫 진화가 상자에 묶여 있으므로 사람처럼 주우러 간다(리드 11-24, progression 요청).
	var box_goal: Vector2 = _nearest_box(pos, 14.0 * K.UNIT_PX) if trial_goal == Vector2.INF and obj_goal == Vector2.INF and eng == Vector3.INF else Vector2.INF
	if trial_goal != Vector2.INF:
		_orbit_center = Vector2.INF
		desire = trial_goal
		orbiting = true
	elif obj_goal != Vector2.INF:
		# 보스 고풀이 매듭·정산 살 덩어리: 밟으러 간다(보스전·정산 경로 시험)
		_orbit_center = Vector2.INF
		desire = (obj_goal - pos).normalized() if pos.distance_to(obj_goal) > 4.0 else Vector2.ZERO
		orbiting = true
	elif eng != Vector3.INF:
		# 중간보스·보스(열림 창): 붙어서 둘레를 돈다(enemies/enemy_bigs.gd bot_engage — 해결 시간 측정용)
		_orbit_center = Vector2.INF
		var ec: Vector2 = Vector2(eng.x, eng.y)
		if eng.z <= 0.0:
			desire = (ec - pos).normalized() if pos.distance_to(ec) > 4.0 else Vector2.ZERO
		else:
			desire = _orbit(pos, ec, eng.z)
		orbiting = true
	elif box_goal != Vector2.INF:
		_orbit_center = Vector2.INF
		desire = (box_goal - pos).normalized()
	elif cycle < 10.0 and big:
		# 큰 원: 반지름 = 길베 지속 동안 걸을 수 있는 둘레의 92%(최대 4.5u)
		var dur: float = 4.0
		var rr: Node = Game.run_root
		var gb: GilbeTrail = (rr.get("gilbe") as GilbeTrail) if rr != null else null
		if gb != null:
			dur = gb.duration()
		var r_u: float = clampf(0.92 * 4.0 * dur / TAU, ORBIT_R_U, BIG_R_MAX_U)
		var ang2: float = _t * (4.0 / r_u)
		desire = Vector2(-sin(ang2), cos(ang2))
		orbiting = true
	elif cycle < 10.0:
		var target: Vector2 = _nearest_pullil(pos, ORBIT_SEEK_U * K.UNIT_PX)
		if target != Vector2.INF:
			# 대상이 움직이므로 중심을 천천히 따라간다(급변하면 고리가 찌그러진다)
			_orbit_center = target if _orbit_center == Vector2.INF else _orbit_center.lerp(target, 0.03)
			desire = _orbit(pos, _orbit_center)
			orbiting = true
		else:
			_orbit_center = Vector2.INF
			var ang: float = _t * (4.0 / ORBIT_R_U)
			desire = Vector2(-sin(ang), cos(ang))
	else:
		_orbit_center = Vector2.INF
		desire = Vector2(cos(_t * 0.3), sin(_t * 0.21)).normalized()
		# 원 그리기 사이에는 가까운 원혼 구슬을 주우러 간다(레벨업·점지 경로 시험)
		var orb: Vector2 = _nearest_orb(pos, 8.0 * K.UNIT_PX)
		if orb != Vector2.INF:
			desire = (orb - pos).normalized()
	# 가까운 적 회피(고리를 도는 중에는 약하게 — 대상 둘레를 지켜야 닫힌다)
	var em: EnemyManager = Game.enemies as EnemyManager
	if em != null:
		var n: int = em.query_circle(pos, (1.2 if orbiting else 2.2) * K.UNIT_PX, _q)
		var away: Vector2 = Vector2.ZERO
		for k in n:
			var i: int = _q[k]
			var d: Vector2 = pos - em.pos_of(i)
			away += d.normalized() / maxf(d.length() / K.UNIT_PX, 0.3)
		if away.length_squared() > 0.0:
			var w: float = 0.25 if orbiting else 1.0
			desire = (desire * 0.6 + away.normalized() * minf(away.length(), 1.5) * w).normalized()
	return desire


## 시련 참여: 강림·확정 단계면 고를 원 쪽으로, 시련 중이면 화신 둘레를 도는 방향. 시련이 아니면 INF.
func _trial_goal(pos: Vector2) -> Vector2:
	var rr: Node = Game.run_root
	if rr == null:
		return Vector2.INF
	var td: TrialDirector = rr.get("trials") as TrialDirector
	if td == null:
		return Vector2.INF
	if td.ph == TrialDirector.Ph.DESCEND or td.ph == TrialDirector.Ph.CONFIRM:
		var k: int = td.slot_next % 2 if td.pick < 0 else td.pick
		var c: Vector2 = td.circle[k]
		if pos.distance_to(c) < 1.0:
			return Vector2.ZERO
		return (c - pos).normalized()
	if td.ph == TrialDirector.Ph.TRIAL and td.avatar != null:
		var ap: Variant = td.avatar.get("pos")
		if ap is Vector2:
			return _orbit(pos, ap as Vector2, TRIAL_ORBIT_U)
	return Vector2.INF


## 붙어 싸울 큰 적(enemies 공개 조회 bot_engage, 없으면 INF). x,y = 중심, z = 돌 반지름(u).
func _engage_goal(pos: Vector2) -> Vector3:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null or em.bigs == null or not em.bigs.has_method("bot_engage"):
		return Vector3.INF
	return em.bigs.call("bot_engage", pos) as Vector3


## 중심 c 둘레 반지름 r_u 를 도는 방향(접선 + 반지름 보정).
func _orbit(pos: Vector2, c: Vector2, r_u: float = ORBIT_R_U) -> Vector2:
	var rel: Vector2 = pos - c
	var dist: float = rel.length()
	if dist < 1.0:
		return Vector2.RIGHT
	var radial: Vector2 = rel / dist
	var tangent: Vector2 = Vector2(-radial.y, radial.x) * _orbit_dir
	var err: float = (dist - r_u * K.UNIT_PX) / K.UNIT_PX
	return (tangent - radial * clampf(err * 0.8, -1.0, 1.0)).normalized()


func _nearest_pullil(from: Vector2, max_r: float) -> Vector2:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return Vector2.INF
	var n: int = em.query_circle(from, max_r, _q)
	var best: float = max_r * max_r
	var out: Vector2 = Vector2.INF
	for k in n:
		var i: int = _q[k]
		if (em.flags[i] & EnemyManager.F_PULLIL) == 0:
			continue
		var d2: float = from.distance_squared_to(em.pos_of(i))
		if d2 < best:
			best = d2
			out = em.pos_of(i)
	return out


## 적 장판 노드(enemies/enemy_hazards.gd)의 매듭(0)·덩어리(1) 오브젝트 중 가장 가까운 것.
func _nearest_obj(from: Vector2, max_r: float) -> Vector2:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return Vector2.INF
	var hz: Node = em.get("hazards") as Node
	if hz == null:
		return Vector2.INF
	var alive: PackedByteArray = hz.get("o_alive")
	var kind: PackedByteArray = hz.get("o_kind")
	var ox: PackedFloat32Array = hz.get("o_x")
	var oy: PackedFloat32Array = hz.get("o_y")
	var best: float = max_r * max_r
	var out: Vector2 = Vector2.INF
	for k in alive.size():
		if alive[k] != 1 or kind[k] > 1:
			continue
		var d2: float = from.distance_squared_to(Vector2(ox[k], oy[k]))
		if d2 < best:
			best = d2
			out = Vector2(ox[k], oy[k])
	return out


## 가장 가까운 상자(길흉함·넋함). 없으면 INF.
func _nearest_box(from: Vector2, max_r: float) -> Vector2:
	var pm: PickupManager = Game.pickups as PickupManager
	if pm == null:
		return Vector2.INF
	var best: float = max_r * max_r
	var out: Vector2 = Vector2.INF
	for i in PickupManager.SP_CAP:
		if pm.s_alive[i] == 0:
			continue
		var k: int = pm.s_kind[i]
		if k != PickupManager.Pk.BOX_GIL and k != PickupManager.Pk.BOX_NEOK:
			continue
		var dx: float = pm.s_x[i] - from.x
		var dy: float = pm.s_y[i] - from.y
		var d2: float = dx * dx + dy * dy
		if d2 < best:
			best = d2
			out = Vector2(pm.s_x[i], pm.s_y[i])
	return out


func _nearest_orb(from: Vector2, max_r: float) -> Vector2:
	var pm: PickupManager = Game.pickups as PickupManager
	if pm == null or pm.count == 0:
		return Vector2.INF
	var best: float = max_r * max_r
	var out: Vector2 = Vector2.INF
	for i in PickupManager.CAPACITY:
		if pm.alive[i] == 0:
			continue
		var dx: float = pm.px[i] - from.x
		var dy: float = pm.py[i] - from.y
		var d2: float = dx * dx + dy * dy
		if d2 < best:
			best = d2
			out = Vector2(pm.px[i], pm.py[i])
	return out


# ─── 점지 정책(--bot-pick=greedy|random|pair) ─────────────────────────
## greedy = 맨 왼쪽(기존 동작), random = Rng "bot_pick", pair = Lv8 짝 패시브 > (빈 칸이면) 결합 짝 새 무구 > 새 무구 > 짝 패시브 Lv1 > 진화 길 무구 강화 > 강화 > 기타.
static func pick_offer(choices: Array, policy: String) -> int:
	var n: int = choices.size()
	if n <= 1 or policy == "greedy" or policy == "":
		return 0
	if policy == "random":
		return Rng.int_s(&"bot_pick", 0, n - 1)
	var wm: WeaponManager = Game.weapons as WeaponManager
	var free_slot: bool = wm != null and wm.slot_count() < WeaponManager.MAX_SLOTS
	var best: int = 0
	var best_s: float = -1e9
	for i in n:
		var c: Dictionary = choices[i]
		var s: float = _offer_score(c, wm, free_slot)
		if s > best_s:
			best_s = s
			best = i
	return best


static func _offer_score(c: Dictionary, wm: WeaponManager, free_slot: bool) -> float:
	var kind: String = String(c.get("kind", ""))
	var is_new: bool = bool(c.get("is_new", false))
	var lv: int = int(c.get("level", 1))
	if kind == "passive":
		if bool(c.get("pair_lv8", false)):
			return 100.0
		if _passive_pairs_held(StringName(String(c.get("id", ""))), wm):
			# 진화 조건은 짝 패시브 Lv1 — 이미 가진 짝 패시브 강화는 진화 길 무구 강화보다 뒤
			return 60.0 if lv <= 1 else 45.0 - float(lv)
		return 10.0 - float(lv)
	if kind == "weapon":
		# 카드에 적힌 진화·결합 길(weapon_manager desc)을 읽는 플레이어: 결합 짝 새 무구 > 새 무구, 짝 패시브 있는 무구 강화 우선
		var u_path: bool = bool(c.get("union_path", false))
		if is_new:
			return (80.0 if u_path else 70.0) if free_slot else 5.0
		return 40.0 + float(lv) + (15.0 if bool(c.get("evo_path", false)) else 0.0) + (5.0 if u_path else 0.0)
	return 0.0


static func _passive_pairs_held(pid: StringName, wm: WeaponManager) -> bool:
	if wm == null:
		return false
	var plist: Variant = Data.get_value("passives", "passives", [])
	if not (plist is Array):
		return false
	for p: Variant in plist:
		if not (p is Dictionary) or StringName(String((p as Dictionary).get("id", ""))) != pid:
			continue
		var pw: Variant = (p as Dictionary).get("pair_weapons", [])
		if pw is Array:
			for wid: Variant in pw:
				if wm.level_of(StringName(String(wid))) > 0:
					return true
		return false
	return false
