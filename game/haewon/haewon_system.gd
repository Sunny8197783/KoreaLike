class_name HaewonSystem
extends Node
## 살기·살 알갱이·원귀 회귀(25/50/75)·신명(피버)·추임새(얼씨구 배너)·신명 오름 색동 테두리. 소유: haewon.
## 데이터: combat_core.salgi, combat_core.sinmyeong, combat_core.chuimsae, enemies.scaling.wongwi, meta_economy.income.neok_sources
##
## 살 알갱이(obj_sal_algaengi, 캐논 3.2.6): 퇴치 지점에 먹빛 알갱이. 맵 최대 200(초과·근접 1.5u 는 병합 → 무게 증가).
##   무당이 밟으면 거둔다(0.6u, 살기는 줄지 않음 — 원귀 재료에서 빠지고 벽사 기세 +0.6%/개).
##   정화(길닦음 zone·소금)는 개당 살기 −0.02.
## 살기 효과(연속식, 캐논 v1.2 D-16): 살기 1당 출현 +0.5%, 정예 확률 +0.5%p, 적 한 +0.2% → 정적 함수로 노출(waves/enemies 가 읽음).
## 원귀 회귀: 살기 25/50/75 최초 도달 → (틱 18) 남은 알갱이가 떠올라 퇴치 상위 3종 원귀로 뭉친다. 수 = 남은 알갱이 30개당 1(1~3).
## 신명: 해원·천도·고리로 차고, 가득 차면 신명 오름 15초(장단 −15%p → jangdan_bonus(), 길베 ×2, 스냅 2.5u, 색동 테두리).
##
## 공개 API(같은 모듈·요청 모듈용):
##   add_sinmyeong(d)                   신명 증가(오름 중 무시, 오름 뒤 20초 ×0.5, 최소 간격 45초)
##   cleanse_zone(ring) -> int          고리 zone 안 알갱이 정화(살기 −0.02/개). 정화 개수 반환
##   cleanse_circle(pos, r_px, max_n) -> int  원 안 알갱이 정화(소금 — combat). max_n ≤0 = 무제한
##   살기 기본치(stat_salgi + 제웅 패시브)는 0.5초마다 반영, 정화 하한
##   static spawn_mult() / elite_chance_bonus() / han_mult() / jangdan_bonus() / ritual_ref_top() / ritual_ref_sum()
##   grains_alive() -> int, grains_collected, byeoksa_gise(0..1)
##   slam(text, px, sec, toechi, force)  붓글씨 배너(추임새와 같은 자리)
##   n_ratio() -> float                  고리 가중 넋 비율 N(11-24): 해원 가중 = 등급 가중 × 원인 가중
##                                       (고리 1.0, 흰 무구 자동 0.5 — combat_core.ring.n_weight_by_cause). 분모 0 이면 0.5.
##   텔레메트리(봇): haewon_ring/white/other, ring_haewon_share(), HP 75% 미만 체류 비율 → [haewon] summary(런 종료)

const GRAIN_CAP: int = 200
const MOTE_CAP: int = 96
const WG_CAP: int = 8
const BANNER_SCALE: float = 1.25   # 1.5→1.25: 가장자리(x 0.14/0.86, y 0.62)로 옮기며 크기도 한 단계 낮춤(design/18 §2.3)
const RITUAL_REF: PackedInt32Array = [10, 12, 14, 16, 18, 21, 24, 28]

# --- 살기 문턱 ---
var _thresholds: PackedInt32Array = PackedInt32Array([25, 50, 75])
var _crossed: PackedByteArray = PackedByteArray()
var _pending_wongwi: PackedInt32Array = PackedInt32Array()
var _salgi_base: float = 0.0          # 살기 기본치(정화 하한)
var _base_tick: int = 0
var _salgi_per_toechi: float = 0.02
var _salgi_elite: float = 1.0
var _salgi_mboss: float = 5.0
var _cleanse_per: float = 0.02
var _grains_per_wongwi: int = 30
var _wongwi_min: int = 1
var _wongwi_max: int = 3
var _wongwi_fx_time: float = 1.2
var _wg_han: float = 4.0
var _toechi_by_species: Dictionary = {}     # StringName -> int (원귀 상위 3종)

# --- 고리 가중 N·텔레메트리(11-24 리뷰: 고리 보상감·생존 긴장감) ---
var _w_tier: Dictionary = {"common": 1.0, "minion": 1.0, "elite": 5.0, "elite_system": 5.0, "mboss": 20.0}
var _w_cause_ring: float = 1.0
var _w_cause_white: float = 0.5
var _sm_white_mult: float = 0.5        # 흰 무구 자동 해원의 신명 가중
var n_w_haewon: float = 0.0
var n_w_toechi: float = 0.0
var haewon_ring: int = 0
var haewon_white: int = 0
var haewon_other: int = 0
var _hp_t: float = 0.0
var _hp_low_t: float = 0.0
var _hp_low_ratio: float = 0.75
var _summary_done: bool = false
var haewon_ring_bound: int = 0          # 고리가 기색에 묶은 적이 그 기색 안에 풀린 수(고리 몫으로 셈)
var _bound_h: PackedInt32Array = PackedInt32Array()      # 슬롯 → 묶인 핸들(-1 없음)
var _bound_until: PackedFloat32Array = PackedFloat32Array()
var _bound_dur: float = 12.0

# --- 신명 ---
var _g_haewon: float = 0.004
var _g_toechi: float = 0.001
var _g_elite_haewon: float = 0.05
var _oreum_dur: float = 15.0
var _oreum_left: float = 0.0
var _oreum_end_t: float = -1000.0
var _post_window: float = 20.0
var _post_mult: float = 0.5
var _min_gap: float = 45.0

# --- 살 알갱이 SoA ---
var g_x: PackedFloat32Array = PackedFloat32Array()
var g_y: PackedFloat32Array = PackedFloat32Array()
var g_w: PackedFloat32Array = PackedFloat32Array()       # 병합 수(무게)
var g_born: PackedFloat32Array = PackedFloat32Array()    # 생성 연출 시각(게임 초)
var g_alive: PackedByteArray = PackedByteArray()
var g_count: int = 0
var grains_collected: int = 0
var byeoksa_gise: float = 0.0                            # 0..1 (벽사 오름은 TODO: deities/combat 과 합의)
var _merge_r: float = 1.5 * 32.0
var _pick_r: float = 0.6 * 32.0
var _gise_per_grain: float = 0.006

# --- 원귀 회귀 연출·지연 스폰 ---
var m_x: PackedFloat32Array = PackedFloat32Array()       # 떠오른 알갱이 → 뭉치는 점(모트)
var m_y: PackedFloat32Array = PackedFloat32Array()
var m_tx: PackedFloat32Array = PackedFloat32Array()
var m_ty: PackedFloat32Array = PackedFloat32Array()
var m_t: PackedFloat32Array = PackedFloat32Array()       # 0..1 진행(연출 시계)
var m_delay: PackedFloat32Array = PackedFloat32Array()
var m_n: int = 0
var _wg_t: PackedFloat32Array = PackedFloat32Array()     # 지연 스폰(게임 초)
var _wg_x: PackedFloat32Array = PackedFloat32Array()
var _wg_y: PackedFloat32Array = PackedFloat32Array()
var _wg_sp: Array[StringName] = []
var _wg_n: int = 0
var _tg_x: PackedFloat32Array = PackedFloat32Array()     # 모트가 날아갈 원귀 자리(연출)
var _tg_y: PackedFloat32Array = PackedFloat32Array()
var _tg_n: int = 0
var wongwi_returns: int = 0

# --- 추임새(얼씨구 배너, 캐논 G5) ---
var _combo_window: float = 2.0
var _hc: int = 0
var _hc_last: float = -100.0
var _tc: int = 0
var _tc_last: float = -100.0
var _h_steps: Array = []
var _t_steps: Array = []
var _slam_last: float = -100.0
## 가시성 측정(tests/vis_probe.gd): 이번 프레임에 그린 화면 글 사각형. 키 → [Rect2(640×360 기준), 그린 프레임].
var vis_rects: Dictionary = {}

# --- 연출 노드(자기 노드 하위만) ---
var _sal_layer: Node2D = null
var _border_layer: CanvasLayer = null
var _border: Node2D = null
var _banner: Control = null
var _sal_fx: Array[Dictionary] = []      # s/m/l
var _wrise_fx: Dictionary = {}
var _brd_fx: Dictionary = {}
var _brd_a: float = 0.0
var _brd_t: float = 0.0
var _brd_vis: bool = false
var _sal_had: bool = false
var _font: Font = null
var _bn_text: String = ""
var _bn_px: int = 24
var _bn_t: float = 99.0
var _bn_dur: float = 1.0
var _bn_toechi: bool = false
var _bn_side: int = 0


func _ready() -> void:
	var th: Variant = Data.get_value("combat_core", "salgi.thresholds", [25, 50, 75])
	if th is Array:
		_thresholds.clear()
		for v: Variant in th:
			_thresholds.append(int(v))
	_crossed.resize(_thresholds.size())
	_crossed.fill(0)
	_g_haewon = Data.num("combat_core", "sinmyeong.gain.haewon", 0.004)
	_g_toechi = Data.num("combat_core", "sinmyeong.gain.toechi", 0.001)
	_g_elite_haewon = Data.num("combat_core", "sinmyeong.gain.elite_haewon", 0.05)
	var wt: Variant = Data.get_value("enemies", "boss_common.form_rule.N_assumption.weights", null)
	if wt is Dictionary:
		_w_tier = wt
	_w_cause_ring = Data.num("combat_core", "ring.n_weight_by_cause.ring", 1.0)
	_w_cause_white = Data.num("combat_core", "ring.n_weight_by_cause.white", 0.5)
	_sm_white_mult = Data.num("combat_core", "ring.n_weight_by_cause.white_sinmyeong", 0.5)
	_hp_low_ratio = Data.num("combat_core", "yeongga.telemetry_hp_low_ratio", 0.75)
	_bound_dur = Data.num("combat_core", "han.giseak_duration", 12.0)
	_bound_h.resize(EnemyManager.CAPACITY)
	_bound_h.fill(-1)
	_bound_until.resize(EnemyManager.CAPACITY)
	_oreum_dur = Data.num("combat_core", "sinmyeong.oreum_duration", 15.0)
	_post_window = Data.num("combat_core", "sinmyeong.post_oreum_window", 20.0)
	_post_mult = Data.num("combat_core", "sinmyeong.post_oreum_gain_mult", 0.5)
	_min_gap = Data.num("combat_core", "sinmyeong.min_gap_after_oreum", 45.0)
	_merge_r = Data.num("combat_core", "salgi.grain_merge_radius_u", 1.5) * K.UNIT_PX
	_cleanse_per = Data.num("combat_core", "ring.sal_cleanse_per_grain", 0.02)
	_grains_per_wongwi = int(Data.num("combat_core", "salgi.wongwi_count.grains_per_wongwi", 30))
	_wongwi_min = int(Data.num("combat_core", "salgi.wongwi_count.min", 1))
	_wongwi_max = int(Data.num("combat_core", "salgi.wongwi_count.max", 3))
	_wongwi_fx_time = Data.num("combat_core", "salgi.wongwi_fx_time", 1.2)
	_wg_han = Data.num("enemies", "scaling.wongwi.han_mult", 4.0)
	_combo_window = Data.num("combat_core", "chuimsae.combo_window", 2.0)
	var hs: Variant = Data.get_value("combat_core", "chuimsae.haewon_steps", [])
	_h_steps = hs if hs is Array else []
	var ts: Variant = Data.get_value("combat_core", "chuimsae.toechi_steps", [])
	_t_steps = ts if ts is Array else []
	for a: String in ["g_x", "g_y", "g_w", "g_born"]:
		var arr: PackedFloat32Array = PackedFloat32Array()
		arr.resize(GRAIN_CAP)
		set(a, arr)
	g_alive.resize(GRAIN_CAP)
	g_alive.fill(0)
	for a: String in ["m_x", "m_y", "m_tx", "m_ty", "m_t", "m_delay"]:
		var arr2: PackedFloat32Array = PackedFloat32Array()
		arr2.resize(MOTE_CAP)
		set(a, arr2)
	_wg_t.resize(WG_CAP)
	_wg_x.resize(WG_CAP)
	_wg_y.resize(WG_CAP)
	_wg_sp.resize(WG_CAP)
	_tg_x.resize(WG_CAP)
	_tg_y.resize(WG_CAP)
	_pending_wongwi.resize(0)
	for id: String in ["vfx_sal_grain_idle_s", "vfx_sal_grain_idle", "vfx_sal_grain_idle_l"]:
		_sal_fx.append(VfxLib.get_fx(StringName(id)))
	_wrise_fx = VfxLib.get_fx(&"vfx_wongwi_rise")
	_brd_fx = VfxLib.get_fx(&"vfx_sinmyeong_oreum_border")
	_build_nodes()
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.run_ended.connect(_on_run_ended)


func _build_nodes() -> void:
	# 살 알갱이·원귀 모트: 월드 공간(카메라 적용), 지면(-10) 위·적(0) 아래
	_sal_layer = Node2D.new()
	_sal_layer.name = "SalLayer"
	_sal_layer.z_index = -1
	_sal_layer.draw.connect(_draw_sal)
	add_child(_sal_layer)
	# 신명 오름 색동 테두리(화면 공간, 후처리 위·HUD 아래)
	_border_layer = CanvasLayer.new()
	_border_layer.layer = 6
	add_child(_border_layer)
	_border = Node2D.new()
	var add_mat: CanvasItemMaterial = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_border.material = add_mat
	_border.draw.connect(_draw_border)
	_border_layer.add_child(_border)
	# 추임새 배너(붓글씨 슬램)
	_banner = Control.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.draw.connect(_draw_banner)
	_border_layer.add_child(_banner)
	var f: Variant = load("res://assets/fonts/nanum_brush/NanumBrushScript-Regular.ttf")
	if f is FontFile:
		var ff: FontFile = (f as FontFile).duplicate() as FontFile
		ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		ff.hinting = TextServer.HINTING_NONE
		_font = ff
	else:
		_font = ThemeDB.fallback_font


# ─── 이벤트 ────────────────────────────────────────────────────────────

func _on_enemy_killed(h: int, sp: StringName, pos: Vector2, kind: StringName, cause: StringName, tier: StringName) -> void:
	var elite: bool = tier != K.TIER_COMMON and tier != K.TIER_MINION
	var t: float = Game.time_sec()
	var slot: int = h & EnemyManager.SLOT_MASK
	if _bound_h[slot] == h:
		_bound_h[slot] = -1
		if kind != K.KIND_TOECHI and cause == &"white" and t <= _bound_until[slot]:
			cause = &"ring"   # 고리가 묶어 둔 적: 흰 무구는 마무리만 — 고리 몫
			haewon_ring_bound += 1
	if cause != &"debug":
		var tw: float = float(_w_tier.get(String(tier), 1.0)) if tier != K.TIER_BOSS else 0.0
		if kind == K.KIND_TOECHI:
			n_w_toechi += tw
		elif cause == &"ring":
			n_w_haewon += tw * _w_cause_ring
			haewon_ring += 1
		elif cause == &"white":
			n_w_haewon += tw * _w_cause_white
			haewon_white += 1
		else:
			n_w_haewon += tw
			haewon_other += 1
	if kind == K.KIND_TOECHI:
		var d: float = _salgi_per_toechi
		if tier == K.TIER_MBOSS or tier == K.TIER_BOSS:
			d = _salgi_mboss
		elif elite:
			d = _salgi_elite
		_add_salgi(d)
		add_sinmyeong(_g_toechi)
		if cause != &"debug" and tier == K.TIER_COMMON and String(sp).begins_with("enm_"):
			_toechi_by_species[sp] = int(_toechi_by_species.get(sp, 0)) + 1
		if cause != &"debug":
			_add_grain(pos, 1.0)
		if t - _tc_last > _combo_window:
			_tc = 0
		_tc += 1
		_tc_last = t
		_check_combo(_tc, _t_steps, true)
	else:
		# 고리로 그린 해원이 흰 무구 자동 해원보다 신명을 더 채운다(고리를 그릴 동기)
		add_sinmyeong((_g_elite_haewon if elite else _g_haewon) * (_sm_white_mult if cause == &"white" else 1.0))
		if t - _hc_last > _combo_window:
			_hc = 0
		_hc += 1
		_hc_last = t
		_check_combo(_hc, _h_steps, false)


func _check_combo(c: int, steps: Array, toechi: bool) -> void:
	# 붓 추임새는 가장자리(x 0.14/0.86, y 0.62)·×1.25 로 옮겨 가운데·무당 안전 상자를 덮지 않는다(design/18 §2.1).
	# 그래서 콤보 20('얼씨구'·'물렀거라')도 다시 붓으로 낸다 — 40 이상만 남기자 보통 런 캡처 63장에서 붓글씨가 0장이 됐다
	# (전 8장, 가시성 리뷰 11-25). 가운데 슬롯 prio 0 규칙은 그대로라 큰 글이 떠 있으면 버린다.
	if c < 20:
		return
	for s: Variant in steps:
		if s is Dictionary and int((s as Dictionary).get("combo", -1)) == c:
			slam(String((s as Dictionary).get("text", "")), int((s as Dictionary).get("px", 24)),
				float((s as Dictionary).get("sec", 1.0)), toechi, false)
			return


## 붓 슬램 배너가 지금 떠 있는가(읽기 전용 — vfx 가 같은 자리 '해원 ×N' 글자를 겹쳐 올리지 않게, 리뷰 11-24).
func banner_active() -> bool:
	return _bn_text != "" and _bn_t < _bn_dur + 0.3


## 붓글씨 슬램 배너(추임새·길닦음). force = 초당 1회 상한 무시(고리 닫힘 — 재사용 대기 1초가 이미 상한).
func slam(text: String, px: int, sec: float, toechi: bool, force: bool) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if not force and now - _slam_last < 1.0:   # slam_max_per_sec 1
		return
	# 가운데 슬롯(design/18 §2.2): 길닦음(force) prio 1, 추임새 prio 0. 차지 못하면 버린다(연속 굿 칩이 대신 말한다).
	if Juice.has_method(&"claim_center") and not bool(Juice.call(&"claim_center", &"brush", 1 if force else 0, sec + 0.3)):
		return
	_slam_last = now
	_bn_text = text
	_bn_px = px
	_bn_dur = sec
	_bn_t = 0.0
	_bn_toechi = toechi
	_bn_side = 1 - _bn_side


# ─── 살기 ──────────────────────────────────────────────────────────────

## 연습 굿판(design/17 §7.3): _add_salgi 공개 래퍼(문턱·원귀 회귀 그대로).
func add_salgi(d: float) -> void:
	_add_salgi(d)


func _add_salgi(d: float) -> void:
	if d == 0.0:
		return
	var before: float = Game.salgi
	Game.salgi = maxf(0.0, Game.salgi + d)
	Events.salgi_changed.emit(Game.salgi, Game.salgi - before)
	for k in _thresholds.size():
		if _crossed[k] == 0 and Game.salgi >= float(_thresholds[k]):
			_crossed[k] = 1
			_pending_wongwi.append(_thresholds[k])   # 실제 스폰은 틱 18(피해 해석 도중 스폰 금지)


func _add_grain(pos: Vector2, w: float) -> void:
	var r2: float = _merge_r * _merge_r
	var free_i: int = -1
	var near_i: int = -1
	var near_d: float = INF
	for i in GRAIN_CAP:
		if g_alive[i] == 0:
			if free_i < 0:
				free_i = i
			continue
		var dx: float = g_x[i] - pos.x
		var dy: float = g_y[i] - pos.y
		var dd: float = dx * dx + dy * dy
		if dd <= r2:
			g_w[i] += w
			return
		if dd < near_d:
			near_d = dd
			near_i = i
	if free_i < 0:
		if near_i >= 0:
			g_w[near_i] += w   # 상한 초과: 가장 가까운 알갱이에 병합
		return
	g_x[free_i] = pos.x
	g_y[free_i] = pos.y
	g_w[free_i] = w
	g_born[free_i] = Game.time_sec()
	g_alive[free_i] = 1
	g_count += 1


func grains_alive() -> int:
	return g_count


## 남은 알갱이 무게 합(병합 포함).
func grains_weight() -> float:
	var s: float = 0.0
	for i in GRAIN_CAP:
		if g_alive[i] != 0:
			s += g_w[i]
	return s


## 고리 zone 안 알갱이 정화. ring.in_zone(p) 는 닫힘 직후에만 유효.
func cleanse_zone(ring: RingClosure) -> int:
	var n: int = 0
	var w: float = 0.0
	for i in GRAIN_CAP:
		if g_alive[i] != 0 and ring.in_zone(Vector2(g_x[i], g_y[i])):
			ring.add_cleanse_fx(Vector2(g_x[i], g_y[i]))
			w += g_w[i]
			g_alive[i] = 0
			g_count -= 1
			n += 1
	_purify(w)
	return n


## 원 안 살 알갱이 정화(소금 등 — combat arch_drop_zone 이 부름). 개당(무게당) 살기 −0.02, 최대 max_n 개. 반환: 정화 수.
func cleanse_circle(pos: Vector2, r_px: float, max_n: int) -> int:
	if g_count <= 0 or max_n == 0:
		return 0
	var r2: float = r_px * r_px
	var n: int = 0
	var w: float = 0.0
	var ring: RingClosure = null
	if Game.run_root != null:
		ring = Game.run_root.get("ring") as RingClosure
	for i in GRAIN_CAP:
		if g_alive[i] == 0:
			continue
		var dx: float = g_x[i] - pos.x
		var dy: float = g_y[i] - pos.y
		if dx * dx + dy * dy > r2:
			continue
		if ring != null:
			ring.add_cleanse_fx(Vector2(g_x[i], g_y[i]))
		w += g_w[i]
		g_alive[i] = 0
		g_count -= 1
		n += 1
		if max_n > 0 and n >= max_n:
			break
	_purify(w)
	return n


## 정화로 살기 감소(기본치 아래로는 내려가지 않음 — stats.stat_salgi floor = baseline).
func _purify(w: float) -> void:
	if w <= 0.0:
		return
	var before: float = Game.salgi
	Game.salgi = maxf(_salgi_base, Game.salgi - _cleanse_per * w)
	if Game.salgi != before:
		Events.salgi_changed.emit(Game.salgi, Game.salgi - before)


## 살기 기본치 = 캐릭터 stat_salgi + 패시브 flat(제웅 3/6/9/12/15). 기본치가 오르면 현재 살기도 같은 양만큼 오른다(passives.psv_jeung).
func _refresh_salgi_base() -> void:
	var b: float = Game.stat(&"stat_salgi", 0.0)
	var wm: Node = Game.weapons
	if wm != null and wm.has_method("passive_level"):
		var order: Variant = wm.get("passive_order")
		if order is Array:
			for pid: Variant in order:
				var lvl: int = int(wm.call("passive_level", pid))
				if lvl <= 0:
					continue
				var mods: Variant = Data.passive(String(pid)).get("modifiers", [])
				if not (mods is Array):
					continue
				for m: Variant in mods:
					if m is Dictionary and String((m as Dictionary).get("stat", "")) == "stat_salgi":
						var lv: Variant = (m as Dictionary).get("levels", [])
						if lv is Array and not (lv as Array).is_empty():
							b += float((lv as Array)[mini(lvl, (lv as Array).size()) - 1])
	if b > _salgi_base + 0.001:
		var d: float = b - _salgi_base
		_salgi_base = b
		_add_salgi(d)
	elif b < _salgi_base - 0.001:
		_salgi_base = b


# ─── 신명 ──────────────────────────────────────────────────────────────

func add_sinmyeong(d: float) -> void:
	if Game.sinmyeong_oreum or d <= 0.0:
		return  # oreum_gain_ignored
	var t: float = Game.time_sec()
	if t - _oreum_end_t < _post_window:
		d *= _post_mult
	Game.sinmyeong = clampf(Game.sinmyeong + d, 0.0, 1.0)
	Events.sinmyeong_changed.emit(Game.sinmyeong)
	if Game.sinmyeong >= 1.0 and t - _oreum_end_t >= _min_gap:
		_start_oreum()


func _start_oreum() -> void:
	if Game.autotest:
		print("[haewon] sinmyeong_oreum t=%.1f" % Game.time_sec())
	Game.sinmyeong_oreum = true
	_oreum_left = _oreum_dur
	Events.sinmyeong_oreum.emit(true)


# ─── 틱 18 ─────────────────────────────────────────────────────────────

func sim_thresholds(dt: float) -> void:
	var t: float = Game.time_sec()
	if Game.run_active and not Game.player_dead and Game.hp_max > 0.0:
		_hp_t += dt
		if Game.hp < _hp_low_ratio * Game.hp_max:
			_hp_low_t += dt
	_base_tick += 1
	if _base_tick >= 30:   # 0.5초마다 기본치(패시브 점지 반영)
		_base_tick = 0
		_refresh_salgi_base()
	if Game.sinmyeong_oreum:
		_oreum_left -= dt
		Game.sinmyeong = clampf(_oreum_left / _oreum_dur, 0.0, 1.0)
		if _oreum_left <= 0.0:
			Game.sinmyeong_oreum = false
			Game.sinmyeong = 0.0
			_oreum_end_t = t
			Events.sinmyeong_oreum.emit(false)
			Events.sinmyeong_changed.emit(0.0)
	elif Game.sinmyeong >= 1.0 and t - _oreum_end_t >= _min_gap:
		_start_oreum()   # 최소 간격 때문에 미뤄진 오름
	# 살 거두기(밟기)
	if Game.player != null and g_count > 0:
		var p: Vector2 = Game.player.global_position
		var r2: float = _pick_r * _pick_r
		for i in GRAIN_CAP:
			if g_alive[i] != 0:
				var dx: float = g_x[i] - p.x
				var dy: float = g_y[i] - p.y
				if dx * dx + dy * dy <= r2:
					grains_collected += int(g_w[i])
					byeoksa_gise = minf(1.0, byeoksa_gise + _gise_per_grain * g_w[i])
					g_alive[i] = 0
					g_count -= 1
	# 원귀 회귀
	if _pending_wongwi.size() > 0:
		var th: int = _pending_wongwi[0]
		_pending_wongwi.remove_at(0)
		_wongwi_return(th)
	# 지연 스폰(알갱이가 뭉친 뒤)
	var k: int = 0
	while k < _wg_n:
		if t >= _wg_t[k]:
			_spawn_wongwi(_wg_sp[k], Vector2(_wg_x[k], _wg_y[k]))
			_wg_n -= 1
			_wg_t[k] = _wg_t[_wg_n]
			_wg_x[k] = _wg_x[_wg_n]
			_wg_y[k] = _wg_y[_wg_n]
			_wg_sp[k] = _wg_sp[_wg_n]
			continue
		k += 1


## 고리가 기색에 묶은 적(ring_closure 가 부름). 그 기색 시간 안에 흰 무구로 풀리면 고리 해원으로 센다.
func mark_ring_bound(slot: int, handle: int) -> void:
	if slot >= 0 and slot < _bound_h.size():
		_bound_h[slot] = handle
		_bound_until[slot] = Game.time_sec() + _bound_dur


## 고리 가중 넋 비율 N. 보스 결말 판정(waves neok_ratio / enemies n_ratio)이 이것을 쓰면 고리가 흰 무구 자동 해원보다 무겁다.
func n_ratio() -> float:
	var tot: float = n_w_haewon + n_w_toechi
	return n_w_haewon / tot if tot > 0.0 else 0.5


func ring_haewon_share() -> float:
	var tot: int = haewon_ring + haewon_white + haewon_other
	return float(haewon_ring) / float(tot) if tot > 0 else 0.0


func hp_low_share() -> float:
	return _hp_low_t / _hp_t if _hp_t > 0.0 else 0.0


func _on_run_ended(_result: Dictionary) -> void:
	_print_summary()


func _exit_tree() -> void:
	_print_summary()


## [haewon] 종료 로그(봇 텔레메트리): 고리 해원 몫(목표 ≥25%), 대신 맞기 수, HP 75% 미만 체류(목표 25~40%).
func _print_summary() -> void:
	if _summary_done or not Game.autotest:
		return
	_summary_done = true
	var subs: int = 0
	var den_small: int = 0
	var den_cd: int = 0
	var rings: int = 0
	var bound: int = 0
	if Game.run_root != null:
		var yt: YeonggaTrain = Game.run_root.get("yeongga") as YeonggaTrain
		if yt != null:
			subs = yt.substitutes
			den_small = yt.substitute_denied_small
			den_cd = yt.substitute_denied_cd
		var rc: RingClosure = Game.run_root.get("ring") as RingClosure
		if rc != null:
			rings = rc.closes
			bound = rc.ring_bound_total
	print("[haewon] summary t=%.1f rings=%d haewon ring=%d white=%d other=%d ring_haewon_share=%.3f bound=%d bound_released=%d n_ratio_w=%.3f substitutes=%d sub_denied_small=%d sub_denied_cd=%d hp_low75_share=%.3f" % [
		Game.time_sec(), rings, haewon_ring, haewon_white, haewon_other, ring_haewon_share(), bound, haewon_ring_bound, n_ratio(),
		subs, den_small, den_cd, hp_low_share()])


func _wongwi_return(th: int) -> void:
	if _toechi_by_species.is_empty() or Game.player == null:
		return  # skip_if_no_toechi
	var w: float = grains_weight()
	wongwi_returns += 1
	# 신호 먼저: enemies 가 이 신호로 원귀를 직접 세우면(같은 틱 스폰) 그 자리를 모트 목표로 쓰고 여기서는 스폰하지 않는다.
	Events.wongwi_return.emit(th)
	_tg_n = 0
	var em: EnemyManager = Game.enemies as EnemyManager
	if em != null:
		var gt: int = Game.game_tick
		for a in em.active_count:
			var i: int = em.active[a]
			if (em.flags[i] & EnemyManager.F_WONGWI) != 0 and em.spawn_tick[i] == gt and _tg_n < WG_CAP:
				_tg_x[_tg_n] = em.px[i]
				_tg_y[_tg_n] = em.py[i]
				_tg_n += 1
	var external: bool = _tg_n > 0
	var n: int = _tg_n
	var sp: Array = []
	if not external:
		# 자체 스폰(캐논 3.2.6): 남은 알갱이 30개당 1(1~3), 퇴치 상위 3종, 알갱이가 뭉친 뒤(1.2초) 등장
		n = clampi(int(floor(w / float(maxi(_grains_per_wongwi, 1)))), _wongwi_min, _wongwi_max)
		sp = _toechi_by_species.keys()
		sp.sort_custom(func(a2: Variant, b2: Variant) -> bool: return int(_toechi_by_species[a2]) > int(_toechi_by_species[b2]))
		var p: Vector2 = Game.player.global_position
		var base_ang: float = Rng.range_s(&"spawn", 0.0, TAU)
		var t: float = Game.time_sec()
		for j in n:
			if _wg_n >= WG_CAP or _tg_n >= WG_CAP:
				break
			var ang: float = base_ang + TAU * float(j) / float(n)
			var tp: Vector2 = p + Vector2(cos(ang), sin(ang)) * 6.0 * K.UNIT_PX
			_wg_sp[_wg_n] = StringName(String(sp[j % mini(sp.size(), 3)]))
			_wg_x[_wg_n] = tp.x
			_wg_y[_wg_n] = tp.y
			_wg_t[_wg_n] = t + _wongwi_fx_time
			_wg_n += 1
			_tg_x[_tg_n] = tp.x
			_tg_y[_tg_n] = tp.y
			_tg_n += 1
	# 연출: 남은 알갱이가 떠올라 원귀 자리로 날아간다(모트). 알갱이는 모두 쓰인다(clears_map_algaengi).
	m_n = 0
	var vfx: VfxPlayer = Game.vfx as VfxPlayer
	var j2: int = 0
	for i2 in GRAIN_CAP:
		if g_alive[i2] == 0:
			continue
		g_alive[i2] = 0
		if m_n < MOTE_CAP and _tg_n > 0:
			var target: int = j2 % _tg_n
			m_x[m_n] = g_x[i2]
			m_y[m_n] = g_y[i2]
			m_tx[m_n] = _tg_x[target]
			m_ty[m_n] = _tg_y[target]
			m_t[m_n] = 0.0
			m_delay[m_n] = Rng.range_s(&"fx", 0.0, 0.35)
			m_n += 1
			if vfx != null and j2 < 32:
				vfx.play(&"vfx_wongwi_rise", Vector2(g_x[i2], g_y[i2]))
		j2 += 1
	g_count = 0
	if Game.autotest:
		print("[haewon] wongwi_return th=%d t=%.1f grains_w=%.0f wongwi=%d by=%s species=%s" % [
			th, Game.time_sec(), w, n, "enemies" if external else "haewon", str(sp.slice(0, 3))])


func _spawn_wongwi(sp: StringName, pos: Vector2) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	em.spawn(sp, pos, {"wongwi": true, "elite_plus": true, "han_mult": _wg_han, "no_recycle": true})
	var vfx: VfxPlayer = Game.vfx as VfxPlayer
	if vfx != null:
		vfx.play(&"vfx_wongwi_form", pos)
	Juice.add_trauma(0.35)


# ─── 정적 질의(다른 모듈이 읽음) ─────────────────────────────────────────

## 살기 연속식: 출현량 배율(1 + 살기 × 0.5%).
static func spawn_mult() -> float:
	return 1.0 + Game.salgi * Data.num("combat_core", "salgi.effect_continuous.spawn_per_point", 0.005)


## 정예 확률 가산(살기 × 0.5%p).
static func elite_chance_bonus() -> float:
	return Game.salgi * Data.num("combat_core", "salgi.effect_continuous.elite_chance_per_point", 0.005)


## 적 한 배율(1 + 살기 × 0.2%).
static func han_mult() -> float:
	return 1.0 + Game.salgi * Data.num("combat_core", "salgi.effect_continuous.han_per_point", 0.002)


## 신명 오름 중 장단(쿨다운 배율) 가산: −0.15 (= 쿨 ×(stat_jangdan − 0.15)).
static func jangdan_bonus() -> float:
	return Data.num("combat_core", "sinmyeong.jangdan_bonus", -0.15) if Game.sinmyeong_oreum else 0.0


## 무구 하나의 ritual_ref(캐논 3.2.3a: Lv1 10 … Lv8 28, 진화형 36, 결합 40). 무구 모듈과 느슨하게(동적 접근) 묶는다.
static func _ritual_ref_of(w: Object) -> int:
	var id: String = String(w.get("id"))
	if id.begins_with("union_"):
		return 40
	if id.begins_with("evo_"):
		return 36
	return RITUAL_REF[clampi(int(w.get("level")), 1, 8) - 1]


static func _is_white(w: Object) -> bool:
	var c: int = int(w.get("color"))
	return c == K.DmgColor.WHITE or c == K.DmgColor.UNION


## 보유 백 무구 ritual_ref 최댓값(없으면 aura_fallback_base 10). 캐논 3.2.3a.
static func ritual_ref_top() -> float:
	var wm: Node = Game.weapons
	var best: int = 0
	if wm != null and wm.has_method("slot_count"):
		var n: int = int(wm.call("slot_count"))
		for i in n:
			var w: Object = wm.call("weapon_at", i)
			if w != null and _is_white(w):
				best = maxi(best, _ritual_ref_of(w))
	return float(best) if best > 0 else Data.num("combat_core", "yeongga.aura_fallback_base", 10.0)


## 보유 백 무구 ritual_ref 합(없으면 10).
static func ritual_ref_sum() -> float:
	var wm: Node = Game.weapons
	var s: int = 0
	if wm != null and wm.has_method("slot_count"):
		var n: int = int(wm.call("slot_count"))
		for i in n:
			var w: Object = wm.call("weapon_at", i)
			if w != null and _is_white(w):
				s += _ritual_ref_of(w)
	return float(s) if s > 0 else Data.num("combat_core", "ring.dmg_fallback_sum", 10.0)


# ─── 연출 ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var adt: float = Game.anim_dt
	if m_n > 0:
		var alive: int = 0
		for k in m_n:
			if m_delay[k] > 0.0:
				m_delay[k] -= adt
				alive += 1
				continue
			m_t[k] = minf(1.0, m_t[k] + adt / maxf(_wongwi_fx_time - 0.35, 0.2))
			if m_t[k] < 1.0:
				alive += 1
		if alive == 0:
			m_n = 0
	if g_count > 0 or m_n > 0 or _sal_had:
		_sal_layer.queue_redraw()
		_sal_had = g_count > 0 or m_n > 0
	# 색동 테두리: 계단 페이드(인 0.15s / 아웃 0.45s)
	var want: float = 1.0 if Game.sinmyeong_oreum else 0.0
	if _brd_a < want:
		_brd_a = minf(want, _brd_a + delta / 0.15)
	elif _brd_a > want:
		_brd_a = maxf(want, _brd_a - delta / 0.45)
	if _brd_a > 0.0:
		_brd_t += delta
		_border.queue_redraw()
		# 신명 오름: 무당 둘레 황빛(오컬트 조명, 박 머리에 부풂)
		var pl: Player = Game.player as Player
		if pl != null:
			var pulse: float = pow(1.0 - Beat.beat_phase(), 2.0)
			Juice.light_frame(pl.render_pos + Vector2(0, -14), 70.0 + 10.0 * pulse, (0.45 + 0.25 * pulse) * _brd_a, 2)
	elif _brd_vis:
		_border.queue_redraw()
	_brd_vis = _brd_a > 0.0
	if _bn_t < _bn_dur + 0.3:
		_bn_t += delta
		_banner.queue_redraw()


func _draw_sal() -> void:
	var t: float = Game.anim_time()
	for i in GRAIN_CAP:
		if g_alive[i] == 0:
			continue
		var w: float = g_w[i]
		var fx: Dictionary = _sal_fx[0 if w < 2.0 else (1 if w < 5.0 else 2)]
		var regions: Array = fx["regions"]
		if regions.is_empty():
			continue
		var fps: float = float(fx["fps"])
		var fi: int = int(floorf(t * fps + float(i) * 0.37)) % regions.size()
		var age: float = t - g_born[i]
		var lift: float = 0.0
		if age < 0.2:
			lift = -3.0 if age < 0.1 else -1.0   # 떨어져 박힘
		var pv: Vector2 = fx["pivot"]
		var pos: Vector2 = Vector2(roundf(g_x[i] - pv.x), roundf(g_y[i] - pv.y + lift))
		var r: Rect2 = regions[fi]
		_sal_layer.draw_texture_rect_region(fx["texture"], Rect2(pos, r.size), r)
	# 원귀 회귀 모트: 먹 알갱이가 떠올라(0.3) 원귀 자리로 빨려 듦, 붉은 심
	for k in m_n:
		if m_delay[k] > 0.0 or m_t[k] >= 1.0:
			continue
		var u: float = m_t[k]
		var rise: float = minf(u / 0.3, 1.0)
		var fly: float = clampf((u - 0.3) / 0.7, 0.0, 1.0)
		fly = fly * fly * fly
		var a: Vector2 = Vector2(m_x[k], m_y[k] - 14.0 * rise)
		var b: Vector2 = Vector2(m_tx[k], m_ty[k] - 18.0)
		var p: Vector2 = a.lerp(b, fly).round()
		var tail: Vector2 = a.lerp(b, maxf(0.0, fly - 0.12)).round()
		_sal_layer.draw_line(tail, p, Color(K.COL_MEOK_2, 0.8), 1.0)
		_sal_layer.draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), K.COL_MEOK)
		_sal_layer.draw_rect(Rect2(p, Vector2(1, 1)), K.COL_JEOK)


func _draw_border() -> void:
	if _brd_a <= 0.0:
		return
	var regions: Array = _brd_fx.get("regions", [])
	if regions.is_empty():
		return
	var fi: int = int(floorf(_brd_t * float(_brd_fx["fps"]))) % regions.size()
	var vs: Vector2 = _border.get_viewport_rect().size
	# 박 맥동: 박 머리 1.0 → 0.7 (계단 4단)
	var ph: float = Beat.beat_phase()
	var pulse: float = 0.7 + 0.3 * floorf(pow(1.0 - ph, 2.0) * 4.0) / 4.0
	var a: float = (1.0 if _brd_a >= 0.99 else (0.5 if _brd_a > 0.33 else 0.25)) * pulse
	# 오름 마지막 3초: 0.25s 간격 점멸(곧 끝남 예고)
	if Game.sinmyeong_oreum and _oreum_left < 3.0 and fmod(_oreum_left, 0.5) < 0.25:
		a *= 0.45
	var r: Rect2 = regions[fi]
	_border.draw_texture_rect_region(_brd_fx["texture"], Rect2(Vector2.ZERO, vs), r, Color(1, 1, 1, a))


func _draw_banner() -> void:
	if _bn_t >= _bn_dur + 0.3 or _bn_text == "" or _font == null:
		return
	var vs: Vector2 = _banner.get_viewport_rect().size
	var base_px: int = int(roundf(float(_bn_px) * BANNER_SCALE))   # 붓 글꼴은 명목 px 보다 작게 보여 ×1.25(640×360 기준 획이 살아 보이게)
	# 가장자리에 머물도록 글 폭 상한 280px(글 가운데가 화면 가운데 상자 x 0.25W 밖) — 넘치면 크기를 낮춘다
	var bw0: float = _font.get_string_size(_bn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, base_px).x
	if bw0 > 280.0:
		base_px = maxi(16, int(floorf(float(base_px) * 280.0 / bw0)))
	var sz: int = base_px
	var off: Vector2 = Vector2.ZERO
	if _bn_t < 0.05:
		sz = int(base_px * 1.6)
	elif _bn_t < 0.1:
		sz = int(base_px * 1.25)
		off = Vector2(0, 2)
	elif _bn_t < 0.15:
		off = Vector2(0, -1)
	var a: float = 1.0
	if _bn_t > _bn_dur:
		a = 0.5 if _bn_t < _bn_dur + 0.15 else 0.0
	if a <= 0.0:
		return
	var tw: float = _font.get_string_size(_bn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	# 가장자리 추임새 자리(x 0.14 / 0.86, y 0.62): 무당 안전 상자(무당 화면 좌표 ±72, −72~+16)를 비운다(design/18 §2.1).
	var cx: float = vs.x * (0.14 if _bn_side == 0 else 0.86)
	var px0: float = clampf(cx - tw * 0.5, 8.0, maxf(8.0, vs.x - 8.0 - tw))
	var pos: Vector2 = Vector2(roundf(px0), roundf(vs.y * 0.62 + sz * 0.5)) + off
	vis_rects["pos:brush"] = [Rect2(pos.x, pos.y - float(sz) * 0.8, tw, float(sz)), Engine.get_process_frames()]
	var outline: Color = K.COL_JEOK if _bn_toechi else K.COL_MEOK
	var fill: Color = K.COL_HANJI
	_banner.draw_string_outline(_font, pos + Vector2(1, 2), _bn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 8, Color(K.COL_MEOK, 0.6 * a))
	_banner.draw_string_outline(_font, pos, _bn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(outline, a))
	_banner.draw_string(_font, pos, _bn_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(fill, a))
	# 슬램 순간 붓 획 밑줄(먹 → 황 점)
	if _bn_t < _bn_dur:
		var y: float = pos.y + 4.0
		_banner.draw_rect(Rect2(Vector2(pos.x + 2.0, y), Vector2(tw - 4.0, 2.0)), Color(outline, 0.85 * a))
		_banner.draw_rect(Rect2(Vector2(pos.x + tw - 4.0, y - 1.0), Vector2(3.0, 3.0)), Color(K.COL_HWANG, a))
