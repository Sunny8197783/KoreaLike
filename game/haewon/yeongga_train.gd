class_name YeonggaTrain
extends Node2D
## 영가 행렬: 해원된 사람의 넋이 무당 뒤를 따른다(최대 24 = stat_haengnyeol, 수명 30초 = stat_neok_sumyeong). 소유: haewon.
## 데이터: combat_core.yeongga, combat_core.ring.cheondo_rule, meta_economy.income.neok_sources
## 캐논 3.2.3 / 02 §7:
##   추종      브레드크럼(0.1u 이상 움직일 때만 기록), 영가 i 는 머리에서 호 길이 0.6 + 0.45·i. 충돌·길찾기 없음.
##   넋두리 오라 영가 반경 0.5u 접촉 적에게 백 피해. 그리드마다 1틱, 틱 피해 = 0.15 × R_top × 신빨 × 무르익음 × g. 한 적에 최대 8기.
##   대신 맞기  try_substitute(): 맨 앞(가장 오래된) 영가 2기가 대신 맞고 천도. 내부 쿨 2초, 행렬 ≤8 이면 꺼짐,
##              장판 지속 피해·원거리 탄 제외(11-24 리뷰: 생존 긴장감). combat_core.yeongga.substitute_*
##   천도      수명 만료·대신 맞기·고리(남은 수명 ≤10초)·넘침. 넋 +1(고리 ×2), 신명 +0.5%.
##   무르익음  머문 10초 ×1.5(소복 금빛 테), 20초 ×2.0(머리 위 등불 점 1.2Hz).
##   비인간(도깨비·불가사리·두억시니·어둑시니·구미호·이무기·강철이) 해원 = 배웅(행렬 미합류, 넋 +1 보너스).
## 그리기: yeongga_body_{f,m,child} 걷기/idle 4방향(서 = 동 반전), 천도 8f·대신 맞기 4f, 백 실루엣 셰이더(shaders/yeongga).
## 공개 API: capacity(), lifetime(), count, try_substitute(source) -> bool, ring_effect(ring) -> int(천도 수), member_pos(k)

const CAP_MAX: int = 64
const CRUMB_CAP: int = 512
const DEP_CAP: int = 48
const BODY_IDS: PackedStringArray = ["yeongga_body_f", "yeongga_body_m", "yeongga_body_child"]
const DIR_NAMES: PackedStringArray = ["south", "east", "north", "west"]
const BAEUNG_PREFIX: PackedStringArray = ["enm_dokkaebi", "elite_dueoksini", "elite_eodukssini", "elite_bulgasari",
	"mboss_gumiho", "mboss_dokkaebi", "mboss_gangcheori", "boss_imugi"]
enum Dep { LIFETIME, SUBSTITUTE, RING, OVERFLOW }

var count: int = 0
var m_species: Array[StringName] = []
var m_body: PackedByteArray = PackedByteArray()
var m_dir: PackedByteArray = PackedByteArray()
var m_moving: PackedByteArray = PackedByteArray()
var m_life: PackedFloat32Array = PackedFloat32Array()
var m_join: PackedFloat32Array = PackedFloat32Array()
var m_stay: PackedFloat32Array = PackedFloat32Array()
var m_x: PackedFloat32Array = PackedFloat32Array()
var m_y: PackedFloat32Array = PackedFloat32Array()
var m_px: PackedFloat32Array = PackedFloat32Array()
var m_py: PackedFloat32Array = PackedFloat32Array()
var m_ph: PackedFloat32Array = PackedFloat32Array()

# 떠나는 영가(연출 전용, 연출 시계)
var d_x: PackedFloat32Array = PackedFloat32Array()
var d_y: PackedFloat32Array = PackedFloat32Array()
var d_tx: PackedFloat32Array = PackedFloat32Array()
var d_ty: PackedFloat32Array = PackedFloat32Array()
var d_t: PackedFloat32Array = PackedFloat32Array()
var d_delay: PackedFloat32Array = PackedFloat32Array()
var d_kind: PackedByteArray = PackedByteArray()
var d_body: PackedByteArray = PackedByteArray()
var d_soft: PackedByteArray = PackedByteArray()      # 1 = 한꺼번에 많이 떠날 때 넘친 것(흐리게·시트 없음, design/19 §5.1 군중 예산)
# 천도 빛 예산(design/19 §5.2 G·§5.1): 0.25초 창에 승천 시트 4장(군중 2), 떠나는 넋 동무 밝은 그림 6(군중 3).
#   고리 하나에 30명이 한꺼번에 떠나면 흰 기둥 30개가 무당 둘레를 덮었다(검토 11-26, 19:30). 넘친 것은 α0.45 로 짧게.
const ASC_WIN: float = 0.25
var _asc_t0: float = -10.0
var _asc_n: int = 0
var _asc_full: int = 0
var d_alive: PackedByteArray = PackedByteArray()
var d_n: int = 0

var _cx: PackedFloat32Array = PackedFloat32Array()
var _cy: PackedFloat32Array = PackedFloat32Array()
var _c_head: int = 0
var _c_count: int = 0

var _step: float = 0.1 * 32.0
var _first: float = 0.6 * 32.0
var _spacing: float = 0.45 * 32.0
var _fade: float = 5.0
var _join_time: float = 0.35
var _aura_r: float = 0.5 * 32.0
var _aura_ratio: float = 0.15
var _aura_stack: int = 8
var _sub_cd: float = 2.0
var _sub_left: float = 0.0
var _sub_min_train: int = 8          # 행렬이 이만큼 이하면 대신 맞기 꺼짐(생존 긴장감, 11-24 리뷰)
var _sub_cost: int = 2               # 대신 맞을 때 천도하는 영가 수
var _sub_ex_ranged: bool = true      # 원거리 탄은 대신 맞기 대상 아님
var _ring_life: float = 10.0
var _ring_add: float = 5.0
var _burst_r: float = 1.0 * 32.0
var _burst_mult: float = 4.0
var _cheondo_sm: float = 0.005
var _neok_cheondo: int = 1
var _neok_ring: int = 2
var _neok_haewon: int = 1
var _neok_overflow: int = 1
var _ripe_sec: PackedFloat32Array = PackedFloat32Array([0.0, 10.0, 20.0])
var _ripe_mult: PackedFloat32Array = PackedFloat32Array([1.0, 1.5, 2.0])

var _q: PackedInt32Array = PackedInt32Array()
var _stack_n: PackedByteArray = PackedByteArray()
var _touched: PackedInt32Array = PackedInt32Array()
var _touched_n: int = 0

# 프레임: _fr[body][anim*4 + dir] (anim 0 walk, 1 idle), _fr_cheondo[body], _fr_sub[body]
var _fr: Array = []
var _fr_cheondo: Array = []
var _fr_sub: Array = []
var _overlay: Node2D = null
var substitutes: int = 0             # 텔레메트리: 대신 맞기 횟수
var substitute_denied_small: int = 0  # 행렬 ≤ min_train 이라 거절
var substitute_denied_cd: int = 0     # 재사용 대기로 거절


func _ready() -> void:
	m_species.resize(CAP_MAX)
	for a: String in ["m_life", "m_join", "m_stay", "m_x", "m_y", "m_px", "m_py", "m_ph"]:
		var arr: PackedFloat32Array = PackedFloat32Array()
		arr.resize(CAP_MAX)
		set(a, arr)
	for b: String in ["m_body", "m_dir", "m_moving"]:
		var arr2: PackedByteArray = PackedByteArray()
		arr2.resize(CAP_MAX)
		set(b, arr2)
	for a3: String in ["d_x", "d_y", "d_tx", "d_ty", "d_t", "d_delay"]:
		var arr3: PackedFloat32Array = PackedFloat32Array()
		arr3.resize(DEP_CAP)
		set(a3, arr3)
	for b4: String in ["d_kind", "d_body", "d_alive", "d_soft"]:
		var arr4: PackedByteArray = PackedByteArray()
		arr4.resize(DEP_CAP)
		arr4.fill(0)
		set(b4, arr4)
	_cx.resize(CRUMB_CAP)
	_cy.resize(CRUMB_CAP)
	_q.resize(64)
	_stack_n.resize(EnemyManager.CAPACITY)
	_stack_n.fill(0)
	_touched.resize(EnemyManager.CAPACITY)
	_step = Data.num("combat_core", "yeongga.breadcrumb_min_step_u", 0.1) * K.UNIT_PX
	_first = Data.num("combat_core", "yeongga.first_offset_u", 0.6) * K.UNIT_PX
	_spacing = Data.num("combat_core", "yeongga.spacing_u", 0.45) * K.UNIT_PX
	_fade = Data.num("combat_core", "yeongga.fade_last_sec", 5.0)
	_join_time = Data.num("combat_core", "yeongga.join_time", 0.35)
	_aura_r = Data.num("combat_core", "yeongga.aura_radius_u", 0.5) * K.UNIT_PX
	_aura_ratio = Data.num("combat_core", "yeongga.aura_ratio_of_ritual_ref", 0.15)
	_aura_stack = int(Data.num("combat_core", "yeongga.aura_stack_cap", 8))
	_sub_cd = Data.num("combat_core", "yeongga.substitute_cooldown", 2.0)
	_sub_min_train = int(Data.num("combat_core", "yeongga.substitute_min_train", 8))
	_sub_cost = maxi(1, int(Data.num("combat_core", "yeongga.substitute_cost", 2)))
	_sub_ex_ranged = bool(Data.get_value("combat_core", "yeongga.substitute_excludes_ranged", true))
	_ring_life = Data.num("combat_core", "ring.cheondo_rule.remaining_life_lte_sec", 10.0)
	_ring_add = Data.num("combat_core", "ring.cheondo_rule.others_life_add_sec", 5.0)
	_burst_r = Data.num("combat_core", "ring.cheondo_rule.others_burst.radius_u", 1.0) * K.UNIT_PX
	_burst_mult = Data.num("combat_core", "ring.cheondo_rule.others_burst.aura_tick_mult", 4.0)
	_cheondo_sm = Data.num("combat_core", "yeongga.cheondo_sinmyeong", 0.005)
	_neok_cheondo = int(Data.num("meta_economy", "income.neok_sources.cheondo", 1))
	_neok_ring = int(Data.num("meta_economy", "income.neok_sources.cheondo_in_ring", 2))
	_neok_haewon = int(Data.num("meta_economy", "income.neok_sources.haewon", 1))
	_neok_overflow = int(Data.num("meta_economy", "income.neok_sources.procession_full_instant_cheondo_bonus", 1))
	var rs: Variant = Data.get_value("combat_core", "yeongga.ripe.stage_sec", [0, 10, 20])
	var rm: Variant = Data.get_value("combat_core", "yeongga.ripe.aura_mult", [1.0, 1.5, 2.0])
	if rs is Array and rm is Array and (rs as Array).size() == 3 and (rm as Array).size() == 3:
		for i in 3:
			_ripe_sec[i] = float(rs[i])
			_ripe_mult[i] = float(rm[i])
	for b5 in BODY_IDS.size():
		var per: Array = []
		for anim: String in ["walk", "idle"]:
			for d in 4:
				var dn: String = DIR_NAMES[d]
				if d == K.Dir.WEST:
					dn = "east"   # 서 = 동 좌우 반전(ART_STYLE: flip_h(E))
				var fr: Array[Texture2D] = SpriteLib.anim_frames(BODY_IDS[b5], anim, dn)
				if fr.is_empty():
					fr.append(SpriteLib.dir_tex(BODY_IDS[b5], "south", 32))
				per.append(fr)
		_fr.append(per)
		_fr_cheondo.append(SpriteLib.anim_frames(BODY_IDS[b5], "cheondo", "south"))
		_fr_sub.append(SpriteLib.anim_frames(BODY_IDS[b5], "daesin_matgi", "south"))
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/yeongga.gdshader") as Shader
	mat.set_shader_parameter(&"tint", 0.45)
	material = mat
	_overlay = Node2D.new()
	_overlay.use_parent_material = false
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	Events.enemy_killed.connect(_on_enemy_killed)


func capacity() -> int:
	return mini(CAP_MAX, int(Game.stat(&"stat_haengnyeol", Data.num("combat_core", "yeongga.cap_base", 24.0))))


func lifetime() -> float:
	return minf(Game.stat(&"stat_neok_sumyeong", Data.num("combat_core", "yeongga.lifetime_base", 30.0)),
		Data.num("combat_core", "yeongga.lifetime_max", 60.0))


func member_pos(k: int) -> Vector2:
	return Vector2(m_x[k], m_y[k])


func _haewon_sys() -> HaewonSystem:
	if Game.run_root == null:
		return null
	return Game.run_root.get("haewon") as HaewonSystem


static func _is_baeung(sp: StringName) -> bool:
	var s: String = String(sp)
	for p: String in BAEUNG_PREFIX:
		if s.begins_with(p):
			return true
	return false


func _on_enemy_killed(h: int, sp: StringName, pos: Vector2, kind: StringName, _cause: StringName, tier: StringName) -> void:
	if kind != K.KIND_HAEWON:
		return
	Game.cur_neok += _neok_haewon
	var hs: HaewonSystem = _haewon_sys()
	if tier == K.TIER_MBOSS or tier == K.TIER_BOSS or tier == K.TIER_CHASER:
		return  # 보스 해원은 waves/deities 연출(고풀이·사자)
	if _is_baeung(sp):
		Game.cur_neok += _neok_overflow   # 배웅: 즉시 배웅 넋
		if hs != null:
			hs.add_sinmyeong(_cheondo_sm)
		Events.yeongga_cheondo.emit(1, &"baeung")
		return
	if count >= capacity():
		Game.cur_neok += _neok_overflow   # 넘침: 합류 없이 바로 하늘로
		if hs != null:
			hs.add_sinmyeong(_cheondo_sm)
		_depart_at(pos, pos, 0 if (h & 1) == 0 else 1, Dep.OVERFLOW, 0.0)
		Events.yeongga_cheondo.emit(1, &"overflow")
		return
	var k: int = count
	m_species[k] = sp
	m_body[k] = 2 if String(sp).ends_with("__child") else (h & 1)
	m_life[k] = lifetime()
	m_join[k] = _join_time
	m_stay[k] = 0.0
	m_x[k] = pos.x
	m_y[k] = pos.y
	m_px[k] = pos.x
	m_py[k] = pos.y
	m_dir[k] = K.Dir.SOUTH
	m_moving[k] = 1
	m_ph[k] = Rng.randf_s(&"fx")
	count += 1
	Events.yeongga_joined.emit(count, sp)


## 틱 15.
func sim_step(dt: float) -> void:
	if Game.player == null:
		return
	if _sub_left > 0.0:
		_sub_left -= dt
	var p: Vector2 = Game.player.global_position
	if _c_count == 0 or Vector2(_cx[(_c_head - 1 + CRUMB_CAP) % CRUMB_CAP], _cy[(_c_head - 1 + CRUMB_CAP) % CRUMB_CAP]).distance_to(p) >= _step:
		_cx[_c_head] = p.x
		_cy[_c_head] = p.y
		_c_head = (_c_head + 1) % CRUMB_CAP
		_c_count = mini(_c_count + 1, CRUMB_CAP)
	# 수명·머문 시간
	var k: int = 0
	var expired: int = 0
	while k < count:
		m_px[k] = m_x[k]
		m_py[k] = m_y[k]
		m_life[k] -= dt
		if m_join[k] > 0.0:
			m_join[k] -= dt
		else:
			m_stay[k] += dt
		if m_life[k] <= 0.0:
			_depart(k, Dep.LIFETIME, 0.0)
			_remove(k)
			Game.cur_neok += _neok_cheondo
			expired += 1
			continue
		k += 1
	if expired > 0:
		var hs: HaewonSystem = _haewon_sys()
		if hs != null:
			hs.add_sinmyeong(_cheondo_sm * expired)
		Events.yeongga_cheondo.emit(expired, &"lifetime")
	# 브레드크럼 위 목표 위치(최신 → 과거로 거리 누적, 한 번 순회)
	var member: int = 0
	var want: float = _first
	var acc: float = 0.0
	var prev: Vector2 = p
	for j in _c_count:
		if member >= count:
			break
		var idx: int = (_c_head - 1 - j + CRUMB_CAP * 2) % CRUMB_CAP
		var c: Vector2 = Vector2(_cx[idx], _cy[idx])
		acc += prev.distance_to(c)
		prev = c
		while member < count and acc >= want:
			_move_member(member, c, dt)
			member += 1
			want += _spacing
	while member < count:   # 브레드크럼이 짧으면(런 시작) 마지막 점에 모인다
		_move_member(member, prev, dt)
		member += 1
	# 넋두리 오라(그리드 틱마다)
	if Beat.is_grid_tick and count > 0:
		_aura_tick(1.0, _aura_r, -1)


func _move_member(k: int, target: Vector2, dt: float) -> void:
	var cur: Vector2 = Vector2(m_x[k], m_y[k])
	var a: float = 1.0 - exp(-dt * (6.0 if m_join[k] > 0.0 else 14.0))
	var nxt: Vector2 = cur.lerp(target, a)
	var v: Vector2 = nxt - cur
	var sp2: float = v.length_squared()
	m_moving[k] = 1 if sp2 > 0.09 else 0
	if sp2 > 0.09:
		if absf(v.x) > absf(v.y) * 1.2:
			m_dir[k] = K.Dir.EAST if v.x > 0.0 else K.Dir.WEST
		elif absf(v.y) > absf(v.x) * 0.8:
			m_dir[k] = K.Dir.SOUTH if v.y > 0.0 else K.Dir.NORTH
	m_x[k] = nxt.x
	m_y[k] = nxt.y


func _ripe_mult_of(k: int) -> float:
	var s: float = m_stay[k]
	if s >= _ripe_sec[2]:
		return _ripe_mult[2]
	if s >= _ripe_sec[1]:
		return _ripe_mult[1]
	return _ripe_mult[0]


## 오라 1틱. only < 0 이면 전원, 아니면 그 영가만(고리 폭발). mult = 틱 배율.
func _aura_tick(mult: float, r: float, only: int) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	var base: float = _aura_ratio * HaewonSystem.ritual_ref_top() * minf(Game.stat(&"stat_sinppal", 1.0), 10.0) * Beat.grid_sec() * mult
	_touched_n = 0
	var k0: int = 0 if only < 0 else only
	var k1: int = count if only < 0 else only + 1
	for k in range(k0, k1):
		if m_join[k] > 0.0:
			continue
		var n: int = em.query_circle(Vector2(m_x[k], m_y[k]), r, _q)
		if n == 0:
			continue
		var dmg: float = base * _ripe_mult_of(k)
		for j in n:
			var s: int = _q[j]
			if _stack_n[s] >= _aura_stack:
				continue
			if _stack_n[s] == 0:
				_touched[_touched_n] = s
				_touched_n += 1
			_stack_n[s] += 1
			em.queue_hit(s, dmg, K.DmgColor.AURA_YEONGGA, false, Vector2.ZERO, 0.0, -1)
	for j2 in _touched_n:
		_stack_n[_touched[j2]] = 0


## 대신 맞기(02 §7.4). 피격 파이프라인(PlayerHit.take_hit)이 iframe·회피 다음에 부른다.
## true 면 무당 피해 0 — 호출자가 iframe = max(iframe, combat_core.player.iframe_substitute 0.2) 를 건다.
func try_substitute(source: StringName) -> bool:
	if count <= 0 or not Game.run_active:
		return false
	# 장판·지속 피해(enemy_zone 등) 제외 + 원거리 탄 제외(11-24: 대신 맞기가 피격 대부분을 막아 긴장감이 없던 문제)
	var s: String = String(source)   # 피격 때만(매 프레임 아님)
	if s.contains("zone") or s.begins_with("hazard") or s.begins_with("pool"):
		return false
	if _sub_ex_ranged and (s.contains("projectile") or s.contains("bullet")):
		return false
	if count <= _sub_min_train:
		substitute_denied_small += 1
		return false
	if _sub_left > 0.0:
		substitute_denied_cd += 1
		return false
	_sub_left = _sub_cd
	var n: int = mini(_sub_cost, count)
	for j in n:
		_depart(0, Dep.SUBSTITUTE, 0.06 * float(j))
		_remove(0)
	substitutes += 1
	Game.cur_neok += _neok_cheondo * n
	var hs: HaewonSystem = _haewon_sys()
	if hs != null:
		hs.add_sinmyeong(_cheondo_sm * float(n))
	Events.yeongga_cheondo.emit(n, &"substitute")
	return true


## 길닦음 효과 3(캐논 v1.1): zone 안 영가 중 남은 수명 ≤10초는 천도(넋 ×2), 나머지는 수명 +5초 + 오라 1박 폭발(×4, r 1u).
## ring.in_zone() 이 유효한 닫힘 틱에만 부른다. 반환: 천도 수.
func ring_effect(ring: RingClosure) -> int:
	var n: int = 0
	var k: int = 0
	var lt: float = lifetime()
	while k < count:
		if not ring.in_zone(Vector2(m_x[k], m_y[k])):
			k += 1
			continue
		if m_life[k] <= _ring_life:
			_depart(k, Dep.RING, 0.03 * float(n))   # 고리 둘레를 따라 순서대로 상승(30ms 간격)
			_remove(k)
			Game.cur_neok += _neok_ring
			n += 1
			continue
		m_life[k] = minf(m_life[k] + _ring_add, lt)
		_aura_tick(_burst_mult, _burst_r, k)
		k += 1
	if n > 0:
		var hs: HaewonSystem = _haewon_sys()
		if hs != null:
			hs.add_sinmyeong(_cheondo_sm * n)
		Events.yeongga_cheondo.emit(n, &"ring")
	return n


func _remove(k: int) -> void:
	for j in range(k, count - 1):
		m_species[j] = m_species[j + 1]
		m_body[j] = m_body[j + 1]
		m_dir[j] = m_dir[j + 1]
		m_moving[j] = m_moving[j + 1]
		m_life[j] = m_life[j + 1]
		m_join[j] = m_join[j + 1]
		m_stay[j] = m_stay[j + 1]
		m_x[j] = m_x[j + 1]
		m_y[j] = m_y[j + 1]
		m_px[j] = m_px[j + 1]
		m_py[j] = m_py[j + 1]
		m_ph[j] = m_ph[j + 1]
	count -= 1


func _depart(k: int, kind: int, delay: float) -> void:
	var tgt: Vector2 = Vector2(m_x[k], m_y[k])
	if kind == Dep.SUBSTITUTE and Game.player != null:
		var pp: Vector2 = Game.player.global_position
		tgt = pp + (Vector2(m_x[k], m_y[k]) - pp).limit_length(10.0)   # 무당 앞으로 0.08초 돌진
	_depart_at(Vector2(m_x[k], m_y[k]), tgt, m_body[k], kind, delay)


func _depart_at(from: Vector2, to: Vector2, body: int, kind: int, delay: float) -> void:
	var slot: int = -1
	for i in DEP_CAP:
		if d_alive[i] == 0:
			slot = i
			break
	if slot < 0:
		return
	d_x[slot] = from.x
	d_y[slot] = from.y
	d_tx[slot] = to.x
	d_ty[slot] = to.y
	d_t[slot] = 0.0
	d_delay[slot] = delay
	d_kind[slot] = kind
	d_body[slot] = body
	d_alive[slot] = 1
	d_n += 1


# ─── 연출 ──────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	var adt: float = Game.anim_dt
	if d_n > 0:
		for i in DEP_CAP:
			if d_alive[i] == 0:
				continue
			if d_delay[i] > 0.0:
				d_delay[i] -= adt
				if d_delay[i] <= 0.0:
					_dep_start_fx(i)
					d_t[i] = 0.0001
				continue
			if d_t[i] == 0.0:
				_dep_start_fx(i)
			d_t[i] += maxf(adt, 0.0001)
			if d_t[i] > _dep_len(d_kind[i]):
				d_alive[i] = 0
				d_n -= 1
	queue_redraw()
	_overlay.queue_redraw()
	# 오컬트 조명: 행렬이 어둠 속에서 은은히 빛나는 넋의 줄(4기마다 1점, 최대 6 — 프레임 광원 48 공유)
	if count > 0:
		var ra: float = Game.render_alpha
		var lights: int = 0
		var k: int = 0
		while k < count and lights < 6:
			if m_join[k] <= 0.0:
				var lp: Vector2 = Vector2(lerpf(m_px[k], m_x[k], ra), lerpf(m_py[k], m_y[k], ra) - 12.0)
				var ripe: bool = m_stay[k] >= _ripe_sec[2]
				Juice.light_frame(lp, 26.0 if ripe else 22.0, (0.32 if ripe else 0.22) * _alpha_of(k), 2 if ripe else 1)
				lights += 1
			k += 4


func _dep_len(kind: int) -> float:
	return 0.08 + 4.0 / 16.0 + 0.3 if kind == Dep.SUBSTITUTE else 8.0 / 12.0


func _dep_start_fx(i: int) -> void:
	var vfx: VfxPlayer = Game.vfx as VfxPlayer
	if vfx == null:
		return
	if d_kind[i] == Dep.SUBSTITUTE:
		return   # 돌진 후 찢김(_draw 에서)
	var now: float = Game.anim_time()
	if now - _asc_t0 >= ASC_WIN:
		_asc_t0 = now
		_asc_n = 0
		_asc_full = 0
	var crowd: bool = bool(Juice.get(&"fx_crowd"))
	_asc_full += 1
	d_soft[i] = 1 if _asc_full > (3 if crowd else 6) else 0
	if _asc_n >= (2 if crowd else 4):
		return
	_asc_n += 1
	vfx.play(&"vfx_cheondo_ascend", Vector2(d_x[i], d_y[i]), 0.0, 1.0, {"additive": true})


func _alpha_of(k: int) -> float:
	var a: float = 0.92
	if m_join[k] > 0.0:
		a = 0.6
	var life: float = m_life[k]
	if life < _fade:
		a *= 0.45 + 0.55 * floorf(life / _fade * 4.0) / 4.0   # 4단 계단(70% → 40% 근사)
		if life < 1.5 and fmod(life, 0.25) < 0.08:
			a *= 0.5
	return a


func _draw() -> void:
	var t: float = Game.anim_time()
	var ra: float = Game.render_alpha
	for k in range(count - 1, -1, -1):
		var b: int = m_body[k]
		var d: int = m_dir[k]
		var anim: int = 0 if m_moving[k] != 0 else 1
		var frames: Array = _fr[b][anim * 4 + d]
		var fps: float = 8.0 if anim == 0 else 6.0
		var fi: int = int(floorf((t + m_ph[k]) * fps)) % frames.size()
		var tex: Texture2D = frames[fi]
		var pos: Vector2 = Vector2(lerpf(m_px[k], m_x[k], ra), lerpf(m_py[k], m_y[k], ra)).round()
		if anim == 1:
			pos.y += roundf(sin((t + m_ph[k] * 5.0) * TAU * 1.2) * 0.6)   # 정지 시 1px 1.2Hz
		var sz: Vector2 = tex.get_size()
		var col: Color = Color(1, 1, 1, _alpha_of(k))
		var org: Vector2 = pos - Vector2(roundf(sz.x * 0.5), sz.y - 3.0)
		if d == K.Dir.WEST:
			draw_set_transform(Vector2(org.x + sz.x, org.y), 0.0, Vector2(-1, 1))
			draw_texture(tex, Vector2.ZERO, col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture(tex, org, col)
	# 떠나는 영가
	for i in DEP_CAP:
		if d_alive[i] == 0 or d_delay[i] > 0.0:
			continue
		var kind: int = d_kind[i]
		var dt_: float = d_t[i]
		var b2: int = d_body[i]
		var fr2: Array[Texture2D]
		var pos2: Vector2 = Vector2(d_x[i], d_y[i])
		var fi2: int = 0
		if kind == Dep.SUBSTITUTE:
			var u: float = clampf(dt_ / 0.08, 0.0, 1.0)
			pos2 = pos2.lerp(Vector2(d_tx[i], d_ty[i]), u)
			fr2 = _fr_sub[b2]
			fi2 = clampi(int((dt_ - 0.08) * 16.0), 0, 3)
			if dt_ > 0.08 + 0.25:
				continue   # 찢긴 뒤에는 종이 조각만(오버레이)
		else:
			fr2 = _fr_cheondo[b2]
			fi2 = clampi(int(dt_ * 12.0), 0, 7)
		if fr2.is_empty():
			continue
		var tex2: Texture2D = fr2[mini(fi2, fr2.size() - 1)]
		var sz2: Vector2 = tex2.get_size()
		var a2: float = 0.95 if fi2 < 6 else 0.5
		if d_soft[i] != 0:
			a2 *= 0.45
		draw_texture(tex2, pos2.round() - Vector2(roundf(sz2.x * 0.5), sz2.y - 9.0), Color(1, 1, 1, a2))


## 셰이더 없이: 무르익음 표식(금빛 테·등불 점), 대신 맞기 넋전 종이 조각.
func _draw_overlay() -> void:
	var t: float = Game.anim_time()
	var ra: float = Game.render_alpha
	for k in count:
		var s: float = m_stay[k]
		if s < _ripe_sec[1] or m_join[k] > 0.0:
			continue
		var pos: Vector2 = Vector2(lerpf(m_px[k], m_x[k], ra), lerpf(m_py[k], m_y[k], ra)).round()
		var a: float = _alpha_of(k)
		# 소복 자락 1px 금빛 테
		_overlay.draw_rect(Rect2(pos + Vector2(-5, -3), Vector2(10, 1)), Color(K.COL_HWANG, 0.8 * a))
		if s >= _ripe_sec[2]:
			var top: float = 30.0 if m_body[k] != 2 else 22.0
			var on: bool = fmod(t * 1.2 + m_ph[k], 1.0) < 0.6
			var lp: Vector2 = pos + Vector2(0, -top - 3.0)
			_overlay.draw_rect(Rect2(lp, Vector2(1, 1)), Color(K.COL_HWANG, a if on else 0.45 * a))
			if on:
				_overlay.draw_rect(Rect2(lp + Vector2(-1, 0), Vector2(3, 1)), Color(K.COL_HWANG, 0.35 * a))
	for i in DEP_CAP:
		if d_alive[i] == 0 or d_kind[i] != Dep.SUBSTITUTE:
			continue
		var dt_: float = d_t[i] - 0.33
		if dt_ < 0.0:
			continue
		# 넋전 종이 조각 6장: 바깥으로 흩날리며 떨어짐(한지·백)
		var c: Vector2 = Vector2(d_tx[i], d_ty[i] - 12.0)
		for j in 6:
			var ang: float = float(j) * TAU / 6.0 + float(i)
			var v: Vector2 = Vector2(cos(ang), sin(ang) * 0.6 - 0.8) * 34.0
			var p: Vector2 = c + v * dt_ + Vector2(sin(dt_ * 14.0 + j) * 2.0, 60.0 * dt_ * dt_)
			var colp: Color = K.COL_BAEK if (j & 1) == 0 else K.COL_HANJI
			_overlay.draw_rect(Rect2(p.round(), Vector2(2, 1) if (int(dt_ * 20.0) + j) % 2 == 0 else Vector2(1, 2)),
				Color(colp, 1.0 if dt_ < 0.18 else 0.5))
