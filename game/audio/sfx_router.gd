extends Node
## SfxRouter — Events → SFX 매핑. 소유: audio. (구독만 한다 — 시뮬레이션 상태를 바꾸지 않는다)
##
## 해원은 음(音), 퇴치는 타(打) (design/12 A3):
##   해원 = 방울 토리 사다리(11.1: 1.5초 안 연속이면 한 칸씩 위로, 같은 프레임 3개는 화음 i,i−1,i−2, 넘치면 마지막 음 +1.5dB/개)
##        + 풍경(처마 바람종) 한 겹(0.22s 간격 상한) — '딸랑' 위에 맑은 여운이 번진다. 첫 해원은 즉시, 다발은 연출 스냅(≤250ms).
##   퇴치 = 한 파열 '탁'(40ms 히트 집계 → __agg2..4 군집 테이크), 결단타 '싹', 정예 이상은 개별.
## 무구: 발동음은 그리드 위(신호가 이미 양자화) + 슬롯 플램 15ms(최대 75ms). 적중음은 즉시·40ms 집계,
##   무구별 고유 적중음(sfx_wpn_<id>_hit). 적중 신호에 무구 id 가 없어서 색별 '가장 최근 발동 무구'로 귀속한다
##   (TODO(enemies): enemy_hit 에 source 무구 슬롯을 실으면 정확해진다 — queue_hit 의 source_slot).

const Buses = preload("res://audio/audio_buses.gd")
const TORI_GYEONG: PackedInt32Array = [0, 2, 5, 7, 9]     # 국사당 경토리(design/12 6.3) 반음 오프셋
const SAME_FRAME_CAP: int = 3
const HW_RESET: float = 1.5
const ORB_RESET: float = 0.6

var tori: PackedInt32Array = TORI_GYEONG

var _d_haewon: int = -1
var _d_haewon_elite: int = -1
var _d_pung: int = -1
var _d_hanpa: int = -1
var _d_gyeoldan: int = -1
var _d_knot: int = -1
var _d_pullil: int = -1
var _d_orb: int = -1
var _orb_m: AudioStream = null
var _orb_l: AudioStream = null
var _hw_oct1: AudioStream = null

var _wpn_fire: Dictionary = {}        # weapon_id -> def
var _wpn_hit: Dictionary = {}         # weapon_id -> def
var _wpn_white: Dictionary = {}       # weapon_id -> bool
var _last_red: StringName = &""
var _last_white: StringName = &""
# combat 이 알려 주는 적중 무구(정확한 귀속) — 색별 가장 최근 것
var _src_red: int = -1
var _src_white: int = -1
var _src_red_t: float = -10.0
var _src_white_t: float = -10.0
var _def_white: Dictionary = {}       # 적중 정의 -> 백 무구인가
# combat 이 직접 부른 발동음 1건 보류(weapon_fired 가 바로 따라오면 라우터 판으로 대체)
var _xf_d: int = -1
var _xf_vol: float = 0.0
var _xf_pv: float = 0.0
var _xf_t: float = 0.0

# 해원 사다리
var _hw_c: int = -1
var _hw_last: float = -10.0
var _hw_play_last: float = -10.0
var _hw_n: int = 0
var _hw_x: float = 0.0
var _hw_y: float = 0.0
var _pung_last: float = -10.0
# 구슬
var _orb_c: int = -1
var _orb_last: float = -10.0
var _orb_n: int = 0
var _orb_amt: float = 0.0
var _orb_play_last: float = -10.0
# 시련 게이지 사다리
var _gauge_w: int = 0
var _gauge_g: int = 0
var _trial_t0: float = -1.0
var _trial_warned: int = 0
var _trial_len: float = 30.0
var _close_ready_last: float = -10.0
var _sinmyeong_full: bool = false
var _pullil_last: float = -10.0
var _tele_last: float = -10.0
var _settle_last: float = -10.0
# 2026-11-24 무음 27종 연결(build_sfx_silent.py): 발소리·신명 틱·도량·기운 경계·적 기척·공물상·시련 과제
const STEP_STRIDE_PX: float = 34.0     # 한 걸음 ≈ 1.05u (기본 속도 4u/s 에서 0.27s 간격)
const STEP_MIN_SPEED: float = 24.0     # px/s 미만은 제자리(발소리 없음)
const ENM_SPECIES_GAP: float = 6.0     # 같은 종 기척 최소 간격(첫 등장은 예외)
const ENM_GLOBAL_GAP: float = 1.5      # 적 기척 전체 최소 간격
var _d_step: int = -1
var _d_tick: int = -1
var _d_doryang: int = -1
var _d_giun: int = -1
var _md_area: int = 60
var _sm_prev: float = 0.0
var _step_acc: float = 0.0
var _flush_last: float = -1.0
var _enm_seen: Dictionary = {}         # species root -> 마지막 기척 시각
var _enm_last: float = -10.0
var _giun_side: int = 0                # 0 미정 · 1 넋쪽 · -1 살쪽
var _giun_next: float = 0.0
var _gongmul_done: bool = false
var _td: Node = null                   # run/Systems/TrialDirector (deities) — 과제 last_event 를 읽기만 한다
var _task_ev_t: float = -10.0
var _task_flag_i: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_d_haewon = Audio.def_of(&"sfx_sys_haewon")
	_d_haewon_elite = Audio.def_of(&"sfx_sys_haewon_elite")
	_d_pung = Audio.def_of(&"sfx_sys_pungyeong")
	_d_hanpa = Audio.def_of(&"sfx_sys_hanpa")
	_d_gyeoldan = Audio.def_of(&"sfx_sys_gyeoldanta")
	_d_knot = Audio.def_of(&"sfx_sys_maedeup_lock")
	_d_pullil = Audio.def_of(&"sfx_sys_pullil_enter")
	_d_orb = Audio.def_of(&"sfx_pick_wonhon")
	_orb_m = Audio.bank.named_stream(_d_orb, "__m")
	_orb_l = Audio.bank.named_stream(_d_orb, "__l")
	_hw_oct1 = Audio.bank.named_stream(_d_haewon, "__oct1")
	_trial_len = Data.num("combat_core", "trial.duration_sec", 30.0)
	_d_step = Audio.def_of(&"sfx_plr_step")
	_d_tick = Audio.def_of(&"sfx_sys_sinmyeong_tick")
	_d_doryang = Audio.def_of(&"sfx_sys_doryang")
	_d_giun = Audio.def_of(&"sfx_sys_giun_cross")
	_md_area = int(Data.num("combat_core", "ring.mandala_area", 60))
	# combat
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.enemy_hit.connect(_on_enemy_hit)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_died.connect(_on_player_died)
	Events.weapon_evolved.connect(func(_f: StringName, _t: StringName) -> void: _play(&"sfx_evo_reveal"))
	# enemies
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.pullil_entered.connect(_on_pullil)
	Events.maetim_returned.connect(func(_h: int, _s: StringName, p: Vector2) -> void: _play_at(&"sfx_sys_maetim", p, -3.0))
	Events.elite_spawned.connect(_on_elite_spawned)
	Events.boss_spawned.connect(func(_h: int, sp: StringName, _f: StringName) -> void: _snap_play(StringName("sfx_" + _species_root(sp)), 0.0))
	Events.xp_collected.connect(_on_xp)
	Events.level_up.connect(func(_l: int) -> void: _play(&"sfx_plr_levelup_ready"))
	Events.enemy_pattern.connect(_on_enemy_pattern)
	Events.pickup_collected.connect(_on_pickup)
	Events.enemy_spawned.connect(_on_enemy_spawned)
	Events.wave_event.connect(_on_wave_event)
	# waves
	Events.midboss_incoming.connect(_on_midboss)
	Events.wave_warn.connect(func(_e: StringName, _t: float, _p: Dictionary) -> void: _play(&"sfx_trl_timeout_warn", -5.0))
	Events.daehaewon.connect(_on_daehaewon)
	Events.boss_resolved.connect(_on_boss_resolved)
	Events.settlement_started.connect(_on_settlement)
	Events.settlement_progress.connect(_on_settlement_progress)
	# haewon
	Events.yeongga_joined.connect(func(_c: int, _s: StringName) -> void: _snap_play(&"sfx_sys_yeongga_join", -5.0))
	Events.yeongga_cheondo.connect(func(_c: int, _r: StringName) -> void: _snap_play(&"sfx_sys_cheondo", -3.0))
	Events.gilbe_ready.connect(_on_gilbe_ready)
	Events.ring_closed.connect(_on_ring_closed)
	Events.wongwi_return.connect(_on_wongwi)
	Events.sinmyeong_changed.connect(_on_sinmyeong)
	Events.sinmyeong_oreum.connect(func(on: bool) -> void: _snap_play(&"sfx_sys_oreum_start" if on else &"sfx_sys_oreum_end", 0.0, true))
	# deities
	Events.trial_warn.connect(func(_s: int, _d: StringName, _t: float) -> void: _play(&"sfx_trl_omen"))
	Events.trial_start.connect(_on_trial_start)
	Events.trial_gauge_changed.connect(_on_trial_gauge)
	Events.trial_end.connect(_on_trial_end)
	Events.hapil_start.connect(func(_ids: Array) -> void: _snap_play(&"sfx_trl_hapil", 0.0, true))
	# ui
	Events.levelup_offer.connect(func(_c: Array) -> void: _play(&"sfx_ui_jeomji_open"))
	Events.levelup_chosen.connect(func(_c: Dictionary) -> void: _play(&"sfx_ui_card_select"))
	Events.pause_changed.connect(_on_pause_changed)
	Events.run_started.connect(_on_run_started)


func _on_run_started(_c: StringName) -> void:
	_hw_c = -1
	_orb_c = -1
	_last_red = &""
	_last_white = &""
	_src_red = -1
	_src_white = -1
	_xf_d = -1
	_sinmyeong_full = false
	_trial_t0 = -1.0
	_sm_prev = 0.0
	_step_acc = 0.0
	_enm_seen.clear()
	_enm_last = -10.0
	_giun_side = 0
	_giun_next = 0.0
	_gongmul_done = false
	_td = null
	_task_ev_t = -10.0
	_task_flag_i = 0
	Audio.play_sfx(&"sfx_sys_deungbul", &"SFX", -4.0)   # 00:00 등불 점화(캐논 3.4) — 장구 덩은 음악 0박


# ─── 헬퍼 ────────────────────────────────────────────────────────────────

func _play(id: StringName, vol: float = 0.0, pitch: float = 1.0) -> void:
	var d: int = Audio.def_of(id)
	if d >= 0 and Audio.router_claim(d):
		Audio.play_def(d, vol, pitch, Audio.NO_POS, Audio._variant_stream(id, d))


func _play_at(id: StringName, pos: Vector2, vol: float = 0.0, pitch: float = 1.0) -> void:
	var d: int = Audio.def_of(id)
	if d >= 0 and Audio.router_claim(d):
		Audio.play_def(d, vol, pitch, pos, Audio._variant_stream(id, d))


## 연출 스냅(≤250ms): 다음 스냅 격자(장단 fx_snap_div) 또는 beat=true 면 다음 박.
func snap_delay(beat: bool = false) -> float:
	if not Game.run_active or Game.is_sim_paused():
		return 0.0
	var div: int = 1 if beat else maxi(1, Audio.music.fx_snap_div())
	var step: float = 1.0 / float(div)
	var b: float = Beat.beat_pos
	var nb: float = ceil(b / step - 1e-4) * step
	var delay: float = (nb - b) * Beat.beat_len_sec()
	return clampf(delay, 0.0, 0.25 if not beat else 0.6)


func _snap_play(id: StringName, vol: float, beat: bool = false) -> void:
	var d: int = Audio.def_of(id)
	if d < 0:
		return
	var delay: float = snap_delay(beat)
	if Audio.router_claim(d, delay):
		Audio.schedule(delay, d, vol, 1.0, Audio.NO_POS, Audio._variant_stream(id, d))


func _species_root(sp: StringName) -> String:
	var s: String = String(sp)
	var k: int = s.find("__")
	return s.substr(0, k) if k >= 0 else s


func _ladder_pitch(i: int) -> float:
	return pow(2.0, float(tori[i % 5]) / 12.0)


# ─── 무구 ────────────────────────────────────────────────────────────────

func _weapon_info(wid: StringName) -> void:
	if _wpn_fire.has(wid):
		return
	_wpn_fire[wid] = Audio.def_of(StringName("sfx_" + String(wid)))
	_wpn_hit[wid] = Audio.def_of(StringName("sfx_" + String(wid) + "_hit"))
	var w: Dictionary = Data.weapon(String(wid))
	var color: String = String(w.get("color", ""))
	if w.is_empty():
		# 진화·결합 무구: 적중음은 원무구의 것(재료가 같다), 색은 진화 정의의 것.
		var base: String = ""
		var e: Dictionary = Data.evolution(String(wid))
		if e.is_empty():
			var u: Dictionary = Data.union(String(wid))
			var evs: Variant = (u.get("recipe", {}) as Dictionary).get("evolutions", []) if u.get("recipe", {}) is Dictionary else []
			color = String(u.get("color", "red"))
			if evs is Array and not (evs as Array).is_empty():
				e = Data.evolution(String((evs as Array)[0]))
		else:
			color = String(e.get("color", "red"))
		var rc: Variant = e.get("recipe", {})
		if rc is Dictionary:
			base = String((rc as Dictionary).get("weapon", ""))
		var hd: int = int(_wpn_hit[wid])
		if base != "" and (hd < 0 or Audio.bank.wpn_kind[hd] != 2):   # 적중 전용 소리가 아니면(결합 = 장구 발동음 대체) 원무구 적중음
			_wpn_hit[wid] = Audio.def_of(StringName("sfx_" + base + "_hit"))
		if int(_wpn_fire[wid]) < 0 and base != "":
			_wpn_fire[wid] = Audio.def_of(StringName("sfx_" + base))
	_wpn_white[wid] = color == "white"


## Audio.play_sfx(sfx_wpn_X_hit) 경유: 이 무구가 방금 적을 맞혔다(곧 enemy_hit 이 온다).
func note_hit_source(d: int) -> void:
	var white: bool
	if _def_white.has(d):
		white = _def_white[d]
	else:
		var nm: String = String(Audio.bank.names[d])
		var w: Dictionary = Data.weapon(nm.substr(4, nm.length() - 8))   # sfx_ + wpn_x + _hit
		white = String(w.get("color", "red")) == "white"
		_def_white[d] = white
	if white:
		_src_white = d
		_src_white_t = Audio.now()
	else:
		_src_red = d
		_src_red_t = Audio.now()


## Audio.play_sfx(sfx_wpn_X) 경유: 보류했다가 weapon_fired 가 안 따라오면 그대로 재생.
func ext_fire(d: int, vol: float, pitch_var: float) -> void:
	if _xf_d >= 0:
		_play_xf()
	_xf_d = d
	_xf_vol = vol
	_xf_pv = pitch_var
	_xf_t = Audio.now()


func _play_xf() -> void:
	var d: int = _xf_d
	_xf_d = -1
	var pitch: float = 1.0 + (Audio.rng().randf_range(-_xf_pv, _xf_pv) if _xf_pv > 0.0 else 0.0)
	Audio.play_def(d, _xf_vol, pitch, Audio.NO_POS, null, &"", _xf_pv <= 0.0)


func _on_weapon_fired(wid: StringName, slot: int, pos: Vector2) -> void:
	_weapon_info(wid)
	var d: int = int(_wpn_fire[wid])
	if _xf_d >= 0 and Audio.now() - _xf_t < 0.004:
		if d >= 0:
			_xf_d = -1       # 같은 발동: 라우터 판(플램·피치·위치)만 울린다
		else:
			_play_xf()
	if bool(_wpn_white[wid]):
		_last_white = wid
	else:
		_last_red = wid
	if d < 0:
		return
	var pitch: float = 1.0
	var vol: float = -2.0
	if wid == &"wpn_bangul":
		pitch = _ladder_pitch(Beat.beat_index)   # 방울 박 펄스: 토리 음을 박마다 한 칸씩
		vol = -5.0
	elif wid == &"wpn_janggu":
		vol = -1.0
	Audio.schedule(minf(float(slot) * 0.015, 0.075), d, vol, pitch, pos)


func _on_enemy_hit(_h: int, _sp: StringName, pos: Vector2, _dmg: float, color: int, crit: bool, knot_locked: bool) -> void:
	if knot_locked:
		Audio.agg_add(_d_knot, pos, false, -3.0)
		return
	var white: bool = color == K.DmgColor.WHITE
	var now: float = Audio.now()
	var d: int = -1
	# 1) combat 이 알려 준 무구(같은 색 우선, 0.35s 안) 2) 다른 색이라도 방금(0.1s) 알려 준 무구 3) 색별 최근 발동 무구
	if white and now - _src_white_t < 0.35:
		d = _src_white
	elif not white and now - _src_red_t < 0.35:
		d = _src_red
	elif now - maxf(_src_white_t, _src_red_t) < 0.1:
		d = _src_white if _src_white_t > _src_red_t else _src_red
	else:
		var wid: StringName = _last_white if white else _last_red
		if wid != &"":
			d = int(_wpn_hit.get(wid, -1))
	if d >= 0:
		Audio.agg_add(d, pos, crit, 0.0)


# ─── 처치 ────────────────────────────────────────────────────────────────

func _on_enemy_killed(_h: int, _sp: StringName, pos: Vector2, kind: StringName, cause: StringName, tier: StringName) -> void:
	var big: bool = tier == K.TIER_ELITE or tier == K.TIER_MBOSS or tier == K.TIER_BOSS
	if kind == K.KIND_HAEWON:
		if big:
			Audio.schedule(snap_delay(), _d_haewon_elite, 0.0, 1.0, pos)
			Audio.buses.duck(Buses.Duck.HAEWON_ELITE)
			return
		if cause == &"ring":
			return   # 고리 일괄 해원은 ring_closed 의 방울 폭포가 대신한다(11.1)
		_hw_n += 1
		_hw_x += pos.x
		_hw_y += pos.y
		return
	if cause == &"saja":
		return
	if cause == &"gyeoldan":
		Audio.play_def(_d_gyeoldan, 0.0, 1.0, pos)
		return
	if big:
		var s: AudioStream = Audio.bank.named_stream(_d_hanpa, "__agg4")
		Audio.play_def(_d_hanpa, 2.0, 0.84, pos, s)
		return
	Audio.agg_add(_d_hanpa, pos, false, -1.0)


## 중간보스 등장 스팅어. waves 가 예고 때 같은 스팅어를 music_cue 로 이미 울렸으면(8s 안) 생략.
func _on_midboss(_s: StringName) -> void:
	var d: int = Audio.def_of(&"stg_mboss_enter")
	if d >= 0 and Audio.now() - Audio._ext_t[d] < 8.0:
		return
	_snap_play(&"stg_mboss_enter", 0.0, true)


func _on_pullil(_h: int, _sp: StringName, pos: Vector2) -> void:
	var t: float = Audio.now()
	if t - _pullil_last < 0.06:
		return   # 같은 순간 다발 진입은 한 번(cap 6 과 별개로 기관총 방지)
	_pullil_last = t
	Audio.schedule(snap_delay(), _d_pullil, -2.0, 1.0, pos)


func _on_elite_spawned(_h: int, sp: StringName) -> void:
	_snap_play(StringName("sfx_" + _species_root(sp)), 0.0)


## 정예·중간보스·보스 패턴 예고: 피하라는 신호(비음정 '우웅-딱'). 예고 길이에 맞춰 '딱'이 발동 순간에 떨어지게 당긴다.
func _on_enemy_pattern(_h: int, _sp: StringName, _pat: StringName, pos: Vector2, tele: float) -> void:
	if tele <= 0.05:
		return
	var t: float = Audio.now()
	if t - _tele_last < 0.18:
		return
	_tele_last = t
	var d: int = Audio.def_of(&"sfx_trl_avatar_telegraph")
	if d >= 0:
		Audio.schedule(maxf(0.0, tele - 0.36), d, -3.0, 1.0, pos)


func _on_pickup(kind: StringName, _value: float, pos: Vector2) -> void:
	var d: int = Audio.def_of(StringName("sfx_pick_" + String(kind)))
	if d >= 0:
		Audio.play_def(d, -2.0, 1.0, pos)


func _on_xp(amount: float) -> void:
	_orb_n += 1
	_orb_amt += amount


func _on_player_damaged(amount: float, _src: StringName, _hp: float, _hpmax: float) -> void:
	if amount <= 0.0:
		_play(&"sfx_plr_hit_blocked")
		return
	_play(&"sfx_plr_hit")
	Audio.buses.duck(Buses.Duck.PLAYER_HIT)


func _on_player_died() -> void:
	_play(&"sfx_plr_death")
	Audio.schedule(0.35, Audio.def_of(&"stg_death"), 0.0)


# ─── 의식(해원·고리·신명·원귀) ────────────────────────────────────────────

func _on_gilbe_ready(closable: bool) -> void:
	if not closable:
		return
	var t: float = Audio.now()
	if t - _close_ready_last < 0.9:
		return
	_close_ready_last = t
	_play(&"sfx_sys_gilbe_close_ready", -3.0)


func _on_ring_closed(area: int, n: int, c: Vector2) -> void:
	var d: int = Audio.def_of(&"sfx_sys_gildakkeum")
	var s: AudioStream = null
	if area >= 80:
		s = Audio.bank.named_stream(d, "__l")
	elif area >= 30:
		s = Audio.bank.named_stream(d, "__m")
	Audio.play_def(d, 0.0, 1.0, Audio.NO_POS, s)
	Audio.buses.duck(Buses.Duck.GILDAKKEUM)
	if n > 0:
		_waterfall(c, n)
	if area >= _md_area and _d_doryang >= 0:
		Audio.schedule(0.35, _d_doryang, -3.0, 1.0, c)   # 오방 만다라 도량(ring_closure 와 같은 면적 기준) — 길닦음 '덩' 뒤


## 방울 폭포: i = 9 → 0 하행 아르페지오(45ms 간격), n ≥ 10 이면 0.5s 뒤 한 번 더(−4dB) + 풍경 세 겹.
func _waterfall(c: Vector2, n: int) -> void:
	var passes: int = 2 if n >= 10 else 1
	var notes: int = clampi(4 + n, 5, 10)
	for ps in passes:
		for k in notes:
			var i: int = notes - 1 - k
			var oct1: bool = i >= 5
			var stream: AudioStream = _hw_oct1 if (oct1 and _hw_oct1 != null) else null
			var pitch: float = _ladder_pitch(i) if (oct1 and _hw_oct1 != null) else pow(2.0, float(tori[i % 5] + (12 if i >= 5 else 0)) / 12.0)
			Audio.schedule(0.06 + float(ps) * 0.5 + float(k) * 0.045, _d_haewon, -6.0 - 4.0 * float(ps) - 0.4 * float(k), pitch, c, stream)
	for k in 3:
		Audio.schedule(0.10 + float(k) * 0.16, _d_pung, -5.0 - 2.0 * float(k), _ladder_pitch(4 - k * 2), c)


func _on_daehaewon(_bound: int, _mult: float, c: Vector2, count: int) -> void:
	var d: int = Audio.def_of(&"sfx_sys_gildakkeum")
	Audio.play_def(d, 2.0, 0.94, Audio.NO_POS, Audio.bank.named_stream(d, "__l"))
	Audio.buses.duck(Buses.Duck.GILDAKKEUM)
	_waterfall(c, maxi(count, 10))


func _on_boss_resolved(_h: int, kind: StringName, _n: float) -> void:
	if kind == K.KIND_HAEWON:
		_play(&"sfx_boss_knot_untie")
		Audio.schedule(0.4, _d_haewon_elite, 2.0)
	else:
		Audio.play_def(_d_hanpa, 3.0, 0.7, Audio.NO_POS, Audio.bank.named_stream(_d_hanpa, "__agg4"))


func _on_settlement(route: StringName, _p: Dictionary) -> void:
	if route == &"saja_bow":
		_snap_play(&"sfx_chaser_saja_eup", 0.0)


## 정산 진행: 건마다 오는 신호를 0.25s 에 한 번만 — 천도 방울을 토리 사다리로 한 칸씩 올린다.
func _on_settlement_progress(_r: StringName, done: int, _total: int, _p: float) -> void:
	var t: float = Audio.now()
	if t - _settle_last < 0.25:
		return
	_settle_last = t
	_play(&"sfx_sys_cheondo", -4.0, _ladder_pitch(maxi(done, 0) % 5))


func _on_wongwi(threshold: int) -> void:
	var id: StringName = &"sfx_sys_wongwi_rise"
	if threshold >= 75:
		id = &"sfx_sys_wongwi_rise__75"
	elif threshold >= 50:
		id = &"sfx_sys_wongwi_rise__50"
	_play(id)
	Audio.buses.duck(Buses.Duck.WONGWI)


func _on_sinmyeong(v: float) -> void:
	# 25/50/75% 를 위로 넘을 때 장구 '기덕'(만충은 아래 sinmyeong_full 이 맡는다)
	if _d_tick >= 0 and v > _sm_prev and v < 0.999:
		var mark: int = 0
		for q: int in [75, 50, 25]:
			if _sm_prev < float(q) / 100.0 and v >= float(q) / 100.0:
				mark = q
				break
		if mark > 0:
			_snap_play(&"sfx_sys_sinmyeong_tick" if mark == 25 else StringName("sfx_sys_sinmyeong_tick__%d" % mark), -4.0)
	_sm_prev = v
	if v >= 0.999 and not _sinmyeong_full:
		_sinmyeong_full = true
		_snap_play(&"sfx_sys_sinmyeong_full", 0.0, true)
	elif v < 0.9:
		_sinmyeong_full = false


# ─── 시련 ────────────────────────────────────────────────────────────────

func _on_trial_start(_slot: int, _deity: StringName) -> void:
	_gauge_w = 0
	_gauge_g = 0
	_trial_t0 = Audio.now()
	_trial_warned = 0
	_play(&"sfx_trl_sinjangdae")   # 원 진입·확정 링·미소는 deities(trial_director)가 제 박자에 직접 울린다


func _on_trial_gauge(_slot: int, wieom: float, gaho: float) -> void:
	var w: int = int(floor(wieom * 10.0 + 1e-4))
	var g: int = int(floor(gaho * 10.0 + 1e-4))
	if w > _gauge_w:
		_gauge_w = w
		_snap_play_pitch(&"sfx_trl_wieom_step", -3.0, _ladder_pitch(mini(w - 1, 9)) * (2.0 if w > 5 else 1.0))
	if g > _gauge_g:
		_gauge_g = g
		_snap_play_pitch(&"sfx_trl_gaho_step", -3.0, _ladder_pitch(mini(g - 1, 9)) * (2.0 if g > 5 else 1.0))


func _snap_play_pitch(id: StringName, vol: float, pitch: float) -> void:
	var d: int = Audio.def_of(id)
	if d < 0:
		return
	var delay: float = snap_delay()
	if Audio.router_claim(d, delay):
		Audio.schedule(delay, d, vol, clampf(pitch, 0.5, 2.0))


func _on_trial_end(_slot: int, deity: StringName, winner: StringName) -> void:
	_trial_t0 = -1.0
	if winner == &"none":
		_play(&"sfx_trl_avatar_smile", -2.0)
		return
	var short: String = String(deity).trim_prefix("deity_")
	_snap_play(StringName("sfx_trl_bingui__" + short), 0.0, true)
	Audio.buses.duck(Buses.Duck.BINGUI)


func _on_pause_changed(paused: bool, reason: StringName) -> void:
	if reason == &"menu":
		_play(&"sfx_ui_pause_in" if paused else &"sfx_ui_pause_out")


# ─── 프레임 끝 정리(해원 화음·구슬·시련 경고) ─────────────────────────────

func flush(now: float) -> void:
	var fdt: float = clampf(now - _flush_last, 0.0, 0.1) if _flush_last >= 0.0 else 0.0
	_flush_last = now
	if Game.run_active and not Game.is_sim_paused():
		_tick_steps(fdt)
		if now >= _giun_next:
			_giun_next = now + 0.25
			_tick_giun()
		_tick_task()
	if _xf_d >= 0:
		_play_xf()
	if _hw_n > 0:
		_flush_haewon(now)
	if _orb_n > 0 and now - _orb_play_last >= 0.05:
		_flush_orbs(now)
	if _trial_t0 > 0.0 and Game.run_active and not Game.is_sim_paused():
		var left: float = _trial_len - (now - _trial_t0)
		if left <= 10.0 and left > 0.0 and _trial_warned < 10:
			var k: int = int(10.0 - left)
			if k >= _trial_warned:
				_trial_warned = k + 1
				_play(&"sfx_trl_timeout_warn", -6.0 + float(k) * 0.4)


func _flush_haewon(now: float) -> void:
	var n: int = _hw_n
	var pos: Vector2 = Vector2(_hw_x / n, _hw_y / n)
	_hw_n = 0
	_hw_x = 0.0
	_hw_y = 0.0
	if now - _hw_last > HW_RESET:
		_hw_c = -1
	_hw_last = now
	var delay: float = 0.0 if now - _hw_play_last > 0.1 else snap_delay()
	_hw_play_last = now + delay
	var play_n: int = mini(n, SAME_FRAME_CAP)
	var extra_db: float = minf(1.5 * float(n - play_n), 6.0)
	for k in play_n:
		_hw_c += 1
		var c: int = _hw_c
		var i: int = c if c <= 9 else (8 if (c % 2) == 0 else 9)   # 9 도달 후 8·9 떠는목
		var oct1: bool = i >= 5 and _hw_oct1 != null
		var stream: AudioStream = _hw_oct1 if oct1 else null
		var pitch: float = _ladder_pitch(i) if oct1 else pow(2.0, float(tori[i % 5] + (12 if i >= 5 else 0)) / 12.0)
		var vol: float = -2.0 - 2.0 * float(play_n - 1 - k) + (extra_db if k == play_n - 1 else 0.0)
		Audio.schedule(delay, _d_haewon, vol, pitch, pos, stream)
	# 풍경: 같은 사다리 음을 한 옥타브 위 바람종으로 한 겹 — 해원이 몰릴수록 맑게 번진다
	if _d_pung >= 0 and now - _pung_last >= 0.22:
		_pung_last = now
		var top: int = _hw_c if _hw_c <= 9 else 9
		Audio.schedule(delay + 0.03, _d_pung, -9.0 + minf(float(n), 6.0) * 0.6, _ladder_pitch(top), pos)


func _flush_orbs(now: float) -> void:
	var n: int = _orb_n
	_orb_n = 0
	_orb_amt = 0.0
	_orb_play_last = now
	if now - _orb_last > ORB_RESET:
		_orb_c = -1
	_orb_last = now
	_orb_c = mini(_orb_c + 1, 9)
	var s: AudioStream = null
	if n >= 6 and _orb_l != null:
		s = _orb_l
	elif n >= 2 and _orb_m != null:
		s = _orb_m
	Audio.play_def(_d_orb, -8.0 + minf(float(n - 1), 4.0) * 0.75, _ladder_pitch(_orb_c), Audio.NO_POS, s)


# ─── 무음 27종 연결(2026-11-24) ─────────────────────────────────────────

## 발소리: 이동 거리 누적 → 한 걸음(34px)마다 1테이크. 배경 질감(−10dB, 정의 반음·볼륨 랜덤).
func _tick_steps(dt: float) -> void:
	if _d_step < 0 or Game.player == null or dt <= 0.0:
		return
	var v: Variant = Game.player.get("vel")
	if not (v is Vector2):
		return
	var sp: float = (v as Vector2).length()
	if sp < STEP_MIN_SPEED:
		_step_acc = minf(_step_acc, STEP_STRIDE_PX * 0.6)   # 멈췄다 출발하면 첫 걸음이 곧 난다
		return
	_step_acc += sp * dt
	if _step_acc >= STEP_STRIDE_PX:
		_step_acc -= STEP_STRIDE_PX
		Audio.play_def(_d_step, -10.0)


## 굿판의 기운(넋 비율 N) 50% 경계 통과: 넋쪽 = 맑은 방울 한 점, 살쪽 = 낮은 바람. 처치 20 전에는 판정하지 않는다(초반 출렁임).
func _tick_giun() -> void:
	if _d_giun < 0 or Game.kills_toechi + Game.kills_haewon < 20:
		return
	var em: Object = Game.enemies
	if em == null or not em.has_method("n_ratio"):
		return
	var r: float = float(em.call("n_ratio"))
	var side: int = _giun_side
	if r >= 0.53:
		side = 1
	elif r <= 0.47:
		side = -1
	if side == _giun_side:
		return
	var first: bool = _giun_side == 0
	_giun_side = side
	if first:
		return
	_snap_play(&"sfx_sys_giun_cross" if side > 0 else &"sfx_sys_giun_cross__sal", -6.0)


## 적 기척: 일반 잡귀 종이 이번 판 처음 나오면 한 번 또렷하게(무엇이 왔는지 소리로 안다), 그 뒤로는 종당 6s·전체 1.5s 간격으로 옅게.
func _on_enemy_spawned(_h: int, sp: StringName, tier: StringName) -> void:
	if tier != K.TIER_COMMON or not Game.run_active:
		return
	var root: String = _species_root(sp)
	var t: float = Audio.now()
	var first: bool = not _enm_seen.has(root)
	if not first and (t - float(_enm_seen[root]) < ENM_SPECIES_GAP or t - _enm_last < ENM_GLOBAL_GAP):
		return
	var d: int = Audio.def_of(StringName("sfx_" + root))
	_enm_seen[root] = t
	if d < 0 or Audio.bank.bus[d] != &"SfxEnemy":
		return
	_enm_last = t
	Audio.play_def(d, -4.0 if first else -12.0)


## 뒷전 공물상 차림(맵 전역 1회): 놋그릇·제기 군집 + 잡귀 발 사락.
func _on_wave_event(id: StringName, _p: Dictionary) -> void:
	if _gongmul_done or not (id == &"geori_dwitjeon" or id == &"evt_sangcharim"):
		return
	_gongmul_done = true
	_snap_play(&"sfx_evt_gongmulsang", -2.0)


## run/Systems/TrialDirector(없으면 null). ambience 의 거점 유지 루프도 이것을 쓴다.
func trial_node() -> Node:
	if _td == null or not is_instance_valid(_td):
		_td = Game.run_root.get_node_or_null(^"Systems/TrialDirector") if Game.run_root != null else null
	return _td


func gaho_steps() -> int:
	return _gauge_g


## 시련 과제(deities trial_task.last_event)를 읽어 과제 소리: 별 = 꽹과리 토리 상행, 오방기 = '쿵' 토리 5음, 넋 도착 = 물방울·방울.
func _tick_task() -> void:
	if _trial_t0 <= 0.0:
		return
	if trial_node() == null:
		return
	var task: Variant = _td.get("task")
	if not (task is Object):
		return
	var tk: Object = task
	var et: float = float(tk.get("last_event_t"))
	if et == _task_ev_t:
		return
	_task_ev_t = et
	match StringName(tk.get("last_event")):
		&"star", &"round":   # 7번째 별은 같은 틱에 round 가 덮어쓴다 → 맨 윗음
			var i: int = 6 if StringName(tk.get("last_event")) == &"round" else maxi(0, int(tk.get("star_next")) - 1) % 7   # 7별 = 토리 상행 7음(0.75배에서 시작해 2배 상한 안)
			var semi: int = tori[i % 5] + (12 if i >= 5 else 0)
			_snap_play_pitch(&"sfx_trl_grm_connect_star", -4.0, 0.75 * pow(2.0, float(semi) / 12.0))
		&"flag":
			_snap_play_pitch(&"sfx_trl_grm_install", -3.0, _ladder_pitch(_task_flag_i))
			_task_flag_i += 1
		&"deliver", &"gate":
			_snap_play(&"sfx_trl_grm_escort_arrive", -3.0)
