class_name TrialDirector
extends Node
## 신령 시련 4회(03:00/06:30/12:30/15:30) · 빙의 · 빙의 점지 · 18:00 합일. 소유: deities. 정본: design/06 §3·4·6·7·10.
## 상태기계: DORMANT → OMEN(10s, 신장대 강림·후보 2신·산통) → DESCEND(≤8s, 화신 원 2) → CONFIRM(1s 확인 링) → CLEAR(0.5s)
##   → TRIAL(30s, 위엄·가호 두 게이지 동시, 먼저 100%가 면 / 만료 = 높은 쪽 미완 70%) → RESOLVE(0.3s) → POSSESSION(1.2s, 비정지·무적)
##   → BINGUI_JEOMJI(정지, 권능 카드) → AFTERGLOW(3s) → DORMANT.  18:00: HAPIL_OMEN(17:58) → DESCEND(2s) → CALL(박마다 1신) → ACTIVE.
## 신령은 적이 아니다: 화신은 EnemyManager 밖의 존재이며 죽지 않는다. 위엄 = 무구가 화신에게 닿는 시험(무구 발사 사거리 판정).
## 고르지 않은 후보는 다음 시련 1회 물러난다. 재점(다시 묻기) = 산통 반경 1.2유닛에 0.6초 머무르기(시련당 2회).
## 시뮬(L2)은 sim_step(틱 6b)에서만 진행. 연출(view/hud)은 이 노드의 공개 상태를 읽기만 한다.

const Defs := preload("res://deities/deity_defs.gd")
const AvatarScript := preload("res://deities/trial_avatar.gd")
const TaskScript := preload("res://deities/trial_task.gd")
const PowersScript := preload("res://deities/deity_powers.gd")
const ViewScript := preload("res://deities/trial_view.gd")
const HudScript := preload("res://deities/trial_hud.gd")
const JeomjiScript := preload("res://deities/bingui_jeomji.gd")

enum Ph { DORMANT, OMEN, DESCEND, CONFIRM, CLEAR, TRIAL, RESOLVE, POSSESSION, JEOMJI, AFTERGLOW, HAPIL_OMEN, HAPIL_DESCEND, HAPIL_CALL, HAPIL_ACTIVE }
const PH_NAME: Array[StringName] = [&"dormant", &"omen", &"descend", &"confirm", &"clear", &"trial", &"resolve", &"possession", &"jeomji", &"afterglow", &"hapil_omen", &"hapil_descend", &"hapil_call", &"hapil_active"]

# 호환(이전 빌드 공개 필드)
const V12_TRIAL_TIMES: PackedFloat32Array = [180.0, 390.0, 750.0, 930.0]

# ─── 수치(data/deities.json constants) ───
var times: PackedFloat32Array = PackedFloat32Array()
var hapil_time: float = 1080.0
var omen_lead: float = 10.0
var descend_max: float = 8.0
var confirm_s: float = 1.0
var clear_s: float = 0.5
var trial_dur: float = 30.0
var trial_dur_slot: PackedFloat32Array = PackedFloat32Array()   # 슬롯별 제한시간(없으면 trial_dur)
var trial_dur_cur: float = 30.0   # 진행 중 시련의 제한시간(hud 가 읽는다)
var hp_meas_mult: float = 1.2
var perf_cfg: Dictionary = {}
var afterglow_s: float = 3.0
var possession_s: float = 1.2
var circle_r: float = 6.0 * 32.0
var circle_off: float = 8.0 * 32.0
var ground_r: float = 12.0 * 32.0
var leave_dist: float = 14.0 * 32.0
var leave_back: float = 12.0 * 32.0
var vuln_mult: float = 1.5
var wieom_hp_s: float = 18.0
var incomplete_mult: float = 0.7
var reach_u: float = 6.5
var white_reach_u: float = 3.2
var col_coef_red: float = 1.0
var col_coef_white: float = 0.4
var col_coef_union: float = 0.7
var side_feed: Dictionary = {}
var gauge_mult: float = 1.0
var face_pct_mult: float = 1.0

# ─── 공개 상태(view·hud 가 읽는다) ───
var ph: int = Ph.DORMANT
var ph_t0: float = 0.0            # 단계 시작 게임 초
var slot: int = -1                # 0..3 (진행 중 시련)
var slot_next: int = 0
var n: int = 1                    # 1..4
var cand: Array[StringName] = [&"", &""]
var circle: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var omen_at: float = 0.0          # DESCEND 시작(=T)
var omen_t0: float = 0.0          # OMEN 시작(신장대 강림 연출 기준)
var descend_end: float = 0.0
var pick: int = -1                # 0 왼쪽 1 오른쪽
var confirm_k: float = 0.0
var auto_picked: bool = false
var anchor: Vector2 = Vector2.ZERO
var active_deity: StringName = &""
var momju: StringName = &"deity_sansin"
var santong_pos: Vector2 = Vector2.ZERO
var santong_k: float = 0.0
var santong_on: bool = false
var reroll_left: int = 1
var reroll_used: int = 0
var reroll_t: float = -10.0       # 재강림 연출 시작(게임 초)
var t_left: float = 0.0
var wieom: float = 0.0
var gaho: float = 0.0
var wieom_dmg: float = 0.0
var wieom_hp: float = 810.0
var task_pct: float = 0.0
var side_w: float = 0.0
var side_g: float = 0.0
var leaving: bool = false
var res_face: StringName = &""
var res_complete: bool = true
var perf_tier: StringName = &""   # 시련 수행 등급(clean_bonus|clean|bonus|plain|incomplete) — 점지 머리말·로그
var perf_min_gil: bool = false
var perf_daegil_mult: float = 1.0
var perf_gil_mult: float = 1.0
var trial_phase: int = 1
var avatar: RefCounted = null     # trial_avatar.gd
var task: RefCounted = null       # trial_task.gd
var powers: RefCounted = null     # deity_powers.gd
var hapil_done: bool = false
var hapil_ids: Array[StringName] = []
var hapil_pos: PackedVector2Array = PackedVector2Array()   # 무당 기준 오프셋
var _low_say_t: float = -100.0   # 맛보기 공수(prio<2) 마지막 표시 시각(가시성, 화면 전용)
var hapil_idx: int = -1
var hapil_form: StringName = &""
var hapil_word_t: float = -10.0
var hapil_word: String = ""
var last_hit_t: float = -10.0     # 마지막 위엄 시험 타격(연출)
var last_hit_from: Vector2 = Vector2.ZERO
var last_hit_crit: bool = false
var wieom_pop_t: float = -10.0    # 위엄 5% 눈금 글자 연출 시작(view)
var _w_pop_step: int = 0
var shock_t: float = -10.0
var shock_pos: Vector2 = Vector2.ZERO
var shock_r: float = 0.0
var overlay_deity: StringName = &""
var overlay_face: StringName = &""
var overlay_t: float = -10.0
var gongsu_text: String = ""
var gongsu_deity: StringName = &""
var gongsu_t: float = -10.0
var gongsu_prio: int = 0
## 쉬운 첫 시험(design/19 §3·§4.6): 처음 두 판(Save.runs_done() < 2)의 첫 시련. 연습 굿판 제외.
##   화신 위엄 체력 ×EASY_HP_MULT, 화신 피해 ×EASY_DMG_MULT, 공수·다시 고르기(산통) 숨김. 안내 글은 trial_hud 가 이 값을 읽는다.
const EASY_HP_MULT: float = 0.7
const EASY_DMG_MULT: float = 0.6
var easy_trial: bool = false

# 호환 필드(이전 HUD/테스트)
var active_slot: int = -1
var hapil_done_compat: bool = false

# 진행 기록
var possessed: Array[StringName] = []
var appeared: Dictionary = {}     # deity -> true(후보로 나온 적 있음)
var retreat_until: Dictionary = {}   # deity -> 이 slot 이상에서 다시 후보 가능
var retreated_now: StringName = &""  # 이번 시련에서 물러난 신령(작별 공수)
var log_lines: PackedStringArray = PackedStringArray()

var _init_done: bool = false
var _gauge_emit_w: float = -1.0
var _gauge_emit_g: float = -1.0
var _poss_step: int = 0
var _speed_factor: float = 1.0
var _left_said: bool = false
var _tw_said: bool = false
var _first_full: StringName = &""
var _trial_t0: float = 0.0
var _hp_min: float = 9999.0
var _debug_omen: bool = false
var _boss_said: bool = false
var _w_step: int = 0              # 게이지 10% 눈금(소리·연출)
var _g_step: int = 0
var _hit_sfx_t: float = -10.0
var _dbg_trial_at: float = -1.0   # 디버그: --trial-at=<게임 초> 에 다음 시련을 3초 예고로 당겨 시작(캡처·검사용)
# 위엄 체력 보정: 시련 밖에서 무구 발사가 화신에 줄 '기대 시험 피해'를 초 단위로 모은다(최근 RATE_WIN 초)
const RATE_WIN: int = 20
var _rate_buf: PackedFloat32Array = PackedFloat32Array()
var _rate_sec: int = -1
var wieom_rate: float = 0.0       # 시련 시작 때 잰 초당 기대 시험 피해(로그·튜닝)
var wieom_hp_anchor: float = 0.0  # 데이터 기준(dps_ref) 체력
var _crisis_next: float = 0.0
var _rng: RandomNumberGenerator
var _view_ground: Node2D
var _view_top: Node2D
var _view_over: Node2D
var _hud: CanvasLayer
var _jeomji: CanvasLayer
var _pending_cards: Array[Dictionary] = []
var _jeomji_open: bool = false
var _q: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_rng = Rng.stream(&"trial")
	_q.resize(256)
	_rate_buf.resize(RATE_WIN)
	_rate_buf.fill(0.0)
	_load_params()
	powers = PowersScript.new()
	avatar = AvatarScript.new()
	task = TaskScript.new()
	_view_ground = ViewScript.new()
	_view_ground.set("layer_kind", 0)
	_view_ground.set("dir", self)
	_view_ground.z_index = -2
	add_child(_view_ground)
	_view_over = ViewScript.new()
	_view_over.set("layer_kind", 2)
	_view_over.set("dir", self)
	_view_over.z_index = 2
	add_child(_view_over)
	_view_top = ViewScript.new()
	_view_top.set("layer_kind", 1)
	_view_top.set("dir", self)
	_view_top.z_index = 4
	add_child(_view_top)
	_hud = HudScript.new()
	_hud.set("dir", self)
	_hud.layer = 12
	add_child(_hud)
	_jeomji = JeomjiScript.new()
	_jeomji.set("dir", self)
	_jeomji.layer = 21
	add_child(_jeomji)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.enemy_hit.connect(_on_enemy_hit)
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.ring_closed.connect(_on_ring_closed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.yeongga_cheondo.connect(func(_c: int, _r: StringName) -> void: (powers as Object).call("on_cheondo"))
	Events.debug_trial_now.connect(start_now)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.pullil_entered.connect(func(h: int, _sp: StringName, pos: Vector2) -> void: (powers as Object).call("on_pullil", h, pos))


func _exit_tree() -> void:
	if Game.has_pause(&"bingui_jeomji"):
		Game.pop_pause(&"bingui_jeomji")
	_set_player_slow(1.0)


func _load_params() -> void:
	var c: Dictionary = Data.get_value("deities", "constants", {})
	var tt: Variant = c.get("trial_times_s", [])
	times = PackedFloat32Array()
	if tt is Array and (tt as Array).size() == 4:
		for v: Variant in tt:
			times.append(float(v))
	else:
		times = V12_TRIAL_TIMES
		print("[TrialDirector] deities.constants.trial_times_s 없음 → 캐논 v1.2 기본값 %s" % [times])
	hapil_time = float(c.get("hapil_time_s", 1080))
	omen_lead = float(c.get("omen_lead_s", 10.0))
	descend_max = float(c.get("descend_max_s", 8.0))
	confirm_s = float(c.get("confirm_s", 1.0))
	clear_s = float(c.get("clear_s", 0.5))
	trial_dur = float(c.get("trial_duration_s", 30.0))
	trial_dur_slot = PackedFloat32Array()
	var tds: Variant = c.get("trial_duration_by_slot_s", [])
	if tds is Array:
		for v: Variant in tds:
			trial_dur_slot.append(float(v))
	hp_meas_mult = float(c.get("wieom_hp_measured_mult", 1.2))
	perf_cfg = c.get("grade_by_performance", {})
	afterglow_s = float(c.get("afterglow_s", 3.0))
	possession_s = float(c.get("possession_s", 1.2))
	circle_r = float(c.get("circle_radius", 6)) * K.UNIT_PX
	circle_off = float(c.get("circle_offset_x", 8)) * K.UNIT_PX
	ground_r = float(c.get("ground_radius", 12)) * K.UNIT_PX
	leave_dist = float(c.get("ground_leave_dist", 14)) * K.UNIT_PX
	var gl: Dictionary = c.get("ground_leave", {})
	leave_back = float(gl.get("hysteresis_from", 12)) * K.UNIT_PX
	vuln_mult = float(c.get("vulnerable_mult", 1.5))
	wieom_hp_s = float(c.get("wieom_hp_seconds", 18))
	incomplete_mult = float(c.get("incomplete_mult", 0.7))
	var cc: Dictionary = c.get("wieom_color_coeff", {})
	col_coef_red = float(cc.get("red", 1.0))
	col_coef_white = float(cc.get("white", 0.4))
	col_coef_union = float(cc.get("union", 0.7))
	side_feed = c.get("side_feed", {})


## 런 시작 시 캐릭터 보정·몸주신·재점 횟수.
func _begin_run_state() -> void:
	momju = Defs.momju_of(Game.char_id)
	var mods: Dictionary = Data.get_value("deities", "character_mods", {}).get(String(Game.char_id), {})
	gauge_mult = float(mods.get("gauge_charge_mult", 1.0))
	face_pct_mult = float(mods.get("face_effect_pct_mult", 1.0))
	reroll_left = maxi(1, int(Game.stat(&"stat_gongsu_gyojeong", 1.0))) + int(mods.get("free_trial_reroll_per_run", 0))
	# 스모크 테스트(디버그 전용): --deity-test=wieom|gaho|mix → 6신 면 효과 + 권능 전부를 시작부터 건다(코드 경로 검사용)
	var dt_mode: String = DebugTools.arg("deity-test", "") if OS.is_debug_build() else ""
	if dt_mode != "":
		var i: int = 0
		for id: String in Defs.ORDER:
			var d: StringName = StringName(id)
			var face: StringName = &"wieom" if dt_mode == "wieom" or (dt_mode == "mix" and i % 2 == 0) else &"gaho"
			powers.call("apply_face", d, face, true, 1.0)
			possessed.append(d)
			for p: Dictionary in powers.call("visible_powers", d, face):
				powers.call("gain_power", {"power_id": String(p.get("id", "")), "deity": d, "grade": "grade_gil", "grade_mult": 1.3})
			i += 1
		overlay_deity = possessed[possessed.size() - 1]
		overlay_face = (powers.get("faces") as Dictionary).get(overlay_deity, &"wieom")
		_log("deity-test mode=%s possessed=%s powers=%d" % [dt_mode, possessed, (powers.get("powers") as Dictionary).size()])


# ─── 공개 API ──────────────────────────────────────────────────────────

## F5(디버그): 다음 시련을 3초 예고로 즉시 시작.
func start_now() -> void:
	if ph != Ph.DORMANT or slot_next >= times.size():
		return
	_debug_omen = true
	_enter_omen(slot_next, Game.time_sec() + 3.0)


## 정규 점지 편입용(ui/combat): 보유 권능 레벨업 후보. [{kind:"deity_power", id, title, desc, level, deity}]
func power_offer_candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pw: Dictionary = powers.get("powers")
	for id: Variant in pw.keys():
		var p: Dictionary = pw[id]
		var lv: int = int(p.get("level", 1))
		if lv >= 3:
			continue
		var def: Dictionary = p.get("def", {})
		out.append({"kind": "deity_power", "id": String(id), "title": String(def.get("name_ko", id)), "desc": String(def.get("desc_ko", "")), "level": lv + 1, "deity": p.get("deity", &"")})
	return out


## 정규 점지에서 권능을 고른 경우(ui 가 호출). 반환: 새 레벨.
func apply_power_choice(power_id: String) -> int:
	return int(powers.call("level_power", power_id))


func phase_name() -> StringName:
	return PH_NAME[ph]


func in_trial() -> bool:
	return ph >= Ph.CLEAR and ph <= Ph.AFTERGLOW


# ─── 틱 6b ─────────────────────────────────────────────────────────────

func sim_step(dt: float) -> void:
	var now: float = Game.time_sec()
	if not _init_done:
		_init_done = true
		_begin_run_state()
		# --start-sec 로 지난 시련은 건너뛴다(예고 전 시각만 유효)
		while slot_next < times.size() and now > times[slot_next] - omen_lead + 0.05:
			slot_next += 1
		if now > hapil_time - 2.0:
			hapil_done = true
		if OS.is_debug_build():
			_dbg_trial_at = float(DebugTools.arg("trial-at", "-1"))
	if _dbg_trial_at >= 0.0 and now >= _dbg_trial_at and ph == Ph.DORMANT:
		_dbg_trial_at = -1.0
		start_now()
	var pp: Vector2 = Game.player.global_position if Game.player != null else Vector2.ZERO
	_hp_min = minf(_hp_min, Game.hp)
	# 위기 공수(정기 25% 미만, 60초 쿨다운)
	if now >= _crisis_next and not possessed.is_empty() and Game.hp > 0.0 and Game.hp < Game.hp_max * 0.25:
		_crisis_next = now + 60.0
		_say(_speaker(), &"gs_crisis", 4)
	(powers as Object).call("sim_step", dt, now)
	match ph:
		Ph.DORMANT:
			if slot_next < times.size() and now >= times[slot_next] - omen_lead:
				_enter_omen(slot_next, times[slot_next])
			elif not hapil_done and now >= hapil_time - 2.0:
				_enter_hapil_omen()
		Ph.OMEN:
			_tick_santong(dt, pp)
			if now >= omen_at:
				_set_ph(Ph.DESCEND)
				descend_end = now + descend_max
				# 첫 시련: 고르는 순간에 두 면의 뜻(꺾으면 위엄 · 모시면 가호)을 길잡이 줄로. '원으로 걸어가라'는 안내판이 이미 말한다.
				if slot == 0:
					Events.hint_requested.emit(&"trial_faces")
				Audio.play_sfx(&"sfx_trl_circle_enter", &"SFX", -4.0)
		Ph.DESCEND:
			_tick_santong(dt, pp)
			for i in 2:
				if pp.distance_to(circle[i]) <= circle_r:
					pick = i
					confirm_k = 0.0
					_set_ph(Ph.CONFIRM)
					Audio.play_sfx(&"sfx_trl_confirm_ring", &"SFX", -3.0)
					if Game.vfx != null:
						(Game.vfx as VfxPlayer).play(StringName("vfx_confirm_ring_" + Defs.vfx_key(cand[i])), circle[i], 0.0, 1.0, {"additive": true, "z": -1})
					break
			if ph == Ph.DESCEND and now >= descend_end:
				_auto_pick(pp)
		Ph.CONFIRM:
			if pp.distance_to(circle[pick]) > circle_r + 4.0:
				confirm_k = 0.0
				pick = -1
				_set_ph(Ph.DESCEND)
			else:
				confirm_k = minf(1.0, confirm_k + dt / maxf(0.05, confirm_s))
				if confirm_k >= 1.0:
					anchor = circle[pick]
					_enter_clear()
			if ph == Ph.DESCEND and now >= descend_end:
				_auto_pick(pp)
		Ph.CLEAR:
			if now - ph_t0 >= clear_s:
				_enter_trial()
		Ph.TRIAL:
			_tick_trial(dt, now, pp)
		Ph.RESOLVE:
			avatar.call("sim_step", dt, now, pp)
			if now - ph_t0 >= 0.3:
				_enter_possession()
		Ph.POSSESSION:
			_tick_possession(now, pp)
		Ph.AFTERGLOW:
			if now - ph_t0 >= afterglow_s:
				_set_ph(Ph.DORMANT)
				slot = -1
				active_slot = -1
		Ph.HAPIL_OMEN:
			if now >= hapil_time:
				_set_ph(Ph.HAPIL_DESCEND)
				for d: StringName in hapil_ids:
					Audio.play_sfx(StringName("sfx_trl_bingui__" + Defs.vfx_key(d)), &"SFX", -10.0)
		Ph.HAPIL_DESCEND:
			if now - ph_t0 >= 2.0:
				_set_ph(Ph.HAPIL_CALL)
				hapil_idx = -1
		Ph.HAPIL_CALL:
			if Beat.is_beat_tick:
				_hapil_beat(pp)
		Ph.HAPIL_ACTIVE:
			pass
	# 화신 둔화(포효·시루)
	var slow: float = 1.0
	if avatar != null and (ph == Ph.TRIAL or ph == Ph.RESOLVE):
		var su: float = float(avatar.get("slow_until"))
		if now < su:
			slow = 1.0 - clampf(float(avatar.get("slow_pct")), 0.0, 0.8)
	_set_player_slow(slow)


func _set_ph(p: int) -> void:
	ph = p
	ph_t0 = Game.time_sec()
	var d: StringName = active_deity if active_deity != &"" else (cand[0] if ph >= Ph.OMEN and ph <= Ph.CONFIRM else &"")
	Events.trial_phase_changed.emit(slot + 1, d, PH_NAME[p])


func _set_player_slow(f: float) -> void:
	if absf(f - _speed_factor) < 0.001:
		return
	var pl: Player = Game.player as Player
	if pl != null and _speed_factor > 0.01:
		pl.speed_mult_ext = pl.speed_mult_ext / _speed_factor * f
	_speed_factor = f


# ─── OMEN: 후보 2신 ─────────────────────────────────────────────────────

func _enter_omen(s: int, at: float) -> void:
	slot = s
	slot_next = s + 1
	n = s + 1
	active_slot = s
	omen_at = at
	omen_t0 = Game.time_sec()
	active_deity = &""
	pick = -1
	confirm_k = 0.0
	auto_picked = false
	reroll_used = 0
	santong_k = 0.0
	retreated_now = &""
	var pp: Vector2 = Game.player.global_position if Game.player != null else Vector2.ZERO
	circle[0] = pp + Vector2(-circle_off, 0.0)
	circle[1] = pp + Vector2(circle_off, 0.0)
	santong_pos = pp + Vector2(0.0, 2.0 * K.UNIT_PX)
	_pick_candidates(s)
	easy_trial = s == 0 and _easy_runs()
	santong_on = reroll_left > 0 and _reroll_pool().size() > 0 and not easy_trial
	_set_ph(Ph.OMEN)
	Audio.play_sfx(&"sfx_trl_omen", &"SFX", 0.0)
	Audio.play_sfx(&"sfx_trl_sinjangdae", &"SFX", -2.0)
	Events.trial_warn.emit(s + 1, cand[0], at - Game.time_sec())
	Events.trial_candidates.emit(s + 1, cand[0], cand[1])
	_say(cand[_rng.randi_range(0, 1)], &"gs_omen", 1)
	_log("omen slot=%d cand=%s,%s momju=%s t=%.1f santong=%s reroll_left=%d easy=%s" % [s + 1, cand[0], cand[1], momju, Game.time_sec(), santong_on, reroll_left, easy_trial])


## 처음 두 판(첫 판 보조와 같은 범위). 연습 굿판·deity-test 는 제외.
func _easy_runs() -> bool:
	if Game.tutorial_mode or (OS.is_debug_build() and DebugTools.arg("deity-test", "") != ""):
		return false
	if Save.has_method(&"first_run_pending") and bool(Save.call(&"first_run_pending")):
		return true
	return Save.has_method(&"runs_done") and int(Save.call(&"runs_done")) < 2


func _pool(s: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in Data.deity_ids():
		var d: StringName = StringName(String(id))
		var def: Dictionary = Data.deity(String(d))
		if String(def.get("scope", "v1")) != "v1":
			continue
		if possessed.has(d):
			continue
		if int(retreat_until.get(d, -1)) > s:
			continue
		out.append(d)
	out.sort()   # 결정론(Dictionary 순서와 무관)
	return out


func _weight(d: StringName, s: int) -> float:
	var tr: Variant = Data.get_value("waves_stage1", "trials", [])
	if tr is Array and s < (tr as Array).size() and tr[s] is Dictionary:
		var sw: Dictionary = (tr[s] as Dictionary).get("stage_weight", {})
		return float(sw.get(String(d), 1.0))
	return 1.0


func _weighted_pick(pool: Array[StringName], s: int) -> StringName:
	var tot: float = 0.0
	for d: StringName in pool:
		tot += _weight(d, s)
	var r: float = _rng.randf() * tot
	for d: StringName in pool:
		r -= _weight(d, s)
		if r <= 0.0:
			return d
	return pool[pool.size() - 1]


## 이 슬롯에 재가집 의뢰가 보장한 신령(없으면 &"").
func _uiroe_guarantee(s: int) -> StringName:
	var g: String = String(Save.active_uiroe_mods().get("deity_guarantee", ""))
	if g == "" or s < 0 or s >= times.size():
		return &""
	var hm: PackedStringArray = String(Data.get_value("meta_economy", "uiroe.deity_guarantee_slot", "06:30")).split(":")
	var at: float = float(hm[0]) * 60.0 + (float(hm[1]) if hm.size() > 1 else 0.0)
	return StringName(g) if absf(times[s] - at) < 1.0 else &""


func _pick_candidates(s: int) -> void:
	var pool: Array[StringName] = _pool(s)
	if pool.size() < 2:
		# 예외: 물러난 신령까지 포함
		for id: Variant in Data.deity_ids():
			var d: StringName = StringName(String(id))
			if not possessed.has(d) and not pool.has(d) and String(Data.deity(String(d)).get("scope", "v1")) == "v1":
				pool.append(d)
	var a: StringName
	var b: StringName
	if pool.size() <= 2:
		a = pool[0] if pool.size() > 0 else &"deity_sansin"
		b = pool[1] if pool.size() > 1 else a
	elif s == 0 and pool.has(momju):
		a = momju
		var rest: Array[StringName] = pool.duplicate()
		rest.erase(momju)
		b = _weighted_pick(rest, s)
	elif _uiroe_guarantee(s) != &"" and pool.has(_uiroe_guarantee(s)):
		# 재가집 의뢰 신령 보장(meta: active_uiroe_mods.deity_guarantee, 슬롯 meta_economy uiroe.deity_guarantee_slot) — core 통합
		a = _uiroe_guarantee(s)
		var rest3: Array[StringName] = pool.duplicate()
		rest3.erase(a)
		b = _weighted_pick(rest3, s)
	else:
		a = _weighted_pick(pool, s)
		var rest2: Array[StringName] = pool.duplicate()
		rest2.erase(a)
		b = _weighted_pick(rest2, s)
	if _rng.randf() < 0.5:
		cand[0] = a
		cand[1] = b
	else:
		cand[0] = b
		cand[1] = a
	appeared[cand[0]] = true
	appeared[cand[1]] = true


func _reroll_pool() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in Data.deity_ids():
		var d: StringName = StringName(String(id))
		if String(Data.deity(String(d)).get("scope", "v1")) != "v1":
			continue
		if possessed.has(d) or d == cand[0] or d == cand[1]:
			continue
		out.append(d)
	out.sort()
	return out


## 산통(算筒): 반경 1.2유닛에 0.6초 머물면 다시 묻기(06 §4.4).
func _tick_santong(dt: float, pp: Vector2) -> void:
	if not santong_on:
		return
	if pp.distance_to(santong_pos) <= 1.2 * K.UNIT_PX:
		santong_k += dt / 0.6
		if santong_k >= 1.0:
			santong_k = 0.0
			var rp: Array[StringName] = _reroll_pool()   # 이벤트 시점 할당
			if rp.is_empty() or reroll_left <= 0 or reroll_used >= 2:
				santong_on = false
				return
			_do_reroll(rp)
	else:
		santong_k = maxf(0.0, santong_k - dt * 2.0)


func _do_reroll(rp: Array[StringName]) -> void:
	reroll_left -= 1
	reroll_used += 1
	var keep_momju: int = -1
	if slot == 0:
		keep_momju = cand.find(momju)
	if keep_momju >= 0:
		cand[1 - keep_momju] = _weighted_pick(rp, slot)
	elif rp.size() >= 2:
		var a: StringName = _weighted_pick(rp, slot)
		var rest: Array[StringName] = rp.duplicate()
		rest.erase(a)
		cand[0] = a
		cand[1] = _weighted_pick(rest, slot)
	else:
		var cur: Array[StringName] = [cand[0], cand[1]]
		cand[_rng.randi_range(0, 1)] = rp[0]
		if cand[0] == cand[1]:
			cand[0] = cur[0]
	appeared[cand[0]] = true
	appeared[cand[1]] = true
	reroll_t = Game.time_sec()
	if ph == Ph.DESCEND or ph == Ph.CONFIRM:
		descend_end = maxf(descend_end, Game.time_sec() + 5.0)
	santong_on = reroll_left > 0 and reroll_used < 2 and not _reroll_pool().is_empty()
	Audio.play_sfx(&"sfx_ui_reroll", &"UI", 0.0)
	Events.trial_candidates.emit(slot + 1, cand[0], cand[1])
	_say(cand[0], &"gs_omen", 1)
	_log("reroll slot=%d cand=%s,%s left=%d" % [slot + 1, cand[0], cand[1], reroll_left])


func _auto_pick(pp: Vector2) -> void:
	var d0: float = pp.distance_to(circle[0])
	var d1: float = pp.distance_to(circle[1])
	var i: int = 0
	if absf(d0 - d1) < 1.0:
		i = 1 if cand[1] == momju else 0
	else:
		i = 0 if d0 < d1 else 1
	pick = i
	auto_picked = true
	var pl: Player = Game.player as Player
	var md: Vector2 = pl.last_move_dir if pl != null else Vector2.RIGHT
	anchor = pp + md * 3.0 * K.UNIT_PX
	_enter_clear()


# ─── CLEAR · TRIAL ─────────────────────────────────────────────────────

func _enter_clear() -> void:
	active_deity = cand[pick]
	var other: StringName = cand[1 - pick]
	if other != active_deity:
		retreat_until[other] = slot + 2
		retreated_now = other
	_set_ph(Ph.CLEAR)
	Audio.play_sfx(&"sfx_trl_sinjangdae", &"SFX", 0.0)
	_say(active_deity, &"gs_pick", 1)
	# 마당 결계: 반경 안 잡귀 밀어내기(enemies API 가 있으면). TODO(enemies): push_radial(center, r_px, dist_px)
	var em: EnemyManager = Game.enemies as EnemyManager
	if em != null and em.has_method("push_radial"):
		em.call("push_radial", anchor, circle_r, 4.0 * K.UNIT_PX)
	if Game.vfx != null:
		(Game.vfx as VfxPlayer).play(StringName("vfx_trial_block_wall_" + Defs.vfx_key(active_deity)), anchor, 0.0, 1.0, {"additive": true, "z": -1})
	Juice.add_trauma(0.12)
	_log("pick slot=%d deity=%s auto=%s anchor=(%d,%d) retreat=%s" % [slot + 1, active_deity, auto_picked, int(anchor.x), int(anchor.y), other])


func _enter_trial() -> void:
	var now: float = Game.time_sec()
	_set_ph(Ph.TRIAL)
	_trial_t0 = now
	trial_dur_cur = trial_dur_slot[slot] if slot >= 0 and slot < trial_dur_slot.size() else trial_dur
	t_left = trial_dur_cur
	wieom = 0.0
	gaho = 0.0
	wieom_dmg = 0.0
	task_pct = 0.0
	side_w = 0.0
	side_g = 0.0
	leaving = false
	_left_said = false
	_tw_said = false
	_first_full = &""
	trial_phase = 1
	_gauge_emit_w = -1.0
	_gauge_emit_g = -1.0
	_w_step = 0
	_g_step = 0
	_w_pop_step = 0
	_hp_min = Game.hp
	wieom_hp = _calc_wieom_hp(now, active_deity)
	var pp: Vector2 = Game.player.global_position if Game.player != null else anchor
	var start: Vector2 = anchor + (anchor - pp).normalized() * 3.0 * K.UNIT_PX if anchor.distance_squared_to(pp) > 16.0 else anchor + Vector2(0, -3.0 * K.UNIT_PX)
	avatar.call("setup", active_deity, n, anchor, start, now)
	if easy_trial and slot == 0:
		wieom_hp = maxf(100.0, roundf(wieom_hp * EASY_HP_MULT / 10.0) * 10.0)
		avatar.set("dmg_scale", float(avatar.get("dmg_scale")) * EASY_DMG_MULT)
	task.call("setup", active_deity, n, anchor, pp, now)
	Events.trial_start.emit(slot + 1, active_deity)
	_say(active_deity, &"gs_start", 1)
	_log("trial_start slot=%d deity=%s hp_wieom=%d (anchor %d, rate %.1f/s) limit=%.0fs easy=%s" % [slot + 1, active_deity, int(wieom_hp), int(wieom_hp_anchor), wieom_rate, trial_dur_cur, easy_trial and slot == 0])


func _calc_wieom_hp(now: float, d: StringName) -> float:
	var anchors: Array = Data.get_value("deities", "dps_ref.anchors_min", [])
	var m: float = now / 60.0
	var dps: float = 45.0
	if anchors.size() > 0:
		dps = float(anchors[0].get("dps", 45))
		for i in anchors.size() - 1:
			var a0: Dictionary = anchors[i]
			var a1: Dictionary = anchors[i + 1]
			if m >= float(a0["min"]) and m <= float(a1["min"]):
				dps = lerpf(float(a0["dps"]), float(a1["dps"]), (m - float(a0["min"])) / maxf(0.01, float(a1["min"]) - float(a0["min"])))
				break
			if m > float(a1["min"]):
				dps = float(a1["dps"])
	var mod: float = float(Data.deity(String(d)).get("avatar", {}).get("deity_mod", 1.0))
	wieom_hp_anchor = maxf(100.0, roundf(dps * wieom_hp_s * mod / 10.0) * 10.0)
	# dps_ref 는 '전탄 명중' 기준이라 발사 1회 = 시험 1타인 실제 판정보다 크다 → 최근 20초 실측 기대 피해로 맞춘다.
	# 화신 곁(사거리 안)에 계속 붙어 있으면 약 wieom_hp_seconds 에 차도록(숨 고르기 ×1.5·마당 위엄 가산은 덤).
	var acc: float = 0.0
	for v: float in _rate_buf:
		acc += v
	wieom_rate = acc / float(RATE_WIN)
	if wieom_rate <= 0.0:
		return wieom_hp_anchor
	# 측정 DPS 의 hp_meas_mult(1.2)배: 화신 곁에 붙어도 약 20초, 피하느라 떨어지면 제한시간 안에 못 채울 수 있다(미완이 실제로 일어난다).
	var measured: float = roundf(wieom_rate * wieom_hp_s * mod * hp_meas_mult / 10.0) * 10.0
	return maxf(100.0, minf(wieom_hp_anchor, maxf(measured, wieom_hp_anchor * 0.12)))


## 시련 밖 무구 발사 → 초당 기대 시험 피해 버킷(무작위 소비 없음: 치명 기대값만).
func _rate_add(w: WeaponBase, now: float) -> void:
	var sec: int = int(now)
	if sec != _rate_sec:
		# 지난 버킷부터 지금까지 비운다(최대 RATE_WIN 칸)
		var gap: int = mini(RATE_WIN, sec - _rate_sec) if _rate_sec >= 0 else RATE_WIN
		for k in gap:
			_rate_buf[(sec - k + RATE_WIN * 4) % RATE_WIN] = 0.0
		_rate_sec = sec
	var coef: float = col_coef_red
	if w.color == K.DmgColor.WHITE:
		coef = col_coef_white
	elif w.color == K.DmgColor.UNION:
		coef = col_coef_union
	var amt: float = maxf(1.0, w.s("amt", 1.0))
	var e: float = w.s("dmg", 5.0) * (1.0 + 0.5 * (amt - 1.0)) * Game.stat(&"stat_sinppal", 1.0) * coef
	if w.color != K.DmgColor.WHITE:
		e *= 1.0 + clampf(Game.stat(&"stat_gyeoldan", 0.05) + w.s("crit", 0.0), 0.0, 0.5)
	_rate_buf[sec % RATE_WIN] += e


func _tick_trial(dt: float, now: float, pp: Vector2) -> void:
	var el: float = now - _trial_t0
	t_left = maxf(0.0, trial_dur_cur - el)
	# 마당 이탈(14 초과 → ×0.5, 12 미만 복귀)
	var da: float = pp.distance_to(anchor)
	if leaving and da < leave_back:
		leaving = false
	elif not leaving and da > leave_dist:
		leaving = true
		if not _left_said:
			_left_said = true
			_say(active_deity, &"gs_leave", 6)
	var pos_k: float = 0.5 if leaving else 1.0
	avatar.call("sim_step", dt, now, pp)
	var g: float = float(task.call("sim_step", dt, now, pp))
	task_pct += g * pos_k * gauge_mult
	# 페이즈(위엄 진척도 반영)
	var p: int = 1
	if el >= 20.0 or wieom >= 0.75:
		p = 3
	elif el >= 10.0 or wieom >= 0.40:
		p = 2
	if p != trial_phase:
		trial_phase = p
		avatar.call("set_phase", p)
	_update_gauges()
	if wieom >= 1.0 or gaho >= 1.0:
		var f: StringName = _first_full
		if f == &"":
			f = &"wieom" if wieom >= gaho else &"gaho"
		_resolve(f, true)
		return
	if t_left <= 5.0 and not _tw_said:
		_tw_said = true
		Audio.play_sfx(&"sfx_trl_timeout_warn", &"SFX", -4.0)
	if t_left <= 0.0:
		var f2: StringName = &"wieom"
		if gaho > wieom:
			f2 = &"gaho"
		elif gaho == wieom:
			var dm: Dictionary = Data.get_value("deities", "character_mods", {}).get(String(Game.char_id), {})
			f2 = StringName(String(dm.get("default_face", "wieom")))
		_resolve(f2, false)


func _update_gauges() -> void:
	var w: float = wieom_dmg / maxf(1.0, wieom_hp) + side_w * 0.01
	var g: float = (task_pct + side_g) * 0.01
	if _first_full == &"":
		if w >= 1.0 and g < 1.0:
			_first_full = &"wieom"
		elif g >= 1.0 and w < 1.0:
			_first_full = &"gaho"
		elif w >= 1.0 and g >= 1.0:
			_first_full = &"wieom" if w >= g else &"gaho"
	wieom = clampf(w, 0.0, 1.0)
	gaho = clampf(g, 0.0, 1.0)
	# 10% 눈금마다 한 번: 위엄 = 북 울림 / 가호 = 방울 — 게이지가 '찬다'는 감각
	var ws: int = int(wieom * 10.0)
	if ws > _w_step:
		_w_step = ws
		Audio.play_sfx(&"sfx_trl_wieom_step", &"SFX", -6.0, 0.03)
	var gs: int = int(gaho * 10.0)
	if gs > _g_step:
		_g_step = gs
		Audio.play_sfx(&"sfx_trl_gaho_step", &"SFX", -6.0, 0.03)
	if absf(wieom - _gauge_emit_w) >= 0.004 or absf(gaho - _gauge_emit_g) >= 0.004:
		_gauge_emit_w = wieom
		_gauge_emit_g = gaho
		Events.trial_gauge_changed.emit(slot + 1, wieom, gaho)


func _resolve(face: StringName, is_complete: bool) -> void:
	res_face = face
	res_complete = is_complete
	avatar.call("smile")
	_set_ph(Ph.RESOLVE)
	Events.trial_end.emit(slot + 1, active_deity, face)
	Audio.play_sfx(&"sfx_trl_avatar_smile", &"SFX", 0.0)
	if is_complete:
		_say(active_deity, StringName("gs_pass_" + String(face)), 1)
	else:
		_say(active_deity, &"gs_incomplete", 1)
	var el: float = Game.time_sec() - _trial_t0
	_set_perf(is_complete, el, int(avatar.get("hits_on_player")))
	_log("resolve slot=%d deity=%s face=%s complete=%s dur=%.1fs wieom=%.2f gaho=%.2f (task %.0f%% side_w %.1f side_g %.1f dmg %d/%d) hits_on_player=%d hp_min=%d/%d leaving=%s perf=%s" % [
		slot + 1, active_deity, face, is_complete, el, wieom, gaho, task_pct, side_w, side_g, int(wieom_dmg), int(wieom_hp),
		int(avatar.get("hits_on_player")), int(_hp_min), int(Game.hp_max), leaving, perf_tier])


## 시련 수행 → 점지 등급 가중(data constants.grade_by_performance). 점괘(grade_formula)는 그 위의 보정치.
##   clean: 완수 · fast_s 안 · 피격 clean_hits 이하 → 최소 길 / bonus: 가호 과제 bonus_task_pct 이상 또는 무피격 → 대길 가중 ×2
##   미완: 대길 없음, 길 가중 ×0.5
func _set_perf(is_complete: bool, el: float, hits: int) -> void:
	perf_min_gil = false
	perf_daegil_mult = 1.0
	perf_gil_mult = 1.0
	if not is_complete:
		perf_tier = &"incomplete"
		perf_daegil_mult = 0.0
		perf_gil_mult = float(perf_cfg.get("incomplete_gil_mult", 0.5))
		return
	var bonus: bool = task_pct >= float(perf_cfg.get("bonus_task_pct", 50)) or hits == 0
	if bonus:
		perf_daegil_mult = float(perf_cfg.get("daegil_bonus_mult", 2.0))
	if el <= float(perf_cfg.get("fast_s", 20)) and hits <= int(perf_cfg.get("clean_hits", 2)):
		perf_min_gil = true
		perf_tier = &"clean_bonus" if bonus else &"clean"
	else:
		perf_tier = &"bonus" if bonus else &"plain"


# ─── POSSESSION(1.2s, 비정지·무적) ─────────────────────────────────────

func _enter_possession() -> void:
	_set_ph(Ph.POSSESSION)
	_poss_step = 0
	var pl: Player = Game.player as Player
	if pl != null:
		pl.hit.iframe_left = maxf(pl.hit.iframe_left, possession_s + 0.2)
	Audio.play_sfx(StringName("sfx_trl_bingui__" + Defs.vfx_key(active_deity)), &"SFX", -6.0)


func _tick_possession(now: float, pp: Vector2) -> void:
	var t: float = now - ph_t0
	if _poss_step == 0 and t >= 0.5:
		_poss_step = 1
		_shockwave(pp)
	if _poss_step == 1 and t >= 0.55:
		_poss_step = 2
		_snap_overlay(pp)
	if _poss_step == 2 and t >= 0.9:
		_poss_step = 3
		_say(active_deity, &"gs_possessed_momju" if active_deity == momju else &"gs_possessed", 1)
	if _poss_step == 3 and t >= possession_s:
		_poss_step = 4
		_open_jeomji()


## 빙의 충격파(06 §3.8): 위엄 = 적 base_red×5 / 가호 = 풀릴 기색 즉시 해원 + 백 base_white×3. 넉백 4. 미완 반경 4.
func _shockwave(pp: Vector2) -> void:
	var sw: Dictionary = Data.get_value("deities", "constants.shockwave", {})
	var r: float = float(sw.get("radius", 6) if res_complete else sw.get("incomplete_radius", 4)) * K.UNIT_PX
	var kb: float = float(sw.get("knockback", 4))
	shock_t = Game.time_sec()
	shock_pos = pp
	shock_r = r
	var em: EnemyManager = Game.enemies as EnemyManager
	if em == null:
		return
	if res_face == &"wieom":
		var dm: float = float(powers.call("base_max", false)) * float(sw.get("wieom_dmg_x_base_red", 5))
		powers.call("strike_circle", pp, r, dm, K.DmgColor.RED, kb, 200)
	else:
		var cnt: int = em.query_circle(pp, r, _q, _q.size())
		for k in cnt:
			var s: int = _q[k]
			if em.is_alive(s) and (em.flags[s] & EnemyManager.F_PULLIL) != 0:
				em.force_haewon(s, &"white")
		var dw: float = float(powers.call("base_max", true)) * float(sw.get("gaho_dmg_x_base_white", 3))
		powers.call("strike_circle", pp, r, dw, K.DmgColor.WHITE, kb, 200)
	Juice.kick(Vector2.DOWN, 2)


func _snap_overlay(pp: Vector2) -> void:
	overlay_deity = active_deity
	overlay_face = res_face
	overlay_t = Game.time_sec()
	if not possessed.has(active_deity):
		possessed.append(active_deity)
	var mult: float = face_pct_mult * (1.0 if res_complete else incomplete_mult)
	powers.call("apply_face", active_deity, res_face, res_complete, mult)
	if Game.vfx != null:
		(Game.vfx as VfxPlayer).play(StringName("vfx_bingui_pillar_" + Defs.vfx_key(active_deity)), pp + Vector2(0, 2), 0.0, 1.0, {"additive": true, "z": 1})   # z 3→1: 정예 층(무당 z2 아래, design/18 §1.3)
	# 빙의 = 굿의 정점: Juice EVENTS["bingui"](T3, 킥 2, 트라우마 .5, 히트스톱 events_ms.bingui 120, 한지 플래시).
	# 미완 빙의는 같은 문법을 한 단계 낮춰(트라우마 .3, 히트스톱 80ms, 플래시 절반) '덜 실렸다'를 몸으로 느끼게 한다.
	if res_complete:
		Juice.feedback_event("bingui", Vector2.DOWN, 0.5)
	else:
		Juice.kick(Vector2.DOWN, 2)
		Juice.add_trauma(0.3)
		Juice.hitstop(80, 3)
		Juice.flash(K.COL_HANJI, 0.18, 0.10)
	Audio.play_sfx(&"sfx_trl_bingui", &"SFX", 0.0)
	_add_sinmyeong(0.10)
	Events.possession_changed.emit(active_deity, true)
	Events.trial_resolved.emit(slot + 1, active_deity, res_face, res_complete)


func _add_sinmyeong(v: float) -> void:
	var rr: Node = Game.run_root
	if rr == null:
		return
	var hs: Variant = rr.get("haewon")
	if hs is Object and (hs as Object).has_method("add_sinmyeong"):
		(hs as Object).call("add_sinmyeong", v)


# ─── 빙의 점지(정지) ───────────────────────────────────────────────────

func _open_jeomji() -> void:
	var cards: Array = powers.call("jeomji_cards", active_deity, res_face, res_complete, active_deity == momju, perf_min_gil, perf_daegil_mult, perf_gil_mult)
	_pending_cards.clear()
	for c: Variant in cards:
		_pending_cards.append(c)
	if _pending_cards.is_empty():
		_after_jeomji()
		return
	_set_ph(Ph.JEOMJI)
	_jeomji_open = true
	Game.push_pause(&"bingui_jeomji")
	_jeomji.call("open", _pending_cards, active_deity, res_face, res_complete)


## bingui_jeomji.gd 가 호출.
func on_jeomji_chosen(idx: int) -> void:
	if not _jeomji_open:
		return
	_jeomji_open = false
	if idx >= 0 and idx < _pending_cards.size():
		var c: Dictionary = _pending_cards[idx]
		powers.call("gain_power", c)
		_log("jeomji slot=%d pick=%s grade=%s" % [slot + 1, c.get("power_id", ""), c.get("grade", "")])
	Game.pop_pause(&"bingui_jeomji")
	var pl: Player = Game.player as Player
	if pl != null:
		pl.hit.iframe_left = maxf(pl.hit.iframe_left, 0.75)
	_after_jeomji()


func _after_jeomji() -> void:
	_set_ph(Ph.AFTERGLOW)
	if retreated_now != &"":
		_say(retreated_now, &"gs_retreat", 2)


# ─── 위엄 시험 타격(무구 발사 → 화신) ───────────────────────────────────

func _on_weapon_fired(wid: StringName, wslot: int, _pos: Vector2) -> void:
	var wm: WeaponManager = Game.weapons as WeaponManager
	var w: WeaponBase = wm.weapon_at(wslot) if wm != null else null
	if w != null:
		powers.call("on_weapon_fired", w)
		if ph < Ph.CLEAR or ph > Ph.RESOLVE:
			_rate_add(w, Game.time_sec())
	if ph != Ph.TRIAL or w == null or Game.player == null:
		return
	if not bool(avatar.call("targetable")):
		return
	var pp: Vector2 = Game.player.global_position
	var ap: Vector2 = avatar.get("pos")
	var d: float = pp.distance_to(ap) / K.UNIT_PX
	var coef: float = col_coef_red
	if w.color == K.DmgColor.WHITE:
		coef = col_coef_white
		if d > white_reach_u:
			return
	else:
		if w.color == K.DmgColor.UNION:
			coef = col_coef_union
		if d > reach_u:
			return
	var amt: float = maxf(1.0, w.s("amt", 1.0))
	var roll: Vector2 = DamageCalc.roll(w.s("dmg", 5.0) * (1.0 + 0.5 * (amt - 1.0)), w.color == K.DmgColor.WHITE, w.s("crit", 0.0), 1.0)
	var vul: bool = bool(avatar.call("is_vulnerable"))
	var dmg: float = roll.x * coef * (vuln_mult if vul else 1.0) * (0.5 if leaving else 1.0) * gauge_mult
	wieom_dmg += dmg
	var now: float = Game.time_sec()
	avatar.set("flash_until", now + 0.07)
	last_hit_t = now
	last_hit_from = pp
	last_hit_crit = roll.y > 0.5 or vul
	if now - _hit_sfx_t >= 0.07:
		_hit_sfx_t = now
		Audio.play_sfx(StringName("sfx_" + String(wid) + "_hit"), &"SFX", -4.0, 0.08)
	# 신령은 처치 대상이 아니다(06 §G5): 피해 숫자·붉은 퇴치 파열 없음. 대신 trial_view 가 황·한지 '징' 울림 고리를 그리고,
	# 위엄 게이지가 5% 오를 때마다(0.4초에 1회까지) 화신 위에 '위엄' 글자가 떠오른다(wieom_pop_t).
	if vul:
		Juice.kick(ap - pp, 1)
	_update_gauges()
	var ps: int = int(wieom * 20.0)
	if ps > _w_pop_step and now - wieom_pop_t >= 0.4:
		_w_pop_step = ps
		wieom_pop_t = now


# ─── 이벤트 ────────────────────────────────────────────────────────────

func _on_enemy_hit(_h: int, _sp: StringName, pos: Vector2, dmg: float, color: int, _crit: bool, _locked: bool) -> void:
	powers.call("on_enemy_hit", pos, dmg, color)


func _on_enemy_killed(_h: int, sp: StringName, pos: Vector2, kind: StringName, _c: StringName, tier: StringName) -> void:
	powers.call("on_enemy_killed", kind, pos, tier)
	if kind == K.KIND_HAEWON and tier != K.TIER_COMMON and tier != K.TIER_MINION and not possessed.is_empty():
		_say(_speaker(), &"gs_elite_haewon", 3)
	if ph != Ph.TRIAL:
		return
	var g: float = float(task.call("on_enemy_killed", sp, pos, kind))
	task_pct += g * gauge_mult * (0.5 if leaving else 1.0)
	if pos.distance_to(anchor) <= ground_r:
		var elite: bool = tier != K.TIER_COMMON and tier != K.TIER_MINION
		if kind == K.KIND_TOECHI:
			var add: float = float(side_feed.get("elite_toechi_wieom_pct", 3)) if elite else float(side_feed.get("toechi_wieom_pct", 0.3))
			side_w = minf(float(side_feed.get("wieom_cap_pct", 10)), side_w + add)
		else:
			var addg: float = float(side_feed.get("elite_haewon_gaho_pct", 4)) if elite else float(side_feed.get("haewon_gaho_pct", 0.5))
			side_g = minf(float(side_feed.get("gaho_cap_pct", 15)), side_g + addg)


func _on_ring_closed(area: int, _hc: int, centroid: Vector2) -> void:
	powers.call("on_ring_closed", centroid, area)
	if area > 0 and not possessed.is_empty() and ph != Ph.TRIAL:
		_say(_speaker(), &"gs_gildakkeum", 3)
	if ph != Ph.TRIAL:
		return
	var g: float = float(task.call("on_ring_closed", area, centroid))
	if g > 0.0:
		task_pct += g * gauge_mult
	elif centroid.distance_to(anchor) <= ground_r and area > 0:
		side_g = minf(float(side_feed.get("gaho_cap_pct", 15)), side_g + float(side_feed.get("gildakkeum_gaho_pct", 2)))


func _on_player_damaged(amt: float, source: StringName, _hp: float, _hpm: float) -> void:
	powers.call("on_player_damaged", amt)
	if ph == Ph.TRIAL and Game.player != null:
		task.call("on_player_damaged", source, Game.player.global_position)


# ─── 합일(18:00) ───────────────────────────────────────────────────────

func _enter_hapil_omen() -> void:
	hapil_done = true
	hapil_done_compat = true
	hapil_ids.clear()
	var order: Array = Data.get_value("deities", "hapil.call_order", [])
	for id: Variant in order:
		if possessed.has(StringName(String(id))):
			hapil_ids.append(StringName(String(id)))
	hapil_pos.clear()
	var k: int = hapil_ids.size()
	for i in k:
		hapil_pos.append(Vector2.from_angle(-PI * 0.5 + TAU * float(i) / maxf(1.0, float(k))) * 3.0 * K.UNIT_PX)
	slot = 4
	_set_ph(Ph.HAPIL_OMEN)
	_say_text(&"", "모신 신령이 모두 내린다…" if k > 0 else "모신 신령이 없다. 홀로 굿판을 지킨다.", 1)
	Audio.play_sfx(&"sfx_trl_omen", &"SFX", 0.0)
	_log("hapil_omen deities=%s" % [hapil_ids])
	if k == 0:
		_set_ph(Ph.HAPIL_ACTIVE)


func _hapil_beat(pp: Vector2) -> void:
	hapil_idx += 1
	var now: float = Game.time_sec()
	if hapil_idx < hapil_ids.size():
		var d: StringName = hapil_ids[hapil_idx]
		hapil_word = Defs.call_word(d)
		hapil_word_t = now
		Events.hapil_call.emit(d, hapil_word, hapil_idx)
		_say_text(d, hapil_word, 2)
		if Game.vfx != null:
			(Game.vfx as VfxPlayer).play(StringName("vfx_bingui_pillar_" + Defs.vfx_key(d)), pp + hapil_pos[hapil_idx], 0.0, 1.0, {"additive": true, "z": 1})   # z 3→1: 정예 층(무당 z2 아래, design/18 §1.3)
		Audio.play_sfx(StringName("sfx_trl_bingui__" + Defs.vfx_key(d)), &"SFX", -2.0)
		Juice.kick(-hapil_pos[hapil_idx], 1)
		return
	# 마지막 강박: "다 실렸다!"
	hapil_word = String(Data.get_value("deities", "hapil.call_final", "다 실렸다!"))
	hapil_word_t = now
	hapil_form = powers.call("apply_hapil")
	shock_t = now
	shock_pos = pp
	shock_r = 7.0 * K.UNIT_PX
	powers.call("strike_circle", pp, shock_r, float(powers.call("base_max", false)) * 4.0, K.DmgColor.RED, 4.0, 240)
	var em: EnemyManager = Game.enemies as EnemyManager
	if em != null:
		var cnt: int = em.query_circle(pp, shock_r, _q, _q.size())
		for k in cnt:
			if em.is_alive(_q[k]) and (em.flags[_q[k]] & EnemyManager.F_PULLIL) != 0:
				em.force_haewon(_q[k], &"white")
	if Game.vfx != null:
		for i in hapil_ids.size():
			(Game.vfx as VfxPlayer).play(StringName("vfx_bingui_pillar_" + Defs.vfx_key(hapil_ids[i])), pp + hapil_pos[i], 0.0, 1.0, {"additive": true, "z": 1})   # z 3→1: 정예 층(무당 z2 아래, design/18 §1.3)
		(Game.vfx as VfxPlayer).play(&"vfx_jakdu_shockwave", pp, 0.0, 2.0, {"additive": true})
	_hapil_feedback()
	Audio.play_sfx(&"sfx_trl_hapil", &"SFX", 0.0)
	_add_sinmyeong(0.5)
	_say_text(&"", hapil_word, 2)
	Events.hapil_start.emit(hapil_ids.duplicate())
	Events.hapil_complete.emit(hapil_form, hapil_ids.duplicate())
	_set_ph(Ph.HAPIL_ACTIVE)
	_log("hapil form=%s deities=%s gangsin=%d hp_max=%d sinppal=%.2f" % [hapil_form, hapil_ids, int(powers.get("gangsin")), int(Game.hp_max), Game.stat(&"stat_sinppal", 1.0)])


## 합일 타격감: Juice EVENTS["hapil"](T4, 킥 2, 트라우마 .8, 히트스톱 150, 황 플래시 .30/.20). 표에 아직 없으면 같은 값으로 직접.
func _hapil_feedback() -> void:
	if Juice.EVENTS.has("hapil"):
		Juice.feedback_event("hapil", Vector2.DOWN)
		return
	Juice.kick(Vector2.DOWN, 2)
	Juice.add_trauma(0.8)
	Juice.hitstop(150, 4)
	Juice.flash(K.COL_HWANG, 0.30, 0.20)


func _on_boss_spawned(_h: int, _sp: StringName, _form: StringName) -> void:
	if _boss_said or possessed.is_empty():
		return
	_boss_said = true
	_say(_speaker(), &"gs_boss", 2)


# ─── 공수 자막 ─────────────────────────────────────────────────────────

## 평시 공수 화자: 모신 신령 가운데 하나(연출 난수). 가장 최근 빙의 신령이 절반.
func _speaker() -> StringName:
	if possessed.is_empty():
		return &""
	if overlay_deity != &"" and Rng.chance(&"fx", 0.5):
		return overlay_deity
	return possessed[Rng.int_s(&"fx", 0, possessed.size() - 1)]


func _say(deity: StringName, trigger: StringName, prio: int) -> void:
	var now: float = Game.time_sec()
	if prio >= 3 and now - gongsu_t < 12.0:
		return
	var face: StringName = (powers.get("faces") as Dictionary).get(deity, &"")
	if face == &"" and deity == active_deity and ph >= Ph.RESOLVE and ph <= Ph.AFTERGLOW:
		face = res_face
	var line: String = Defs.gongsu(deity, String(trigger), face)
	if line == "":
		return
	gongsu_text = line
	gongsu_deity = deity
	gongsu_t = now
	gongsu_prio = prio
	# 맛보기 공수(prio<2)는 5초 간격으로만 화면에 낸다(design/18 §2.3 — 8초는 오컬트 맛을 지나치게 깎았다, 리뷰 hitfeel). 상태·난수 소비는 그대로 두어 시뮬레이션이 갈라지지 않게 한다.
	if prio < 2:
		if now - _low_say_t < 5.0:
			return
		_low_say_t = now
	# 쉬운 첫 시험: 공수 인용을 화면에 내지 않는다(글 줄이기, design/19 §4.6). 상태·난수는 위에서 이미 같다.
	if easy_trial and slot == 0 and ph >= Ph.OMEN and ph <= Ph.AFTERGLOW:
		return
	Events.gongsu_spoken.emit(deity, trigger, line)
	Audio.play_sfx(&"sfx_ui_gongsu_show", &"UI", -8.0)


func _say_text(deity: StringName, line: String, prio: int) -> void:
	gongsu_text = line
	gongsu_deity = deity
	gongsu_t = Game.time_sec()
	gongsu_prio = prio
	Events.gongsu_spoken.emit(deity, &"gs_hapil_word", line)


func _log(s: String) -> void:
	log_lines.append(s)
	print("[trial] ", s)
