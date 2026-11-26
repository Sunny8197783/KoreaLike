extends Node2D
## 적 공격 예고(텔레그래프) · 장판 · 파동 · 보스 오브젝트(고 매듭·살 덩어리·대접 게이지) — 시뮬 + 그리기. 소유: enemies.
##
## 규칙(07 E5·E7, 13 2.6.3): 적 공격 표시는 청 #2a5caa / 흑 #1a1a1a 만. 백 #f2ece0 은 고 매듭(캐논)·해원 전용.
##   예고 최소 시간: 일반 0.5 / 정예 0.7 / 중간보스·보스 0.8초(호출자가 보장, add_tg 가 하한을 다시 건다).
##   반투명 없음: 선·점선·해칭(단색 픽셀)만. 좌표는 정수 픽셀(K.rnd).
## 시뮬: EnemyManager.sim_think_move 끝에서 sim_step(dt) 1회(틱 7·8). 결정론: 시뮬 난수는 Rng 스트림만.
## 예고가 끝나는 틱에 효과(act)를 실행한다: 판정(HIT) · 방사탄(BULLETS) · 장판(ZONE) · 파동(WAVE).
## 소유자가 죽거나(세대 불일치) 일반 잡귀가 풀릴 기색에 들면 cancel_owner() 로 취소(07 4.2 "텔레그래프 0.2초 페이드").
## 위험 층(design/18 §1.3): 채움·해칭은 이 노드(z −1, 바닥)에 그대로 두고, 예고 테두리(원·부채·돌진 선·표식 원)와
##   파동 고리만 자식 Edge(z8 절대, 적 몸·내 VFX·무당 테 위)에서 한 번 더 그린다. 터지기 0.3초 전부터는 2px 청 ↔ 먹 점멸.

const TG_CAP: int = 160
const Z_CAP: int = 96
const OBJ_CAP: int = 24

enum Shape { CIRCLE, CONE, LINE, RAYS, MARK, RING }
enum Act { NONE, HIT, BULLETS, ZONE, HIT_ZONE, WAVE, CALLBACK }
enum ZKind { MUL, MUL_BLACK, MUL_CLEAR, HYUNGSAL, YEOKBYEONG, PLAGUE, GAMUM, DANBI, WAVE }
enum OKind { KNOT, LUMP, GAUGE }

const C_CH: Color = Color(42.0 / 255.0, 92.0 / 255.0, 170.0 / 255.0)       # ch #2a5caa
const C_CH_DK: Color = Color(27.0 / 255.0, 58.0 / 255.0, 112.0 / 255.0)    # ch #1b3a70
const C_CH_HI: Color = Color(95.0 / 255.0, 147.0 / 255.0, 222.0 / 255.0)   # ch #5f93de
const C_HK: Color = Color(26.0 / 255.0, 26.0 / 255.0, 26.0 / 255.0)        # hk #1a1a1a
const C_MK: Color = Color(14.0 / 255.0, 11.0 / 255.0, 22.0 / 255.0)        # mk #0e0b16
const C_MK3: Color = Color(47.0 / 255.0, 40.0 / 255.0, 64.0 / 255.0)       # mk #2f2840
const C_CR: Color = Color(47.0 / 255.0, 140.0 / 255.0, 134.0 / 255.0)      # cr #2f8c86 (맑은 물: 아군)
const C_CR_HI: Color = Color(85.0 / 255.0, 184.0 / 255.0, 170.0 / 255.0)   # cr #55b8aa
const C_BAEK: Color = Color(242.0 / 255.0, 236.0 / 255.0, 224.0 / 255.0)   # bk #f2ece0 (고 매듭 전용)
const C_BAEK_DK: Color = Color(214.0 / 255.0, 207.0 / 255.0, 193.0 / 255.0) # bk #d6cfc1
const C_HJ: Color = Color(233.0 / 255.0, 220.0 / 255.0, 192.0 / 255.0)     # hj #e9dcc0
const C_HJ_DK: Color = Color(133.0 / 255.0, 113.0 / 255.0, 84.0 / 255.0)   # hj #857154
const C_JK: Color = Color(200.0 / 255.0, 50.0 / 255.0, 45.0 / 255.0)       # jk #c8322d
const C_JK_DK: Color = Color(140.0 / 255.0, 31.0 / 255.0, 34.0 / 255.0)    # jk #8c1f22
const C_HW: Color = Color(232.0 / 255.0, 185.0 / 255.0, 49.0 / 255.0)      # hw #e8b931
const C_ET: Color = Color(124.0 / 255.0, 103.0 / 255.0, 75.0 / 255.0)      # et #7c674b (가뭄 장판)
const C_HJ2: Color = Color(210.0 / 255.0, 193.0 / 255.0, 156.0 / 255.0)    # hj #d2c19c (손님 대접 게이지 바탕)
const C_HJ_HI: Color = Color(246.0 / 255.0, 238.0 / 255.0, 220.0 / 255.0)  # hj ui_only_highlight #f6eedc (말풍선)
const C_HW_DK: Color = Color(169.0 / 255.0, 124.0 / 255.0, 27.0 / 255.0)   # hw #a97c1b (놋 방울 점)
const C_HW_HI: Color = Color(245.0 / 255.0, 214.0 / 255.0, 107.0 / 255.0)  # hw #f5d66b

var em: Node = null              # EnemyManager (순환 참조를 피해 타입 미지정)

# --- 텔레그래프 SoA ---
var tg_alive: PackedByteArray = PackedByteArray()
var tg_shape: PackedByteArray = PackedByteArray()
var tg_act: PackedByteArray = PackedByteArray()
var tg_x: PackedFloat32Array = PackedFloat32Array()
var tg_y: PackedFloat32Array = PackedFloat32Array()
var tg_dx: PackedFloat32Array = PackedFloat32Array()
var tg_dy: PackedFloat32Array = PackedFloat32Array()
var tg_a: PackedFloat32Array = PackedFloat32Array()      # 반지름 / 길이
var tg_b: PackedFloat32Array = PackedFloat32Array()      # 폭 / 반각(rad)
var tg_t: PackedFloat32Array = PackedFloat32Array()
var tg_dur: PackedFloat32Array = PackedFloat32Array()
var tg_dmg: PackedFloat32Array = PackedFloat32Array()
var tg_p0: PackedFloat32Array = PackedFloat32Array()
var tg_p1: PackedFloat32Array = PackedFloat32Array()
var tg_p2: PackedFloat32Array = PackedFloat32Array()
var tg_p3: PackedFloat32Array = PackedFloat32Array()
var tg_kind: PackedInt32Array = PackedInt32Array()
var tg_owner: PackedInt32Array = PackedInt32Array()      # 소유 적 핸들(-1 없음)
var tg_follow: PackedByteArray = PackedByteArray()      # 1 = 소유자 위치를 따라감(근접 휘두르기)
var tg_cancel_t: PackedFloat32Array = PackedFloat32Array()  # >0 = 취소 페이드 중(남은 초)
var tg_cb: PackedInt32Array = PackedInt32Array()          # CALLBACK 키(EnemyBigs.on_tg)
var tg_count: int = 0
var _tg_n: int = 0               # 사용 중 상한 인덱스(+1)

# --- 장판·파동 SoA ---
var z_alive: PackedByteArray = PackedByteArray()
var z_kind: PackedByteArray = PackedByteArray()
var z_x: PackedFloat32Array = PackedFloat32Array()
var z_y: PackedFloat32Array = PackedFloat32Array()
var z_r: PackedFloat32Array = PackedFloat32Array()
var z_r1: PackedFloat32Array = PackedFloat32Array()     # 파동 목표 반지름
var z_w: PackedFloat32Array = PackedFloat32Array()      # 파동 두께
var z_t: PackedFloat32Array = PackedFloat32Array()      # 남은 초
var z_dur: PackedFloat32Array = PackedFloat32Array()
var z_dps: PackedFloat32Array = PackedFloat32Array()
var z_slow: PackedFloat32Array = PackedFloat32Array()
var z_gap: PackedFloat32Array = PackedFloat32Array()    # 파동 틈 시작 각
var z_gaps: PackedByteArray = PackedByteArray()
var z_hit: PackedByteArray = PackedByteArray()
var z_owner: PackedInt32Array = PackedInt32Array()
var z_born: PackedInt32Array = PackedInt32Array()
var z_count: int = 0
var _z_n: int = 0
var _zone_tick_acc: float = 0.0
var _slow_applied: bool = false

# --- 보스 오브젝트(고 매듭·살 덩어리·대접 게이지) ---
var o_alive: PackedByteArray = PackedByteArray()
var o_kind: PackedByteArray = PackedByteArray()
var o_x: PackedFloat32Array = PackedFloat32Array()
var o_y: PackedFloat32Array = PackedFloat32Array()
var o_r: PackedFloat32Array = PackedFloat32Array()
var o_v: PackedFloat32Array = PackedFloat32Array()      # 매듭: 0 묶임 / 1 반쯤 풀림, 덩어리: 진행 0..1, 게이지: 0..100
var o_lx: PackedFloat32Array = PackedFloat32Array()     # 연결선 끝(보스 위치)
var o_ly: PackedFloat32Array = PackedFloat32Array()
var o_born: PackedInt32Array = PackedInt32Array()
var o_label: PackedInt32Array = PackedInt32Array()      # 매듭 번호 등

var _src_ids: Array[StringName] = []                     # 피해 출처 이름(tg_kind/z 와 별개, 적 종 이름 색인)
var _player_r: float = 9.6
var _caps: Dictionary = {}
var _zone_cap_total: int = 90
var _t_now: float = 0.0
var _pend_bul: PackedFloat32Array = PackedFloat32Array()
# 한형 고풀이 표지(EnemyBigs 가 매 틱 채움): 보스 발 위치, 열림 창 남은 비율(−1 = 묶임/없음)
var gop_x: float = 0.0
var gop_y: float = 0.0
var gop_f: float = -1.0
var _font: Font = null
var _knot_label_k: int = -1        # 이 번호 이하 매듭은 처음 6초 '매듭' 이름표(첫 2개)
var _bubble_t0: int = -1           # 손님 '공물을 바쳐 대접' 말풍선 시작(연출 틱), 런당 1회
var _bubble_done: bool = false
var _edge: Node2D = null           # 예고 테두리 위험 층(z8)
const EDGE_Z: int = 8
const EDGE_LATE_S: float = 0.3     # 터지기 직전 강조 구간(초)


func _ready() -> void:
	z_index = -1
	for a: String in ["tg_x", "tg_y", "tg_dx", "tg_dy", "tg_a", "tg_b", "tg_t", "tg_dur", "tg_dmg", "tg_p0", "tg_p1", "tg_p2", "tg_p3", "tg_cancel_t"]:
		var f: PackedFloat32Array = PackedFloat32Array()
		f.resize(TG_CAP)
		set(a, f)
	for a2: String in ["tg_kind", "tg_owner", "tg_cb"]:
		var n: PackedInt32Array = PackedInt32Array()
		n.resize(TG_CAP)
		set(a2, n)
	tg_alive.resize(TG_CAP)
	tg_shape.resize(TG_CAP)
	tg_act.resize(TG_CAP)
	tg_follow.resize(TG_CAP)
	for a3: String in ["z_x", "z_y", "z_r", "z_r1", "z_w", "z_t", "z_dur", "z_dps", "z_slow", "z_gap"]:
		var g: PackedFloat32Array = PackedFloat32Array()
		g.resize(Z_CAP)
		set(a3, g)
	z_alive.resize(Z_CAP)
	z_kind.resize(Z_CAP)
	z_gaps.resize(Z_CAP)
	z_hit.resize(Z_CAP)
	z_owner.resize(Z_CAP)
	z_born.resize(Z_CAP)
	for a4: String in ["o_x", "o_y", "o_r", "o_v", "o_lx", "o_ly"]:
		var h: PackedFloat32Array = PackedFloat32Array()
		h.resize(OBJ_CAP)
		set(a4, h)
	o_alive.resize(OBJ_CAP)
	o_kind.resize(OBJ_CAP)
	o_born.resize(OBJ_CAP)
	o_label.resize(OBJ_CAP)
	_player_r = Data.num("enemies", "global_rules.player_hitbox_u", 0.3) * K.UNIT_PX
	_zone_cap_total = int(Data.num("enemies", "zones.total_enemy_zone_cap", 90))
	_edge = Node2D.new()
	_edge.name = "Edge"
	_edge.z_as_relative = false
	_edge.z_index = EDGE_Z
	add_child(_edge)
	_edge.draw.connect(_draw_edges)


func clear_all() -> void:
	gop_f = -1.0
	tg_alive.fill(0)
	z_alive.fill(0)
	o_alive.fill(0)
	tg_count = 0
	z_count = 0
	_tg_n = 0
	_z_n = 0
	_restore_slow()


# ─── 텔레그래프 ─────────────────────────────────────────────────────────

## 예고 추가. 반환: 슬롯(-1 = 가득). owner = 적 핸들(-1 없음). 효과 매개변수는 set_act_* 로 이어서 지정.
func add_tg(shape: int, pos: Vector2, dir: Vector2, a: float, b: float, dur: float, dmg: float, owner: int, act: int = Act.HIT, follow: bool = false) -> int:
	var i: int = -1
	for k in TG_CAP:
		if tg_alive[k] == 0:
			i = k
			break
	if i < 0:
		return -1
	tg_alive[i] = 1
	tg_shape[i] = shape
	tg_act[i] = act
	tg_x[i] = pos.x
	tg_y[i] = pos.y
	var dl: float = dir.length()
	tg_dx[i] = dir.x / dl if dl > 0.0001 else 1.0
	tg_dy[i] = dir.y / dl if dl > 0.0001 else 0.0
	tg_a[i] = a
	tg_b[i] = b
	tg_t[i] = 0.0
	tg_dur[i] = maxf(dur, 0.05)
	tg_dmg[i] = dmg
	tg_p0[i] = 0.0
	tg_p1[i] = 0.0
	tg_p2[i] = 0.0
	tg_p3[i] = 0.0
	tg_kind[i] = 0
	tg_owner[i] = owner
	tg_follow[i] = 1 if follow else 0
	tg_cancel_t[i] = 0.0
	tg_cb[i] = -1
	tg_count += 1
	_tg_n = maxi(_tg_n, i + 1)
	return i


## 방사탄: n 발, 속도 px/s, 시작 각(rad), 수명 s. 탄 피해 = add_tg 의 dmg.
func set_act_bullets(i: int, n: int, speed_px: float, ang0: float, life_s: float) -> void:
	if i < 0:
		return
	tg_p0[i] = float(n)
	tg_p1[i] = speed_px
	tg_p2[i] = ang0
	tg_p3[i] = life_s


## 장판: kind(ZKind), 반지름 px, 지속 s, 초당 피해. HIT_ZONE 이면 판정 뒤 장판.
func set_act_zone(i: int, zkind: int, r_px: float, dur_s: float, dps: float) -> void:
	if i < 0:
		return
	tg_kind[i] = zkind
	tg_p0[i] = r_px
	tg_p1[i] = dur_s
	tg_p2[i] = dps


## 파동(고리형 확산): 목표 반지름 px, 걸리는 초, 두께 px, 틈 수(30° 틈). 피해 = add_tg 의 dmg.
func set_act_wave(i: int, r1_px: float, time_s: float, thick_px: float, gaps: int) -> void:
	if i < 0:
		return
	tg_p0[i] = r1_px
	tg_p1[i] = time_s
	tg_p2[i] = thick_px
	tg_p3[i] = float(gaps)


func set_callback(i: int, key: int) -> void:
	if i >= 0:
		tg_cb[i] = key


func tg_progress(i: int) -> float:
	if i < 0 or i >= TG_CAP or tg_alive[i] == 0:
		return 1.0
	return clampf(tg_t[i] / tg_dur[i], 0.0, 1.0)


func tg_active(i: int) -> bool:
	return i >= 0 and i < TG_CAP and tg_alive[i] == 1 and tg_cancel_t[i] <= 0.0


## 소유 적의 예고를 모두 취소(0.2초 페이드, 효과 없음).
func cancel_owner(handle: int) -> void:
	if handle < 0:
		return
	for k in _tg_n:
		if tg_alive[k] == 1 and tg_owner[k] == handle and tg_cancel_t[k] <= 0.0:
			tg_cancel_t[k] = 0.2


func cancel(i: int) -> void:
	if i >= 0 and i < TG_CAP and tg_alive[i] == 1:
		tg_cancel_t[i] = 0.2


## 같은 슬롯을 다시 겨냥(도깨비 뚝딱 3연타).
func move_tg(i: int, pos: Vector2, dir: Vector2 = Vector2.ZERO) -> void:
	if i < 0 or i >= TG_CAP or tg_alive[i] == 0:
		return
	tg_x[i] = pos.x
	tg_y[i] = pos.y
	if dir.length_squared() > 0.0001:
		var d: Vector2 = dir.normalized()
		tg_dx[i] = d.x
		tg_dy[i] = d.y


# ─── 장판 ──────────────────────────────────────────────────────────────

func add_zone(zkind: int, pos: Vector2, r_px: float, dur_s: float, dps: float, owner: int = -1, slow: float = 0.0) -> int:
	if z_count >= _zone_cap_total:
		_evict_oldest_zone()
	var i: int = -1
	for k in Z_CAP:
		if z_alive[k] == 0:
			i = k
			break
	if i < 0:
		return -1
	z_alive[i] = 1
	z_kind[i] = zkind
	z_x[i] = pos.x
	z_y[i] = pos.y
	z_r[i] = r_px
	z_r1[i] = r_px
	z_w[i] = 0.0
	z_t[i] = dur_s
	z_dur[i] = dur_s
	z_dps[i] = dps
	z_slow[i] = slow
	z_gap[i] = 0.0
	z_gaps[i] = 0
	z_hit[i] = 0
	z_owner[i] = owner
	z_born[i] = Game.game_tick
	z_count += 1
	_z_n = maxi(_z_n, i + 1)
	return i


func zones_of(owner: int, zkind: int = -1) -> int:
	var n: int = 0
	for k in _z_n:
		if z_alive[k] == 1 and z_owner[k] == owner and (zkind < 0 or z_kind[k] == zkind):
			n += 1
	return n


func zone_count_kind(zkind: int) -> int:
	var n: int = 0
	for k in _z_n:
		if z_alive[k] == 1 and z_kind[k] == zkind:
			n += 1
	return n


## 소유자 장판을 다른 종류로(물귀신 퇴치 → 검은 물, 해원 → 맑은 물) 또는 제거(to_kind < 0).
func convert_owner_zones(owner: int, to_kind: int, r_px: float = -1.0, add_s: float = 0.0, slow: float = 0.0, dps: float = 0.0) -> void:
	for k in _z_n:
		if z_alive[k] == 1 and z_owner[k] == owner:
			if to_kind < 0:
				_free_zone(k)
				continue
			z_kind[k] = to_kind
			if r_px > 0.0:
				z_r[k] = r_px
				z_r1[k] = r_px
			z_t[k] += add_s
			z_dur[k] = maxf(z_dur[k], z_t[k])
			z_slow[k] = slow
			z_dps[k] = dps
			z_owner[k] = -1


func _free_zone(k: int) -> void:
	if z_alive[k] == 1:
		z_alive[k] = 0
		z_count -= 1


func _evict_oldest_zone() -> void:
	var best: int = -1
	var bt: int = 1 << 30
	for k in _z_n:
		if z_alive[k] == 1 and z_kind[k] != ZKind.WAVE and z_born[k] < bt:
			bt = z_born[k]
			best = k
	if best >= 0:
		_free_zone(best)


# ─── 보스 오브젝트 ─────────────────────────────────────────────────────

func add_obj(okind: int, pos: Vector2, r_px: float, label: int = 0) -> int:
	for k in OBJ_CAP:
		if o_alive[k] == 0:
			o_alive[k] = 1
			o_kind[k] = okind
			o_x[k] = pos.x
			o_y[k] = pos.y
			o_r[k] = r_px
			o_v[k] = 0.0
			o_lx[k] = pos.x
			o_ly[k] = pos.y
			o_born[k] = Game.game_tick
			o_label[k] = label
			return k
	return -1


func free_obj(k: int) -> void:
	if k >= 0 and k < OBJ_CAP:
		o_alive[k] = 0


# ─── 틱(시뮬) ──────────────────────────────────────────────────────────

func sim_step(dt: float) -> void:
	_t_now = Game.time_sec()
	var pl: Node2D = Game.player
	var pp: Vector2 = pl.global_position if pl != null else Vector2(1.0e9, 1.0e9)
	# 텔레그래프
	var hi: int = 0
	for i in _tg_n:
		if tg_alive[i] == 0:
			continue
		hi = i + 1
		if tg_cancel_t[i] > 0.0:
			tg_cancel_t[i] -= dt
			if tg_cancel_t[i] <= 0.0:
				_free_tg(i)
			continue
		var ow: int = tg_owner[i]
		if ow >= 0 and em != null:
			var s: int = em.slot_of(ow)
			if s < 0 or not em.is_alive(s):
				tg_cancel_t[i] = 0.2
				continue
			if tg_follow[i] == 1:
				tg_x[i] = em.px[s]
				tg_y[i] = em.py[s]
		tg_t[i] += dt
		if tg_t[i] >= tg_dur[i]:
			_fire(i, pp)
			_free_tg(i)
	_tg_n = hi
	# 장판·파동
	_zone_tick_acc += dt
	var dmg_tick: bool = false
	if _zone_tick_acc >= 0.5:
		_zone_tick_acc -= 0.5
		dmg_tick = true
	var slow: float = 0.0
	var regen: float = 0.0
	var hit_dmg: float = 0.0
	var hit_src: StringName = &""
	var zhi: int = 0
	for k in _z_n:
		if z_alive[k] == 0:
			continue
		zhi = k + 1
		z_t[k] -= dt
		if z_t[k] <= 0.0:
			_free_zone(k)
			continue
		var dx: float = pp.x - z_x[k]
		var dy: float = pp.y - z_y[k]
		var d2: float = dx * dx + dy * dy
		if z_kind[k] == ZKind.WAVE:
			var prog: float = 1.0 - z_t[k] / maxf(z_dur[k], 0.01)
			z_r[k] = lerpf(z_w[k], z_r1[k], prog)
			if z_hit[k] == 0:
				var d: float = sqrt(d2)
				var half: float = 6.0
				if absf(d - z_r[k]) <= half + _player_r * 0.5 and not _in_gap(k, atan2(dy, dx)):
					z_hit[k] = 1
					hit_dmg = maxf(hit_dmg, z_dps[k])
					hit_src = &"enemy_wave"
			continue
		var rr: float = z_r[k] + _player_r * 0.5
		if d2 > rr * rr:
			continue
		match z_kind[k]:
			ZKind.MUL_CLEAR, ZKind.DANBI:
				regen = maxf(regen, z_dps[k])
			_:
				slow = maxf(slow, z_slow[k])
				if dmg_tick and z_dps[k] > 0.0:
					hit_dmg = maxf(hit_dmg, z_dps[k] * 0.5)
					hit_src = &"enemy_zone"
	_z_n = zhi
	if pl != null:
		if hit_dmg > 0.0 and pl.has_method("take_hit"):
			pl.call("take_hit", hit_dmg, hit_src)
		if regen > 0.0 and dmg_tick:
			var ph: Variant = pl.get("hit")
			if ph is Object and (ph as Object).has_method("heal") and Game.hp < Game.hp_max:
				(ph as Object).call("heal", regen * 0.5)
		_apply_slow(pl, slow)


func _in_gap(k: int, ang: float) -> bool:
	var n: int = z_gaps[k]
	if n <= 0:
		return false
	var step: float = TAU / float(n)
	var half_gap: float = deg_to_rad(15.0)
	var rel: float = fposmod(ang - z_gap[k], step)
	return rel < half_gap or rel > step - half_gap


func _apply_slow(pl: Node2D, slow: float) -> void:
	if slow > 0.0:
		pl.set("speed_mult_ext", clampf(1.0 - slow, 0.4, 1.0))   # E4: 감속 상한 −60%
		_slow_applied = true
	elif _slow_applied:
		_restore_slow()


func _restore_slow() -> void:
	if _slow_applied and Game.player != null:
		Game.player.set("speed_mult_ext", 1.0)
	_slow_applied = false


func _free_tg(i: int) -> void:
	if tg_alive[i] == 1:
		tg_alive[i] = 0
		tg_count -= 1


## 예고 끝: 효과 실행.
func _fire(i: int, pp: Vector2) -> void:
	var act: int = tg_act[i]
	var c: Vector2 = Vector2(tg_x[i], tg_y[i])
	if act == Act.HIT or act == Act.HIT_ZONE:
		if tg_dmg[i] > 0.0 and _player_inside(i, pp) and Game.player != null:
			Game.player.call("take_hit", tg_dmg[i], &"enemy_attack")
	if act == Act.BULLETS:
		_spawn_bullets(c, int(tg_p0[i]), tg_p1[i], tg_p2[i], tg_p3[i], tg_dmg[i])
	if act == Act.ZONE or act == Act.HIT_ZONE:
		var zk: int = tg_kind[i]
		var slow: float = 0.0
		if zk == ZKind.MUL:
			slow = Data.num("enemies", "zones.obj_mul_ungdeongi.player_slow_pct", 25.0) / 100.0
		add_zone(zk, c, tg_p0[i], tg_p1[i], tg_p2[i], tg_owner[i], slow)
	if act == Act.WAVE:
		var z: int = add_zone(ZKind.WAVE, c, tg_a[i], tg_p1[i], tg_dmg[i], tg_owner[i])
		if z >= 0:
			z_w[z] = tg_a[i]
			z_r1[z] = tg_p0[i]
			z_gaps[z] = int(tg_p3[i])
			z_gap[z] = Rng.range_s(&"ai", 0.0, TAU)
	if tg_cb[i] >= 0 and em != null:
		var bigs: Variant = em.get("bigs")
		if bigs is Object:
			(bigs as Object).call("on_tg", tg_cb[i], i, c)
	if em != null:
		em.call("on_telegraph_fired", tg_owner[i], tg_shape[i], c)


func _spawn_bullets(c: Vector2, n: int, spd: float, ang0: float, life: float, dmg: float) -> void:
	var pool: Variant = Game.projectiles
	if not (pool is Object) or n <= 0:
		return
	var po: Object = pool as Object
	var r: float = Data.num("enemies", "projectiles.prj_wonhon_tan.radius_u", 0.18) * K.UNIT_PX
	for k in n:
		var a: float = ang0 + TAU * float(k) / float(n)
		var v: Vector2 = Vector2(cos(a), sin(a)) * spd
		po.call("spawn_enemy", c + v.normalized() * 6.0, v, life, r, dmg, &"prj_pox")


## 판정: 플레이어 원(히트박스)과 도형.
func _player_inside(i: int, pp: Vector2) -> bool:
	var cx: float = tg_x[i]
	var cy: float = tg_y[i]
	var dx: float = pp.x - cx
	var dy: float = pp.y - cy
	match tg_shape[i]:
		Shape.CIRCLE, Shape.RING:
			var rr: float = tg_a[i] + _player_r
			return dx * dx + dy * dy <= rr * rr
		Shape.CONE:
			var d: float = sqrt(dx * dx + dy * dy)
			if d > tg_a[i] + _player_r:
				return false
			if d < _player_r * 2.0:
				return true
			var cosv: float = (dx * tg_dx[i] + dy * tg_dy[i]) / d
			return cosv >= cos(tg_b[i])
		Shape.LINE:
			var along: float = dx * tg_dx[i] + dy * tg_dy[i]
			var side: float = absf(-dx * tg_dy[i] + dy * tg_dx[i])
			return along >= -_player_r and along <= tg_a[i] + _player_r and side <= tg_b[i] * 0.5 + _player_r
	return false


## 근접 판정을 다른 지점(돌진 끝 등)에서 즉시: 원.
func hit_circle_now(c: Vector2, r: float, dmg: float, src: StringName = &"enemy_attack") -> bool:
	var pl: Node2D = Game.player
	if pl == null:
		return false
	var d: Vector2 = pl.global_position - c
	var rr: float = r + _player_r
	if d.length_squared() <= rr * rr:
		pl.call("take_hit", dmg, src)
		return true
	return false


# ─── 그리기 ────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	queue_redraw()
	if _edge != null:
		_edge.queue_redraw()


func _draw() -> void:
	var tick: int = Game.anim_tick_cur
	# 장판(바닥) 먼저
	for k in _z_n:
		if z_alive[k] == 0:
			continue
		_draw_zone(k, tick)
	for k2 in OBJ_CAP:
		if o_alive[k2] == 1 and o_kind[k2] == OKind.LUMP:
			_draw_lump(k2, tick)
	for i in _tg_n:
		if tg_alive[i] == 0:
			continue
		_draw_tg(i, tick)
	for k3 in OBJ_CAP:
		if o_alive[k3] == 1 and o_kind[k3] != OKind.LUMP:
			if o_kind[k3] == OKind.KNOT:
				_draw_knot(k3, tick)
			# 대접 게이지(GAUGE)는 오버레이(적 위, z 4)에서 그린다 — draw_overlay


func _p(v: Vector2) -> Vector2:
	return Vector2(floorf(v.x + 0.5) + 0.5, floorf(v.y + 0.5) + 0.5)


## 점선 원(정수 픽셀 근사): dash/gap px.
func _dash_circle(c: Vector2, r: float, col: Color, dash: float = 4.0, gap: float = 3.0, phase: float = 0.0) -> void:
	if r < 2.0:
		return
	var circ: float = TAU * r
	var n: int = maxi(6, int(circ / (dash + gap)))
	var step: float = TAU / float(n)
	var da: float = step * dash / (dash + gap)
	for k in n:
		var a0: float = phase + step * float(k)
		draw_line(_p(c + Vector2(cos(a0), sin(a0)) * r), _p(c + Vector2(cos(a0 + da), sin(a0 + da)) * r), col, -1.0)


func _circle(c: Vector2, r: float, col: Color) -> void:
	if r < 1.0:
		return
	draw_arc(_p(c), r, 0.0, TAU, maxi(12, int(r * 0.8)), col, -1.0, false)


## 해칭(대각선, 단색): 원 안 현(chord). spacing px.
func _hatch_circle(c: Vector2, r: float, col: Color, spacing: float, phase: float = 0.0) -> void:
	var s: float = -r * 1.42 + fposmod(phase, spacing)
	while s < r * 1.42:
		# 직선 x + y = s 와 원 교점(중심 기준): t = s/√2 기준 반 현 길이
		var dd: float = s / 1.41421
		if absf(dd) < r:
			var h: float = sqrt(r * r - dd * dd)
			var base: Vector2 = c + Vector2(s * 0.5, s * 0.5)
			var dir: Vector2 = Vector2(0.70711, -0.70711) * h
			draw_line(_p(base - dir), _p(base + dir), col, -1.0)
		s += spacing


func _draw_tg(i: int, tick: int) -> void:
	var c: Vector2 = Vector2(tg_x[i], tg_y[i])
	var p: float = clampf(tg_t[i] / tg_dur[i], 0.0, 1.0)
	var cancel: bool = tg_cancel_t[i] > 0.0
	if cancel and (tick & 2) == 0:
		return                                  # 취소 페이드 = 2틱 간격 점멸(반투명 없음)
	var col: Color = C_CH_DK if cancel else C_CH
	var hot: bool = p > 0.72 and not cancel
	var blink: bool = hot and ((tick / 3) & 1) == 0
	var d: Vector2 = Vector2(tg_dx[i], tg_dy[i])
	match tg_shape[i]:
		Shape.CIRCLE, Shape.RING:
			var r: float = tg_a[i]
			_circle(c, r + 1.0, C_HK)
			_dash_circle(c, r, col, 4.0, 3.0, float(tick) * 0.01)
			# 수축 고리: r+14 → r (4단계 정수 단계로 끊는다 — 13 "4프레임 수축")
			var stage: float = floorf(p * 4.0) / 4.0
			var rr: float = r + 14.0 * (1.0 - stage)
			if not cancel:
				_circle(c, rr, C_CH_HI if hot else C_CH)
			if blink:
				_hatch_circle(c, r - 2.0, C_CH_DK, 5.0, float(tick))
		Shape.CONE:
			var half: float = tg_b[i]
			var ra: float = tg_a[i]
			var a0: float = atan2(d.y, d.x)
			var e1: Vector2 = c + Vector2(cos(a0 - half), sin(a0 - half)) * ra
			var e2: Vector2 = c + Vector2(cos(a0 + half), sin(a0 + half)) * ra
			draw_line(_p(c), _p(e1), C_HK, -1.0)
			draw_line(_p(c), _p(e2), C_HK, -1.0)
			draw_line(_p(c + Vector2(0, -1)), _p(e1 + Vector2(0, -1)), col, -1.0)
			draw_line(_p(c + Vector2(0, -1)), _p(e2 + Vector2(0, -1)), col, -1.0)
			draw_arc(_p(c), ra, a0 - half, a0 + half, maxi(8, int(ra * half * 0.5)), col, -1.0, false)
			var stage2: float = floorf(p * 4.0) / 4.0
			draw_arc(_p(c), maxf(4.0, ra * stage2), a0 - half, a0 + half, maxi(6, int(ra * half * 0.4)), C_CH_HI if hot else C_CH_DK, -1.0, false)
			if blink:
				var rr2: float = ra * 0.5
				draw_arc(_p(c), rr2, a0 - half, a0 + half, 8, C_CH_DK, -1.0, false)
		Shape.LINE:
			var ln: float = tg_a[i]
			var w: float = tg_b[i] * 0.5
			var side: Vector2 = Vector2(-d.y, d.x) * w
			var p0: Vector2 = c + side
			var p1: Vector2 = c + side + d * ln
			var p2: Vector2 = c - side + d * ln
			var p3: Vector2 = c - side
			draw_dashed_line(_p(p0), _p(p1), col, -1.0, 4.0, false)
			draw_dashed_line(_p(p3), _p(p2), col, -1.0, 4.0, false)
			draw_line(_p(p1), _p(p2), col, -1.0)
			var stage3: float = floorf(p * 4.0) / 4.0
			draw_line(_p(c), _p(c + d * ln * stage3), C_CH_HI if hot else C_CH, -1.0)
			draw_line(_p(c + Vector2(0, 1)), _p(c + d * ln * stage3 + Vector2(0, 1)), C_HK, -1.0)
			if blink:
				draw_line(_p(p0 + d * 2.0), _p(p3 + d * 2.0), C_CH_DK, -1.0)
		Shape.RAYS:
			# 탄 예고: 발사 방향마다 짧은 점선(길이 p 비례) + 끝 점(흑 코어 · 청 림)
			var n: int = int(tg_p0[i])
			var a00: float = tg_p2[i]
			var len0: float = 10.0 + 22.0 * (floorf(p * 4.0) / 4.0)
			for k in n:
				var aa: float = a00 + TAU * float(k) / float(maxi(n, 1))
				var u: Vector2 = Vector2(cos(aa), sin(aa))
				var s0: Vector2 = c + u * 8.0
				draw_dashed_line(_p(s0), _p(s0 + u * len0), col, -1.0, 2.0, false)
				var tip: Vector2 = _p(s0 + u * len0)
				draw_rect(Rect2(tip - Vector2(1.5, 1.5), Vector2(3, 3)), C_CH if not blink else C_CH_HI)
				draw_rect(Rect2(tip - Vector2(0.5, 0.5), Vector2(1, 1)), C_HK)
		Shape.MARK:
			var r2: float = tg_a[i]
			var stage4: float = floorf(p * 4.0) / 4.0
			_dash_circle(c, r2, col, 2.0, 2.0)
			draw_line(_p(c + Vector2(-3, -3)), _p(c + Vector2(3, 3)), C_HK, -1.0)
			draw_line(_p(c + Vector2(-3, 3)), _p(c + Vector2(3, -3)), C_HK, -1.0)
			_circle(c, r2 * (1.0 - stage4) + 2.0, C_CH_DK)


## 위험 층(Edge z8) draw 신호: 예고 테두리 + 파동 고리. 채움은 그리지 않는다(바닥 z −1 에 이미 있음).
## 선분을 색별로 모아 색마다 draw_multiline 한 번 → 예고가 많아도 묶음(draw call)이 색 수(≤4)만큼만 는다.
var _eseg: Dictionary = {}          # Color -> PackedVector2Array(선분 쌍)


func _draw_edges() -> void:
	var tick: int = Game.anim_tick_cur
	for key: Variant in _eseg:
		(_eseg[key] as PackedVector2Array).clear()
	for i in _tg_n:
		if tg_alive[i] == 0 or tg_cancel_t[i] > 0.0:
			continue
		_edge_tg(i, tick)
	for k in _z_n:
		if z_alive[k] == 0 or z_kind[k] != ZKind.WAVE:
			continue
		if z_hit[k] != 0 and (tick & 1) != 0:
			continue
		var c: Vector2 = Vector2(z_x[k], z_y[k])
		var r: float = z_r[k]
		var n: int = z_gaps[k]
		if n <= 0:
			_e_arc(c, r + 1.0, 0.0, TAU, maxi(16, int(r)), C_HK)
			_e_arc(c, r, 0.0, TAU, maxi(16, int(r)), C_CH)
		else:
			var step: float = TAU / float(n)
			var hg: float = deg_to_rad(15.0)
			for g in n:
				var a0: float = z_gap[k] + step * float(g) + hg
				var a1: float = z_gap[k] + step * float(g + 1) - hg
				_e_arc(c, r + 1.0, a0, a1, 12, C_HK)
				_e_arc(c, r, a0, a1, 12, C_CH)
	# 받침(먹·흑) 먼저, 청 나중
	for col: Color in [C_HK, C_MK, C_CH, C_CH_HI]:
		var arr: Variant = _eseg.get(col)
		if arr != null and (arr as PackedVector2Array).size() >= 2:
			_edge.draw_multiline(arr, col, -1.0)


func _e_line(a: Vector2, b: Vector2, col: Color) -> void:
	var arr: Variant = _eseg.get(col)
	if arr == null:
		arr = PackedVector2Array()
		_eseg[col] = arr
	(arr as PackedVector2Array).append(_p(a))
	(arr as PackedVector2Array).append(_p(b))


func _e_arc(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color) -> void:
	if r < 1.0:
		return
	var cc: Vector2 = Vector2(floorf(c.x + 0.5), floorf(c.y + 0.5))
	var prev: Vector2 = cc + Vector2(cos(a0), sin(a0)) * r
	for k in range(1, n + 1):
		var a: float = lerpf(a0, a1, float(k) / float(n))
		var q: Vector2 = cc + Vector2(cos(a), sin(a)) * r
		_e_line(prev, q, col)
		prev = q


func _e_dash_line(a: Vector2, b: Vector2, col: Color, dash: float) -> void:
	var v: Vector2 = b - a
	var ln: float = v.length()
	if ln < 0.5:
		return
	var u: Vector2 = v / ln
	var t: float = 0.0
	while t < ln:
		_e_line(a + u * t, a + u * minf(t + dash, ln), col)
		t += dash * 2.0


## 예고 하나의 테두리(z8). 평소 = 먹 받침 + 청 1px. 마지막 0.3초 = 2px, 3틱마다 청 #2a5caa ↔ 먹.
func _edge_tg(i: int, tick: int) -> void:
	var c: Vector2 = Vector2(tg_x[i], tg_y[i])
	var p: float = clampf(tg_t[i] / tg_dur[i], 0.0, 1.0)
	var late: bool = tg_dur[i] - tg_t[i] <= EDGE_LATE_S
	var col: Color = C_CH
	var back: Color = C_HK
	if late:
		var on: bool = ((tick / 3) & 1) == 0
		col = C_CH if on else C_MK
		back = C_MK if on else C_CH
	var d: Vector2 = Vector2(tg_dx[i], tg_dy[i])
	match tg_shape[i]:
		Shape.CIRCLE, Shape.RING:
			var r: float = tg_a[i]
			var seg: int = maxi(12, int(r * 0.8))
			_e_arc(c, r + 1.0, 0.0, TAU, seg, back)
			if late:
				_e_arc(c, r, 0.0, TAU, seg, col)
				_e_arc(c, r - 1.0, 0.0, TAU, seg, col)
			else:
				_edge_dash_circle(c, r, col, 4.0, 3.0, float(tick) * 0.01)
				var stage: float = floorf(p * 4.0) / 4.0
				var rr: float = r + 14.0 * (1.0 - stage)
				_e_arc(c, rr, 0.0, TAU, maxi(12, int(rr * 0.8)), C_CH_HI if p > 0.72 else C_CH)
		Shape.CONE:
			var half: float = tg_b[i]
			var ra: float = tg_a[i]
			var a0: float = atan2(d.y, d.x)
			var e1: Vector2 = c + Vector2(cos(a0 - half), sin(a0 - half)) * ra
			var e2: Vector2 = c + Vector2(cos(a0 + half), sin(a0 + half)) * ra
			var seg2: int = maxi(8, int(ra * half * 0.5))
			_e_line(c, e1, back)
			_e_line(c, e2, back)
			_e_arc(c, ra + 1.0, a0 - half, a0 + half, seg2, back)
			_e_line(c + Vector2(0, -1), e1 + Vector2(0, -1), col)
			_e_line(c + Vector2(0, -1), e2 + Vector2(0, -1), col)
			_e_arc(c, ra, a0 - half, a0 + half, seg2, col)
			if late:
				_e_arc(c, ra - 1.0, a0 - half, a0 + half, seg2, col)
				_e_line(c + Vector2(0, -2), e1 + Vector2(0, -2), col)
				_e_line(c + Vector2(0, -2), e2 + Vector2(0, -2), col)
		Shape.LINE:
			var ln: float = tg_a[i]
			var w: float = tg_b[i] * 0.5
			var nrm: Vector2 = Vector2(-d.y, d.x)
			var side: Vector2 = nrm * w
			var p0: Vector2 = c + side
			var p1: Vector2 = c + side + d * ln
			var p2: Vector2 = c - side + d * ln
			var p3: Vector2 = c - side
			_e_dash_line(p0 + nrm, p1 + nrm, back, 4.0)
			_e_dash_line(p3 - nrm, p2 - nrm, back, 4.0)
			# 돌진 선: 옆선은 늘 점선(긴 실선 여러 개가 화면을 가르지 않게), 끝선만 실선. 마지막 0.3초는 2px 점선 + 점멸.
			_e_dash_line(p0, p1, col, 4.0)
			_e_dash_line(p3, p2, col, 4.0)
			_e_line(p1, p2, col)
			if late:
				_e_dash_line(p0 - nrm, p1 - nrm, col, 4.0)
				_e_dash_line(p3 + nrm, p2 + nrm, col, 4.0)
				_e_line(p1 - d, p2 - d, col)
		Shape.MARK:
			var r2: float = tg_a[i]
			var seg3: int = maxi(12, int(r2 * 0.8))
			if late:
				_e_arc(c, r2 + 1.0, 0.0, TAU, seg3, back)
				_e_arc(c, r2, 0.0, TAU, seg3, col)
				_e_arc(c, r2 - 1.0, 0.0, TAU, seg3, col)
			else:
				_edge_dash_circle(c, r2, col, 2.0, 2.0, 0.0)


func _edge_dash_circle(c: Vector2, r: float, col: Color, dash: float, gap: float, phase: float) -> void:
	if r < 2.0:
		return
	var n: int = maxi(6, int(TAU * r / (dash + gap)))
	var step: float = TAU / float(n)
	var da: float = step * dash / (dash + gap)
	for k in n:
		var a0: float = phase + step * float(k)
		_e_line(c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a0 + da), sin(a0 + da)) * r, col)


func _draw_zone(k: int, tick: int) -> void:
	var c: Vector2 = Vector2(z_x[k], z_y[k])
	var r: float = z_r[k]
	var age: int = tick - z_born[k]
	var ending: bool = z_t[k] < 1.0 and ((tick / 4) & 1) == 0
	match z_kind[k]:
		ZKind.WAVE:
			if z_hit[k] == 0 or (tick & 1) == 0:
				var n: int = z_gaps[k]
				if n <= 0:
					_circle(c, r, C_CH)
					_circle(c, r - 1.0, C_HK)
				else:
					var step: float = TAU / float(n)
					var hg: float = deg_to_rad(15.0)
					for g in n:
						var a0: float = z_gap[k] + step * float(g) + hg
						var a1: float = z_gap[k] + step * float(g + 1) - hg
						draw_arc(_p(c), r, a0, a1, 12, C_CH, -1.0, false)
						draw_arc(_p(c), maxf(1.0, r - 1.0), a0, a1, 12, C_HK, -1.0, false)
		ZKind.MUL_CLEAR, ZKind.DANBI:
			_dash_circle(c, r, C_CR_HI if not ending else C_CR, 3.0, 3.0)
			_hatch_circle(c, r - 2.0, C_CR, 7.0, float(age) * 0.1)
		ZKind.GAMUM:
			_dash_circle(c, r, C_ET, 3.0, 2.0)
			_hatch_circle(c, r - 2.0, C_ET, 6.0, 0.0)
		_:
			var dark: bool = z_kind[k] == ZKind.MUL_BLACK
			var fill: Color = C_MK3 if dark else C_CH_DK
			var edge: Color = C_HK if dark else C_CH
			if age < 8:
				r *= float(age + 1) / 9.0            # 퍼짐(8틱)
			_hatch_circle(c, r - 2.0, fill, 5.0 if z_dps[k] > 0.0 else 7.0, 0.0)
			if not ending:
				_dash_circle(c, r, edge, 4.0, 2.0, float(age) * 0.004)
				_circle(c, r + 1.0, C_HK)


func _draw_knot(k: int, tick: int) -> void:
	var c: Vector2 = Vector2(o_x[k], o_y[k])
	var l: Vector2 = Vector2(o_lx[k], o_ly[k])
	# 무명천 선(보스 ↔ 매듭): 한지 점선(흰색은 매듭 자체에만)
	draw_dashed_line(_p(l), _p(c), C_HJ_DK, -1.0, 3.0, false)
	var r: float = o_r[k]
	var pulse: int = 1 if ((tick / 20) & 1) == 0 else 0
	_circle(c, r + float(pulse), C_BAEK_DK)
	_dash_circle(c, r - 3.0, C_BAEK, 3.0, 2.0, float(tick) * 0.02)
	# 매듭 글리프(무명 고 매듭 13×11): 좌우 고리 + 가운데 묶음 + 늘어진 두 끈. 먹 외곽 1px. 반쯤 풀린 덧매듭은 한지색 끈.
	var g: Vector2 = _p(c) - Vector2(0.5, 0.5) + Vector2(0, -2)
	var tail: Color = C_BAEK_DK if o_v[k] < 0.5 else C_HJ_DK
	draw_rect(Rect2(g + Vector2(-7, -4), Vector2(6, 7)), C_HK)
	draw_rect(Rect2(g + Vector2(2, -4), Vector2(6, 7)), C_HK)
	draw_rect(Rect2(g + Vector2(-2, -2), Vector2(5, 5)), C_HK)
	draw_rect(Rect2(g + Vector2(-4, 2), Vector2(4, 6)), C_HK)
	draw_rect(Rect2(g + Vector2(1, 2), Vector2(4, 6)), C_HK)
	# 고리(속이 빈 4×5)
	draw_rect(Rect2(g + Vector2(-6, -3), Vector2(4, 1)), C_BAEK)
	draw_rect(Rect2(g + Vector2(-6, 1), Vector2(4, 1)), C_BAEK)
	draw_rect(Rect2(g + Vector2(-6, -2), Vector2(1, 3)), C_BAEK)
	draw_rect(Rect2(g + Vector2(3, -3), Vector2(4, 1)), C_BAEK)
	draw_rect(Rect2(g + Vector2(3, 1), Vector2(4, 1)), C_BAEK)
	draw_rect(Rect2(g + Vector2(6, -2), Vector2(1, 3)), C_BAEK)
	# 가운데 묶음
	draw_rect(Rect2(g + Vector2(-1, -1), Vector2(3, 3)), C_BAEK)
	draw_rect(Rect2(g + Vector2(0, 0), Vector2(1, 1)), C_BAEK_DK)
	# 늘어진 끈
	draw_rect(Rect2(g + Vector2(-2, 2), Vector2(1, 2)), tail)
	draw_rect(Rect2(g + Vector2(-3, 4), Vector2(1, 3)), tail)
	draw_rect(Rect2(g + Vector2(2, 2), Vector2(1, 2)), tail)
	draw_rect(Rect2(g + Vector2(3, 4), Vector2(1, 3)), tail)


func _draw_lump(k: int, tick: int) -> void:
	var c: Vector2 = Vector2(o_x[k], o_y[k])
	var r: float = o_r[k]
	var wob: float = float((tick / 8) % 3) - 1.0
	draw_circle(_p(c + Vector2(0, 2)), r + 1.0, C_HK, true, -1.0, false)
	draw_circle(_p(c), r, C_MK, true, -1.0, false)
	draw_circle(_p(c + Vector2(-r * 0.35, -r * 0.2 + wob)), r * 0.55, C_MK3, true, -1.0, false)
	draw_circle(_p(c + Vector2(r * 0.3, r * 0.15 - wob)), r * 0.45, C_MK3, true, -1.0, false)
	# 살 눈(적 2px)
	draw_rect(Rect2(_p(c + Vector2(-4, -2)) - Vector2(0.5, 0.5), Vector2(2, 1)), C_JK)
	draw_rect(Rect2(_p(c + Vector2(2, -2)) - Vector2(0.5, 0.5), Vector2(2, 1)), C_JK)
	if o_v[k] > 0.0:
		# 거둠 진행: 바깥 청흑 고리 호
		draw_arc(_p(c), r + 5.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(o_v[k], 0.0, 1.0), 24, C_CH_HI, -1.0, false)
		_circle(c, r + 6.0, C_HK)


## 손님 대접 게이지(07 6.5.2 / 01 §913: 화신 규격 계열, HP바 아님): 한지 바탕·흙 테·왼쪽 공물 그릇·황 채움·50/100 놋 방울 점.
## 게이지 0 이고 무당이 6u 안이면 런당 1회 '공물을 바쳐 대접' 한지 말풍선 4초.
func _draw_gauge(ci: Node2D, k: int, tick: int) -> void:
	var c: Vector2 = _p(Vector2(o_x[k], o_y[k])) - Vector2(0.5, 0.5)
	var w: float = 36.0
	var org: Vector2 = c + Vector2(-w * 0.5 + 5.0, 0)
	# 공물 그릇(8×6): 놋그릇 + 위로 쌓인 떡·과일 점
	var b: Vector2 = org + Vector2(-11, -2)
	ci.draw_rect(Rect2(b + Vector2(0, 2), Vector2(8, 4)), C_HJ_DK)
	ci.draw_rect(Rect2(b + Vector2(1, 2), Vector2(6, 2)), C_HW_DK)
	ci.draw_rect(Rect2(b + Vector2(2, 5), Vector2(4, 1)), C_HJ_DK)
	ci.draw_rect(Rect2(b + Vector2(2, 0), Vector2(2, 2)), C_JK)
	ci.draw_rect(Rect2(b + Vector2(4, 0), Vector2(2, 2)), C_HJ)
	ci.draw_rect(Rect2(b + Vector2(3, -1), Vector2(2, 1)), C_HW)
	# 막대: 흙 테 1px + 한지 바탕 + 황 채움
	ci.draw_rect(Rect2(org - Vector2(1, 1), Vector2(w + 2, 5)), C_HJ_DK)
	ci.draw_rect(Rect2(org, Vector2(w, 3)), C_HJ2)
	var v: float = clampf(o_v[k] / 100.0, 0.0, 1.0)
	var fillw: float = floorf(w * v)
	if fillw > 0.0:
		ci.draw_rect(Rect2(org, Vector2(fillw, 3)), C_HW)
		ci.draw_rect(Rect2(org, Vector2(fillw, 1)), C_HW_HI)
	# 놋 방울 점(50·100): 채워지면 밝게
	for th: float in [0.5, 1.0]:
		var dp: Vector2 = org + Vector2(floorf(w * th) - 1.0, -2)
		var lit: bool = v >= th
		ci.draw_rect(Rect2(dp, Vector2(3, 3)), C_HJ_DK)
		ci.draw_rect(Rect2(dp + Vector2(1, 1), Vector2(1, 1)), C_HW_HI if lit else C_HW_DK)
	# 말풍선(런당 1회)
	var pl: Node2D = Game.player
	if not _bubble_done and _bubble_t0 < 0 and o_v[k] <= 0.0 and pl != null \
			and pl.global_position.distance_to(Vector2(o_x[k], o_y[k])) <= 6.0 * K.UNIT_PX:
		_bubble_t0 = tick
	if _bubble_t0 >= 0 and not _bubble_done:
		var e: int = tick - _bubble_t0
		if e >= 240 or o_v[k] > 0.0:
			_bubble_done = true
		else:
			_draw_bubble(ci, c + Vector2(0, -10), "공물을 바쳐 대접하라")


func _draw_bubble(ci: Node2D, bottom: Vector2, text: String) -> void:
	var f: Font = _get_font()
	var fs: int = 10
	var tw: float = ceilf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x)
	var bw: float = tw + 8.0
	var org: Vector2 = Vector2(floorf(bottom.x - bw * 0.5), bottom.y - 14.0)
	ci.draw_rect(Rect2(org - Vector2(1, 1), Vector2(bw + 2, 14)), C_HJ_DK)
	ci.draw_rect(Rect2(org, Vector2(bw, 12)), C_HJ_HI)
	ci.draw_rect(Rect2(Vector2(floorf(bottom.x) - 1.0, bottom.y - 2.0), Vector2(3, 1)), C_HJ_HI)
	ci.draw_rect(Rect2(Vector2(floorf(bottom.x), bottom.y - 1.0), Vector2(1, 1)), C_HJ_DK)
	f.draw_string(ci.get_canvas_item(), org + Vector2(4, 10), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, C_MK)


func _get_font() -> Font:
	if _font == null:
		_font = UiKit.font(UiKit.F_SMALL)
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


## 한형 매듭 길잡이(오버레이 z 4): 흰 셰브론(위아래 흔들림)·첫 매듭 '매듭' 이름표·화면 밖이면 가장자리 흰 마름모 + 화살.
func _draw_knot_guides(ci: Node2D, tick: int) -> void:
	var cam: Camera2D = Game.camera
	var have_cam: bool = cam != null and is_instance_valid(cam)
	var cc: Vector2 = Vector2.ZERO
	var half: Vector2 = Vector2(320, 180)
	if have_cam:
		cc = cam.get_screen_center_position()
		half = get_viewport_rect().size * 0.5 / cam.zoom
	for k in OBJ_CAP:
		if o_alive[k] == 0 or o_kind[k] != OKind.KNOT:
			continue
		if _knot_label_k < 0:
			_knot_label_k = o_label[k] + 1
		var kp: Vector2 = Vector2(o_x[k], o_y[k])
		var rel: Vector2 = kp - cc
		var inside: bool = not have_cam or (absf(rel.x) < half.x - 10.0 and absf(rel.y) < half.y - 10.0)
		if inside:
			var bob: float = float((tick / 10) % 2)
			var g: Vector2 = _p(kp) - Vector2(0.5, 0.5) + Vector2(0, -o_r[k] - 9.0 - bob)
			# 셰브론 ▼ (먹 외곽 + 백)
			ci.draw_rect(Rect2(g + Vector2(-4, -1), Vector2(9, 2)), C_HK)
			ci.draw_rect(Rect2(g + Vector2(-3, 1), Vector2(7, 2)), C_HK)
			ci.draw_rect(Rect2(g + Vector2(-1, 3), Vector2(3, 2)), C_HK)
			ci.draw_rect(Rect2(g + Vector2(-3, 0), Vector2(7, 1)), C_BAEK)
			ci.draw_rect(Rect2(g + Vector2(-2, 2), Vector2(5, 1)), C_BAEK)
			ci.draw_rect(Rect2(g + Vector2(0, 4), Vector2(1, 1)), C_BAEK)
			if o_label[k] <= _knot_label_k and Game.game_tick - o_born[k] < 360:
				var f: Font = _get_font()
				var lp: Vector2 = g + Vector2(-10, -4)
				f.draw_string_outline(ci.get_canvas_item(), lp, "매듭", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, 3, C_MK)
				f.draw_string(ci.get_canvas_item(), lp, "매듭", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, C_BAEK)
		else:
			# 화면 가장자리 표지(백 마름모 + 바깥쪽 꼭짓점)
			var m: Vector2 = Vector2(clampf(rel.x, -half.x + 12.0, half.x - 12.0), clampf(rel.y, -half.y + 12.0, half.y - 12.0)) + cc
			m = _p(m) - Vector2(0.5, 0.5)
			var pulse: int = 1 if ((tick / 15) & 1) == 0 else 0
			var r: int = 4 + pulse
			for yy in range(-r, r + 1):
				var wv: int = r - absi(yy)
				ci.draw_rect(Rect2(m + Vector2(-wv - 1, yy), Vector2(wv * 2 + 3, 1)), C_HK)
			for yy2 in range(-r + 1, r):
				var wv2: int = r - 1 - absi(yy2)
				ci.draw_rect(Rect2(m + Vector2(-wv2, yy2), Vector2(wv2 * 2 + 1, 1)), C_BAEK)
			var dirv: Vector2 = rel.normalized()
			var tip: Vector2 = _p(m + dirv * float(r + 4)) - Vector2(0.5, 0.5)
			ci.draw_rect(Rect2(tip - Vector2(1, 1), Vector2(3, 3)), C_HK)
			ci.draw_rect(Rect2(tip, Vector2(1, 1)), C_BAEK)


## 한형 열림 창 남은 시간: 보스 발밑 백 호(1px, 줄어듦) + 먹 바탕 원.
func _draw_gopuri_open(ci: Node2D) -> void:
	if gop_f < 0.0:
		return
	var c: Vector2 = _p(Vector2(gop_x, gop_y + 2.0))
	var r: float = 30.0
	ci.draw_arc(c, r + 1.0, 0.0, TAU, 48, C_HK, 1.0, false)
	ci.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * gop_f, 48, C_BAEK, 1.0, false)


## 정예 머리 위 소형 체력바(32px, 35% 눈금 백) — 07 6.0 / 11 UI. EnemyManager.render 가 화면 안 정예만 넘긴다.
var _bars: PackedFloat32Array = PackedFloat32Array()    # [x, y, ratio, pullil] × n
var _bar_n: int = 0


func set_bars(buf: PackedFloat32Array, n: int) -> void:
	_bars = buf
	_bar_n = n


## 오버레이 노드(z 4, 적 위)의 draw 신호에서 호출: 정예 체력바 · 조임 3단계 흰 매듭 아이콘.
func draw_overlay(ci: Node2D) -> void:
	var tick: int = Game.anim_tick_cur
	_draw_gopuri_open(ci)
	for k in OBJ_CAP:
		if o_alive[k] == 1 and o_kind[k] == OKind.GAUGE:
			_draw_gauge(ci, k, tick)
	_draw_knot_guides(ci, tick)
	# 무당 몸 상자(발 기준 x±14, y−40~+4)와 겹치는 체력바는 α0.5 — 오버레이(z8)가 무당 금 테(z7)를 덮지 않게(design/18 ①)
	var pl: Node2D = Game.player
	var body: Rect2 = Rect2(pl.global_position + Vector2(-14, -40), Vector2(28, 44)) if pl != null else Rect2()
	for b in _bar_n:
		var x: float = floorf(_bars[b * 4] + 0.5)
		var y: float = floorf(_bars[b * 4 + 1] + 0.5)
		var ratio: float = _bars[b * 4 + 2]
		if ratio < 0.0:
			# 조임 3단계(매듭 잠금 6회+): 머리 위 흰 매듭 1개(07 2.7 "풀 준비가 된 귀신")
			var g: Vector2 = Vector2(x, y)
			ci.draw_rect(Rect2(g + Vector2(-3, -2), Vector2(7, 5)), C_HK)
			ci.draw_rect(Rect2(g + Vector2(-2, -1), Vector2(2, 2)), C_BAEK)
			ci.draw_rect(Rect2(g + Vector2(1, -1), Vector2(2, 2)), C_BAEK)
			ci.draw_rect(Rect2(g + Vector2(0, 0), Vector2(1, 3)), C_BAEK_DK)
			continue
		var pull: bool = _bars[b * 4 + 3] > 0.5
		var w: float = 32.0
		var org: Vector2 = Vector2(x - 16.0, y)
		var ba: float = 0.5 if (pl != null and body.intersects(Rect2(org - Vector2(1, 1), Vector2(w + 2, 5)))) else 1.0
		ci.draw_rect(Rect2(org - Vector2(1, 1), Vector2(w + 2, 5)), Color(C_HK, C_HK.a * ba))
		ci.draw_rect(Rect2(org, Vector2(w, 3)), Color(C_MK3, C_MK3.a * ba))
		var fw: float = floorf(w * clampf(ratio, 0.0, 1.0))
		if fw > 0.0:
			var fc: Color = C_BAEK_DK if pull else C_JK
			ci.draw_rect(Rect2(org, Vector2(fw, 3)), Color(fc, fc.a * ba))
		ci.draw_rect(Rect2(org + Vector2(floorf(w * 0.35), -1), Vector2(1, 5)), Color(C_BAEK, C_BAEK.a * ba))


