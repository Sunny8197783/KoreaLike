class_name DamageNumbers
extends Node2D
## 데미지 숫자(노드 없이 _draw, 풀 256 = perf caps.damage_numbers, 동시 표시 48). 소유: vfx.
## GAME_FEEL 5.4: 정수 폰트 크기(기본 크기 고정, 치명타만 첫 2틱 ×2), 알파 페이드 없음, 연출 시계(히트스톱 중 팝 상태로 홀드).
##   움직임: 0~2틱 팝 → 2~14틱 위로 8px(ease-out 정수 계단) → 14~32틱 정지 → 32~36틱 2틱 점멸 → 소멸.
##   묶음: 같은 key(적 핸들) 0.15s 안의 타격은 합산해 한 숫자로 갱신(상승 위상 유지, 치명 팝만 다시). 적 슬롯 → 숫자 맵으로 O(1).
##   정렬: spawn·묶음 때 글자 너비를 캐시해 x − floor(w/2) 에서 왼쪽 정렬로 그린다(치명 2배 팝은 2w 기준 — 가운데로 커진다).
##   군중 모드(Juice.number_crowd): 동시 표시 상한 Juice.crowd_max_visible(16). Juice.numbers_hidden() 동안 플레이어 숫자 외 숨김.
##   군집 합산(군집 타격 가독성): 다른 적이라도 같은 색 숫자가 cluster_px × cluster_py(24 × 24) 안에서 cluster_s(0.25s) 안에
##     갱신됐으면 그 숫자에 더한다(그 적 슬롯도 그 숫자로 묶인다) — 찌르기 한 줄·몰린 무리를 때려도 숫자 하나가 커지며 올라간다.
##   밀도 상한: 어디서든 local_px × local_py(40 × 32) 안 일반 숫자 local_cap(3)개, 플레이어 주변 near_px(56) 안 near_cap(5)개,
##     화면 전체 max_visible. 넘치면 그 구역의 가장 오래된 일반 숫자 칸을 새 숫자가 쓴다.
##     치명(결단타)·플레이어 숫자는 정리 대상에서 뒤로 미룬다(타격감 유지) — 일반 숫자가 하나도 없을 때만 지운다.
## kind 색(팔레트): red 적 밝음 #e4604f, white 백 #f2ece0(풀릴 기색 대상 백 피해만), crit 황 #e8b931, locked 귀회,
##          player 적 밝음, heal 청록. 모두 먹 #0e0b16 외곽선 OUTLINE(치명 팝 OUTLINE_POP) — 흰 빛기둥·흰 귀신 위에서도 읽힌다.
## 가시성(design/18 §3): 작은 숫자 거르기(최근 2초 최대 타격의 8% 미만 일반 숫자는 새 칸 없음, 합산은 함),
##   화면 밖 128px 넘는 일반 숫자 없음, 무당 몸 상자(±14, −40~+4) 안에 생기면 상자 위로, crowd_soft(잡귀 ≥40) 면 일반 숫자 α0.8.
##   흔들기(x ±4)는 일련번호 해시 — 게임 난수 스트림(fx: 구슬 위치와 공유)을 쓰지 않는다.
## 글자 표식(spawn_label, Juice.label) — 퇴치/해원을 색·움직임으로 구분한다(처음 하는 사람이 두 결말을 읽게):
##   haewon  "풀어 줌"   백 #f2ece0 + 먹. 천천히 14px 떠오른다(48틱) — 풀려 올라가는 넋
##   toechi  "처치"      적 밝음 #e4604f + 적 가장 어둠. 좌우 1px 떨다가 2px 내려앉는다(26틱) — 깎여 부서짐
##   ring    "한꺼번에 풀림 ×N" 백, 글자 2배, 10px 상승(70틱) — 길닦음 일괄 해원

const CAP: int = 256

var _x: PackedFloat32Array = PackedFloat32Array()
var _y: PackedFloat32Array = PackedFloat32Array()
var _v: PackedFloat32Array = PackedFloat32Array()
var _t0: PackedInt32Array = PackedInt32Array()
var _last: PackedInt32Array = PackedInt32Array()      # 마지막 묶음 틱(묶음 창 판정)
var _pop0: PackedInt32Array = PackedInt32Array()      # 치명 팝 시작 틱(묶음 때 다시)
var _w: PackedFloat32Array = PackedFloat32Array()     # 기본 크기 글자 너비(px)
var _map: PackedInt32Array = PackedInt32Array()       # 적 슬롯 → 숫자 인덱스(-1 없음)
var _key: PackedInt32Array = PackedInt32Array()
var _ser: PackedInt32Array = PackedInt32Array()       # 숫자 칸 재사용 일련번호(슬롯 맵 유효성)
var _map_key: PackedInt32Array = PackedInt32Array()   # 적 슬롯 → 묶인 적 핸들
var _map_ser: PackedInt32Array = PackedInt32Array()   # 적 슬롯 → 묶인 숫자 칸의 일련번호
var _ser_next: int = 1
var _k: PackedByteArray = PackedByteArray()
var _alive: PackedByteArray = PackedByteArray()
var _alive_n: int = 0
var _head: int = 0
var _font: Font
var _font_size: int = 12
var _strs: PackedStringArray = PackedStringArray()

# 글자 표식 풀
const LCAP: int = 32
var _lx: PackedFloat32Array = PackedFloat32Array()
var _ly: PackedFloat32Array = PackedFloat32Array()
var _lt0: PackedInt32Array = PackedInt32Array()
var _lk: PackedByteArray = PackedByteArray()
var _lalive: PackedByteArray = PackedByteArray()
var _lstr: PackedStringArray = PackedStringArray()
var _lw: PackedFloat32Array = PackedFloat32Array()
var _lhead: int = 0
var _lalive_n: int = 0
const LKINDS: Dictionary = {&"haewon": 0, &"toechi": 1, &"ring": 2}
const L_LIFE: PackedInt32Array = [48, 26, 70]
const L_RISE: PackedInt32Array = [14, 0, 10]
const L_COL: Array[Color] = [Color8(0xf2, 0xec, 0xe0), Color8(0xe4, 0x60, 0x4f), Color8(0xf2, 0xec, 0xe0)]
const L_SHADOW: Array[Color] = [Color8(0x0e, 0x0b, 0x16), Color8(0x56, 0x13, 0x18), Color8(0x0e, 0x0b, 0x16)]

var _rise_px: int = 8
var _life_ticks: int = 36
var _merge_ticks: int = 9
var _max_visible: int = 48
var _cluster_ticks: int = 15
var _cluster_px: float = 24.0
var _cluster_py: float = 24.0
var _local_px: float = 40.0
var _local_py: float = 32.0
var _local_cap: int = 3
var _near_px: float = 56.0
var _near_cap: int = 5
# 계측(검증 로그 [juice] 줄): 런 시작에 0
var stat_spawned: int = 0
var stat_merged_key: int = 0
var stat_merged_cluster: int = 0
var stat_evicted: int = 0
var stat_alive_max: int = 0
var stat_crit: int = 0
var stat_small_cut: int = 0
var stat_off_cut: int = 0
var stat_moved: int = 0
# 가시성(design/18 §3)
const OUTLINE: int = 4                                # draw_string_outline 크기 4 = 먹 2px(Galmuri11 12px)
const OUTLINE_POP: int = 6                            # 치명 팝(글자 2배) 3px
const COL_OUTLINE: Color = Color(0.0549, 0.0431, 0.0863, 1.0)   # 먹 #0e0b16
const SMALL_MIN: float = 20.0                         # 최근 최대 타격이 이 이상일 때만 거른다
const SMALL_FRAC: float = 0.08
const SMALL_WIN_TICKS: int = 120                      # 2초
const OFF_MARGIN: float = 128.0
const BODY_HX: float = 14.0                           # 무당 몸 상자(발 기준) ±14 × −40..+4
const BODY_TOP: float = -40.0
const BODY_BOT: float = 4.0
const CROWD_SOFT_A: float = 0.8
var crowd_soft: bool = false                          # hit_feedback 이 매 프레임 씀(화면 일반 잡귀 ≥40)
var _imp: PackedByteArray = PackedByteArray()         # 정예 이상 적의 숫자(α·거르기 예외)
var _rmax: float = 0.0
var _rmax_t: int = -100000
var _view_tick: int = -1
var _view: Rect2 = Rect2()

const KINDS: Dictionary = {&"red": 0, &"white": 1, &"crit": 2, &"locked": 3, &"player": 4, &"heal": 5}
const COL_TEXT: Array[Color] = [
	Color8(0xe4, 0x60, 0x4f), Color8(0xf2, 0xec, 0xe0), Color8(0xe8, 0xb9, 0x31),
	Color8(0x6f, 0x77, 0x80), Color8(0xe4, 0x60, 0x4f), Color8(0x55, 0xb8, 0xaa)]


func _ready() -> void:
	z_index = 20
	_x.resize(CAP)
	_y.resize(CAP)
	_v.resize(CAP)
	_t0.resize(CAP)
	_last.resize(CAP)
	_pop0.resize(CAP)
	_w.resize(CAP)
	_map.resize(EnemyManager.CAPACITY)
	_map.fill(-1)
	_map_key.resize(EnemyManager.CAPACITY)
	_map_key.fill(-1)
	_map_ser.resize(EnemyManager.CAPACITY)
	_ser.resize(CAP)
	_key.resize(CAP)
	_k.resize(CAP)
	_imp.resize(CAP)
	_alive.resize(CAP)
	_strs.resize(CAP)
	_lx.resize(LCAP)
	_ly.resize(LCAP)
	_lt0.resize(LCAP)
	_lk.resize(LCAP)
	_lalive.resize(LCAP)
	_lstr.resize(LCAP)
	_lw.resize(LCAP)
	_font = ThemeDB.fallback_font
	var th: Theme = load("res://ui/theme/main_theme.tres") as Theme
	if th != null and th.default_font != null:
		_font = th.default_font
		if th.default_font_size > 0:
			_font_size = th.default_font_size
	_rise_px = int(Data.num("combat_core", "feel.dmg_num.rise_px", 8))
	_life_ticks = int(Data.num("combat_core", "feel.dmg_num.life_ticks", 36))
	_merge_ticks = int(roundf(Data.num("combat_core", "feel.dmg_num.merge_s", 0.15) * K.TICK_HZ))
	_max_visible = int(Data.num("combat_core", "feel.dmg_num.max_visible", 48))
	_cluster_ticks = int(roundf(Data.num("combat_core", "feel.dmg_num.cluster_s", 0.25) * K.TICK_HZ))
	_cluster_px = Data.num("combat_core", "feel.dmg_num.cluster_px", 24.0)
	_cluster_py = Data.num("combat_core", "feel.dmg_num.cluster_py", 24.0)
	_local_px = Data.num("combat_core", "feel.dmg_num.local_px", 40.0)
	_local_py = Data.num("combat_core", "feel.dmg_num.local_py", 32.0)
	_local_cap = int(Data.num("combat_core", "feel.dmg_num.local_cap", 3))
	_near_px = Data.num("combat_core", "feel.dmg_num.near_px", 56.0)
	_near_cap = int(Data.num("combat_core", "feel.dmg_num.near_cap", 5))
	if DebugTools.arg("crowd-fx-off") != "":          # 디버그 A/B 캡처 전용: 군집 합산·밀도 상한 끔
		_cluster_ticks = 0
		_near_cap = 0
		_local_cap = 0
	Juice.damage_numbers = self
	Events.run_started.connect(_on_run_started)


func _on_run_started(_c: StringName) -> void:
	stat_spawned = 0
	stat_merged_key = 0
	stat_merged_cluster = 0
	stat_evicted = 0
	stat_alive_max = 0
	stat_crit = 0
	stat_small_cut = 0
	stat_off_cut = 0
	stat_moved = 0
	_rmax = 0.0
	_rmax_t = -100000


## 살아 있는 숫자 수(군중 모드 판정 — hit_feedback).
func alive_count() -> int:
	return _alive_n


## 화면(월드 좌표) 사각형 — 틱마다 한 번.
func _view_rect(now: int) -> Rect2:
	if now != _view_tick:
		_view_tick = now
		var inv: Transform2D = get_canvas_transform().affine_inverse()
		var sz: Vector2 = get_viewport_rect().size
		_view = Rect2(inv * Vector2.ZERO, inv.basis_xform(sz)).abs()
	return _view


func _exit_tree() -> void:
	if Juice.damage_numbers == self:
		Juice.damage_numbers = null


func _now() -> int:
	return Game.game_tick


func spawn(pos: Vector2, amount: float, kind: StringName = &"red", key: int = -1) -> void:
	var now: int = _now()
	var kid: int = int(KINDS.get(kind, 0))
	if kid == 2:
		stat_crit += 1
	var normal: bool = kid == 0 or kid == 1 or kid == 3
	if normal:
		if amount >= _rmax or now - _rmax_t >= SMALL_WIN_TICKS:
			_rmax = amount
			_rmax_t = now
	var ms: int = -1
	if key >= 0:
		ms = key & EnemyManager.SLOT_MASK
		if ms < _map.size():
			var j: int = _map[ms]
			if j >= 0 and _alive[j] == 1 and _map_key[ms] == key and _map_ser[ms] == _ser[j] and _k[j] == kid 					and now - _last[j] < _merge_ticks and now - _t0[j] < _life_ticks - 8:
				_merge(j, amount, now)
				stat_merged_key += 1
				return
		else:
			ms = -1
	var px: float = K.rnd(pos.x)
	var py: float = K.rnd(pos.y)
	# 무당 몸 상자 안에 생기면 상자 위로(플레이어·회복 숫자 제외) — 숫자가 무당을 덮지 않게
	var pl: Node2D = Game.player
	if kid != 4 and kid != 5 and pl != null:
		var foot: Vector2 = (pl as Player).render_pos if pl is Player else pl.global_position
		if absf(px - foot.x) <= BODY_HX and py - foot.y >= BODY_TOP and py - foot.y <= BODY_BOT:
			py = foot.y + BODY_TOP - 2.0
			stat_moved += 1
	# 군집 합산: 근처(같은 색)의 막 갱신된 숫자에 더한다. 플레이어·회복 숫자는 묶지 않는다.
	if kid != 4 and kid != 5 and _alive_n > 0:
		var best: int = -1
		var best_d: float = 1e9
		for j in CAP:
			if _alive[j] == 0 or _k[j] != kid:
				continue
			if now - _last[j] >= _cluster_ticks or now - _t0[j] >= _life_ticks - 8:
				continue
			var ddx: float = absf(_x[j] - px)
			var ddy: float = absf(_y[j] - py)
			if ddx > _cluster_px or ddy > _cluster_py:
				continue
			var d: float = ddx + ddy
			if d < best_d:
				best_d = d
				best = j
		if best >= 0:
			_merge(best, amount, now)
			stat_merged_cluster += 1
			if ms >= 0:
				_bind(ms, key, best)
			return
	# 치명(결단타) 구역 하나: 금 큰 숫자가 쌓이면 무당 금 테와 섞인다(리뷰 review_main 18:00 '68' ×5) —
	# near_px 상자 안에 살아 있는 치명 숫자가 있으면 시간 창과 상관없이 거기에 더한다(다시 튀어 오른다).
	if kid == 2:
		for j in CAP:
			if _alive[j] == 1 and _k[j] == 2 and now - _t0[j] < _life_ticks - 8 					and absf(_x[j] - px) <= _near_px and absf(_y[j] - py) <= _near_px:
				_merge(j, amount, now)
				stat_merged_cluster += 1
				return
	# 새 칸을 만들기 전 거르기(합산은 위에서 이미 했다). 정예 이상 적의 숫자는 거르지 않는다.
	var imp: bool = false
	if key >= 0:
		var em: EnemyManager = Game.enemies as EnemyManager
		var sl: int = key & EnemyManager.SLOT_MASK
		imp = em != null and sl < em.flags.size() and (em.flags[sl] & EnemyManager.F_ELITE_PLUS) != 0
	if normal and not imp:
		if _rmax >= SMALL_MIN and amount < _rmax * SMALL_FRAC:
			stat_small_cut += 1
			return
		if not _view_rect(now).grow(OFF_MARGIN).has_point(Vector2(px, py)):
			stat_off_cut += 1
			return
	var cap: int = mini(_max_visible, Juice.crowd_max_visible) if Juice.number_crowd else _max_visible
	var i: int = -1
	# 구역 밀도 상한: 같은 자리 근처 일반 숫자가 local_cap 이상이면 그중 가장 오래된 칸을 쓴다(치명·플레이어는 세지 않는다)
	if kid != 2 and kid != 4 and kid != 5 and _local_cap > 0 and _alive_n >= _local_cap:
		var ln: int = 0
		var lo_j: int = -1
		var lo_t: int = 0x7fffffff
		for j in CAP:
			if _alive[j] == 0 or _k[j] == 2 or _k[j] == 4 or _k[j] == 5:
				continue
			if absf(_x[j] - px) <= _local_px and absf(_y[j] - py) <= _local_py:
				ln += 1
				if _t0[j] < lo_t:
					lo_t = _t0[j]
					lo_j = j
		if ln >= _local_cap and lo_j >= 0:
			i = lo_j
	# 플레이어 주변 밀도 상한: 일반 숫자가 near_cap 을 넘으면 그 안의 가장 오래된 일반 숫자 칸을 쓴다
	if i < 0 and kid < 2 and pl != null and _near_cap > 0:
		var c: Vector2 = pl.global_position + Vector2(0, -16)
		if absf(px - c.x) <= _near_px and absf(py - c.y) <= _near_px:
			var near_n: int = 0
			var old_j: int = -1
			var old_t: int = 0x7fffffff
			for j in CAP:
				if _alive[j] == 0 or _k[j] >= 2:
					continue
				if absf(_x[j] - c.x) <= _near_px and absf(_y[j] - c.y) <= _near_px:
					near_n += 1
					if _t0[j] < old_t:
						old_t = _t0[j]
						old_j = j
			if near_n >= _near_cap and old_j >= 0:
				i = old_j
	if i < 0 and _alive_n >= cap:
		i = _oldest(true)
		if i < 0:
			i = _oldest(false)
	if i >= 0:
		stat_evicted += 1
	else:
		for n in CAP:
			var j3: int = (_head + n) % CAP
			if _alive[j3] == 0:
				i = j3
				break
		if i < 0:
			i = _head
	_head = (i + 1) % CAP
	if _alive[i] == 0:
		_alive_n += 1
	_alive[i] = 1
	# x 흔들기 ±4: 일련번호 해시(연출 전용 — 게임 난수 스트림을 소모하지 않는다)
	_x[i] = px + float(((_ser_next * 1103515245 + 12345) >> 9) % 9 - 4)
	_y[i] = py
	_v[i] = amount
	_t0[i] = now
	_last[i] = now
	_pop0[i] = now
	_key[i] = key
	_k[i] = kid
	_imp[i] = 1 if imp else 0
	_ser[i] = _ser_next
	_ser_next += 1
	_strs[i] = str(int(roundf(amount)))
	_w[i] = _font.get_string_size(_strs[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
	if ms >= 0:
		_bind(ms, key, i)
	stat_spawned += 1
	stat_alive_max = maxi(stat_alive_max, _alive_n)


func _merge(j: int, amount: float, now: int) -> void:
	_v[j] += amount
	_strs[j] = str(int(roundf(_v[j])))
	_w[j] = _font.get_string_size(_strs[j], HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
	_last[j] = now
	_pop0[j] = now


func _bind(ms: int, key: int, j: int) -> void:
	_map[ms] = j
	_map_key[ms] = key
	_map_ser[ms] = _ser[j]


## 가장 오래 산(시작 틱이 가장 이른) 숫자 칸. normal_only 면 일반(적·백·잠김) 숫자만 — 치명·플레이어·회복은 뒤로 미룬다.
func _oldest(normal_only: bool) -> int:
	var best: int = -1
	var bt: int = 0x7fffffff
	for j in CAP:
		if _alive[j] == 0:
			continue
		if normal_only and (_k[j] == 2 or _k[j] == 4 or _k[j] == 5):
			continue
		if _t0[j] < bt:
			bt = _t0[j]
			best = j
	return best


## 검증 로그 한 줄([juice] 줄에 붙는다).
func stats_line() -> String:
	return "num spawned=%d merged_key=%d merged_cluster=%d evicted=%d alive_max=%d crit=%d small_cut=%d off_cut=%d moved=%d" % [
		stat_spawned, stat_merged_key, stat_merged_cluster, stat_evicted, stat_alive_max, stat_crit, stat_small_cut,
		stat_off_cut, stat_moved]


## 글자 표식. kind: &"haewon" | &"toechi" | &"ring". 풀이 차면 가장 오래된 것을 덮는다.
func spawn_label(pos: Vector2, text: String, kind: StringName = &"haewon") -> void:
	var i: int = _lhead
	_lhead = (_lhead + 1) % LCAP
	if _lalive[i] == 0:
		_lalive_n += 1
	var k: int = int(LKINDS.get(kind, 0))
	_lalive[i] = 1
	_lx[i] = K.rnd(pos.x)
	_ly[i] = K.rnd(pos.y)
	_lt0[i] = _now()
	_lk[i] = k
	_lstr[i] = text
	var lfs: int = _font_size * (2 if k == 2 else 1)
	_lw[i] = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
	# 글자 상자(기준선 위 lfs, 아래 2px)가 무당 몸 상자와 겹치면 머리 위로 올린다 — 고리 가운데 무당 위에 '해원' 큰 글자가 덮이던 것(vis after 12:01·15:00)
	var pl: Node2D = Game.player
	if pl != null:
		var foot: Vector2 = (pl as Player).render_pos if pl is Player else pl.global_position
		var hw: float = _lw[i] * 0.5
		# 비키는 거리 = 몸 상자 + 16px(무당 바로 아래 32px 안에 붙던 '해원' 큰 글자, 리뷰 after/0300)
		if absf(_lx[i] - foot.x) <= BODY_HX + hw + 16.0 and _ly[i] + 2.0 >= foot.y + BODY_TOP - 16.0 and _ly[i] - float(lfs) <= foot.y + BODY_BOT + 16.0:
			_ly[i] = K.rnd(foot.y + BODY_TOP - 4.0)
			stat_moved += 1


func _process(_delta: float) -> void:
	if _alive_n <= 0 and _lalive_n <= 0:
		return
	var now: int = Game.anim_tick_cur
	for i in CAP:
		if _alive[i] == 1 and now - _t0[i] >= _life_ticks:
			_alive[i] = 0
			_alive_n -= 1
	for i in LCAP:
		if _lalive[i] == 1 and now - _lt0[i] >= L_LIFE[_lk[i]]:
			_lalive[i] = 0
			_lalive_n -= 1
	queue_redraw()


func _draw() -> void:
	var now: int = Game.anim_tick_cur
	var rise_end: int = 14
	var hidden: bool = Juice.numbers_hidden()
	# 두 번 그린다: 먹 외곽선 전부 → 글자 전부. 외곽선 글리프는 다른 캐시 텍스처라 숫자마다 번갈아 그리면 배치가 끊긴다.
	for pass_i in 2:
		for i in CAP:
			if _alive[i] == 0:
				continue
			if hidden and _k[i] != 4:
				continue
			var t: int = maxi(0, now - _t0[i])
			if t >= _life_ticks - 4 and ((t - (_life_ticks - 4)) / 2) % 2 == 0:
				continue                                        # 마지막 4틱: 2틱 숨김 / 2틱 보임
			var k: int = _k[i]
			var fs: int = _font_size
			var w: float = _w[i]
			var osz: int = OUTLINE
			if k == 2 and now - _pop0[i] < 2:
				fs = _font_size * 2                             # 치명타 팝: 정수 2배(가운데 기준)
				w *= 2.0
				osz = OUTLINE_POP
			var rise: int = 0
			if t >= 2:
				var u: float = clampf(float(t - 2) / float(rise_end - 2), 0.0, 1.0)
				rise = int(floorf(float(_rise_px) * (1.0 - (1.0 - u) * (1.0 - u))))
			var p: Vector2 = Vector2(roundf(_x[i] - floorf(w * 0.5)), roundf(_y[i] - float(rise)))
			var col: Color = COL_TEXT[k]
			var ol: Color = COL_OUTLINE
			if crowd_soft and (k == 0 or k == 1 or k == 3) and _imp[i] == 0:
				col.a = CROWD_SOFT_A
				ol.a = CROWD_SOFT_A
			# 먹 외곽선 → 글자(그림자 (1,1) 대신): 빛기둥·흰 귀신 위에서도 숫자 모양이 남는다
			if pass_i == 0:
				draw_string_outline(_font, p, _strs[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, osz, ol)
			else:
				draw_string(_font, p, _strs[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# 글자 표식(숫자 위에 그린다)
	for i in LCAP:
		if _lalive[i] == 0:
			continue
		var lk: int = _lk[i]
		var lt: int = maxi(0, now - _lt0[i])
		var life: int = L_LIFE[lk]
		if lt >= life - 6 and ((lt - (life - 6)) / 2) % 2 == 0:
			continue                                        # 마지막 6틱 점멸
		var ox: int = 0
		var oy: int = 0
		if lk == 1:
			if lt < 6:
				ox = 1 if (lt / 2) % 2 == 0 else -1         # 퇴치: 좌우 1px 떨림 → 2px 내려앉음
			else:
				oy = 2
		else:
			var lu: float = clampf(float(lt) / float(life - 12), 0.0, 1.0)
			oy = -int(floorf(float(L_RISE[lk]) * (1.0 - (1.0 - lu) * (1.0 - lu))))
		var lfs: int = _font_size * (2 if lk == 2 else 1)
		var lp: Vector2 = Vector2(_lx[i] - floorf(_lw[i] * 0.5) + float(ox), _ly[i] + float(oy))
		draw_string(_font, lp + Vector2(1, 1), _lstr[i], HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, L_SHADOW[lk])
		draw_string(_font, lp, _lstr[i], HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, L_COL[lk])

