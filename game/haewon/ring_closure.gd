class_name RingClosure
extends Node2D
## 길닦음: 길베가 자기 자신과 만나 고리가 닫히면 안의 풀릴 기색 잡귀를 일괄 해원. 소유: haewon.
## 데이터: combat_core.ring (snap_u 1.5, exclude_recent_sec 0.5, min_points 8, min_area_tiles 9, cooldown 1.0, grid_u 1.0,
##        min_targets_for_effect, dmg_*, heal_*, sinmyeong_*, mandala_*, sal_cleanse_per_grain, fx_max_delay_ms, cheondo_rule)
## 알고리즘(design/14 §3.7.3): 후보점(가장 오래된 것) → [O(1) 신발끈 넓이 조기 탈출] → 1u 격자 래스터(경계 표시)
##   → 바깥 플러드필 → 내부 칸 수 ≥ 9 → zone(내부+경계)의 적: 풀릴 기색 = 해원,
##   일괄 풀이(11-24): 일반·하위 적 한 ≤50% = 해원, 그 밖의 일반·하위 = 기색에 들여 한 1로 묶음, 정예↑ = 백 피해(2×Σritual_ref×신빨, 보스 ×0.5)
##   → 해원 ≥3: 구슬 끌어오기 + 신명 +5% / 넓이 ≥30: 고리 해원 경험치 ×1.5(보너스 구슬)
##   → 영가(남은 수명 ≤10초 천도·나머지 +5초·오라 폭발) → 회복(+1%/천도, 10초 창 10%) → 신명(+2%/해원, ≤15%)
##   → 면적 ≥60: 오방 만다라 도량 6초 → zone 안 살 알갱이 정화. 할당 없음(스크래치 버퍼 재사용).
## 넓이 0 판정 수정(2026-11-22): 되돌아가기·제자리·느린 걸음에서 0.5초 전 점이 스냅 안에 들어와 매 틱 넓이 0 래스터를 돌던 문제 →
##   길베 누적 외적으로 후보 구간 넓이를 O(1)로 구해 9타일² 미만이면 래스터하지 않는다(내부 칸 넓이 ≤ 폴리곤 넓이 이므로 정확한 필요조건).
##   빈 고리(대상 없음) 뒤에는 6틱 동안 재래스터하지 않는다.
## 가이드: 닫을 수 있는 후보(스냅 3.5u 이내 + 넓이 충족 + 대상 있음)가 생기면 Events.gilbe_ready(true) 와 예상선(점선·매듭 표지·zone 음영).
## 연출(닫힘): 매듭(vfx_gildakkeum_knot ×2) → 둘레 섬광이 매듭에서 양쪽으로 달려 만남 → 다음 박(≤250ms)에 만다라 채움이
##   매듭에서 칸마다 번져 감(vfx_gildakkeum_fill) → 꽃잎(vfx_gildakkeum_petals) 흩날림. 히트스톱·플래시·흔들림은 vfx(HitFeedback),
##   소리는 audio 가 Events.ring_closed 로 처리. 모든 연출은 연출 시계(히트스톱 중 정지 = 임팩트 프레임 유지).

const GRID_MAX: int = 64            # 64u × 64u 까지(그 이상은 판정하지 않음)
const CELL_CAP: int = 1024          # 연출 칸 상한
const POLY_CAP: int = 1024
const PET_CAP: int = 96
const GUIDE_EVERY: int = 6

var trail: GilbeTrail = null
var auto_knot: bool = false         # 접근성 '자동 매듭': 스냅 2.5u
var guide_enabled: bool = true      # 접근성 '고리 보조선'(ui/설정이 끔·켬)

var _snap: float = 1.5 * 32.0
var _snap_auto: float = 2.5 * 32.0
var _snap_sinmyeong: float = 2.5 * 32.0
var _guide_r: float = 3.5 * 32.0
var _exclude_recent: float = 0.5
var _min_points: int = 8
var _min_area: int = 9
var _cooldown: float = 1.0
var _cd_left: float = 0.0
var _cell: float = 32.0
var _dmg_mult: float = 2.0
var _boss_mult: float = 0.5
var _min_giseak: int = 1
var _min_enemies: int = 3
var _heal_per: float = 0.01
var _heal_cap: float = 0.1
var _heal_window: float = 10.0
var _sm_per: float = 0.02
var _sm_cap: float = 0.15
var _md_area: int = 60
var _md_dur: float = 6.0
var _fx_max_delay: float = 0.25
# 일괄 풀이(2026-11-24 리뷰: 고리 보상감) — combat_core.ring.bulk_*
var _bulk_han: float = 0.5            # 일반·하위 적 한 ≤ 50% → 즉시 해원, 나머지는 기색에 들여 한 1로 묶음
var _bulk_min: int = 3                # 고리 해원 ≥3 → 구슬 끌어오기 + 신명 +5%
var _bulk_sm: float = 0.05
var _xp_area: int = 30                # 넓이 ≥30 → 고리 해원 경험치 ×1.5(보너스 구슬)
var _xp_mult: float = 1.5
var _xp_cache: Dictionary = {}        # StringName -> float (고리 닫힘 때만 채움)
var ring_haewon_total: int = 0        # 텔레메트리: 고리로 해원된 수(누계)
var ring_bound_total: int = 0         # 기색에 묶인 수(누계)
var _grid: PackedByteArray = PackedByteArray()
var _stack: PackedInt32Array = PackedInt32Array()
var _q: PackedInt32Array = PackedInt32Array()
var _gx0: int = 0
var _gy0: int = 0
var _gw: int = 0
var _gh: int = 0
var _minp: Vector2 = Vector2.ZERO
var _maxp: Vector2 = Vector2.ZERO
var _tick: int = 0
var _retry_tick: int = 0
var _heal_t: PackedFloat32Array = PackedFloat32Array()
var _heal_v: PackedFloat32Array = PackedFloat32Array()
var _heal_head: int = 0
var last_area: int = 0
var _haewon_rings: int = 0           # 해원이 있었던 고리 수(첫 고리는 ui/guide 이름표만 — 글자 겹침 방지)
var closes: int = 0
var empty_skips: int = 0
var prefilter_skips: int = 0

# --- 가이드(시뮬에서 계산, 연출이 읽음) ---
var guide_on: bool = false
var _guide_pt: Vector2 = Vector2.ZERO
var _g_cells: PackedInt32Array = PackedInt32Array()
var _g_cells_n: int = 0
var _g_next_tick: int = 0
var _g_k_time: float = -1.0

# --- 닫힘 연출 ---
var _cl_t: float = -1.0              # 연출 시계 경과(초), <0 = 없음
var _cl_fill_delay: float = 0.0
var _cl_knot: Vector2 = Vector2.ZERO
var _cl_poly: PackedVector2Array = PackedVector2Array()
var _cl_len: PackedFloat32Array = PackedFloat32Array()
var _cl_poly_n: int = 0
var _cl_cells: PackedInt32Array = PackedInt32Array()
var _cl_cells_n: int = 0
var _cl_big: bool = false
var _cl_center: Vector2 = Vector2.ZERO
var _cl_radius: float = 64.0
# --- 만다라 도량 ---
var _md_grid: PackedByteArray = PackedByteArray()
var _md_gx0: int = 0
var _md_gy0: int = 0
var _md_gw: int = 0
var _md_gh: int = 0
var _md_end: float = -1.0            # 게임 초
var _md_cells: PackedInt32Array = PackedInt32Array()
var _md_cells_n: int = 0
# --- 꽃잎·정화 티끌 ---
var p_x: PackedFloat32Array = PackedFloat32Array()
var p_y: PackedFloat32Array = PackedFloat32Array()
var p_vx: PackedFloat32Array = PackedFloat32Array()
var p_vy: PackedFloat32Array = PackedFloat32Array()
var p_t: PackedFloat32Array = PackedFloat32Array()
var p_life: PackedFloat32Array = PackedFloat32Array()
var p_kind: PackedByteArray = PackedByteArray()      # 0 꽃잎, 1 정화 티끌
var p_n: int = 0

var _fx_knot: Dictionary = {}
var _fx_fill: Dictionary = {}
var _fx_petal: Dictionary = {}
var _fx_md: Dictionary = {}
var _add: Node2D = null
var _top: Node2D = null


func _ready() -> void:
	_snap = Data.num("combat_core", "ring.snap_u", 1.5) * K.UNIT_PX
	_snap_auto = Data.num("combat_core", "ring.snap_auto_knot_u", 2.5) * K.UNIT_PX
	_snap_sinmyeong = Data.num("combat_core", "ring.snap_sinmyeong_u", 2.5) * K.UNIT_PX
	_exclude_recent = Data.num("combat_core", "ring.exclude_recent_sec", 0.5)
	_min_points = int(Data.num("combat_core", "ring.min_points", 8))
	_min_area = int(Data.num("combat_core", "ring.min_area_tiles", 9))
	_cooldown = Data.num("combat_core", "ring.cooldown", 1.0)
	_cell = Data.num("combat_core", "ring.grid_u", 1.0) * K.UNIT_PX
	_dmg_mult = Data.num("combat_core", "ring.dmg_ritual_ref_sum_mult", 2.0)
	_boss_mult = Data.num("combat_core", "ring.dmg_boss_mult", 0.5)
	_min_giseak = int(Data.num("combat_core", "ring.min_targets_for_effect.giseak", 1))
	_min_enemies = int(Data.num("combat_core", "ring.min_targets_for_effect.or_enemies", 3))
	_heal_per = Data.num("combat_core", "ring.heal_per_yeongga", 0.01)
	_heal_cap = Data.num("combat_core", "ring.heal_cap", 0.1)
	_heal_window = Data.num("combat_core", "ring.heal_window_sec", 10.0)
	_sm_per = Data.num("combat_core", "ring.sinmyeong_per_haewon", 0.02)
	_sm_cap = Data.num("combat_core", "ring.sinmyeong_cap", 0.15)
	_md_area = int(Data.num("combat_core", "ring.mandala_area", 60))
	_md_dur = Data.num("combat_core", "ring.mandala_duration", 6.0)
	_fx_max_delay = Data.num("combat_core", "ring.fx_max_delay_ms", 250) / 1000.0
	_bulk_han = Data.num("combat_core", "ring.bulk_release_han_pct", 50.0) / 100.0
	_bulk_min = int(Data.num("combat_core", "ring.bulk_bonus_min_haewon", 3))
	_bulk_sm = Data.num("combat_core", "ring.bulk_bonus_sinmyeong", 0.05)
	_xp_area = int(Data.num("combat_core", "ring.big_ring_xp_area", 30))
	_xp_mult = Data.num("combat_core", "ring.big_ring_xp_mult", 1.5)
	_grid.resize(GRID_MAX * GRID_MAX)
	_stack.resize(GRID_MAX * GRID_MAX)
	_md_grid.resize(GRID_MAX * GRID_MAX)
	_q.resize(1024)
	_g_cells.resize(CELL_CAP)
	_cl_cells.resize(CELL_CAP)
	_md_cells.resize(CELL_CAP)
	_cl_poly.resize(POLY_CAP)
	_cl_len.resize(POLY_CAP)
	_heal_t.resize(16)
	_heal_t.fill(-1000.0)
	_heal_v.resize(16)
	_heal_v.fill(0.0)
	for a: String in ["p_x", "p_y", "p_vx", "p_vy", "p_t", "p_life"]:
		var arr: PackedFloat32Array = PackedFloat32Array()
		arr.resize(PET_CAP)
		set(a, arr)
	p_kind.resize(PET_CAP)
	_fx_knot = VfxLib.get_fx(&"vfx_gildakkeum_knot")
	_fx_fill = VfxLib.get_fx(&"vfx_gildakkeum_fill")
	_fx_petal = VfxLib.get_fx(&"vfx_gildakkeum_petals")
	_fx_md = VfxLib.get_fx(&"vfx_doryang_mandala")
	z_index = -1
	_add = Node2D.new()
	var am: CanvasItemMaterial = CanvasItemMaterial.new()
	am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add.material = am
	_add.draw.connect(_draw_add)
	add_child(_add)
	_top = Node2D.new()
	_top.z_index = 4
	_top.draw.connect(_draw_top)
	add_child(_top)


func _snap_r() -> float:
	if Game.sinmyeong_oreum:
		return _snap_sinmyeong
	return _snap_auto if auto_knot else _snap


## 틱 5.
func sim_check(dt: float) -> void:
	_tick += 1
	if _cd_left > 0.0:
		_cd_left -= dt
		_set_guide(false)
		return
	if trail == null or trail.count < _min_points:
		_set_guide(false)
		return
	var n: int = trail.count
	var b: int = n - 1
	var latest: Vector2 = trail.point(b)
	var t_now: float = trail.time_at(b)
	var snap: float = _snap_r()
	var gr: float = maxf(_guide_r, snap + 32.0)
	var min_a2: float = 2.0 * float(_min_area) * _cell * _cell
	var cand: int = -1
	var gk: int = -1
	var k: int = 0
	var last_k: int = b - _min_points
	while k <= last_k:
		if t_now - trail.time_at(k) < _exclude_recent:
			break
		# 건너뛰기: 머리에서 d 떨어진 점 뒤로 경로가 (d − r) 만큼 더 가기 전에는 r 안에 들어올 수 없다(이분 탐색)
		var r: float = gr if (gk < 0 and guide_enabled) else snap
		var d: float = trail.point(k).distance_to(latest)
		if d > r:
			var nk: int = trail.first_len_at_least(trail.len_at(k) + (d - r) - 0.5, k + 1, last_k)
			k = maxi(nk, k + 1)
			continue
		var a2: float = absf(trail.area2(k, b))
		if a2 < min_a2:
			# 넓이 0·되돌아가기: 래스터하지 않는다. 시작점을 길이 s 만큼 옮길 때 넓이×2 는 많아야 s·d 변하므로
			# 경로 L 동안 변화 ≤ d·L + L²/2 → 모자란 넓이를 채우는 최소 L 까지 건너뛴다(정확한 필요조건).
			prefilter_skips += 1
			var need_l: float = sqrt(d * d + 2.0 * (min_a2 - a2)) - d
			var nk2: int = trail.first_len_at_least(trail.len_at(k) + need_l - 0.5, k + 1, last_k)
			k = maxi(nk2, k + 1)
			continue
		if d <= snap:
			cand = k
			break      # pick_oldest_candidate
		if gk < 0:
			gk = k
		k += 1
	if cand >= 0 and _tick >= _retry_tick:
		if _evaluate(cand, b):
			_set_guide(false)
			return
		_retry_tick = _tick + GUIDE_EVERY
	if cand >= 0 and gk < 0:
		gk = cand
	_update_guide(gk, b)


## 가이드: 스냅 직전 후보의 zone 을 미리 래스터해 대상이 있으면 예상선을 켠다(6틱마다, 후보가 바뀌면 즉시).
func _update_guide(k: int, b: int) -> void:
	if k < 0 or not guide_enabled:
		_set_guide(false)
		return
	_guide_pt = trail.point(k)
	var kt: float = trail.time_at(k)
	if _tick < _g_next_tick and absf(kt - _g_k_time) < 0.25:
		return
	_g_next_tick = _tick + GUIDE_EVERY
	_g_k_time = kt
	var area: int = _raster(k, b)
	if area < _min_area:
		_set_guide(false)
		return
	var giseak: int = _scan_targets(false)
	var others: int = _q_others
	if giseak < _min_giseak and others < _min_enemies:
		_set_guide(false)
		return
	_g_cells_n = _collect_cells(_g_cells)
	_set_guide(true)


func _set_guide(on: bool) -> void:
	if on == guide_on:
		return
	guide_on = on
	if not on:
		_g_cells_n = 0
	Events.gilbe_ready.emit(on)


## 구간 [a..b] 를 래스터 + 바깥 플러드필. 반환 내부 칸 수(-1 = 너무 큼/작음). _grid: 0 내부, 1 경계, 2 바깥.
func _raster(a: int, b: int) -> int:
	var minp: Vector2 = trail.point(a)
	var maxp: Vector2 = minp
	for k in range(a, b + 1):
		var p: Vector2 = trail.point(k)
		minp = minp.min(p)
		maxp = maxp.max(p)
	_minp = minp
	_maxp = maxp
	var gx0: int = int(floor(minp.x / _cell)) - 1
	var gy0: int = int(floor(minp.y / _cell)) - 1
	var gw: int = int(floor(maxp.x / _cell)) - gx0 + 2
	var gh: int = int(floor(maxp.y / _cell)) - gy0 + 2
	if gw > GRID_MAX or gh > GRID_MAX or gw < 5 or gh < 5:
		return -1   # 내부 9칸(3×3) 이상이려면 패딩 포함 5×5 이상
	_gx0 = gx0
	_gy0 = gy0
	_gw = gw
	_gh = gh
	for i in gw * gh:
		_grid[i] = 0
	# 경계 래스터(선분을 1/4칸 간격으로 샘플, 닫는 선분 포함)
	var step: float = _cell * 0.25
	for k in range(a, b + 1):
		var p0: Vector2 = trail.point(k)
		var p1: Vector2 = trail.point(a) if k == b else trail.point(k + 1)
		var steps: int = maxi(1, int(ceil(p0.distance_to(p1) / step)))
		for s in steps + 1:
			var p: Vector2 = p0.lerp(p1, float(s) / float(steps))
			var cx: int = int(floor(p.x / _cell)) - gx0
			var cy: int = int(floor(p.y / _cell)) - gy0
			if cx >= 0 and cy >= 0 and cx < gw and cy < gh:
				_grid[cy * gw + cx] = 1
	# 바깥 플러드필(테두리에서 시작) → 2
	var sp: int = 0
	for x in gw:
		sp = _push(x, 0, gw, sp)
		sp = _push(x, gh - 1, gw, sp)
	for y in gh:
		sp = _push(0, y, gw, sp)
		sp = _push(gw - 1, y, gw, sp)
	while sp > 0:
		sp -= 1
		var c: int = _stack[sp]
		var cx2: int = c % gw
		var cy2: int = c / gw
		if cx2 > 0:
			sp = _push(cx2 - 1, cy2, gw, sp)
		if cx2 < gw - 1:
			sp = _push(cx2 + 1, cy2, gw, sp)
		if cy2 > 0:
			sp = _push(cx2, cy2 - 1, gw, sp)
		if cy2 < gh - 1:
			sp = _push(cx2, cy2 + 1, gw, sp)
	var area: int = 0
	for i in gw * gh:
		if _grid[i] == 0:
			area += 1
	return area


func _push(x: int, y: int, gw: int, sp: int) -> int:
	var i: int = y * gw + x
	if _grid[i] != 0:
		return sp
	_grid[i] = 2
	_stack[sp] = i
	return sp + 1


## 마지막 래스터의 zone(내부+경계) 안인가. 닫힘 처리 중(같은 틱)에만 유효.
func in_zone(p: Vector2) -> bool:
	var cx: int = int(floor(p.x / _cell)) - _gx0
	var cy: int = int(floor(p.y / _cell)) - _gy0
	if cx < 0 or cy < 0 or cx >= _gw or cy >= _gh:
		return false
	return _grid[cy * _gw + cx] != 2


## 공개: 방금 닫힌 고리의 zone(내부+경계) 안인가. Events.ring_closed 핸들러 안에서만 유효(같은 틱, 다음 래스터 전).
## waves(뒷전 공물상)·deities 가 등가 원 대신 정확한 포함 판정에 쓴다.
func contains(p: Vector2) -> bool:
	return _in_closed and in_zone(p)


var _in_closed: bool = false
var _q_others: int = 0

## zone 안 적을 _q 앞으로 압축. 반환 풀릴 기색 수(_q_others = 나머지 수).
func _scan_targets(compact: bool) -> int:
	_q_others = 0
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return 0
	var center: Vector2 = (_minp + _maxp) * 0.5
	var r: float = (_maxp - _minp).length() * 0.5 + _cell
	var nq: int = em.query_circle(center, r, _q)
	var giseak: int = 0
	var m: int = 0
	for k in nq:
		var i: int = _q[k]
		if not in_zone(Vector2(em.px[i], em.py[i])):
			continue
		if (em.flags[i] & EnemyManager.F_PULLIL) != 0:
			giseak += 1
		else:
			_q_others += 1
		if compact:
			_q[m] = i
		m += 1
	return giseak


## zone 칸 수집. interior_only = 경계 칸 제외(연출용: 채움이 고리 선 밖으로 각지게 삐져나오지 않게).
func _collect_cells(out: PackedInt32Array, interior_only: bool = false) -> int:
	var n: int = 0
	var lim: int = 1 if interior_only else 2
	for cy in _gh:
		for cx in _gw:
			if _grid[cy * _gw + cx] < lim and n < CELL_CAP:
				out[n] = ((cy + _gy0) + 32768) << 16 | (((cx + _gx0) + 32768) & 0xFFFF)
				n += 1
	return n


static func _cell_x(c: int) -> int:
	return (c & 0xFFFF) - 32768


static func _cell_y(c: int) -> int:
	return ((c >> 16) & 0xFFFF) - 32768


func _evaluate(a: int, b: int) -> bool:
	var area: int = _raster(a, b)
	if area < _min_area:
		return false
	var giseak: int = _scan_targets(true)
	var others: int = _q_others
	if giseak < _min_giseak and others < _min_enemies:
		empty_skips += 1
		return false  # empty_ring_silent: 효과·소모·재사용 대기·연출 모두 생략
	last_area = area
	closes += 1
	var em: EnemyManager = Game.enemies as EnemyManager
	# 효과 1·2
	var dmg: float = _dmg_mult * HaewonSystem.ritual_ref_sum() * minf(Game.stat(&"stat_sinppal", 1.0), 10.0)
	var haewon_n: int = 0
	var bound_n: int = 0
	var xp_bonus: bool = area >= _xp_area and _xp_mult > 1.0
	var pk: PickupManager = Game.pickups as PickupManager
	var yt: YeonggaTrain = null
	var hs: HaewonSystem = null
	if Game.run_root != null:
		yt = Game.run_root.get("yeongga") as YeonggaTrain
		hs = Game.run_root.get("haewon") as HaewonSystem
	for k in giseak + others:
		var i: int = _q[k]
		var tier: StringName = em.tier_of(i)
		var bossy: bool = tier == K.TIER_BOSS or tier == K.TIER_MBOSS or tier == K.TIER_CHASER
		var f: int = em.flags[i]
		var commonish: bool = (tier == K.TIER_COMMON or tier == K.TIER_MINION) and (f & EnemyManager.F_ELITE_PLUS) == 0
		var release: bool = (f & EnemyManager.F_PULLIL) != 0 and not bossy
		# 일괄 풀이: 일반·하위 적은 한 ≤ 50% 면 기색이 아니어도 즉시 해원
		if not release and commonish and em.han[i] <= _bulk_han * em.han_max[i]:
			release = true
		if release:
			var sp: StringName = em.species_id_of(i)
			var pos: Vector2 = Vector2(em.px[i], em.py[i])
			em.force_haewon(i, &"ring")
			if em.is_alive(i):
				continue   # 거대 개체·비적대가 강제 해원을 거부
			haewon_n += 1
			if xp_bonus and pk != null:
				var xv: float = _xp_of(sp)
				if xv > 0.0:
					pk.spawn_orb(pos, xv * (_xp_mult - 1.0))
		elif commonish and (f & EnemyManager.F_NO_PULLIL) == 0:
			# 나머지 일반·하위 적: 강제로 풀릴 기색에 들여 한을 1로 묶는다(흰 무구 한 번이면 풀림)
			em.set_han(i, 1.0)
			em.enter_pullil_now(i)
			bound_n += 1
			if hs != null:
				hs.mark_ring_bound(i, em.handle_of(i))
		else:
			em.queue_hit(i, dmg * (_boss_mult if bossy else 1.0), K.DmgColor.RING, false, Vector2.ZERO, 0.0, -1)
	ring_haewon_total += haewon_n
	ring_bound_total += bound_n
	# 효과 3: 영가
	var cheondo_n: int = yt.ring_effect(self) if yt != null else 0
	if cheondo_n > 0:
		_heal(cheondo_n)
	var bulk_bonus: bool = haewon_n >= _bulk_min
	if hs != null:
		hs.add_sinmyeong(minf(_sm_per * float(haewon_n), _sm_cap) + (_bulk_sm if bulk_bonus else 0.0))
	if bulk_bonus and pk != null:
		# 고리 보상: 고리 둘레 + 3u 안 구슬이 한꺼번에 무당에게 끌려온다(해원 구슬 포함 — 방금 떨어졌다)
		pk.pull_all((_minp + _maxp) * 0.5, (_maxp - _minp).length() * 0.5 + 3.0 * K.UNIT_PX)
	# 효과 4: 만다라 도량
	_cl_big = area >= _md_area
	if _cl_big:
		_start_mandala()
	# 효과 5: 살 알갱이 정화
	if hs != null:
		hs.cleanse_zone(self)
	# 연출 스냅샷
	_snapshot_fx(a, b)
	var center: Vector2 = (_minp + _maxp) * 0.5
	if haewon_n > 0:
		_haewon_rings += 1
	if hs != null and _haewon_rings > 1 and (haewon_n >= 3 or (_cl_big and haewon_n > 0)):   # 작은 고리는 ui 가 중심에 '길닦음' 표지만(글자 겹침 방지)
		# 붓글씨 배너: 무엇을 해냈는지 한눈에(처음 하는 사람용) — 이벤트 시에만 문자열 생성
		hs.slam("한꺼번에 풀림 ×%d" % haewon_n,
			24 if haewon_n < 5 else (30 if haewon_n < 12 else 38), 0.9 if haewon_n < 12 else 1.2, false, true)
	_in_closed = true
	Events.ring_closed.emit(area, haewon_n, center)
	_in_closed = false
	if Game.autotest:
		print("[haewon] ring t=%.2f tick=%d area=%d haewon=%d others=%d cheondo=%d mandala=%s pts=%d prefilter_skips=%d empty=%d" % [
			Game.time_sec(), Game.game_tick, area, haewon_n, others, cheondo_n, str(_cl_big), b - a + 1, prefilter_skips, empty_skips])
		print("[haewon]   ring_bulk bound=%d bonus=%s xp_bonus=%s" % [bound_n, str(bulk_bonus), str(xp_bonus)])
	trail.consume_keep_last(1)
	_cd_left = _cooldown
	return true


func _xp_of(sp: StringName) -> float:
	if not _xp_cache.has(sp):
		var xv: Variant = Data.enemy(String(sp)).get("xp", 1)
		_xp_cache[sp] = float(xv) if (xv is float or xv is int) else 0.0
	return float(_xp_cache[sp])


func _heal(cheondo_n: int) -> void:
	var p: Player = Game.player as Player
	if p == null:
		return
	var t: float = Game.time_sec()
	var used: float = 0.0
	for i in _heal_t.size():
		if t - _heal_t[i] < _heal_window:
			used += _heal_v[i]
	var ratio: float = minf(_heal_per * float(cheondo_n), _heal_cap - used)
	if ratio <= 0.0:
		return
	_heal_t[_heal_head] = t
	_heal_v[_heal_head] = ratio
	_heal_head = (_heal_head + 1) % _heal_t.size()
	p.hit.heal(Game.hp_max * ratio)


func _start_mandala() -> void:
	_md_gx0 = _gx0
	_md_gy0 = _gy0
	_md_gw = _gw
	_md_gh = _gh
	for i in _gw * _gh:
		_md_grid[i] = 1 if _grid[i] != 2 else 0
	_md_end = Game.time_sec() + _md_dur
	_md_cells_n = _collect_cells(_md_cells)


## 오방 만다라 도량(면적 ≥60 고리가 6초 남김) 활성 여부. combat(신빨 +15%)·enemies(둔화 20%)가 읽는다.
func mandala_active() -> bool:
	return Game.time_sec() < _md_end


func mandala_contains(p: Vector2) -> bool:
	if not mandala_active():
		return false
	var cx: int = int(floor(p.x / _cell)) - _md_gx0
	var cy: int = int(floor(p.y / _cell)) - _md_gy0
	if cx < 0 or cy < 0 or cx >= _md_gw or cy >= _md_gh:
		return false
	return _md_grid[cy * _md_gw + cx] != 0


## 살 정화 티끌(HaewonSystem.cleanse_zone 이 부름).
func add_cleanse_fx(p: Vector2) -> void:
	for j in 2:
		_add_particle(p + Vector2(Rng.range_s(&"fx", -3, 3), -2), Vector2(Rng.range_s(&"fx", -6, 6), Rng.range_s(&"fx", -34, -22)), 0.7, 1)


func _add_particle(p: Vector2, v: Vector2, life: float, kind: int) -> void:
	if p_n >= PET_CAP:
		return
	p_x[p_n] = p.x
	p_y[p_n] = p.y
	p_vx[p_n] = v.x
	p_vy[p_n] = v.y
	p_t[p_n] = 0.0
	p_life[p_n] = life
	p_kind[p_n] = kind
	p_n += 1


func _snapshot_fx(a: int, b: int) -> void:
	_cl_t = 0.0
	_cl_knot = trail.point(b)
	_cl_center = (_minp + _maxp) * 0.5
	_cl_radius = maxf((_maxp - _minp).length() * 0.5, 48.0)
	# 둘레: 매듭(최신 점)에서 시작해 거꾸로 — 섬광이 매듭에서 양쪽으로 달린다
	var stride: int = maxi(1, int(ceil(float(b - a + 1) / float(POLY_CAP - 1))))
	_cl_poly_n = 0
	var acc: float = 0.0
	var k: int = b
	while k >= a and _cl_poly_n < POLY_CAP - 1:
		var p: Vector2 = trail.point(k)
		if _cl_poly_n > 0:
			acc += p.distance_to(_cl_poly[_cl_poly_n - 1])
		_cl_poly[_cl_poly_n] = p
		_cl_len[_cl_poly_n] = acc
		_cl_poly_n += 1
		k -= stride
	acc += _cl_poly[_cl_poly_n - 1].distance_to(_cl_knot)
	_cl_poly[_cl_poly_n] = _cl_knot
	_cl_len[_cl_poly_n] = acc
	_cl_poly_n += 1
	_cl_cells_n = _collect_cells(_cl_cells, true)
	# 연출은 다음 박에 스냅(≤250ms), 판정은 즉시
	var to_beat: float = (1.0 - Beat.beat_phase()) * Beat.beat_len_sec()
	_cl_fill_delay = to_beat if to_beat <= _fx_max_delay else 0.0
	# 매듭
	var vfx: VfxPlayer = Game.vfx as VfxPlayer
	if vfx != null:
		vfx.play(&"vfx_gildakkeum_knot", _cl_knot, 0.0, 2.0, {"additive": true})
	# 오컬트 조명: 매듭에 백 섬광 + 고리 전체를 비추는 해원 빛(어둠이 한순간 걷힌다)
	Juice.light_pulse(_cl_knot, 56.0, 1.0, 1, 0.35)
	Juice.light_pulse(_cl_center, _cl_radius * 1.5 + 24.0, 0.9 if _cl_big else 0.7, 1, 1.1 if _cl_big else 0.8)
	# 꽃잎: 둘레를 따라 고르게(최대 40장), 바깥·위로 흩날림
	var center: Vector2 = (_minp + _maxp) * 0.5
	var np: int = clampi(_cl_poly_n / 3, 12, 40)
	for j in np:
		var idx: int = int(float(j) / float(np) * float(_cl_poly_n - 1))
		var p2: Vector2 = _cl_poly[idx]
		var out: Vector2 = (p2 - center).normalized()
		var v: Vector2 = out * Rng.range_s(&"fx", 14.0, 30.0) + Vector2(Rng.range_s(&"fx", -6, 6), Rng.range_s(&"fx", -48.0, -26.0))
		_add_particle(p2, v, Rng.range_s(&"fx", 1.0, 1.6), 0)
	if _cl_big:
		for j2 in 16:   # 큰 고리: 중심에서 꽃비
			var ang: float = TAU * float(j2) / 16.0
			_add_particle(center, Vector2(cos(ang), sin(ang) * 0.6 - 0.9) * 46.0, 1.8, 0)


# ─── 연출(연출 시계) ───────────────────────────────────────────────────

func _process(_delta: float) -> void:
	var adt: float = Game.anim_dt
	var busy: bool = guide_on or _g_cells_n > 0
	if guide_on:
		# 매듭 자리 표지 빛(박에 맞춰 숨쉼): 어두운 판에서도 '여기로 돌아와 묶어라'가 보이게
		var gp: float = pow(1.0 - Beat.beat_phase(), 2.0)
		Juice.light_frame(_guide_pt, 30.0 + 6.0 * gp, 0.3 + 0.3 * gp, 1)
	if _cl_t >= 0.0:
		_cl_t += adt
		busy = true
		if _cl_t > _cl_fill_delay + 1.6:
			_cl_t = -1.0
	if p_n > 0:
		busy = true
		var k: int = 0
		while k < p_n:
			p_t[k] += adt
			if p_t[k] >= p_life[k]:
				p_n -= 1
				p_x[k] = p_x[p_n]
				p_y[k] = p_y[p_n]
				p_vx[k] = p_vx[p_n]
				p_vy[k] = p_vy[p_n]
				p_t[k] = p_t[p_n]
				p_life[k] = p_life[p_n]
				p_kind[k] = p_kind[p_n]
				continue
			var g: float = 46.0 if p_kind[k] == 0 else -8.0
			p_vy[k] += g * adt
			p_vx[k] *= 1.0 - 1.5 * adt
			p_x[k] += p_vx[k] * adt
			p_y[k] += p_vy[k] * adt
			k += 1
	if mandala_active() or _md_cells_n > 0:
		busy = true
		if not mandala_active():
			_md_cells_n = 0
	if busy or _was_busy:
		queue_redraw()
		_add.queue_redraw()
		_top.queue_redraw()
	_was_busy = busy


var _was_busy: bool = false


func _draw() -> void:
	var t: float = Game.anim_time()
	var ph: float = Beat.beat_phase()
	var pulse: float = pow(1.0 - ph, 2.0)
	# ① 가이드: zone 음영(칸) + 점선 예상선 + 스냅 원(점) + 매듭 표지
	if guide_on and _g_cells_n > 0:
		# zone 칸마다 가운데 2px 점(단청 격자처럼) — 박 머리에 밝아짐: '여기가 풀린다'
		var ca: float = 0.22 + 0.4 * pulse
		for i in _g_cells_n:
			var c: int = _g_cells[i]
			var cc: Vector2 = Vector2(_cell_x(c), _cell_y(c)) * _cell + Vector2(_cell * 0.5 - 1.0, _cell * 0.5 - 1.0)
			draw_rect(Rect2(cc, Vector2(2, 2)), Color(K.COL_BAEK, ca))
		var pl: Player = Game.player as Player
		if pl != null:
			var from: Vector2 = pl.render_pos
			var to: Vector2 = _guide_pt
			var d: float = from.distance_to(to)
			if d > 2.0:
				var dir: Vector2 = (to - from) / d
				var march: float = fmod(t * 24.0, 7.0)
				var s: float = march
				while s < d:
					var e: float = minf(s + 4.0, d)
					draw_line((from + dir * s).round(), (from + dir * e).round(), Color(K.COL_BAEK, 0.85), 1.0)
					s += 7.0
			# 스냅 원(16점, 박에 맞춰 1px 숨쉼)
			var sr: float = _snap_r() + (1.0 if pulse > 0.5 else 0.0)
			for j in 16:
				var ang: float = TAU * float(j) / 16.0 + t * 0.8
				draw_rect(Rect2((to + Vector2(cos(ang), sin(ang)) * sr).round(), Vector2(1, 1)), Color(K.COL_BAEK, 0.7))
			_draw_fx_frame(self, _fx_knot, 0, to, Color(1, 1, 1, 0.55 + 0.45 * pulse), 1)
	# ② 닫힘 둘레: 빛 머리 하나가 매듭에서 흰 길을 따라 0.25초에 한 바퀴 달린다(한지 2px, 꼬리 6px — design/19 §5.2 G).
	#    지나간 길은 백으로 남았다가 계단 감쇠. 다 돌면 안쪽 원 마스크 섬광(한지 α0.25, 1f).
	if _cl_t >= 0.0 and _cl_poly_n >= 2:
		var total: float = _cl_len[_cl_poly_n - 1]
		var lap: float = 0.25
		var run: float = clampf(_cl_t / lap, 0.0, 1.0) * total
		var fade_a: float = 1.0
		if _cl_t > 0.5:
			fade_a = 0.6 if _cl_t < 0.75 else (0.3 if _cl_t < 1.0 else 0.0)
		if fade_a > 0.0:
			var core: bool = _cl_t >= lap and _cl_t < lap + 0.05
			var col: Color = Color(K.COL_BAEK_FLASH if core else K.COL_BAEK, fade_a)
			var w: float = 1.0 if WeaponBase.fx_crowd() else 2.0
			for i in range(1, _cl_poly_n):
				if _cl_len[i - 1] > run:
					break
				draw_line(_cl_poly[i - 1].round(), _cl_poly[i].round(), col, w)
			if run < total:
				_draw_head(run)
		if _cl_t >= lap and _cl_t < lap + 2.5 / K.TICK_HZ:
			draw_circle(_cl_center.round(), roundf(_cl_radius * 0.9), Color(K.COL_HANJI, 0.25))
		# 매듭 임팩트: 8갈래 섬광(0.12초, 히트스톱 동안 그대로 멈춰 임팩트 프레임이 된다)
		if _cl_t < 0.12:
			var r0: float = 5.0 if _cl_t < 0.05 else 9.0
			var r1: float = 14.0 if _cl_t < 0.05 else (22.0 if _cl_big else 18.0)
			var kp: Vector2 = _cl_knot.round()
			for j in 8:
				var dv: Vector2 = Vector2.RIGHT.rotated(TAU * float(j) / 8.0 + 0.3927)
				draw_line((kp + dv * r0).round(), (kp + dv * r1).round(), K.COL_BAEK_FLASH, 2.0 if (j & 1) == 0 else 1.0)
		# 채움과 함께 퍼지는 점 고리(중심 → 바깥, 3단 계단 감쇠): '안쪽이 한꺼번에 풀렸다'
		var wt: float = _cl_t - _cl_fill_delay
		if wt >= 0.0 and wt < 0.4:
			var wu: float = wt / 0.4
			var wr: float = _cl_radius * (0.25 + 0.95 * (1.0 - (1.0 - wu) * (1.0 - wu)))
			var wa: float = 0.9 if wu < 0.4 else (0.55 if wu < 0.7 else 0.25)
			var cp: Vector2 = _cl_center
			for j2 in 40:
				var ang2: float = TAU * float(j2) / 40.0
				draw_rect(Rect2((cp + Vector2(cos(ang2), sin(ang2)) * wr).round(), Vector2(2, 2)), Color(K.COL_BAEK, wa))


## 빛 머리(한지 3px + 백 심 1px) + 뒤로 6px 꼬리(한지 2px).
func _draw_head(dist: float) -> void:
	var hp: Vector2 = _point_at(dist).round()
	var tp: Vector2 = _point_at(maxf(0.0, dist - 6.0)).round()
	draw_line(tp, hp, K.COL_HANJI, 2.0)
	draw_rect(Rect2(hp - Vector2(2, 2), Vector2(5, 5)), Color(K.COL_HANJI, 0.7))
	draw_rect(Rect2(hp - Vector2(1, 1), Vector2(3, 3)), K.COL_HANJI)
	draw_rect(Rect2(hp, Vector2.ONE), K.COL_BAEK_FLASH)


func _point_at(dist: float) -> Vector2:
	for i in range(1, _cl_poly_n):
		if _cl_len[i] >= dist:
			var seg: float = maxf(_cl_len[i] - _cl_len[i - 1], 0.001)
			return _cl_poly[i - 1].lerp(_cl_poly[i], (dist - _cl_len[i - 1]) / seg)
	return _cl_poly[_cl_poly_n - 1]


func _draw_runner(dist: float) -> void:
	for i in range(1, _cl_poly_n):
		if _cl_len[i] >= dist:
			var seg: float = maxf(_cl_len[i] - _cl_len[i - 1], 0.001)
			var p: Vector2 = _cl_poly[i - 1].lerp(_cl_poly[i], (dist - _cl_len[i - 1]) / seg).round()
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), Color(K.COL_BAEK, 0.6))
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), K.COL_BAEK_FLASH)
			return


## 가산 레이어: 만다라 채움(칸마다 매듭에서 번져 감) + 오방 만다라 도량.
func _draw_add() -> void:
	var t: float = Game.anim_time()
	# 도량: 64px 시트를 칸 짝·홀로 4등분해 이음매 없이 타일링
	if mandala_active() and _md_cells_n > 0:
		var regions: Array = _fx_md.get("regions", [])
		if not regions.is_empty():
			var left: float = _md_end - Game.time_sec()
			var a: float = 0.5 if left > 1.0 else (0.3 if left > 0.5 else 0.15)
			var fi: int = int(floorf(t * float(_fx_md["fps"]))) % regions.size()
			var r: Rect2 = regions[fi]
			for i in _md_cells_n:
				var c: int = _md_cells[i]
				var cx: int = _cell_x(c)
				var cy: int = _cell_y(c)
				var sub: Rect2 = Rect2(r.position + Vector2((cx & 1) * 32, (cy & 1) * 32), Vector2(32, 32))
				_add.draw_texture_rect_region(_fx_md["texture"], Rect2(Vector2(cx, cy) * _cell, Vector2(_cell, _cell)), sub, Color(1, 1, 1, a))
	if _cl_t < 0.0 or _cl_cells_n == 0:
		return
	var regions2: Array = _fx_fill.get("regions", [])
	if regions2.is_empty():
		return
	# 칸마다 매듭에서 번져 감: ① 0~1프레임 = 바둑판 칸에 첫 프레임 가운데 크롭(가산 0.5→0.25, 칸 전체 사각은 그리지 않음)
	#   ② 3프레임~ = 가운데 꽃 문양만 잘라(16px) 바둑판 칸에 남겼다가 계단 감쇠 — 격자 바닥처럼 보이지 않게.
	var fps: float = float(_fx_fill["fps"])
	var nf: int = regions2.size()
	var kc: Vector2 = _cl_knot / _cell
	var tt: float = _cl_t - _cl_fill_delay
	var tex: Texture2D = _fx_fill["texture"]
	for i in _cl_cells_n:
		var c2: int = _cl_cells[i]
		var cx2: int = _cell_x(c2)
		var cy2: int = _cell_y(c2)
		var dly: float = minf(Vector2(cx2 + 0.5, cy2 + 0.5).distance_to(kc) * 0.035, 0.45)
		var lt: float = tt - dly
		if lt < 0.0:
			continue
		var fi2: int = int(lt * fps)
		var org: Vector2 = Vector2(cx2, cy2) * _cell
		var checker: bool = ((cx2 + cy2) & 1) == 0
		if fi2 < 2:
			# 0~1프레임: 칸 전체 사각 섬광은 회색 격자로 읽혀(리뷰 design/18 §8) 빼고, 바둑판 칸에만
			# 꽃 문양 프레임 가운데 16px 크롭을 가산 α0.5 → 0.25 로 — 매듭에서 꽃이 번지는 모양만 남긴다.
			if checker:
				var r0: Rect2 = regions2[mini(3, nf - 1)]   # 0프레임은 칸 전체 백 칸이라 잘라도 사각 — 꽃 문양 프레임을 일찍 띄운다
				var cr0: Rect2 = Rect2(r0.position + Vector2(8, 8), Vector2(16, 16))
				_add.draw_texture_rect_region(tex, Rect2(org + Vector2(8, 8), cr0.size), cr0, Color(1, 1, 1, 0.5 if fi2 == 0 else 0.25))
			if fi2 == 0:
				continue
		var hold: float = lt - 1.0 / fps
		var a2: float
		if checker:
			a2 = 0.85 if hold < 0.2 else (0.55 if hold < 0.4 else (0.25 if hold < 0.55 else 0.0))
		else:
			a2 = 0.5 if hold < 0.08 else (0.2 if hold < 0.16 else 0.0)
		if a2 <= 0.0:
			continue
		var fi3: int = mini(3 + int(hold * fps * 0.5), nf - 1)
		var rc: Rect2 = regions2[fi3]
		var crop: Rect2 = Rect2(rc.position + Vector2(8, 8), Vector2(16, 16))
		_add.draw_texture_rect_region(tex, Rect2(org + Vector2(8, 8), crop.size), crop, Color(1, 1, 1, a2))


## 위 레이어: 꽃잎·정화 티끌(적 위로 흩날림).
func _draw_top() -> void:
	var regions: Array = _fx_petal.get("regions", [])
	for k in p_n:
		var u: float = p_t[k] / maxf(p_life[k], 0.01)
		var a: float = 1.0 if u < 0.7 else (0.6 if u < 0.85 else 0.3)
		var p: Vector2 = Vector2(p_x[k] + sin(p_t[k] * 9.0 + float(k)) * 2.0, p_y[k]).round()
		if p_kind[k] == 1:
			_top.draw_rect(Rect2(p, Vector2(1, 1 if u > 0.5 else 2)), Color(K.COL_BAEK, a))
			continue
		if regions.is_empty():
			_top.draw_rect(Rect2(p, Vector2(2, 1)), Color(K.COL_HANJI, a))
			continue
		var fi: int = (int(p_t[k] * float(_fx_petal["fps"])) + k) % regions.size()
		_draw_fx_frame(_top, _fx_petal, fi, p, Color(1, 1, 1, a), (k >> 1) & 1)


func _draw_fx_frame(ci: CanvasItem, fx: Dictionary, fi: int, pos: Vector2, col: Color, flip: int) -> void:
	var regions: Array = fx.get("regions", [])
	if regions.is_empty():
		return
	var r: Rect2 = regions[fi % regions.size()]
	var pv: Vector2 = fx["pivot"]
	var org: Vector2 = (pos - pv).round()
	if flip != 0:
		ci.draw_set_transform(org + Vector2(r.size.x, 0), 0.0, Vector2(-1, 1))
		ci.draw_texture_rect_region(fx["texture"], Rect2(Vector2.ZERO, r.size), r, col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_texture_rect_region(fx["texture"], Rect2(org, r.size), r, col)
