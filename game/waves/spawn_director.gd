class_name SpawnDirector
extends Node
## 스폰 디렉터 + 20분 굿판 타임라인. 소유: waves. 데이터: waves_stage1.json (+ spawn_tables.json 공통 규칙,
## combat_core.json run_end 정산 흐름). 시뮬(L2): run.gd 틱 6 에서 sim_step. 연출은 자식 WavePresenter(L3)가 Events 로 받는다.
##
## 흐름(08 7장·8.8):
##   RUN        분당 공급(target/floor/주기, 창 배율 시련·중간보스·합일, 살기 연속식, 첫 등장 게이트)
##              + 이벤트(예고 wave_warn → 발동 wave_event): 풀릴 기색 시범, 떼몰이, 창귀 행렬, 에워싸기, 상차림(뒷전)
##              + 정예 예약표(시련 창·중간보스 연기, 살기 추가 정예) + 10:00 중간보스(90초 제한)
##              + scripted(첫 무리·고리 가이드·합일·마지막 행렬·작두 강림) + lighting(ambient_changed)
##              + 18:35 작두 강림 40초(박마다 충격파, 정기 낮을수록 강함) + 19:15 뒷전 공물상 7 · 대해원
##   PRE_CLEAR  19:55 스폰 정지, 19:58 퇴송(풀릴 기색 = 해원, 나머지 = 물러남 + 구슬 50%)
##   SILENCE    20:00 정적 2초(금줄 굿청 형성) → BOSS 역려(20:00 진입 순간 넋 비율 N 으로 한형/살형)
##   RESOLVED   보스 해결 → 손님 배송 2초 → SETTLE
##   SETTLE     N_final = N ± 0.10 ≥ 0.50 → 사자의 읍 / 미만 → 살 거둠(덩어리 3 × 30초, 원귀 저지) / 23:00 미해결 → 굿판 닫힘
##   DONE       Events.stage_finished(result) → core(run.gd) 가 Game.end_run(result.victory, result) → Events.run_ended
##
## 적 진형 이동(떼몰이 직진·에워싸기 수축·뒷전 공물 유인)은 EnemyManager.spawn opts 로 요청만 한다
## (march_dir/march_speed_u/march_sec, march_target/march_stop_u, event). 지원 전에는 일반 추적 AI 로 다가온다.

const Formations := preload("res://waves/wave_formations.gd")
const PresenterScript := preload("res://waves/wave_presenter.gd")

enum Phase { RUN, PRE_CLEAR, SILENCE, BOSS, RESOLVED, SETTLE, DONE }
enum TrialSt { NONE, WARN, ACTIVE, POST }

const BUF_N: int = 2560

var enabled: bool = true
var phase: int = Phase.RUN

# ── 공통 규칙(director)
var cap_alive: int = 400
var event_cap_bonus: int = 80
var refill_per_tick: int = 12
var floor_ratio: float = 0.5
var stage_density: float = 1.0
var r_min: float = 12.5 * 32.0
var r_max: float = 15.0 * 32.0
var front_cone: float = deg_to_rad(60.0)
var w_front: float = 0.5
var w_side: float = 0.35
var idle_uniform_after: float = 2.0
var salgi_spawn_per_point: float = 0.005
var salgi_elite_per_point: float = 0.005
var salgi_han_per_point: float = 0.002
var wm_trial_warn: float = 0.8
var wm_trial: float = 0.6
var wm_post: float = 0.7
var wm_post_sec: float = 15.0
var wm_post_ramp: float = 10.0
var wm_midboss: float = 0.5
var elite_trial_excl: float = 10.0

# ── 분 표(컴파일): {min_alive, interval, batch, ids, w, gate, windows:[{from,to,min_alive,interval,batch,ids,w,gate}]}
var _minutes: Array[Dictionary] = []
var _first_appear: Dictionary = {}
var _boss_adds: Dictionary = {}

# 현재 공급 상태(틱마다 바뀌지 않으면 그대로)
var _cur_key: int = -999
var _cur_ids: Array[StringName] = []
var _cur_w: PackedFloat32Array = PackedFloat32Array()
var _cur_gate: PackedFloat32Array = PackedFloat32Array()
var _cur_min_alive: int = 12
var _cur_interval: float = 2.0
var _cur_batch: int = 1
var _interval_left: float = 0.0
var _minute: int = -1
var _started: bool = false
var _idle_t: float = 0.0
var _opts_common: Dictionary = {"han_mult": 1.0}

# ── 시련 창(Events)
var _trial_st: int = TrialSt.NONE
var _trial_t: float = 0.0
var _hapil_stop_until: float = -1.0
var window_mult: float = 1.0                 # 읽기 전용(HUD/디버그)

# ── 이벤트·정예·scripted·조명
var _events: Array[Dictionary] = []          # {t, id, params, cond, st(0 대기,1 예고,2 발동), warn, geo}
var _elites: Array[Dictionary] = []          # {t, id, count, placement, defer_trial, defer_mb, st, ang, extra...}
var _scripted: Array[Dictionary] = []
var _scr_idx: int = 0
var _lighting: Array[Dictionary] = []
var _light_idx: int = 0
var _signatures: PackedFloat32Array = PackedFloat32Array()
var _sig_window: float = 2.0
var _tele: Dictionary = {}
var _rt: Dictionary = {}

# ── 중간보스
var _mb_time: float = 600.0
var _mb_limit: float = 90.0
var _mb_state: int = 0                       # 0 대기 1 예고 2 생존 3 끝
var _mb_h: int = -1
var _mb_species: StringName = &""
var _mb_ang: float = 0.0
var _mb_post_until: float = -1.0
var _mb_post_mult: float = 0.7

# ── 작두 강림(18:35)
var jakdu_active: bool = false
var _jk_start: float = 1115.0
var _jk_end: float = 1155.0
var _jk_beat_pending: bool = false
var _jk_beat_idx: int = 0
var jakdu_pulses: int = 0

# ── 뒷전(19:15) — 읽기 전용(WavePresenter)
var dw_active: bool = false
var dw_pos: PackedVector2Array = PackedVector2Array()
var dw_serv: PackedInt32Array = PackedInt32Array()
var dw_radius: float = 96.0
var dw_count: int = 0
var dw_t0: float = 0.0
var _dw_drain_left: float = 0.0

# ── 보스·정산 — 읽기 전용(WavePresenter)
var pre_clear_t: float = 1198.0
var _spawn_stop_t: float = 1195.0
var boss_time: float = 1200.0
var _silence_sec: float = 2.0
var boss_h: int = -1
var boss_species: StringName = &"boss_yeokryeo"
var boss_form: StringName = &""
var boss_kind: StringName = &""
var arena_center: Vector2 = Vector2.ZERO
var arena_r: float = 11.0 * 32.0
var _arena_slowed: bool = false
var _forced_saja_t: float = 1380.0
var n_at_boss: float = 0.5
var n_final: float = 0.5
var route: StringName = &""
var settle_t: float = 0.0
var _phase_t: float = 0.0
var lumps: PackedVector2Array = PackedVector2Array()
var lump_idx: int = 0
var lump_t: float = 0.0
var _lump_wongwi: PackedInt32Array = PackedInt32Array()
var lumps_done: int = 0
var wongwi_done: int = 0
var _prog_emit_left: float = 0.0
var _fallback_clear_at: float = -1.0
var saja_h: int = -1                         # enemies 가 저승사자 개체를 만들었으면 그 핸들
var _saja_done_at: float = -1.0              # 개체 저승사자가 정산 완료 신호를 낸 settle_t
var _result: Dictionary = {}

# ── 넋 비율 N(캐논 3.2.6a): 가중 해원 / (가중 해원 + 가중 퇴치)
var _nw_haewon: float = 0.0
var _nw_toechi: float = 0.0
var _toechi_by_sp: Dictionary = {}

var _buf: PackedInt32Array = PackedInt32Array()
var presenter: Node = null

# ── 자동 테스트 훅
var _dbg_n: float = -1.0                     # --waves-n=<0..1>: 넋 비율 강제(정산 경로 검증)
var _dbg_resolve: StringName = &""           # --waves-boss-resolve=haewon|toechi: 보스 등장 뒤 강제 해결
var _dbg_resolve_after: float = 6.0          # --waves-boss-resolve-after=<초>

# ── 첫 굿판 보조(waves_stage1.first_run_assist, onboarding first_gutpan_assist 의 값싼 부분)
var assist: bool = false                     # 읽기 전용: 이번 런에 보조가 켜졌나
var assist_no_wongwi: bool = false           # 읽기 전용: haewon 원귀 회귀를 끄라는 뜻(haewon 이 본다)
var _assist_until: float = 0.0
var _assist_mult: float = 1.0
var _first_run: bool = false
var _giun_hint_t: float = -1.0               # 이 시각 이후 hint_requested(&"giun") 한 번(ui 길잡이가 중복을 거른다)


func _ready() -> void:
	_buf.resize(BUF_N)
	_init_assist()
	_load()
	if OS.is_debug_build():
		_lint_banned_words()
	Events.geori_changed.connect(_on_geori)
	Events.trial_warn.connect(func(_s: int, _d: StringName, _in: float) -> void: _set_trial(TrialSt.WARN))
	Events.trial_start.connect(func(_s: int, _d: StringName) -> void: _set_trial(TrialSt.ACTIVE))
	Events.trial_end.connect(func(_s: int, _d: StringName, _w: StringName) -> void: _set_trial(TrialSt.POST))
	Events.trial_phase_changed.connect(_on_trial_phase)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.ring_closed.connect(_on_ring_closed)
	Events.beat.connect(_on_beat)
	Events.settlement_progress.connect(_on_settlement_progress)
	if Game.autotest:
		var dn: String = DebugTools.arg("waves-n")
		if dn != "":
			_dbg_n = clampf(float(dn), 0.0, 1.0)
		_dbg_resolve = StringName(DebugTools.arg("waves-boss-resolve"))
		var da: String = DebugTools.arg("waves-boss-resolve-after")
		if da != "":
			_dbg_resolve_after = float(da)
	presenter = PresenterScript.new()
	presenter.name = "WavePresenter"
	presenter.set("director", self)
	add_child(presenter)


# ─── 데이터 ────────────────────────────────────────────────────────────

func _load() -> void:
	var W: String = "waves_stage1"
	cap_alive = int(Data.num(W, "director.cap_alive", 400))
	event_cap_bonus = int(Data.num(W, "director.event_cap_bonus", 80))
	refill_per_tick = int(Data.num(W, "director.refill_per_tick", 12))
	floor_ratio = Data.num(W, "director.floor_ratio", 0.5)
	stage_density = Data.num(W, "multipliers.stage_density", 1.0)
	r_min = Data.num(W, "director.spawn_ring.r_min", 12.5) * K.UNIT_PX
	r_max = Data.num(W, "director.spawn_ring.r_max", 15.0) * K.UNIT_PX
	front_cone = deg_to_rad(Data.num(W, "director.spawn_ring.dir_weights.front_cone_deg", 60.0))
	w_front = Data.num(W, "director.spawn_ring.dir_weights.front", 0.5)
	w_side = Data.num(W, "director.spawn_ring.dir_weights.side", 0.35)
	idle_uniform_after = Data.num(W, "director.spawn_ring.idle_uniform_after_sec", 2.0)
	salgi_spawn_per_point = Data.num(W, "director.salgi_continuous.spawn_per_point", 0.005)
	salgi_elite_per_point = Data.num(W, "director.salgi_continuous.elite_chance_per_point", 0.005)
	salgi_han_per_point = Data.num(W, "director.salgi_continuous.han_per_point", 0.002)
	wm_trial_warn = Data.num(W, "director.window_mult.trial_warn", 0.8)
	wm_trial = Data.num(W, "director.window_mult.trial", 0.6)
	wm_post = Data.num(W, "director.window_mult.post_trial", 0.7)
	wm_post_sec = Data.num(W, "director.window_mult.post_trial_sec", 15.0)
	wm_post_ramp = Data.num(W, "director.window_mult.post_trial_ramp_sec", 10.0)
	wm_midboss = Data.num(W, "director.window_mult.midboss", 0.5)
	elite_trial_excl = Data.num(W, "director.elite_trial_exclusion_sec", 10.0)
	_first_appear = Data.get_value(W, "first_appear_sec", {})
	_tele = Data.get_value(W, "telegraph", {})
	_rt = Data.get_value(W, "runtime", {})
	# 분 표 컴파일
	_minutes.clear()
	for mv: Variant in Data.get_value(W, "minutes", []):
		if not (mv is Dictionary):
			continue
		var m: Dictionary = mv
		var e: Dictionary = _compile_pool(m.get("pool", []))
		e["min_alive"] = int(m.get("min_alive", 20))
		e["interval"] = float(m.get("interval_sec", 1.0))
		e["batch"] = int(m.get("batch", 1))
		var wins: Array[Dictionary] = []
		var wv: Variant = m.get("pool_windows", [])
		if wv is Array:
			for w: Variant in wv:
				if w is Dictionary:
					var wd: Dictionary = w
					var c: Dictionary = _compile_pool(wd.get("pool", [])) if wd.has("pool") else {}
					c["from"] = float(wd.get("from_sec", 0))
					c["to"] = float(wd.get("to_sec", 0))
					c["min_alive"] = int(wd.get("min_alive", -1))
					c["interval"] = float(wd.get("interval_sec", -1.0))
					c["batch"] = int(wd.get("batch", -1))
					wins.append(c)
		e["windows"] = wins
		_minutes.append(e)
	var ad: Variant = Data.get_value(W, "boss.adds", {})
	if ad is Dictionary:
		_boss_adds = _compile_pool((ad as Dictionary).get("pool", []))
		_boss_adds["min_alive"] = int((ad as Dictionary).get("min_alive", 40))
		_boss_adds["interval"] = float((ad as Dictionary).get("interval_sec", 1.0))
		_boss_adds["batch"] = int((ad as Dictionary).get("batch", 3))
	# 이벤트
	_events.clear()
	for ev: Variant in Data.get_value(W, "events", []):
		if ev is Dictionary:
			var id: String = String(ev.get("id", ""))
			_events.append({"t": float(ev.get("time_sec", 0)), "id": StringName(id), "params": ev.get("params", {}),
				"cond": String(ev.get("condition", "")), "st": 0, "warn": _warn_sec(id), "geo": {}})
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	# 정예
	var defer_all: bool = bool(Data.get_value(W, "director.elite_defer_if_in_trial", true))
	_elites.clear()
	for el: Variant in Data.get_value(W, "elites", []):
		if el is Dictionary:
			var d: Dictionary = (el as Dictionary).duplicate()
			d["t"] = float(d.get("time_sec", 0))
			d["st"] = 0
			d["defer_trial"] = defer_all or bool(d.get("defer_if_in_trial", false))
			d["defer_mb"] = bool(d.get("defer_if_midboss_alive", false))
			d["ang"] = 0.0
			if assist:
				_assist_replace_elite(d)
			_elites.append(d)
	_elites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	# scripted / lighting
	_scripted.clear()
	for s: Variant in Data.get_value(W, "scripted", []):
		if s is Dictionary:
			_scripted.append(s)
	_scripted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("time_sec", 0)) < float(b.get("time_sec", 0)))
	_signatures.clear()
	for s: Dictionary in _scripted:
		if s.has("hero_window_sec"):
			_signatures.append(float(s.get("time_sec", 0)))
			_sig_window = float(s.get("hero_window_sec", 2.0))
	_lighting.clear()
	for l: Variant in Data.get_value(W, "lighting", []):
		if l is Dictionary:
			_lighting.append(l)
	_lighting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("start_sec", 0)) < float(b.get("start_sec", 0)))
	# 중간보스·보스
	_mb_time = Data.num(W, "midboss.time_sec", 600.0)
	_mb_limit = Data.num(W, "midboss.time_limit_sec", 90.0)
	_mb_post_mult = Data.num(W, "midboss.post_breather_mult", 0.7)
	boss_time = Data.num(W, "boss_time_sec", 1200.0)
	pre_clear_t = Data.num(W, "boss.pre_clear_sec", 1198.0)
	_spawn_stop_t = Data.num(W, "boss.spawn_stop_sec", 1195.0)
	_silence_sec = Data.num(W, "boss.silence_sec", 2.0)
	boss_species = StringName(String(Data.get_value(W, "boss.id", "boss_yeokryeo")))
	arena_r = Data.num(W, "boss.arena.radius", 11.0) * K.UNIT_PX
	_forced_saja_t = Data.num(W, "forced_saja_sec", 1380.0)
	_jk_start = Data.num(W, "jakdu_ganglim.start_sec", 1115.0)
	_jk_end = _jk_start + Data.num(W, "jakdu_ganglim.duration_sec", 40.0)
	dw_radius = Data.num(W, "geori_dwitjeon_rules.effect_radius", 3.0) * K.UNIT_PX


## 표시 문자열 금지어 검사(디버그 빌드, 로드 1회): waves_stage1 의 *_ko 문자열에 loc_glossary banned_words.ko 가 있으면
## push_error → godot_check 실패. '~다' 동사는 어간으로 본다('죽이다' → '죽이지 말고'도 걸린다).
func _lint_banned_words() -> void:
	var bv: Variant = Data.get_value("narrative/loc_glossary", "banned_words.ko", [])
	if not (bv is Array):
		return
	var stems: PackedStringArray = PackedStringArray()
	for w: Variant in bv:
		var ws: String = String(w)
		if ws.length() >= 3 and ws.ends_with("다"):
			ws = ws.left(ws.length() - 1)
		if ws != "":
			stems.append(ws)
	_lint_walk(Data.tables.get("waves_stage1", {}), "waves_stage1", "", stems)


func _lint_walk(v: Variant, path: String, key: String, stems: PackedStringArray) -> void:
	if v is Dictionary:
		for k: Variant in (v as Dictionary).keys():
			_lint_walk((v as Dictionary)[k], path + "." + String(k), String(k), stems)
	elif v is Array:
		for i in (v as Array).size():
			_lint_walk((v as Array)[i], "%s[%d]" % [path, i], key, stems)
	elif v is String and (key.ends_with("_ko") or key == "ko"):
		for st: String in stems:
			if (v as String).contains(st):
				push_error("[waves] 금지어 '%s' in %s: %s" % [st, path, v])


## 첫 굿판 보조 판정: Save.first_run_pending() 또는 끝낸 판 수 < runs_done_lt. --waves-assist=on|off(autotest)로 강제.
func _init_assist() -> void:
	_first_run = Save.first_run_pending()
	var av: Variant = Data.get_value("waves_stage1", "first_run_assist", {})
	var A: Dictionary = av if av is Dictionary else {}
	var on: bool = bool(A.get("enabled", false)) and (_first_run or Save.runs_done() < int(A.get("runs_done_lt", 2)))
	if Game.autotest:
		var fa: String = DebugTools.arg("waves-assist")
		if fa == "on":
			on = true
		elif fa == "off":
			on = false
	assist = on
	assist_no_wongwi = on and bool(A.get("no_wongwi_return", true))
	_assist_until = float(A.get("until_sec", 180.0)) if on else 0.0
	_assist_mult = float(A.get("spawn_budget_mult", 0.8)) if on else 1.0
	# 기운 안내: 첫 판은 기운 바가 열린 뒤(10:52), 이후 판은 120초(onboarding hint_giun)
	_giun_hint_t = Data.num("waves_stage1", "giun_hint.first_run_sec", 652.0) if _first_run 		else Data.num("waves_stage1", "giun_hint.later_sec", 120.0)


## 보조 중 정예 대체(어둑시니 → 거구귀): 처음 하는 사람에게 시야 가림 정예를 늦춘다.
func _assist_replace_elite(d: Dictionary) -> void:
	var rv: Variant = Data.get_value("waves_stage1", "first_run_assist.replace_elites", {})
	if not (rv is Dictionary):
		return
	var rid: String = Data.resolve_id(String(d.get("id", "")))
	for k: Variant in (rv as Dictionary).keys():
		if Data.resolve_id(String(k)) != rid:
			continue
		var to: String = Data.resolve_id(String((rv as Dictionary)[k]))
		if Data.enemy(to).is_empty():
			return
		d["id"] = to
		d.erase("variant")
		d.erase("fallback")
		d.erase("tutorial_card")
		d["placement"] = "ring"
		return


func _compile_pool(pool: Variant) -> Dictionary:
	var ids: Array[StringName] = []
	var w: PackedFloat32Array = PackedFloat32Array()
	var gate: PackedFloat32Array = PackedFloat32Array()
	# 재가집 의뢰 종 출현 배율(meta Save.active_uiroe_mods().species_weight) — core 통합(meta 요청)
	var uw: Dictionary = {}
	var um: Variant = Save.active_uiroe_mods().get("species_weight", {})
	if um is Dictionary:
		uw = um
	if pool is Array:
		for pv: Variant in pool:
			if not (pv is Dictionary):
				continue
			var id: String = Data.resolve_id(String(pv.get("id", "")))
			if id == "" or Data.enemy(id).is_empty():
				continue
			ids.append(StringName(id))
			w.append(float(pv.get("weight", 1)) * float(uw.get(id, 1.0)))
			gate.append(maxf(float(pv.get("from_sec", 0)), float(_first_appear.get(id, 0))))
	return {"ids": ids, "w": w, "gate": gate}


func _warn_sec(id: String) -> float:
	var evs: Dictionary = _tele.get("events", {})
	if evs.has(id):
		return float((evs[id] as Dictionary).get("warn_sec", _tele.get("default_warn_sec", 3.0)))
	return float(_tele.get("default_warn_sec", 3.0))


func _tele_text(id: String) -> Dictionary:
	var evs: Dictionary = _tele.get("events", {})
	if evs.has(id):
		return evs[id]
	var sc: Dictionary = _tele.get("scripted", {})
	return sc.get(id, {})


func _rtf(path: String, default: float) -> float:
	return Data.num("waves_stage1", "runtime." + path, default)


# ─── 신호 ──────────────────────────────────────────────────────────────

func _on_geori(geori_id: StringName, _bpm: float, _j: StringName) -> void:
	if String(geori_id) == "geori_myeongbu":
		return  # 보스 음악은 형태가 정해진 뒤(_spawn_boss)
	for g: Variant in Data.get_value("waves_stage1", "geori", []):
		if g is Dictionary and String(g.get("id", "")) == String(geori_id) and g.has("bgm_cue"):
			if _mb_state == 2:
				return  # 중간보스 음악 유지
			Events.music_cue.emit(StringName(String(g["bgm_cue"])))


func _set_trial(st: int) -> void:
	if st == _trial_st:
		return
	if st == TrialSt.POST and _trial_st == TrialSt.NONE:
		return
	_trial_st = st
	_trial_t = 0.0


func _on_trial_phase(_slot: int, _deity: StringName, ph: StringName) -> void:
	match ph:
		&"omen":
			_set_trial(TrialSt.WARN)
		&"descend", &"confirm", &"clear", &"trial", &"resolve", &"possession", &"jeomji", &"afterglow":
			_set_trial(TrialSt.ACTIVE)
		&"dormant":
			if _trial_st == TrialSt.ACTIVE or _trial_st == TrialSt.WARN:
				_set_trial(TrialSt.POST)


func _on_beat(idx: int, _down: bool) -> void:
	_jk_beat_pending = true
	_jk_beat_idx = idx


func _on_enemy_killed(h: int, sp: StringName, _pos: Vector2, kind: StringName, _cause: StringName, tier: StringName) -> void:
	if h == boss_h and boss_h >= 0:
		if phase == Phase.BOSS:
			boss_kind = kind
			_resolve_boss()
		return
	if h == _mb_h and _mb_h >= 0 and _mb_state == 2:
		_mb_state = 3
		_log("midboss resolved %s kind=%s in %.1fs" % [String(sp), String(kind), Game.time_sec() - _mb_time])
		_mb_post_until = Game.time_sec() + Data.num("waves_stage1", "midboss.post_breather_sec", 20.0)
		_restore_geori_music()
	for k in _lump_wongwi.size():
		if _lump_wongwi[k] == h:
			_lump_wongwi[k] = -1
			wongwi_done += 1
	var w: float = 0.0
	match tier:
		K.TIER_COMMON, K.TIER_MINION:
			w = 1.0
		K.TIER_ELITE:
			w = 5.0
		K.TIER_MBOSS:
			w = 20.0
	if w <= 0.0:
		return
	if kind == K.KIND_HAEWON:
		_nw_haewon += w
	else:
		_nw_toechi += w
		_toechi_by_sp[sp] = int(_toechi_by_sp.get(sp, 0)) + 1


## 캐논 3.2.6a sys_neok_ratio. 분모 0 이면 0.5. EnemyManager.n_ratio()(07 정본)가 있으면 그것을 쓴다.
func neok_ratio() -> float:
	if _dbg_n >= 0.0:
		return _dbg_n
	var em: EnemyManager = Game.enemies as EnemyManager
	if em != null and em.has_method("n_ratio"):
		return float(em.call("n_ratio"))
	var s: float = _nw_haewon + _nw_toechi
	return 0.5 if s <= 0.0 else _nw_haewon / s


# ─── 틱 6 ──────────────────────────────────────────────────────────────

func sim_step(dt: float) -> void:
	if not enabled:
		return
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null or Game.player == null:
		return
	var t: float = Game.time_sec()
	if not _started:
		_started = true
		_skip_past(t, em)
		if assist:
			Events.wave_event.emit(&"first_run_assist", {"until_sec": _assist_until, "spawn_mult": _assist_mult,
				"no_wongwi_return": assist_no_wongwi})
			_log("first_run_assist on until=%.0f mult=%.2f" % [_assist_until, _assist_mult])
	if _giun_hint_t >= 0.0 and t >= _giun_hint_t and phase == Phase.RUN and _trial_st != TrialSt.ACTIVE 			and _trial_st != TrialSt.WARN and _mb_state != 2:
		_giun_hint_t = -1.0
		Events.hint_requested.emit(&"giun")
	var m: int = int(t / 60.0)
	if m != _minute:
		_minute = m
		Events.minute_changed.emit(m)
	_update_trial(dt)
	_update_idle(dt)
	_run_lighting(t)
	_run_scripted(t, em)
	_phase_t += dt
	match phase:
		Phase.RUN:
			window_mult = _window_mult(t)
			if t < _spawn_stop_t:
				_select_entry(t)
				_supply(dt, em, window_mult, _cur_ids, _cur_w, _cur_gate, _cur_min_alive, _cur_interval, _cur_batch, t)
			_run_events(t, em)
			_run_elites(t, em)
			_run_midboss(t, em)
			_run_jakdu(t, em)
			_run_dwitjeon(t, dt, em)
			if t >= boss_time - _warn_sec("boss") and not _boss_warned:
				_boss_warned = true
				_emit_warn(&"boss", _warn_sec("boss"), {"species": boss_species})
				Events.boss_incoming.emit(boss_species)
			if t >= pre_clear_t:
				_pre_clear(em)
		Phase.PRE_CLEAR:
			_run_dwitjeon(t, dt, em)
			if _fallback_clear_at > 0.0 and t >= _fallback_clear_at:
				_fallback_clear_at = -1.0
				em.clear_all()
			if t >= boss_time:
				_begin_silence()
		Phase.SILENCE:
			if t >= boss_time + _silence_sec:
				_spawn_boss(em)
		Phase.BOSS:
			_supply(dt, em, 1.0, _boss_adds.get("ids", _cur_ids), _boss_adds.get("w", _cur_w), _boss_adds.get("gate", _cur_gate),
				int(_boss_adds.get("min_alive", 40)), float(_boss_adds.get("interval", 1.0)), int(_boss_adds.get("batch", 3)), t)
			_arena_step()
			if _dbg_resolve != &"" and _phase_t >= _dbg_resolve_after and boss_h >= 0 and em.slot_of(boss_h) >= 0:
				var bs: int = em.slot_of(boss_h)
				_dbg_resolve_after = 1e9
				if _dbg_resolve == K.KIND_HAEWON:
					em.force_haewon(bs, &"debug")
					if em.is_alive(bs) and em.has_method("kill_now"):
						em.call("kill_now", bs, K.KIND_HAEWON, &"debug")
				else:
					em.force_toechi(bs, &"debug")
			elif boss_h >= 0 and em.slot_of(boss_h) < 0 and boss_kind == &"":
				boss_kind = K.KIND_TOECHI  # 신호를 놓친 경우(외부 clear 등)
				_resolve_boss()
			elif t >= _forced_saja_t:
				_begin_settlement(&"timeout")
		Phase.RESOLVED:
			if _phase_t >= _rtf("settlement.sonnim_baesong_sec", 2.0):
				_begin_settlement(&"saja_bow" if n_final >= 0.5 else &"sal_geodum")
		Phase.SETTLE:
			_settle_step(dt, t, em)
		_:
			pass


var _boss_warned: bool = false


## --start-sec 로 중간에서 시작하면 지난 예약은 건너뛴다(한꺼번에 발동하지 않게).
func _skip_past(t: float, em: EnemyManager) -> void:
	if t < 1.0:
		return
	for e: Dictionary in _events:
		if float(e["t"]) < t - 0.5:
			e["st"] = 2
	for e: Dictionary in _elites:
		if float(e["t"]) < t - 0.5:
			e["st"] = 2
	while _scr_idx < _scripted.size() and float(_scripted[_scr_idx].get("time_sec", 0)) < t - 0.5:
		var s: Dictionary = _scripted[_scr_idx]
		_scr_idx += 1
		if String(s.get("id", "")) == "jakdu_ganglim" and t < _jk_end:
			_jakdu_begin()
	if t > _mb_time + _mb_limit:
		_mb_state = 3
	var dws: float = Data.num("waves_stage1", "geori_dwitjeon_rules.start_sec", 1155.0)
	if t >= dws and t < pre_clear_t:
		_dwitjeon_begin(em)
	if t >= pre_clear_t:
		_boss_warned = true
	if t >= boss_time:
		boss_time = t
		_begin_silence()
		boss_time = t - _silence_sec   # 다음 틱에 바로 보스


func _update_trial(dt: float) -> void:
	if _trial_st == TrialSt.NONE:
		return
	_trial_t += dt
	if _trial_st == TrialSt.POST and _trial_t >= wm_post_sec + wm_post_ramp:
		_trial_st = TrialSt.NONE
	elif _trial_st == TrialSt.ACTIVE and _trial_t > 75.0:
		_set_trial(TrialSt.POST)  # 종료 신호 유실 안전장치(시련 묶음 최대 54초)
	elif _trial_st == TrialSt.WARN and _trial_t > 30.0:
		_set_trial(TrialSt.ACTIVE)


func _update_idle(dt: float) -> void:
	var p: Player = Game.player as Player
	if p != null and p.vel.length_squared() > 4.0:
		_idle_t = 0.0
	else:
		_idle_t += dt


func _in_trial_window() -> bool:
	return _trial_st == TrialSt.ACTIVE or (_trial_st == TrialSt.POST and _trial_t < elite_trial_excl)


func _window_mult(t: float) -> float:
	if t < _hapil_stop_until:
		return 0.0
	var m: float = 1.0
	match _trial_st:
		TrialSt.WARN:
			m = wm_trial_warn
		TrialSt.ACTIVE:
			m = wm_trial
		TrialSt.POST:
			if _trial_t < wm_post_sec:
				m = wm_post
			else:
				m = lerpf(wm_post, 1.0, clampf((_trial_t - wm_post_sec) / maxf(0.01, wm_post_ramp), 0.0, 1.0))
	if _mb_state == 2:
		m = minf(m, wm_midboss)
	elif t < _mb_post_until:
		m = minf(m, _mb_post_mult)
	if assist and t < _assist_until:
		m *= _assist_mult
	return m


func _select_entry(t: float) -> void:
	if _minutes.is_empty():
		return
	var mi: int = clampi(int(t / 60.0), 0, _minutes.size() - 1)
	var e: Dictionary = _minutes[mi]
	var wi: int = -1
	var wins: Array[Dictionary] = e["windows"]
	for k in wins.size():
		if t >= float(wins[k]["from"]) and t < float(wins[k]["to"]):
			wi = k
			break
	var key: int = mi * 16 + wi + 1
	if key == _cur_key:
		return
	_cur_key = key
	_cur_ids = e["ids"]
	_cur_w = e["w"]
	_cur_gate = e["gate"]
	_cur_min_alive = int(e["min_alive"])
	_cur_interval = float(e["interval"])
	_cur_batch = int(e["batch"])
	if wi >= 0:
		var w: Dictionary = wins[wi]
		if w.has("ids") and not (w["ids"] as Array).is_empty():
			_cur_ids = w["ids"]
			_cur_w = w["w"]
			_cur_gate = w["gate"]
		if int(w["min_alive"]) >= 0:
			_cur_min_alive = int(w["min_alive"])
		if float(w["interval"]) > 0.0:
			_cur_interval = float(w["interval"])
		if int(w["batch"]) > 0:
			_cur_batch = int(w["batch"])


## 08 5.1: target = min_alive × 밀도 × 살기 × 창, floor = target × 0.5 즉시 보충(틱당 12), 주기 공급(alive ≥ target 이면 생략).
func _supply(dt: float, em: EnemyManager, wmult: float, ids: Array[StringName], w: PackedFloat32Array, gate: PackedFloat32Array,
		min_alive: int, interval: float, batch: int, t: float) -> void:
	if wmult <= 0.0 or ids.is_empty():
		return
	var salgi: float = Game.salgi
	_opts_common["han_mult"] = 1.0 + salgi_han_per_point * salgi
	var target: int = mini(int(float(min_alive) * stage_density * (1.0 + salgi_spawn_per_point * salgi) * wmult), cap_alive)
	var floor_n: int = int(float(target) * floor_ratio)
	var alive: int = em.active_count
	if alive < floor_n:
		var n: int = mini(floor_n - alive, refill_per_tick)
		for k in n:
			_spawn_pick(em, ids, w, gate, t)
	_interval_left -= dt
	if _interval_left <= 0.0:
		_interval_left = maxf(0.05, interval / wmult)
		if em.active_count < target:
			for b in batch:
				_spawn_pick(em, ids, w, gate, t)


func _spawn_pick(em: EnemyManager, ids: Array[StringName], w: PackedFloat32Array, gate: PackedFloat32Array, t: float) -> void:
	var sum: float = 0.0
	for k in w.size():
		if t >= gate[k]:
			sum += w[k]
	if sum <= 0.0:
		return
	var r: float = Rng.randf_s(&"spawn") * sum
	var pick: int = -1
	for k in w.size():
		if t >= gate[k]:
			pick = k
			r -= w[k]
			if r < 0.0:
				break
	if pick >= 0:
		em.spawn(ids[pick], ring_point(), _opts_common)


## 스폰 링 위 한 점(이동 방향 앞쪽 가중, 2초 이상 정지면 균등).
func ring_point() -> Vector2:
	return Game.player.global_position + Vector2.from_angle(_ring_angle()) * Rng.range_s(&"spawn", r_min, r_max)


func _ring_angle() -> float:
	var p: Player = Game.player as Player
	var fwd: float = p.last_move_dir.angle() if p != null else 0.0
	if _idle_t >= idle_uniform_after:
		return Rng.range_s(&"spawn", 0.0, TAU)
	var roll: float = Rng.randf_s(&"spawn")
	if roll < w_front:
		return fwd + Rng.range_s(&"spawn", -front_cone * 0.5, front_cone * 0.5)
	elif roll < w_front + w_side:
		var side: float = 1.0 if Rng.randf_s(&"spawn") < 0.5 else -1.0
		return fwd + side * Rng.range_s(&"spawn", front_cone * 0.5, PI * 0.75)
	return fwd + PI + Rng.range_s(&"spawn", -PI * 0.25, PI * 0.25)


func _fwd() -> Vector2:
	var p: Player = Game.player as Player
	var f: Vector2 = p.last_move_dir if p != null else Vector2.DOWN
	return f.normalized() if f.length_squared() > 0.0001 else Vector2.DOWN


func _event_room(em: EnemyManager) -> int:
	return maxi(0, cap_alive + event_cap_bonus - em.active_count)


## 주인공 창(7장): 시그니처 시작 후 2초 안에는 대형 이벤트를 시작하지 않는다 → 창 끝으로 민다.
func _hero_delay(t: float) -> float:
	for s: float in _signatures:
		if t >= s and t < s + _sig_window:
			return s + _sig_window
	return t


func _emit_warn(id: StringName, in_sec: float, geo: Dictionary) -> void:
	var p: Dictionary = geo.duplicate()
	var tx: Dictionary = _tele_text(String(id))
	p["title_ko"] = String(tx.get("title_ko", ""))
	p["hint_ko"] = String(tx.get("hint_ko", ""))
	Events.wave_warn.emit(id, in_sec, p)
	_log("warn %s in %.1fs" % [id, in_sec])


func _log(msg: String) -> void:
	if Game.autotest:
		print("[waves] %s %s" % [K.fmt_time(Game.time_sec()), msg])


# ─── 이벤트 ────────────────────────────────────────────────────────────

func _run_events(t: float, em: EnemyManager) -> void:
	for e: Dictionary in _events:
		var st: int = int(e["st"])
		if st == 2:
			continue
		var at: float = float(e["t"])
		var warn: float = float(e["warn"])
		if st == 0:
			if t < at - warn:
				break
			var id: StringName = e["id"]
			if String(e["cond"]) == "no_haewon_yet" and Game.kills_haewon > 0:
				e["st"] = 2
				_log("skip %s (haewon %d)" % [id, Game.kills_haewon])
				continue
			if _is_major(id):
				var nt: float = _hero_delay(at)
				if nt != at:
					e["t"] = nt
					continue
			e["geo"] = _event_geometry(id, e["params"])
			e["st"] = 1
			if warn > 0.0:
				_emit_warn(id, at - t, e["geo"])
			st = 1
		if st == 1 and t >= float(e["t"]):
			e["st"] = 2
			_fire_event(e, em)


func _is_major(id: StringName) -> bool:
	return id == &"evt_ttemolli" or id == &"evt_ewossagi" or id == &"evt_changgwi_haengnyeol"


## 예고 시점에 방향을 정한다(플레이어 기준 상대 기하 — 발동 시 그때의 플레이어 위치에 놓는다).
func _event_geometry(id: StringName, params: Dictionary) -> Dictionary:
	var fwd: Vector2 = _fwd()
	match id:
		&"evt_ttemolli":
			var groups: Array = params.get("groups", [])
			var dirs: PackedVector2Array = PackedVector2Array()
			var starts: PackedVector2Array = PackedVector2Array()
			var widths: PackedFloat32Array = PackedFloat32Array()
			var speeds: PackedFloat32Array = PackedFloat32Array()
			var side: float = 1.0 if Rng.randf_s(&"event") < 0.5 else -1.0
			var perp: Vector2 = Vector2(-fwd.y, fwd.x) * side
			var sd: float = _rtf("ttemolli.start_dist_u", 18.0) * K.UNIT_PX
			var fo: float = _rtf("ttemolli.fwd_offset_u", 4.0) * K.UNIT_PX
			var stg: float = _rtf("ttemolli.group_fwd_stagger_u", 2.5) * K.UNIT_PX
			for gi in groups.size():
				var g: Dictionary = groups[gi]
				var d: Vector2 = perp
				var dn: String = String(g.get("direction", ""))
				if g.has("direction_deg"):
					d = Formations.dir_from_deg(float(g["direction_deg"]))
				elif dn == "perp_opposite":
					d = -perp
				var off: Vector2 = fwd * (fo + stg * float(gi)) - d * sd
				dirs.append(d)
				starts.append(off)
				widths.append(float(g.get("width", 4.0)) * K.UNIT_PX)
				speeds.append(float(g.get("speed", 2.2)) * K.UNIT_PX)
			return {"kind": &"band", "dirs": dirs, "starts": starts, "widths": widths, "speeds": speeds,
				"cross_px": _shown_cross(_rtf("ttemolli.cross_len_u", 36.0) * K.UNIT_PX, sd)}
		&"evt_ewossagi":
			var gaps: PackedFloat32Array = PackedFloat32Array()
			var ng: int = int(params.get("gaps", 1))
			var cone: float = deg_to_rad(_rtf("ewossagi.gap_cone_deg", 30.0))
			gaps.append(fwd.angle() + Rng.range_s(&"event", -cone, cone))
			for k in range(1, ng):
				gaps.append(gaps[0] + TAU * float(k) / float(ng) + Rng.range_s(&"event", -0.4, 0.4))
			var R: float = float(params.get("radius", 9.0)) * K.UNIT_PX
			return {"kind": &"ring", "radius_px": R, "gaps": gaps,
				"gap_half": (float(params.get("gap_width", 2.5)) * K.UNIT_PX * 0.5) / R,
				"stop_px": float(params.get("stop_radius", 3.0)) * K.UNIT_PX,
				"shrink_px": float(params.get("shrink_speed", 0.8)) * K.UNIT_PX}
		&"evt_changgwi_haengnyeol":
			var d2: Vector2 = Formations.dir_from_deg(float(params.get("direction_deg", 270)))
			var from: Vector2 = Formations.dir_from_name(String(params.get("from", "north")))
			if from == Vector2.ZERO:
				from = -d2
			var dist: float = _rtf("changgwi.shield_dist_u", 13.0) * K.UNIT_PX
			var dirs2: PackedVector2Array = PackedVector2Array([d2])
			var starts2: PackedVector2Array = PackedVector2Array([from * dist])
			return {"kind": &"column", "dirs": dirs2, "starts": starts2,
				"widths": PackedFloat32Array([4.0 * K.UNIT_PX]),
				"speeds": PackedFloat32Array([float(params.get("speed", 1.8)) * K.UNIT_PX]), "cross_px": _shown_cross(dist * 2.0, dist)}
		&"evt_pullil_demo":
			return {"kind": &"arc", "ang": fwd.angle()}
		&"evt_sangcharim":
			return {"kind": &"none"}
	return {"kind": &"none"}


## 떼 진로 표시 길이. EnemyManager 가 진형 직진(march_* opts)을 지원하면 화면 횡단 전체, 아니면 일반 추적 AI 로
## 플레이어에게 모여드므로 '출발점 → 플레이어 옆'까지만 그린다(지키지 못할 진로를 보여 주지 않는다).
## TODO(enemies): spawn opts march_dir/march_speed_u/march_sec(직진)·march_target/march_stop_u(수축) 지원 + supports_march() -> true.
func _shown_cross(full_px: float, start_dist_px: float) -> float:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em != null and em.has_method("supports_march") and bool(em.call("supports_march")):
		return full_px
	return minf(full_px, start_dist_px + _rtf("march_fallback_extra_u", 3.0) * K.UNIT_PX)


func _fire_event(e: Dictionary, em: EnemyManager) -> void:
	var id: StringName = e["id"]
	var params: Dictionary = e["params"]
	var geo: Dictionary = e["geo"]
	var pp: Vector2 = Game.player.global_position
	var out: Dictionary = params.duplicate()
	out.merge(geo, true)
	out["origin"] = pp
	var spawned: int = 0
	match id:
		&"evt_pullil_demo":
			spawned = _evt_pullil_demo(params, em)
		&"evt_ttemolli":
			spawned = _evt_ttemolli(params, geo, pp, em)
		&"evt_ewossagi":
			spawned = _evt_ewossagi(params, geo, pp, em)
		&"evt_changgwi_haengnyeol":
			spawned = _evt_changgwi(params, geo, pp, em)
		&"evt_sangcharim":
			_dwitjeon_begin(em)
			out["tables"] = dw_pos
			out["radius_px"] = dw_radius
	out["spawned"] = spawned
	var tx: Dictionary = _tele_text(String(id))
	out["title_ko"] = String(tx.get("title_ko", ""))
	out["hint_ko"] = String(tx.get("hint_ko", ""))
	Events.wave_event.emit(id, out)
	_log("event %s spawned=%d alive=%d" % [id, spawned, em.active_count])


func _spawn_list(em: EnemyManager, species: Array, pts: PackedVector2Array, opts: Dictionary) -> int:
	var room: int = _event_room(em)
	var n: int = 0
	for k in pts.size():
		if n >= room:
			break
		var sp: StringName = StringName(Data.resolve_id(String(species[k % species.size()])))
		if em.spawn(sp, pts[k], opts) >= 0:
			n += 1
	return n


## 풀릴 기색 시범(온보딩): 플레이어 앞 호(arc).
func _evt_pullil_demo(params: Dictionary, em: EnemyManager) -> int:
	var sp: String = String(params.get("species", "enm_dalgyal_gwisin"))
	var n: int = int(params.get("count", 6))
	var dist: float = float(params.get("distance", 7.0)) * K.UNIT_PX
	var pts: PackedVector2Array = Formations.arc(Game.player.global_position, _fwd().angle(),
		deg_to_rad(_rtf("pullil_demo.arc_deg", 90.0)), dist, n)
	return _spawn_list(em, [sp], pts, {"han_ratio": float(params.get("han_ratio", 1.0)), "event": true})


## 떼몰이(5.4.1): 진행 방향 직교로 화면을 가로지르는 떼. 수명 = 횡단 거리/속도 + 2초.
func _evt_ttemolli(params: Dictionary, geo: Dictionary, pp: Vector2, em: EnemyManager) -> int:
	var groups: Array = params.get("groups", [])
	var dirs: PackedVector2Array = geo.get("dirs", PackedVector2Array())
	var starts: PackedVector2Array = geo.get("starts", PackedVector2Array())
	var spacing: float = _rtf("ttemolli.spacing_u", 0.9) * K.UNIT_PX
	var jit: float = _rtf("ttemolli.jitter_u", 0.2) * K.UNIT_PX
	var cross: float = float(geo.get("cross_px", 36.0 * K.UNIT_PX))
	var total: int = 0
	for gi in mini(groups.size(), dirs.size()):
		var g: Dictionary = groups[gi]
		var d: Vector2 = dirs[gi]
		var spd_u: float = float(g.get("speed", 2.2))
		var pts: PackedVector2Array = Formations.band(pp + starts[gi], d, float(g.get("width", 4.0)) * K.UNIT_PX,
			int(g.get("count", 20)), spacing, jit, &"event")
		var opts: Dictionary = {"no_recycle": true, "event": true, "march_dir": d, "march_speed_u": spd_u,
			"march_sec": cross / (spd_u * K.UNIT_PX) + _rtf("ttemolli.lifetime_pad_sec", 2.0), "han_mult": _opts_common["han_mult"]}
		total += _spawn_list(em, g.get("species", ["enm_dalgyal_gwisin"]), pts, opts)
	return total


## 에워싸기(5.4.2): 반경 R 원 + 진행 방향 틈. 수축 v 로 stop_radius 까지.
func _evt_ewossagi(params: Dictionary, geo: Dictionary, pp: Vector2, em: EnemyManager) -> int:
	var R: float = float(geo.get("radius_px", 9.0 * K.UNIT_PX))
	var pts: PackedVector2Array = Formations.ring_with_gaps(pp, R, int(params.get("count", 28)), geo.get("gaps", PackedFloat32Array()),
		float(geo.get("gap_half", 0.14)), _rtf("ewossagi.ring_jitter_u", 0.15) * K.UNIT_PX, &"event")
	var v_u: float = float(params.get("shrink_speed", 0.8))
	var stop_u: float = float(params.get("stop_radius", 3.0))
	var opts: Dictionary = {"no_recycle": true, "event": true, "march_target": pp, "march_speed_u": v_u, "march_stop_u": stop_u,
		"march_sec": (R / K.UNIT_PX - stop_u) / maxf(0.1, v_u) + 1.0, "han_mult": _opts_common["han_mult"]}
	return _spawn_list(em, params.get("species", ["enm_yeongsan"]), pts, opts)


## 창귀 행렬(선바위 굿당 고유): 앞줄 잡귀(방패) + 뒷줄 호식 원혼이 고정 방향(산 쪽)에서 내려온다.
func _evt_changgwi(params: Dictionary, geo: Dictionary, pp: Vector2, em: EnemyManager) -> int:
	var d: Vector2 = (geo.get("dirs", PackedVector2Array([Vector2.DOWN])) as PackedVector2Array)[0]
	var start: Vector2 = pp + (geo.get("starts", PackedVector2Array([Vector2.UP * 13.0 * K.UNIT_PX])) as PackedVector2Array)[0]
	var spd_u: float = float(params.get("speed", 1.8))
	var life: float = 30.0 * K.UNIT_PX / (spd_u * K.UNIT_PX) + 2.0
	var spacing: float = _rtf("changgwi.spacing_u", 0.9) * K.UNIT_PX
	var shield_n: int = int(params.get("shield_count", 16))
	var lead_n: int = int(params.get("leader_count", 4))
	var opts: Dictionary = {"no_recycle": true, "event": true, "march_dir": d, "march_speed_u": spd_u, "march_sec": life,
		"han_mult": _opts_common["han_mult"]}
	var shield_w: float = ceil(sqrt(float(shield_n))) * spacing
	var pts: PackedVector2Array = Formations.band(start, d, shield_w, shield_n, spacing, spacing * 0.15, &"event")
	var n: int = _spawn_list(em, [String(params.get("shield", "enm_dalgyal_gwisin"))], pts, opts)
	var back: Vector2 = start - d * (_rtf("changgwi.leader_back_u", 2.5) * K.UNIT_PX + shield_w * 0.5)
	var lpts: PackedVector2Array = Formations.band(back, d, float(lead_n - 1) * _rtf("changgwi.leader_spacing_u", 1.6) * K.UNIT_PX,
		lead_n, _rtf("changgwi.leader_spacing_u", 1.6) * K.UNIT_PX, 0.0, &"event")
	n += _spawn_list(em, [String(params.get("leader", "enm_hosik_wonhon"))], lpts, opts)
	return n


# ─── 정예 ──────────────────────────────────────────────────────────────

func _elite_blocked(e: Dictionary) -> bool:
	if bool(e["defer_trial"]) and _in_trial_window():
		return true
	if bool(e["defer_mb"]) and _mb_state == 2:
		return true
	return false


func _run_elites(t: float, em: EnemyManager) -> void:
	var warn: float = _warn_sec("elite")
	for e: Dictionary in _elites:
		var st: int = int(e["st"])
		if st == 2:
			continue
		var at: float = float(e["t"])
		if st == 0 and t >= at - warn:
			var nt: float = _hero_delay(at)
			if _elite_blocked(e) or nt != at:
				e["t"] = maxf(nt, t + warn + 0.5)
				continue
			e["ang"] = _elite_angle(String(e.get("placement", "ring")))
			e["st"] = 1
			var sid: StringName = _elite_species(e)
			_emit_warn(&"elite", maxf(0.0, at - t), {"species": sid, "ang": float(e["ang"]),
				"name_ko": String(Data.enemy(String(sid)).get("name", "")), "tutorial": String(e.get("tutorial_card", ""))})
		elif st == 1 and t >= at:
			if _elite_blocked(e):
				e["st"] = 0
				e["t"] = t + warn + 0.5
				continue
			e["st"] = 2
			_spawn_elite(e, em)


func _elite_species(e: Dictionary) -> StringName:
	var id: String = Data.resolve_id(String(e.get("variant", e.get("id", ""))))
	if Data.enemy(id).is_empty():
		id = Data.resolve_id(String(e.get("fallback", e.get("id", ""))))
	return StringName(id)


func _elite_angle(placement: String) -> float:
	var fwd: float = _fwd().angle()
	if placement == "darkest_fog_edge":
		# TODO(waves): 광원·안개 연동 전에는 '무당 등 뒤' 원뿔 = 가장 어두운 쪽으로 본다
		var c: float = deg_to_rad(_rtf("elite.dark_edge_back_cone_deg", 50.0))
		return fwd + PI + Rng.range_s(&"spawn", -c * 0.5, c * 0.5)
	return _ring_angle()


func _spawn_elite(e: Dictionary, em: EnemyManager) -> void:
	var sid: StringName = _elite_species(e)
	if Data.enemy(String(sid)).is_empty():
		_log("elite %s missing" % sid)
		return
	var n: int = int(e.get("count", 1))
	if Rng.chance(&"spawn", clampf(salgi_elite_per_point * Game.salgi, 0.0, 1.0)):
		n += 1  # 살기 추가 정예(08 5.5)
	var dist: float = _rtf("elite.ring_u", 13.0) * K.UNIT_PX
	var ang: float = float(e["ang"])
	var pp: Vector2 = Game.player.global_position
	var hs: Array[int] = []
	for k in n:
		var a: float = ang + (float(k) - float(n - 1) * 0.5) * 0.35
		var h: int = em.spawn(sid, pp + Vector2.from_angle(a) * dist, {"han_mult": _opts_common["han_mult"]})
		if h >= 0:
			hs.append(h)
	Events.wave_event.emit(&"elite", {"species": sid, "count": hs.size(), "handles": hs, "ang": ang,
		"gongsu_key": String(e.get("gongsu_key", "")), "tutorial": String(e.get("tutorial_card", ""))})
	_log("elite %s x%d" % [sid, hs.size()])


# ─── 중간보스 ──────────────────────────────────────────────────────────

func _run_midboss(t: float, em: EnemyManager) -> void:
	match _mb_state:
		0:
			var warn: float = _warn_sec("midboss")
			if t >= _mb_time - warn:
				var pool: Variant = Data.get_value("waves_stage1", "midboss.pool", ["mboss_daegwi"])
				var ws: Variant = Data.get_value("waves_stage1", "midboss.weights", [])
				var items: Array = []
				if pool is Array:
					for k in (pool as Array).size():
						var wv: float = float((ws as Array)[k]) if ws is Array and k < (ws as Array).size() else 1.0
						items.append({"id": String(pool[k]), "weight": wv})
				var idx: int = Rng.pick_weighted_index(&"mboss", items)
				_mb_species = StringName(String(items[idx]["id"])) if idx >= 0 else &"mboss_daegwi"
				var mfix: String = String(Save.active_uiroe_mods().get("mboss_fixed", ""))   # 재가집 의뢰 중간보스 고정(core 통합)
				if mfix != "" and not Data.enemy(mfix).is_empty():
					_mb_species = StringName(mfix)
				_mb_ang = _fwd().angle()
				_mb_state = 1
				_emit_warn(&"midboss", maxf(0.0, _mb_time - t), {"species": _mb_species, "ang": _mb_ang,
					"name_ko": String(Data.enemy(String(_mb_species)).get("name", ""))})
				var stg: String = String(Data.get_value("waves_stage1", "midboss.stinger", ""))
				if stg != "":
					Events.music_cue.emit(StringName(stg))
		1:
			if t >= _mb_time:
				var pp: Vector2 = Game.player.global_position
				_mb_h = em.spawn(_mb_species, pp + Vector2.from_angle(_mb_ang) * _rtf("midboss.spawn_dist_u", 9.0) * K.UNIT_PX, {"no_recycle": true})
				_mb_state = 2 if _mb_h >= 0 else 3
				Events.midboss_incoming.emit(_mb_species)
				var cues: Variant = Data.get_value("waves_stage1", "midboss.bgm_cue", {})
				if cues is Dictionary and (cues as Dictionary).has(String(_mb_species)):
					Events.music_cue.emit(StringName(String(cues[String(_mb_species)])))
				Events.wave_event.emit(&"midboss", {"species": _mb_species, "handle": _mb_h, "limit_sec": _mb_limit})
				_log("midboss %s h=%d" % [_mb_species, _mb_h])
		2:
			if em.slot_of(_mb_h) < 0:
				_mb_state = 3
				_mb_post_until = t + Data.num("waves_stage1", "midboss.post_breather_sec", 20.0)
				_restore_geori_music()
			elif t >= _mb_time + _mb_limit:
				# 미해결: 화면 밖으로 퇴장(보상·살기 변화 없음). despawn 지원 전에는 남겨 두고 웨이브만 정상화.
				_vanish(em, em.slot_of(_mb_h))
				_mb_state = 3
				Events.wave_event.emit(&"midboss_exit", {"species": _mb_species, "line_key": String(Data.get_value("waves_stage1", "midboss.unresolved.line_key", ""))})
				_restore_geori_music()
				_log("midboss unresolved exit")


## 보상·신호 없이 조용히 없앤다(퇴송·중간보스 이탈). EnemyManager.vanish(07) 우선. 없으면 false.
func _vanish(em: EnemyManager, slot: int) -> bool:
	if em.has_method("vanish"):
		em.call("vanish", slot)
		return true
	if em.has_method("despawn"):
		em.call("despawn", slot)
		return true
	return false


func _restore_geori_music() -> void:
	var t: float = Game.time_sec()
	for g: Variant in Data.get_value("waves_stage1", "geori", []):
		if g is Dictionary and t >= float(g.get("start_sec", 0)) and (g.get("end_sec") == null or t < float(g.get("end_sec"))):
			if String(g.get("id", "")) != "geori_myeongbu":
				Events.music_cue.emit(StringName(String(g.get("bgm_cue", ""))))
			return


# ─── scripted · 조명 ───────────────────────────────────────────────────

func _run_lighting(t: float) -> void:
	while _light_idx < _lighting.size() and t >= float(_lighting[_light_idx].get("start_sec", 0)):
		var l: Dictionary = _lighting[_light_idx]
		var fade: float = 0.0 if _light_idx == 0 else (0.6 if float(l.get("start_sec", 0)) < 10.0 else 2.0)
		_light_idx += 1
		Events.ambient_changed.emit(float(l.get("ambient", 0.3)), fade)


func _run_scripted(t: float, em: EnemyManager) -> void:
	while _scr_idx < _scripted.size() and t >= float(_scripted[_scr_idx].get("time_sec", 0)):
		var s: Dictionary = _scripted[_scr_idx]
		_scr_idx += 1
		var id: String = String(s.get("id", ""))
		var p: Dictionary = s.duplicate()
		match id:
			"first_spawn":
				var pts: PackedVector2Array = Formations.arc(Game.player.global_position, _fwd().angle(),
					deg_to_rad(_rtf("first_spawn.arc_deg", 100.0)), float(s.get("distance", 9.0)) * K.UNIT_PX, int(s.get("count", 8)))
				p["spawned"] = _spawn_list(em, [String(s.get("species", "enm_agwi"))], pts, {"event": true})
			"hapil":
				_hapil_stop_until = t + _rtf("hapil_spawn_stop_sec", 1.2)
			"jakdu_ganglim":
				_jakdu_begin()
			"stinger":
				Events.music_cue.emit(StringName(String(s.get("cue", ""))))
		var tx: Dictionary = _tele_text(id)
		p["title_ko"] = String(tx.get("title_ko", ""))
		p["hint_ko"] = String(tx.get("hint_ko", ""))
		Events.wave_event.emit(StringName(id), p)
		_log("scripted %s" % id)


# ─── 작두 강림(18:35, 40초) ────────────────────────────────────────────

func _jakdu_begin() -> void:
	jakdu_active = true
	jakdu_pulses = 0
	_jk_beat_pending = false


func _run_jakdu(t: float, em: EnemyManager) -> void:
	if not jakdu_active:
		return
	if t >= _jk_end:
		jakdu_active = false
		Events.wave_event.emit(&"jakdu_end", {"pulses": jakdu_pulses})
		_log("jakdu end pulses=%d" % jakdu_pulses)
		return
	if not _jk_beat_pending:
		return
	_jk_beat_pending = false
	var every: int = maxi(1, int(Data.num("waves_stage1", "jakdu_ganglim.pulse_beats", 2)))
	if _jk_beat_idx % every != 0:
		return
	var J: String = "waves_stage1"
	var pp: Vector2 = Game.player.global_position
	var r: float = Data.num(J, "jakdu_ganglim.radius_u", 4.5) * K.UNIT_PX
	var hp_ratio: float = clampf(Game.hp / maxf(1.0, Game.hp_max), 0.0, 1.0)
	# 캐논 3.4 '정기 비례 역보정': 정기가 낮을수록 강하다(0 → ×low_hp_bonus_max)
	var mult: float = 1.0 + (Data.num(J, "jakdu_ganglim.low_hp_bonus_max", 1.5) - 1.0) * (1.0 - hp_ratio)
	var dmg: float = Data.num(J, "jakdu_ganglim.damage", 45.0) * mult
	var kb: float = Data.num(J, "jakdu_ganglim.knockback_u", 1.4)
	var n: int = em.query_circle(pp, r, _buf, BUF_N)
	for k in n:
		var s: int = _buf[k]
		if not em.is_alive(s):
			continue
		var d: Vector2 = em.pos_of(s) - pp
		em.queue_hit(s, dmg, K.DmgColor.RED, false, d.normalized() if d.length_squared() > 1.0 else Vector2.RIGHT, kb)
	var p: Player = Game.player as Player
	if p != null and p.hit != null:
		p.hit.iframe_left = maxf(p.hit.iframe_left, Data.num(J, "jakdu_ganglim.iframe_sec", 0.25))
	jakdu_pulses += 1
	Events.wave_event.emit(&"jakdu_pulse", {"pos": pp, "radius_px": r, "mult": mult, "hits": n, "index": jakdu_pulses})


# ─── 뒷전 풀어먹이기(19:15~20:00) ──────────────────────────────────────

func _dwitjeon_begin(_em: EnemyManager) -> void:
	if dw_active:
		return
	var D: String = "waves_stage1"
	var fwd: Vector2 = _fwd()
	var c: Vector2 = Game.player.global_position + fwd * Data.num(D, "geori_dwitjeon_rules.center_offset_forward", 5.0) * K.UNIT_PX
	dw_pos = Formations.hex7(c, Data.num(D, "geori_dwitjeon_rules.spacing", 3.5) * K.UNIT_PX, fwd.angle())
	dw_serv.resize(dw_pos.size())
	dw_serv.fill(int(Data.num(D, "geori_dwitjeon_rules.servings_per_gongmulsang", 2)))
	dw_count = 0
	dw_t0 = Game.time_sec()
	_dw_drain_left = 0.0
	dw_active = true
	_log("dwitjeon tables=%d" % dw_pos.size())


func _run_dwitjeon(_t: float, dt: float, em: EnemyManager) -> void:
	if not dw_active:
		return
	_dw_drain_left -= dt
	if _dw_drain_left > 0.0:
		return
	var tick: float = _rtf("dwitjeon.drain_tick_sec", 1.0)
	_dw_drain_left = tick
	var drain: float = Data.num("waves_stage1", "geori_dwitjeon_rules.han_drain_per_sec", 0.05) * tick
	for i in dw_pos.size():
		if dw_serv[i] <= 0:
			continue
		var n: int = em.query_circle(dw_pos[i], dw_radius, _buf, 256)
		for k in n:
			var s: int = _buf[k]
			if not em.is_alive(s) or (em.flags[s] & EnemyManager.F_PULLIL) != 0:
				continue
			var tier: StringName = em.tier_of(s)
			if tier != K.TIER_COMMON and tier != K.TIER_MINION:
				continue
			em.queue_hit(s, em.han_max[s] * drain, K.DmgColor.WHITE)


## 고리 닫힘(틱 5) → 고리 안 공물상 ≥ bind_min 이면 대해원. 고리 모양 대신 등가 원(면적 → 반경)으로 판정한다.
## TODO(haewon): ring_closed 에 다각형(또는 RingClosure.contains(p))을 주면 정확한 포함 판정으로 바꾼다.
func _on_ring_closed(area_tiles: int, _n: int, centroid: Vector2) -> void:
	if not dw_active:
		return
	var D: String = "waves_stage1"
	if dw_count >= int(Data.num(D, "geori_dwitjeon_rules.daehaewon_max", 4)):
		return
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	var r_eq: float = sqrt(float(area_tiles) / PI) * K.UNIT_PX + _rtf("dwitjeon.bind_slack_u", 0.6) * K.UNIT_PX
	var bound: int = 0
	for i in dw_pos.size():
		if dw_serv[i] > 0 and dw_pos[i].distance_to(centroid) <= r_eq:
			bound += 1
	if bound < int(Data.num(D, "geori_dwitjeon_rules.bind_min", 3)):
		return
	var cnt: int = 0
	var n: int = em.query_circle(centroid, r_eq, _buf, BUF_N)
	for k in n:
		var s: int = _buf[k]
		var tier: StringName = em.tier_of(s)
		if em.is_alive(s) and (tier == K.TIER_COMMON or tier == K.TIER_MINION):
			em.force_haewon(s, &"ring")
			cnt += 1
	n = em.query_circle(Game.player.global_position, _rtf("dwitjeon.screen_radius_u", 12.0) * K.UNIT_PX, _buf, BUF_N)
	for k in n:
		var s2: int = _buf[k]
		if em.is_alive(s2) and (em.flags[s2] & EnemyManager.F_PULLIL) != 0 and em.tier_of(s2) != K.TIER_BOSS:
			em.force_haewon(s2, &"ring")
			cnt += 1
	var bound_idx: PackedInt32Array = PackedInt32Array()
	for i in dw_pos.size():
		if dw_serv[i] > 0 and dw_pos[i].distance_to(centroid) <= r_eq:
			dw_serv[i] -= 1
			bound_idx.append(i)
	var bonus: float = 1.0
	var bt: Variant = Data.get_value(D, "geori_dwitjeon_rules.bonus", {})
	if bt is Dictionary:
		for key: Variant in (bt as Dictionary).keys():
			if bound >= int(String(key)):
				bonus = maxf(bonus, float(bt[key]))
	dw_count += 1
	Events.daehaewon.emit(bound, bonus, centroid, cnt)
	Events.wave_event.emit(&"daehaewon", {"bound": bound, "bonus": bonus, "centroid": centroid, "haewon": cnt,
		"tables": bound_idx, "index": dw_count, "radius_px": r_eq})
	_log("daehaewon bound=%d haewon=%d bonus=%.1f (%d)" % [bound, cnt, bonus, dw_count])


# ─── 퇴송 → 정적 → 보스 ────────────────────────────────────────────────

## 19:58 보스전 화면 정리: 풀릴 기색 = 해원, 나머지 = 퇴송(연기처럼 물러남, 원혼 구슬 50%, 살 없음).
func _pre_clear(em: EnemyManager) -> void:
	phase = Phase.PRE_CLEAR
	_phase_t = 0.0
	var pp: Vector2 = Game.player.global_position
	var n: int = em.query_circle(pp, 40.0 * K.UNIT_PX, _buf, BUF_N)
	var ratio: float = Data.num("waves_stage1", "boss.pre_clear_rule.toesong_orb_ratio", 0.5)
	var vfx_id: StringName = StringName(String(_rt.get("pre_clear", {}).get("toesong_vfx", "vfx_eodukssini_vanish")))
	var vfx_cap: int = int(_rtf("pre_clear.toesong_vfx_cap", 40))
	var can_despawn: bool = em.has_method("vanish") or em.has_method("despawn")
	var vp: VfxPlayer = Game.vfx as VfxPlayer
	var pk: PickupManager = Game.pickups as PickupManager
	var n_h: int = 0
	var n_t: int = 0
	var shown: int = 0
	for k in n:
		var s: int = _buf[k]
		if not em.is_alive(s):
			continue
		if (em.flags[s] & EnemyManager.F_PULLIL) != 0:
			em.force_haewon(s, &"ring")
			n_h += 1
			continue
		var pos: Vector2 = em.pos_of(s)
		var xp: float = float(Data.enemy(String(em.species_id_of(s))).get("xp", 1))
		if pk != null:
			pk.spawn_orb(pos, xp * ratio)
		if vp != null and shown < vfx_cap and absf(pos.x - pp.x) < 11.0 * K.UNIT_PX and absf(pos.y - pp.y) < 7.0 * K.UNIT_PX:
			vp.play(vfx_id, pos)
			shown += 1
		if can_despawn:
			_vanish(em, s)
		n_t += 1
	if not can_despawn:
		_fallback_clear_at = Game.time_sec() + _rtf("pre_clear.fallback_clear_after_sec", 0.6)
	if dw_active:
		dw_active = false
	Events.wave_event.emit(&"pre_clear", {"haewon": n_h, "toesong": n_t})
	_log("pre_clear haewon=%d toesong=%d" % [n_h, n_t])


func _begin_silence() -> void:
	phase = Phase.SILENCE
	_phase_t = 0.0
	n_at_boss = neok_ratio()
	boss_form = _decide_form(n_at_boss)
	arena_center = Game.player.global_position
	Audio.stop_music()
	Events.wave_event.emit(&"boss_silence", {"sec": _silence_sec, "form": boss_form, "n": n_at_boss, "arena_center": arena_center, "arena_r": arena_r})
	_log("silence N=%.3f form=%s" % [n_at_boss, boss_form])


## 캐논 3.4: N ≥ 0.55 한형, ≤ 0.45 살형, 그 사이 살기 ≥ 50 이면 살형.
func _decide_form(n: float) -> StringName:
	var B: String = "waves_stage1"
	if n >= Data.num(B, "boss.form_rule.han_if_neok_ratio_gte", 0.55):
		return &"han"
	if n <= Data.num(B, "boss.form_rule.sal_if_neok_ratio_lte", 0.45):
		return &"sal"
	return &"sal" if Game.salgi >= Data.num(B, "boss.form_rule.tiebreak_salgi_gte_for_sal", 50.0) else &"han"


func _spawn_boss(em: EnemyManager) -> void:
	phase = Phase.BOSS
	_phase_t = 0.0
	var pos: Vector2 = Game.player.global_position + _fwd() * Data.num("waves_stage1", "boss.spawn_dist_u", 8.0) * K.UNIT_PX
	boss_h = em.spawn(boss_species, pos, {"form": boss_form, "no_recycle": true})
	if em.has_method("boss_form_of"):
		# enemies(bigs) 가 형태를 정하고 boss_spawned 를 낸다 — 그쪽 값을 따른다
		var f: StringName = StringName(em.call("boss_form_of", em.slot_of(boss_h))) if boss_h >= 0 else &""
		if f != &"":
			boss_form = f
	else:
		Events.boss_spawned.emit(boss_h, boss_species, boss_form)
	Events.music_cue.emit(StringName("mus_boss_yeokryeo_%s" % boss_form))
	Events.wave_event.emit(&"boss", {"species": boss_species, "form": boss_form, "handle": boss_h, "arena_center": arena_center, "arena_r": arena_r})
	_log("boss %s form=%s h=%d" % [boss_species, boss_form, boss_h])
	if boss_h < 0:
		boss_kind = K.KIND_TOECHI
		_resolve_boss()


func _arena_step() -> void:
	var p: Player = Game.player as Player
	if p == null:
		return
	var outside: bool = p.global_position.distance_to(arena_center) > arena_r
	if outside != _arena_slowed:
		_arena_slowed = outside
		p.speed_mult_ext = Data.num("waves_stage1", "boss.arena.outside_speed_mult", 0.5) if outside else 1.0


func _release_arena() -> void:
	if _arena_slowed:
		_arena_slowed = false
		var p: Player = Game.player as Player
		if p != null:
			p.speed_mult_ext = 1.0


func _resolve_boss() -> void:
	phase = Phase.RESOLVED
	_phase_t = 0.0
	_release_arena()
	var nr: float = neok_ratio()
	n_final = clampf(nr + (0.10 if boss_kind == K.KIND_HAEWON else -0.10), 0.0, 1.0)
	Events.boss_resolved.emit(boss_h, boss_kind, n_final)
	Events.wave_event.emit(&"boss_resolved", {"kind": boss_kind, "n": nr, "n_final": n_final})
	_log("boss resolved kind=%s N=%.3f N_final=%.3f in %.1fs" % [boss_kind, nr, n_final, Game.time_sec() - boss_time])


# ─── 정산 ──────────────────────────────────────────────────────────────

func _begin_settlement(r: StringName) -> void:
	_release_arena()
	route = r
	phase = Phase.SETTLE
	_phase_t = 0.0
	settle_t = 0.0
	lump_idx = 0
	lump_t = 0.0
	lumps_done = 0
	wongwi_done = 0
	lumps.clear()
	_saja_done_at = -1.0
	# 저승사자: enemies(bigs)가 개체를 지원하면 개체가 정산을 맡는다 — 덩어리·원귀 깨움·settlement_started/progress 를
	# bigs 가 낸다(같은 일을 여기서 또 하면 덩어리·배너·음악 큐가 두 번 난다). 디렉터는 완료 신호를 기다려 마무리만 한다.
	saja_h = -1
	var em: EnemyManager = Game.enemies as EnemyManager
	if r == &"timeout" and em != null and boss_h >= 0 and em.slot_of(boss_h) >= 0:
		_vanish(em, em.slot_of(boss_h))  # 굿판이 닫힌다: 역려는 보상·결말 없이 물러난다(사자가 오는 동안 맞지 않게)
	if em != null and em.has_method("boss_form_of"):
		var ro: StringName = &"bow" if r == &"saja_bow" else (&"forced" if r == &"timeout" else &"sal_geodum")
		var sp: Vector2 = Game.player.global_position + Vector2(0, -2.0 * K.UNIT_PX)
		saja_h = em.spawn(StringName(String(Data.get_value("waves_stage1", "settlement.saja_id", "chaser_jeoseung_saja"))), sp,
			{"route": ro, "no_recycle": true})
	if saja_h >= 0:
		_log("settlement %s (saja h=%d)" % [r, saja_h])
		return
	var params: Dictionary = {"route": r, "n_final": n_final, "n": n_at_boss, "form": boss_form}
	if r == &"sal_geodum":
		var E: String = "combat_core"
		var nl: int = int(Data.num(E, "run_end.E3_sal_geodum.lumps", 3))
		var rr: float = Data.num(E, "run_end.E3_sal_geodum.lump_ring_radius_u", 9.0) * K.UNIT_PX
		var a0: float = _fwd().angle()
		lumps.clear()
		for k in nl:
			lumps.append(Game.player.global_position + Vector2.from_angle(a0 + TAU * float(k) / float(nl)) * rr)
		_lump_wongwi.resize(nl)
		_lump_wongwi.fill(-1)
		params["lumps"] = lumps
		_lump_begin(0)
	# 개체 저승사자가 없으면 WavePresenter 가 저승사자를 그리고 덩어리는 여기서 돌린다
	params["saja_handle"] = saja_h
	var tx: Dictionary = _tele_text(String(r))
	params["title_ko"] = String(tx.get("title_ko", ""))
	params["hint_ko"] = String(tx.get("hint_ko", ""))
	Events.settlement_started.emit(r, params)
	_log("settlement %s" % r)


func _lump_begin(k: int) -> void:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null or k >= lumps.size():
		return
	lump_idx = k
	lump_t = 0.0
	var E: String = "combat_core"
	var nw: int = int(Data.num(E, "run_end.E3_sal_geodum.wongwi_per_lump", 1))
	var ne: int = int(Data.num(E, "run_end.E3_sal_geodum.escort_per_lump", 8))
	var top: StringName = _top_toechi_species(k)
	var c: Vector2 = lumps[k]
	for i in nw:
		var h: int = em.spawn(top, c, {"wongwi": true, "elite_plus": true, "no_recycle": true, "han_mult": _rtf("settlement.wongwi_han_mult", 6.0)})
		if i == 0:
			_lump_wongwi[k] = h
	var pts: PackedVector2Array = Formations.ring_with_gaps(c, 1.6 * K.UNIT_PX, ne, PackedFloat32Array(), 0.0, 4.0, &"event")
	_spawn_list(em, [String(top)], pts, {"no_recycle": true, "event": true})
	Events.wave_event.emit(&"sal_lump", {"index": k, "pos": c, "wongwi": top})


## 원귀 원종: 이번 런 퇴치 수 상위 종(07 elite_wongwi.from_species). k 번째 덩어리 = k 번째 순위.
func _top_toechi_species(k: int) -> StringName:
	var em: EnemyManager = Game.enemies as EnemyManager
	if em != null and em.has_method("top_toechi_species"):
		return StringName(em.call("top_toechi_species", k))
	var arr: Array = []
	for sp: Variant in _toechi_by_sp.keys():
		if String(sp).begins_with("enm_"):
			arr.append([int(_toechi_by_sp[sp]), sp])
	arr.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	if arr.is_empty():
		return &"enm_dalgyal_gwisin"
	return StringName(String(arr[mini(k, arr.size() - 1)][1]))


## bigs 저승사자의 진행 신호: done == total 이고 progress 1 이면 정산 끝(사자가 물러나는 동안 기다렸다 마무리).
func _on_settlement_progress(r: StringName, done: int, total: int, progress: float) -> void:
	if phase != Phase.SETTLE or saja_h < 0 or r != route:
		return
	if route == &"sal_geodum":
		lumps_done = done
	if done >= total and progress >= 1.0 and _saja_done_at < 0.0:
		_saja_done_at = settle_t
		_log("settlement %s done by saja (%d/%d)" % [r, done, total])


func _settle_step(dt: float, t: float, em: EnemyManager) -> void:
	settle_t += dt
	if saja_h >= 0:
		if route == &"sal_geodum" and _saja_done_at < 0.0:
			_supply(dt, em, 1.0, _boss_adds.get("ids", _cur_ids), _boss_adds.get("w", _cur_w), _boss_adds.get("gate", _cur_gate),
				int(_rtf("settlement.sal_geodum_trickle_min_alive", 16)), 1.5, 2, t)
		var gone: bool = em.slot_of(saja_h) < 0
		var win: bool = route != &"timeout"
		if _saja_done_at >= 0.0 and (gone or settle_t - _saja_done_at >= _rtf("settlement.saja_exit_wait_sec", 3.2)):
			_finish(win)
		elif gone and _saja_done_at < 0.0:
			_finish(win)  # 사자가 신호 없이 사라짐(외부 정리)
		else:
			var cap: float = _rtf("settlement.saja_max_sec_" + String(route), 150.0 if route == &"sal_geodum" else 20.0)
			if settle_t >= cap:
				_log("settlement %s safety timeout" % route)
				_finish(win)
		return
	match route:
		&"saja_bow":
			if settle_t >= _rtf("settlement.saja_bow_sec", 6.5):
				_finish(true)
		&"timeout":
			if settle_t >= _rtf("settlement.timeout_sec", 3.0):
				_finish(false)
		&"sal_geodum":
			var per: float = Data.num("combat_core", "run_end.E3_sal_geodum.collect_sec_per_lump", 30.0)
			if lump_idx < lumps.size():
				var trickle: int = int(_rtf("settlement.sal_geodum_trickle_min_alive", 16))
				_supply(dt, em, 1.0, _boss_adds.get("ids", _cur_ids), _boss_adds.get("w", _cur_w), _boss_adds.get("gate", _cur_gate),
					trickle, 1.5, 2, t)
				lump_t += dt
				var killed: bool = bool(Data.get_value("combat_core", "run_end.E3_sal_geodum.kill_wongwi_completes_lump", true)) \
					and _lump_wongwi[lump_idx] == -1 and lump_t > 1.0
				var prog: float = clampf(lump_t / per, 0.0, 1.0)
				if killed:
					prog = 1.0
				_prog_emit_left -= dt
				if _prog_emit_left <= 0.0 or prog >= 1.0:
					_prog_emit_left = _rtf("settlement.progress_emit_sec", 0.25)
					Events.settlement_progress.emit(route, lumps_done, lumps.size(), prog)
				if prog >= 1.0:
					lumps_done += 1
					Events.wave_event.emit(&"sal_lump_done", {"index": lump_idx, "pos": lumps[lump_idx]})
					if lumps_done < lumps.size():
						_lump_begin(lumps_done)
					else:
						lump_idx = lumps.size()
						settle_t = 0.0
			elif settle_t >= 3.0:
				_finish(true)


func _finish(victory: bool) -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	_release_arena()
	_result = {
		"victory": victory, "ending": route, "boss_form": boss_form, "boss_kind": boss_kind,
		"n_ratio": n_at_boss, "n_final": n_final, "time_sec": Game.time_sec(),
		"daehaewon": dw_count, "lumps_done": lumps_done, "wongwi_done": wongwi_done,
		"jakdu_pulses": jakdu_pulses,
	}
	Events.stage_finished.emit(_result)
	_log("stage_finished %s" % str(_result))
	_bridge_run_end.call_deferred(victory)


## 안전망: run.gd 가 stage_finished 를 받아 Game.end_run 한다. 신호 처리 뒤에도 런이 열려 있으면(구독 누락) 여기서 닫는다.
func _bridge_run_end(victory: bool) -> void:
	if not Game.run_active:
		return
	var rr: Node = Game.run_root
	if rr != null and is_instance_valid(rr) and rr.has_method("_finish"):
		rr.call("_finish", victory, _result)
	else:
		Game.end_run(victory, _result)
