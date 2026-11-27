class_name TutorialDirector
extends Node
## 연습 굿판 디렉터(design/17 §5). 소유: tutorial_run.
## main.start_tutorial 이 런 씬의 마지막 자식으로 붙인다(R4: Run._ready 보다 먼저 _ready 가 돈다).
##   _ready  : 기본 웨이브 끔 · 자동 시련/합일 끔 · 점지 게이트 닫음(형제 노드는 이미 준비됨 — get_node 로 접근).
##   _begin  : (call_deferred, Game.reset_run·무구 설정 뒤) 방울 예약 지움 · 월드 표지 · HUD · 봇 · tutorial_started.
## 규칙
##  - 신호 처리기는 표시(카운터·플래그)만 세운다. 스폰은 _physics_process(Run 틱 다음)에서만(피해 해석 도중 스폰 금지).
##  - 시각은 게임 시각(Game.time_sec, 멈춤 제외). 자동 ack·종료 대기만 실시간.
##  - 실패 없음: 정기 35% 아래면 70%로 채운다. 0이 되어도 run.gd 가 죽음 대신 가득 채운다.
##  - 저장: practice_done 플래그 · ui.practice_log(최근 5회)만. flags.tutorial_done 은 건드리지 않는다(F3).

## 점지 단계 뒤 단계에서 이름표가 뜨는 동안 점지 창을 미루는 시간(게임 초)
const GATE_HOLD_S: float = 2.5
var _gate_reopen_at: float = -1.0

const STEP_IDS: Array[StringName] = [&"move", &"beat", &"cut", &"ring", &"white", &"yeongga", &"jeomji", &"trial", &"sal", &"settle"]
const Copy = preload("res://tutorial/tutorial_copy.gd")
const MarksScript = preload("res://tutorial/tutorial_marks.gd")
const HUD_PATH: String = "res://ui/tutorial_hud.gd"
const U: float = 32.0
const HAN_GISEAK: float = 18.0          # 신칼 Lv1(14) 1타에 풀릴 기색(≤35%), 다음 타부터 매듭 잠금(F11)
const STEP_TIMEOUT: float = 120.0       # --tutorial-autotest: 넘기면 push_error 후 강제 완료
const SP_GAEK: StringName = &"enm_gaekgwi"
const SP_DAL: StringName = &"enm_dalgyal_gwisin"
## 도움 단계 시각(단계 시작 뒤 게임 초). 'sal' 은 9b(원귀) 시작 뒤로 잰다.
const HELP_T: Dictionary = {
	&"move": {1: 8.0},
	&"beat": {1: 15.0, 2: 30.0, 3: 60.0, 4: 120.0},
	&"cut": {1: 15.0, 2: 30.0, 3: 60.0, 4: 120.0},
	&"ring": {1: 12.0, 2: 30.0, 3: 60.0, 4: 120.0},
	&"white": {1: 15.0, 2: 30.0, 3: 60.0, 4: 120.0},
	&"yeongga": {1: 10.0, 3: 30.0},
	&"jeomji": {1: 15.0, 2: 30.0, 4: 120.0},
	&"trial": {},
	&"sal": {1: 12.0, 3: 35.0},
	&"settle": {},
}

var from_step: StringName = &""
var step_id: StringName = &""            # TutorialBot·HUD 가 읽는다
var ring_center: Vector2 = Vector2.ZERO  # TutorialBot 이 읽는다(고리 단계 무리 중심)

var run: Run = null
var em: EnemyManager = null
var pm: PickupManager = null
var wm: WeaponManager = null
var marks: Node2D = null
var hud: Node = null

var _auto: bool = false
var _persist: bool = true
var _begun: bool = false
var _finished: bool = false
var _idx: int = -1
var _t0: float = 0.0
var _help: int = 0
var _help_max: int = 0
var _met: bool = false
var _met_t: float = 0.0
var _complete_delay: float = 0.4
var _completed: bool = false
var _next_t: float = 0.0
var _c: Dictionary = {}                  # 단계별 카운터·플래그
var _delayed: Array = []                 # [[game_t, method, args]]
var _log_steps: Dictionary = {}
var _done_n: int = 0
var _t_begin: float = 0.0
var _ack_wait_real: float = -1.0
var _quit_wait_real: float = -1.0
var _exit_wait_real: float = -1.0
var _exit_next: StringName = &"title"
var _orig_auto_knot: bool = false
var _han_logged: int = 0
var _q: PackedInt32Array = PackedInt32Array()
var _skip_req: bool = false
var _hurry_trial: bool = false           # 시련 단계를 건너뛰면 뒤에서 도는 시련을 바로 매듭짓는다(_tick_hurry_trial)
var _skip_all_s: float = -1.0           # --tutorial-skip-all=<초>(자동 테스트): 단계마다 그 초에 건너뛰기 경로 시험
var _screen_t: float = 0.0               # 화면 시각(_process delta 합: 멈춤 카드·점지처럼 게임 시각이 멈춘 동안도 흐른다)
var _screen0: float = 0.0
var _shot_dir: String = ""               # --tutorial-shots=<절대 경로>(디버그, non-headless): 단계 대표 프레임만 PNG 로
var _shots: Array = []                   # [[screen_t, name]]
## 단계마다 사람이 목표 줄을 읽을 최소 게임 시각(완료 조건이 바로 차도 이만큼은 머문다).
## move: 시작 연출('연습 굿판' 1.2초) 뒤 목표 줄이 1.8초는 보이게. white: 앞 단계의 기색 귀신이 방울에 바로 풀려도.
const MIN_STEP_S: Dictionary = {&"move": 3.0, &"white": 4.0}


func _ready() -> void:
	name = "TutorialDirector"
	_q.resize(256)
	run = get_parent() as Run
	if run == null:
		push_error("[tutorial] TutorialDirector 는 Run 의 자식이어야 한다")
		return
	# @onready 는 Run._ready 직전에 채워지므로 여기서는 경로로 접근한다(형제 노드는 이미 준비됨).
	var sd: SpawnDirector = run.get_node("Systems/SpawnDirector") as SpawnDirector
	if sd != null:
		sd.enabled = false
	var td: TrialDirector = run.get_node("Systems/TrialDirector") as TrialDirector
	if td != null:
		td.times = PackedFloat32Array([1e9, 1e9, 1e9, 1e9])
		td.hapil_done = true
	run.jeomji_gate = false
	_auto = DebugTools.args.has("tutorial-autotest")
	_persist = (not _auto) or Game.autotest
	_shot_dir = DebugTools.arg("tutorial-shots")
	if _shot_dir != "":
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	if _auto and DebugTools.arg("tutorial-skip-all") != "":
		_skip_all_s = float(DebugTools.arg("tutorial-skip-all"))
	if _auto and not Game.autotest:
		push_warning("[tutorial] --tutorial-autotest 는 --autotest 와 함께 쓴다 — practice_done·practice_log 를 쓰지 않는다")
	if from_step == &"":
		from_step = &"move"
	if not STEP_IDS.has(from_step):
		push_warning("[tutorial] 모르는 단계 id '%s' → move" % from_step)
		from_step = &"move"
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.pullil_entered.connect(_on_pullil_entered)
	Events.enemy_hit.connect(_on_enemy_hit)
	Events.ring_closed.connect(_on_ring_closed)
	Events.level_up.connect(_on_level_up)
	Events.levelup_chosen.connect(_on_levelup_chosen)
	Events.trial_phase_changed.connect(_on_trial_phase)
	Events.trial_resolved.connect(_on_trial_resolved)
	Events.trial_gauge_changed.connect(_on_trial_gauge)
	Events.wongwi_return.connect(_on_wongwi_return)
	Events.enemy_spawned.connect(_on_enemy_spawned)
	Events.yeongga_cheondo.connect(_on_cheondo)
	Events.yeongga_joined.connect(_on_yeongga_joined)
	Events.tutorial_ack.connect(_on_ack)
	Events.tutorial_skip_step_requested.connect(skip_step)
	Events.tutorial_exit_requested.connect(_on_exit_requested)
	call_deferred("_begin")


func _begin() -> void:
	if run == null or not is_inside_tree():
		return
	em = Game.enemies as EnemyManager
	pm = Game.pickups as PickupManager
	wm = Game.weapons as WeaponManager
	if em == null or pm == null or wm == null:
		push_error("[tutorial] 런 서비스가 준비되지 않았다")
		return
	wm.drop_schedule(&"wpn_bangul")        # 방울은 '흰 무구' 단계에서 내린다
	marks = MarksScript.new()
	marks.name = "TutorialMarks"
	run.world.add_child(marks)
	if ResourceLoader.exists(HUD_PATH):
		var hs: Script = load(HUD_PATH) as Script
		if hs != null:
			hud = hs.new() as Node
			if hud != null:
				hud.name = "TutorialHud"
				run.add_child(hud)
	if _auto:
		var b: TutorialBot = TutorialBot.new()
		b.director = self
		run.player.set_bot(b)
	# --tutorial-step 준비(§5.5)
	var fi: int = STEP_IDS.find(from_step)
	if fi >= STEP_IDS.find(&"yeongga"):
		_give_bangul(false)
	if fi >= STEP_IDS.find(&"trial"):
		run.jeomji_gate = true
	_begun = true
	_t_begin = Game.time_sec()
	print("[tutorial] begin from=%s" % from_step)
	# 실전 기록 불변 검사(§9-3·4): 첫 연습 시작 때의 세이브 요약을 남겨 두고, 끝날 때 비교한다(다시 연습을 거쳐도 첫 값 기준).
	var snap: String = _save_snapshot()
	if not Engine.has_meta(&"tutorial_snap0"):
		Engine.set_meta(&"tutorial_snap0", snap)
	print("[tutorial] save %s" % snap)
	Events.tutorial_started.emit(from_step, STEP_IDS.size())
	_start_step(fi)


# ─── 진행 ──────────────────────────────────────────────────────────────

func step_elapsed() -> float:
	return Game.time_sec() - _t0


## 쉼 메뉴 '이 단계 건너뛰기'(Events.tutorial_skip_step_requested). 완료 연출 없이 다음 단계.
## 요청만 받아 두고 실제 전환(다음 단계 스폰)은 _physics_process 에서 한다(신호 처리기 안 스폰 금지).
func skip_step() -> void:
	if not _begun or _finished or _idx < 0:
		return
	_skip_req = true


func _do_skip() -> void:
	_skip_req = false
	if _finished or _idx < 0:
		return
	print("[tutorial] skip step=%s t=%.1f" % [step_id, Game.time_sec()])
	if not _log_steps.has(String(step_id)):
		_log_steps[String(step_id)] = {"dur": snappedf(step_elapsed(), 0.1), "help_max": _help_max, "skipped": true}
	if step_id == &"settle" and Game.has_pause(&"tutorial_card"):
		# HUD 가 카드를 닫게 ack 로 보낸다(pause 만 빼면 HUD 의 _card_on 이 남아 끝 화면 입력을 가로챈다)
		if hud != null:
			Events.tutorial_ack.emit(&"settle")
		if Game.has_pause(&"tutorial_card"):
			Game.pop_pause(&"tutorial_card")
	if step_id == &"trial" and run != null and run.trials != null and run.trials.ph != TrialDirector.Ph.DORMANT:
		_hurry_trial = true
	_advance()


func _start_step(i: int) -> void:
	_cleanup_step()
	_idx = i
	step_id = STEP_IDS[i]
	_t0 = Game.time_sec()
	_help = 0
	_help_max = 0
	_met = false
	_completed = false
	_complete_delay = 0.4
	_c = {}
	_screen0 = _screen_t
	# 앞 단계를 건너뛰었어도 뒤 단계가 성립하게: 방울(흰 무구 단계 뒤)·점지 게이트(점지 단계 뒤)
	if i > STEP_IDS.find(&"white"):
		_give_bangul(false)
	if i > STEP_IDS.find(&"jeomji"):
		# 단계 이름표(약 1.65초)가 떠 있는 동안은 점지 창이 덮지 않게 잠시 닫았다가 연다
		run.jeomji_gate = false
		_gate_reopen_at = _t0 + GATE_HOLD_S
	var d: Dictionary = Copy.STEPS[step_id]
	_lines(String(d.get("goal", "")), String(d.get("sub", "")))
	print("[tutorial] step=%s start t=%.1f" % [step_id, _t0])
	_shot(1.0, "a_goal")
	call("_enter_" + String(step_id))
	# --tutorial-exit-at=<id>(자동 테스트): 그 단계가 처음 시작되면 연습을 중간에 그만두고 다시 연습(종료 후 재실행 안전 검사)
	if _auto and DebugTools.arg("tutorial-exit-at") == String(step_id) and not Engine.has_meta(&"tutorial_exit_at_used"):
		Engine.set_meta(&"tutorial_exit_at_used", true)
		print("[tutorial] quit_mid step=%s → again" % step_id)
		_exit_next = &"again"
		_exit_wait_real = 0.5


func _advance() -> void:
	var n: int = _idx + 1
	if n >= STEP_IDS.size():
		_cleanup_step()
		_idx = -1
		step_id = &""
		_finish()
	else:
		_start_step(n)


func _cleanup_step() -> void:
	if marks != null:
		marks.call("clear_all")
	if step_id == &"ring" and run != null:
		run.ring.auto_knot = _orig_auto_knot


func _lines(goal: String, sub: String) -> void:
	if _idx < 0:
		return
	Events.tutorial_step_started.emit(step_id, _idx, STEP_IDS.size(), _fmt(goal), _fmt(sub))


func _progress(done: int, need: int) -> void:
	Events.tutorial_step_progress.emit(step_id, mini(done, need), need)


func _tag(text: String, hanja: String, pos: Vector2) -> void:
	Events.tutorial_tag.emit(text, hanja, pos)


func _fmt(s: String) -> String:
	if s.find("{") < 0:
		return s
	var gd: float = Data.num("combat_core", "gilbe.duration_base", 4.0)
	if run != null and run.gilbe != null:
		gd = run.gilbe.duration()
	return s.format({"gilbe": "%d" % int(roundf(gd)), "sumyeong": "%d" % int(roundf(Game.stat(&"stat_neok_sumyeong", 30.0)))})


func _met_now(delay: float = 0.4) -> void:
	if _met:
		return
	_met = true
	_met_t = Game.time_sec()
	_complete_delay = delay


func _emit_completed() -> void:
	_completed = true
	var now: float = Game.time_sec()
	var d: Dictionary = Copy.STEPS[step_id]
	var label: String = String(d.get("label", ""))
	var hanja: String = String(d.get("hanja", ""))
	if step_id == &"trial" and _c.get("face", &"") == &"gaho":
		label = String(d.get("label_gaho", label))
		hanja = String(d.get("hanja_gaho", hanja))
	var dur: float = now - _t0
	# screen = 그 단계가 화면에 떠 있던 초(배속·멈춤 포함). settle 처럼 멈춤 카드인 단계는 dur(게임 시각)가 0에 가깝다.
	print("[tutorial] step=%s done t=%.1f dur=%.1f help=%d screen=%.1f" % [step_id, now, dur, _help_max, _screen_t - _screen0])
	_log_steps[String(step_id)] = {"dur": snappedf(dur, 0.1), "help_max": _help_max, "skipped": false}
	_done_n += 1
	if marks != null:
		marks.call("clear_all")
	Events.tutorial_step_completed.emit(step_id, label, hanja)
	_shot(0.45, "z_name")
	var after: String = String(d.get("after", ""))
	if after != "":
		_lines(String(d.get("goal", "")) if not _c.has("goal_now") else String(_c["goal_now"]), after)
	_next_t = now + 1.6


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var now: float = Game.time_sec()
	print("[tutorial] finished t=%.1f done=%d/%d" % [now, _done_n, STEP_IDS.size()])
	if _persist:
		Save.set_flag("practice_done", true, false)
		var logs: Array = []
		var prev: Variant = Save.get_value("ui.practice_log", [])
		if prev is Array:
			logs = (prev as Array).duplicate(true)
		logs.append({"t_total": snappedf(now - _t_begin, 0.1), "steps": _log_steps.duplicate(true)})
		while logs.size() > 5:
			logs.remove_at(0)
		Save.set_value("ui.practice_log", logs)
		Save.save_profile()
	var snap: String = _save_snapshot()
	var snap0: String = String(Engine.get_meta(&"tutorial_snap0", snap))
	print("[tutorial] save %s" % snap)
	print("[tutorial] save_same=%s" % ("true" if snap == snap0 else "false"))
	if snap != snap0:
		push_error("[tutorial] 연습 굿판이 실전 기록을 바꿨다: %s → %s" % [snap0, snap])
	Events.tutorial_finished.emit(true)
	_shot(1.2, "end", "11_end")
	if _auto:
		# --tutorial-exit=<real|again|title>(자동 테스트): 끝 화면에서 그 버튼을 고른 것처럼 한 번 나간다. 없으면 종료.
		var ex: String = DebugTools.arg("tutorial-exit")
		if ex in ["real", "again", "title"] and not Engine.has_meta(&"tutorial_exit_used"):
			Engine.set_meta(&"tutorial_exit_used", true)
			_exit_next = StringName(ex)
			_exit_wait_real = 1.0
		else:
			_quit_wait_real = 1.0 if _shot_dir == "" else 1.6   # 끝 화면 대표 프레임(1.2초)을 찍고 끝낸다
	elif hud == null:
		_exit_wait_real = 2.0        # 끝 화면(tutorial_hud)이 없으면 타이틀로


func _process(delta: float) -> void:
	_screen_t += delta
	if not _shots.is_empty() and _screen_t >= float(_shots[0][0]):
		var e: Array = _shots.pop_front()
		var img: Image = get_viewport().get_texture().get_image()
		if img != null and not img.is_empty():
			var path: String = _shot_dir.path_join(String(e[1]) + ".png")
			img.save_png(path)
			print("[tutorial] shot %s" % path)
	if _ack_wait_real > 0.0:
		_ack_wait_real -= delta
		if _ack_wait_real <= 0.0 and step_id == &"settle" and not _met:
			if Game.has_pause(&"tutorial_card"):
				Game.pop_pause(&"tutorial_card")
			Events.tutorial_ack.emit(&"settle")
	if _quit_wait_real > 0.0:
		_quit_wait_real -= delta
		if _quit_wait_real <= 0.0:
			Game.quit_game(0)
	if _exit_wait_real > 0.0:
		_exit_wait_real -= delta
		if _exit_wait_real <= 0.0:
			Events.tutorial_exit_requested.emit(_exit_next)


func _physics_process(delta: float) -> void:
	if not _begun or _finished or not Game.run_active:
		return
	_heal_guard()
	if _hurry_trial:
		_tick_hurry_trial()
	if _skip_req:
		_do_skip()
	_run_delayed()
	if _idx < 0:
		return
	var now: float = Game.time_sec()
	if _gate_reopen_at >= 0.0 and now >= _gate_reopen_at:
		_gate_reopen_at = -1.0
		run.jeomji_gate = true
	if _skip_all_s >= 0.0 and not _met and now - _t0 >= _skip_all_s:
		skip_step()
	if not _met:
		call("_tick_" + String(step_id), delta)
		if not _met:
			_tick_help()
		if not _met and _auto and now - _t0 > STEP_TIMEOUT:
			push_error("[tutorial] step=%s timeout %.0fs — 강제 완료" % [step_id, STEP_TIMEOUT])
			_met_now(0.0)
	elif not _completed:
		if now - _met_t >= _complete_delay and now - _t0 >= float(MIN_STEP_S.get(step_id, 0.0)):
			_emit_completed()
	elif now >= _next_t and not Game.is_sim_paused():
		_advance()


## 대표 프레임 예약(화면 시각 after 초 뒤). 이름 = <단계 번호>_<id>_<what>.
func _shot(after: float, what: String, full_name: String = "") -> void:
	if _shot_dir == "":
		return
	var nm: String = full_name if full_name != "" else "%02d_%s_%s" % [_idx + 1, step_id, what]
	_shots.append([_screen_t + after, nm])
	_shots.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))


## 실전 기록 요약(§9-4): 끝낸 판 수·ui.runs·본 힌트·첫 판 플래그·첫 실전 대기·재화·넋기록 수. practice_* 는 뺀다.
func _save_snapshot() -> String:
	var hints: Variant = Save.get_value("ui.hints_seen", {})
	var recs: Variant = Save.get_value("ui.records", {})
	var hist: Variant = Save.get_value("ui.run_history", [])
	var wallet: Variant = Save.profile.get("wallet", {})
	return "runs_done=%d ui_runs=%d hints=%d tutorial_done=%s first_run_pending=%s wallet=%s records=%d history=%d" % [
		Save.runs_done(), int(Save.get_value("ui.runs", 0)), (hints as Dictionary).size() if hints is Dictionary else 0,
		str(Save.flag("tutorial_done")), str(Save.first_run_pending()), JSON.stringify(wallet),
		(recs as Dictionary).size() if recs is Dictionary else 0, (hist as Array).size() if hist is Array else 0]


## 건너뛴 시련을 빨리 매듭짓는다: 강림 → 자동 고르기, 시련 → 0.3초 뒤 시간 끝. 빙의 점지는 그대로 보여 준다.
func _tick_hurry_trial() -> void:
	var td: TrialDirector = run.trials
	if td == null:
		_hurry_trial = false
		return
	var now: float = Game.time_sec()
	match td.ph:
		TrialDirector.Ph.DORMANT, TrialDirector.Ph.AFTERGLOW:
			_hurry_trial = false
		TrialDirector.Ph.OMEN:
			td.omen_at = minf(td.omen_at, now)
		TrialDirector.Ph.DESCEND, TrialDirector.Ph.CONFIRM:
			td.descend_end = minf(td.descend_end, now)
		TrialDirector.Ph.TRIAL:
			td.trial_dur_cur = minf(td.trial_dur_cur, td.trial_dur_cur - td.t_left + 0.3)


## 기록 불변 검사 기준값(tutorial_snap0)은 '다시 연습' 사슬 안에서만 이어 쓴다. 타이틀·실전으로 나가면 지운다
## (안 지우면 같은 프로세스에서 실전을 한 판 한 뒤 다시 연습할 때 save_same=false 오탐).
func _on_exit_requested(next: StringName) -> void:
	if next != &"again" and Engine.has_meta(&"tutorial_snap0"):
		Engine.remove_meta(&"tutorial_snap0")


func _heal_guard() -> void:
	if Game.hp_max <= 0.0:
		return
	if Game.hp < Game.hp_max * 0.35:
		var to: float = Game.hp_max * 0.7
		var amt: float = to - Game.hp
		Game.hp = to
		Events.player_healed.emit(amt, Game.hp, Game.hp_max)


func _later(sec: float, method: StringName, args: Array = []) -> void:
	_delayed.append([Game.time_sec() + sec, method, args])


func _run_delayed() -> void:
	if _delayed.is_empty():
		return
	var now: float = Game.time_sec()
	var k: int = 0
	while k < _delayed.size():
		var e: Array = _delayed[k]
		if now >= float(e[0]):
			_delayed.remove_at(k)
			callv(StringName(e[1]), e[2])
		else:
			k += 1


func _help_elapsed() -> float:
	if step_id == &"sal":
		return Game.time_sec() - float(_c["b_t"]) if bool(_c.get("b", false)) else -1.0
	return step_elapsed()


func _tick_help() -> void:
	var tbl: Dictionary = HELP_T.get(step_id, {})
	if tbl.is_empty():
		return
	var el: float = _help_elapsed()
	if el < 0.0:
		return
	for lv: int in [1, 2, 3, 4]:
		if lv <= _help or not tbl.has(lv) or el < float(tbl[lv]):
			continue
		_help = lv
		_help_max = maxi(_help_max, lv)
		var text: String = Copy.L4 if lv == 4 else String((Copy.STEPS[step_id].get("help", {}) as Dictionary).get(lv, ""))
		print("[tutorial] step=%s help=%d t=%.1f" % [step_id, lv, Game.time_sec()])
		Events.tutorial_help.emit(step_id, lv, _fmt(text))
		_shot(1.5, "help%d" % lv)
		var m: String = "_help_" + String(step_id)
		if has_method(m):
			call(m, lv)
		if _met:
			return


# ─── 스폰 도우미 ─────────────────────────────────────────────────────────

func _fwd() -> Vector2:
	var d: Vector2 = run.player.last_move_dir if run != null and run.player != null else Vector2.RIGHT
	return d.normalized() if d.length_squared() > 0.01 else Vector2.RIGHT


func _ppos() -> Vector2:
	return run.player.global_position


## 스폰 + (han > 0 이면) 한을 목표값으로 맞춘다. 반환: 핸들(-1 실패).
func _spawn(sp: StringName, pos: Vector2, han: float = -1.0, extra: Dictionary = {}) -> int:
	var opts: Dictionary = {"intro_s": 0.4}
	if sp == SP_DAL:
		opts["no_variant"] = true
	opts.merge(extra, true)
	var h: int = em.spawn(sp, pos, opts)
	if h < 0:
		return h
	var s: int = em.slot_of(h)
	if s >= 0 and han > 0.0:
		em.han_max[s] = han
		em.han[s] = han
	if s >= 0 and _han_logged < 8:
		_han_logged += 1
		print("[tutorial] han sp=%s max=%.1f step=%s" % [sp, em.han_max[s], step_id])
	return h


func _arc(center: Vector2, fwd: Vector2, arc_deg: float, dist_u: float, n: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var a0: float = fwd.angle()
	var arc: float = deg_to_rad(arc_deg)
	for k in n:
		var f: float = (float(k) / float(maxi(1, n - 1)) - 0.5) if n > 1 else 0.0
		out.append(center + Vector2.from_angle(a0 + f * arc) * dist_u * U)
	return out


## 원(틈 gaps 곳): count + gaps 칸으로 나눠 틈 칸을 비운다.
func _ring_pts(center: Vector2, r_u: float, count: int, gaps: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var slots: int = count + gaps
	var base: float = Rng.range_s(&"spawn", 0.0, TAU)
	var gap_idx: Array[int] = []
	for g in gaps:
		gap_idx.append(int(float(g) * float(slots) / float(maxi(1, gaps))))
	for k in slots:
		if gap_idx.has(k):
			continue
		out.append(center + Vector2.from_angle(base + TAU * float(k) / float(slots)) * r_u * U)
	return out


func _spawn_list(sp: StringName, pts: PackedVector2Array, han: float = -1.0) -> void:
	for p: Vector2 in pts:
		_spawn(sp, p, han)


func _force_pullil() -> void:
	if em != null:
		em.debug_force_pullil()


func _alive_count(need_flag: int = 0, without_flag: int = 0) -> int:
	var n: int = 0
	for a in em.active_count:
		var i: int = em.active[a]
		if not em.is_alive(i) or (em.flags[i] & (EnemyManager.F_PASS | EnemyManager.F_NONHOSTILE)) != 0:
			continue
		if need_flag != 0 and (em.flags[i] & need_flag) == 0:
			continue
		if without_flag != 0 and (em.flags[i] & without_flag) != 0:
			continue
		n += 1
	return n


func _nearest_enemy(need_flag: int = 0, without_flag: int = 0) -> Vector2:
	var pp: Vector2 = _ppos()
	var best: float = INF
	var out: Vector2 = Vector2.INF
	for a in em.active_count:
		var i: int = em.active[a]
		if not em.is_alive(i) or (em.flags[i] & (EnemyManager.F_PASS | EnemyManager.F_NONHOSTILE)) != 0:
			continue
		if need_flag != 0 and (em.flags[i] & need_flag) == 0:
			continue
		if without_flag != 0 and (em.flags[i] & without_flag) != 0:
			continue
		var d2: float = pp.distance_squared_to(em.pos_of(i))
		if d2 < best:
			best = d2
			out = em.pos_of(i)
	return out


func _nearest_orb() -> Vector2:
	var pp: Vector2 = _ppos()
	var best: float = INF
	var out: Vector2 = Vector2.INF
	for i in PickupManager.CAPACITY:
		if pm.alive[i] == 0:
			continue
		var p: Vector2 = Vector2(pm.px[i], pm.py[i])
		var d2: float = pp.distance_squared_to(p)
		if d2 < best:
			best = d2
			out = p
	return out


func _set_arrow(p: Vector2) -> void:
	if marks == null:
		return
	marks.set("arrows", PackedVector2Array([p]) if p != Vector2.INF else PackedVector2Array())


func _give_bangul(show: bool) -> void:
	# guide.gd 가 시작 흰 무구 지급 때 같은 뜻의 레인('몸주 신령이 방울을 내리셨다 — …')을 이미 띄우면
	# 여기서 또 띄우지 않는다(두 줄이 5초 넘게 겹쳐 단계 이름표 한자와 부딪쳤다 — 리뷰 11-25).
	var guide_lane: bool = false
	if wm.level_of(&"wpn_bangul") <= 0:
		var g: Object = run.hud.get("guide") if run.hud != null else null
		if g != null and bool(g.get("guide_on")) and Game.time_sec() > 1.0:
			var seen: Variant = g.get("_seen")
			guide_lane = not (seen is Dictionary and (seen as Dictionary).has("white_grant"))
		wm.add_or_level(&"wpn_bangul")
	if show:
		if not guide_lane and run.hud != null and run.hud.has_method("push_lane"):
			run.hud.call("push_lane", "내 신령이 방울을 내렸다", true, 2.5)
		Audio.play_sfx(&"sfx_ui_unlock", &"UI")


func _bangul_r() -> float:
	for i in wm.slot_count():
		var w: WeaponBase = wm.weapon_at(i)
		if w != null and w.id == &"wpn_bangul":
			return w.s("area", 2.5) * Game.stat(&"stat_doryang", 1.0) * U
	return 2.5 * Game.stat(&"stat_doryang", 1.0) * U


# ─── 신호 처리(표시만) ─────────────────────────────────────────────────────

func _on_enemy_killed(handle: int, _sp: StringName, pos: Vector2, kind: StringName, cause: StringName, _tier: StringName) -> void:
	if _idx < 0 or _met:
		return
	match step_id:
		&"beat":
			if kind == &"toechi":
				_c["kills"] = int(_c.get("kills", 0)) + 1
				if int(_c["kills"]) == 1:
					_tag("처치", "퇴치", pos)
					_c["second_at"] = Game.time_sec() + 0.5
				_progress(int(_c["kills"]), int(_c.get("need", 5)))
		&"white":
			if kind == &"haewon" and cause == &"white":
				_c["white"] = int(_c.get("white", 0)) + 1
				if int(_c["white"]) == 1:
					_tag("풀어 줌", "해원", pos)
				_progress(int(_c["white"]), int(_c.get("need", 4)))
		&"sal":
			if not bool(_c.get("b", false)):
				if kind == &"toechi":
					_c["k"] = int(_c.get("k", 0)) + 1
					if int(_c["k"]) == 1:
						_tag("원한", "살", pos)
					_progress(int(_c["k"]), 6)
			else:
				var wg: Dictionary = _c.get("wg", {})
				if wg.has(handle):
					wg.erase(handle)
					_c["wg_done"] = int(_c.get("wg_done", 0)) + 1
					_tag("처치" if kind == &"toechi" else "풀어 줌", "퇴치" if kind == &"toechi" else "해원", pos)


func _on_pullil_entered(_h: int, _sp: StringName, pos: Vector2) -> void:
	if step_id != &"cut" or _met:
		return
	_c["pullil"] = int(_c.get("pullil", 0)) + 1
	if int(_c["pullil"]) == 1:
		_tag("흰 테두리", "", pos)
	_progress(int(_c["pullil"]), int(_c.get("need_p", 3)))


func _on_enemy_hit(_h: int, _sp: StringName, pos: Vector2, _d: float, _col: int, _crit: bool, knot_locked: bool) -> void:
	if step_id != &"cut" or _met or not knot_locked:
		return
	_c["locks"] = int(_c.get("locks", 0)) + 1
	if int(_c["locks"]) == 1:
		_tag("칼로는 못 끊음", "", pos)


func _on_ring_closed(area: int, n: int, centroid: Vector2) -> void:
	if step_id != &"ring" or _met:
		return
	_c["rings"] = int(_c.get("rings", 0)) + 1
	print("[tutorial] ring area=%d haewon=%d" % [area, n])
	var ok: bool = n >= 3 or (_help >= 3 and (n >= 1 or area >= 9))
	if n > 0:
		_tag("한꺼번에 풀림 ×%d" % n, "", centroid)
	if ok:
		_met_now(1.0)       # 고리 연출(만다라·'덩')이 끝난 뒤 이름표
	elif marks != null:
		marks.set("cp_lit", PackedByteArray([0, 0, 0, 0]))


func _on_level_up(_lv: int) -> void:
	if step_id == &"jeomji" and not bool(_c.get("opened", false)):
		_c["open_req"] = true


func _on_levelup_chosen(_choice: Dictionary) -> void:
	if step_id == &"jeomji" and bool(_c.get("opened", false)):
		_met_now(0.4)


func _on_trial_phase(_slot: int, _deity: StringName, phase: StringName) -> void:
	if step_id != &"trial" or _met:
		return
	_c["phase"] = phase
	var d: Dictionary = Copy.STEPS[&"trial"]
	match phase:
		&"descend", &"confirm":
			if phase == &"descend":
				_shot(1.2, "b_descend")
				_lines(String(d["descend_goal"]), String(d["descend_sub"]))
				_c["goal_now"] = d["descend_goal"]
		&"clear", &"trial":
			if not bool(_c.get("trial_on", false)):
				_c["trial_on"] = true
				_c["trial_t"] = Game.time_sec()
				_shot(2.5, "c_trial")
				_lines(String(d["trial_goal"]), String(d["trial_sub"]))
				_c["goal_now"] = d["trial_goal"]
		&"jeomji":
			_shot(0.6, "d_bingui")
			_lines(String(d["jeomji_goal"]), String(d["jeomji_sub"]))
			_c["goal_now"] = d["jeomji_goal"]
		&"possession", &"resolve":
			pass
		&"afterglow", &"dormant":
			if bool(_c.get("resolved", false)):
				_c["goal_now"] = d["after_goal"]
				_met_now(0.4)


func _on_trial_resolved(_slot: int, _deity: StringName, face: StringName, _complete: bool) -> void:
	if step_id != &"trial":
		return
	_c["resolved"] = true
	_c["face"] = face


func _on_trial_gauge(_slot: int, w: float, g: float) -> void:
	if step_id == &"trial":
		_c["gw"] = w
		_c["gg"] = g


func _on_wongwi_return(_th: int) -> void:
	if step_id == &"sal":
		_c["watch_until"] = Game.time_sec() + 3.0


func _on_enemy_spawned(h: int, _sp: StringName, _tier: StringName) -> void:
	if step_id != &"sal" or Game.time_sec() > float(_c.get("watch_until", -1.0)) or em == null:
		return
	var s: int = em.slot_of(h)
	if s < 0 or (em.flags[s] & EnemyManager.F_WONGWI) == 0:
		return
	var wg: Dictionary = _c.get("wg", {})
	wg[h] = true
	_c["wg"] = wg
	_c["wg_seen"] = int(_c.get("wg_seen", 0)) + 1
	if int(_c["wg_seen"]) == 1:
		_tag("성난 귀신", "원귀", em.pos_of(s))


func _on_cheondo(_count: int, reason: StringName) -> void:
	if step_id != &"yeongga" or reason != &"lifetime" or bool(_c.get("cheondo_tag", false)):
		return
	_c["cheondo_tag"] = true
	var yt: YeonggaTrain = run.yeongga
	var p: Vector2 = _ppos()
	if yt != null and yt.count > 0:
		p = Vector2(yt.m_x[yt.count - 1], yt.m_y[yt.count - 1])
	_tag("떠남", "천도", p)


func _on_yeongga_joined(count: int, _sp: StringName) -> void:
	if step_id == &"yeongga" and count >= 2 and not bool(_c.get("bracket", false)):
		_c["bracket"] = true
		if marks != null:
			marks.set("bracket_left", 1.5)


func _on_ack(sid: StringName) -> void:
	if sid == &"settle" and step_id == &"settle" and not _met:
		_ack_wait_real = -1.0
		_met_now(0.2)


# ─── 1 move ──────────────────────────────────────────────────────────────

func _enter_move() -> void:
	_c["dist"] = 0.0
	_c["last"] = _ppos()


func _tick_move(_dt: float) -> void:
	var p: Vector2 = _ppos()
	_c["dist"] = float(_c["dist"]) + p.distance_to(_c["last"])
	_c["last"] = p
	if float(_c["dist"]) >= 4.0 * U and step_elapsed() >= 2.0:
		if marks != null:
			marks.set("dir4", false)
		_met_now()


func _help_move(lv: int) -> void:
	if lv == 1 and marks != null:
		marks.set("dir4", true)


# ─── 2 beat ──────────────────────────────────────────────────────────────

func _enter_beat() -> void:
	_c["kills"] = 0
	_c["need"] = 5
	_spawn_list(SP_GAEK, _arc(_ppos(), _fwd(), 60.0, 6.0, 3))
	_progress(0, 5)


func _tick_beat(_dt: float) -> void:
	var now: float = Game.time_sec()
	if _c.has("second_at") and now >= float(_c["second_at"]):
		_c.erase("second_at")
		_c["second"] = true
		_spawn_list(SP_GAEK, _ring_pts(_ppos(), 7.0, 5, 2))
	if int(_c["kills"]) >= int(_c["need"]):
		_met_now()
		return
	# 보충: 다 사라졌는데 아직 모자라면 셋을 다시 세운다
	if _alive_count() == 0 and not _c.has("second_at"):
		_spawn_list(SP_GAEK, _ring_pts(_ppos(), 4.0, 3, 0))
	if _help >= 1:
		_set_arrow(_nearest_enemy())


func _help_beat(lv: int) -> void:
	if lv == 2:
		_spawn_list(SP_GAEK, _ring_pts(_ppos(), 3.0, 3, 0))
	elif lv == 3:
		_c["need"] = 3
		_progress(int(_c["kills"]), 3)


# ─── 3 cut ───────────────────────────────────────────────────────────────

func _enter_cut() -> void:
	_c["pullil"] = 0
	_c["locks"] = 0
	_c["need_p"] = 3
	_c["need_l"] = 2
	_spawn_list(SP_DAL, _arc(_ppos(), _fwd(), 90.0, 6.0, 5), HAN_GISEAK)
	_progress(0, 3)


func _tick_cut(_dt: float) -> void:
	if int(_c["pullil"]) >= int(_c["need_p"]) and int(_c["locks"]) >= int(_c["need_l"]):
		_met_now()
		return
	# 보충: 깎을 귀신(기색 아님)이 없고 기색 수가 모자라면
	if int(_c["pullil"]) < int(_c["need_p"]) and _alive_count(0, EnemyManager.F_PULLIL) == 0:
		_spawn_list(SP_DAL, _arc(_ppos(), _fwd(), 60.0, 3.5, 3), HAN_GISEAK)
	if _help >= 1:
		var t: Vector2 = _nearest_enemy(0, EnemyManager.F_PULLIL)
		_set_arrow(t if t != Vector2.INF else _nearest_enemy())


func _help_cut(lv: int) -> void:
	if lv == 2:
		_spawn_list(SP_DAL, _arc(_ppos(), _fwd(), 60.0, 3.5, 3), HAN_GISEAK)
	elif lv == 3:
		_c["need_p"] = 2
		_c["need_l"] = 1
		_progress(int(_c["pullil"]), 2)


# ─── 4 ring ──────────────────────────────────────────────────────────────

func _enter_ring() -> void:
	_orig_auto_knot = run.ring.auto_knot
	run.ring.auto_knot = true
	var f: Vector2 = _fwd()
	_tag("흰 길", "", _ppos() - f * 1.0 * U)
	ring_center = _ppos() + f * 5.0 * U
	_spawn_ring_crowd(6)
	_later(0.6, &"_force_pullil")
	_c["maint_t"] = Game.time_sec() + 1.5
	_c["rings"] = 0


func _spawn_ring_crowd(n: int) -> void:
	_spawn(SP_DAL, ring_center, HAN_GISEAK)
	var m: int = n - 1
	for k in m:
		_spawn(SP_DAL, ring_center + Vector2.from_angle(TAU * float(k) / float(maxi(1, m))) * 0.8 * U, HAN_GISEAK)


func _tick_ring(dt: float) -> void:
	var now: float = Game.time_sec()
	# 무리 중심은 기색 귀신 무게중심을 천천히 따라간다(귀신이 무당 쪽으로 기어 오므로)
	var sum: Vector2 = Vector2.ZERO
	var cnt: int = 0
	var n: int = em.query_circle(ring_center, 5.0 * U, _q)
	for k in n:
		var i: int = _q[k]
		if (em.flags[i] & EnemyManager.F_PULLIL) != 0:
			sum += em.pos_of(i)
			cnt += 1
	if cnt > 0:
		ring_center = ring_center.lerp(sum / float(cnt), clampf(0.8 * dt, 0.0, 1.0))
	if now >= float(_c["maint_t"]):
		_c["maint_t"] = now + 0.5
		if cnt < 3:
			_spawn_ring_crowd(3)
			_later(0.6, &"_force_pullil")
	if marks != null and _help >= 1:
		var r: float = 2.2 * U
		marks.set("circle_c", ring_center)
		marks.set("circle_r", r)
		var cps: PackedVector2Array = PackedVector2Array()
		var lit: PackedByteArray = marks.get("cp_lit")
		if lit.size() != 4:
			lit = PackedByteArray([0, 0, 0, 0])
		var pp: Vector2 = _ppos()
		for k in 4:
			var cp: Vector2 = ring_center + Vector2.from_angle(TAU * float(k) / 4.0 - PI / 2.0) * r
			cps.append(cp)
			if lit[k] == 0 and pp.distance_to(cp) <= 0.7 * U:
				lit[k] = 1
				Audio.play_sfx(&"sfx_ui_nav", &"UI", -6.0)
		marks.set("checkpoints", cps)
		marks.set("cp_lit", lit)


func _help_ring(lv: int) -> void:
	if marks == null:
		return
	if lv == 1:
		marks.set("circle_on", true)
		marks.set("cp_lit", PackedByteArray([0, 0, 0, 0]))
	elif lv == 2:
		marks.set("demo_on", true)
		marks.set("demo_period", 3.8)


# ─── 5 white ─────────────────────────────────────────────────────────────

func _enter_white() -> void:
	_give_bangul(true)
	_c["white"] = 0
	_c["need"] = 4
	_spawn_list(SP_DAL, _arc(_ppos(), _fwd(), 90.0, 6.0, 6), HAN_GISEAK)
	_progress(0, 4)


func _tick_white(_dt: float) -> void:
	if int(_c["white"]) >= int(_c["need"]):
		_met_now()
		return
	if _alive_count() == 0 and not _c.has("refill_wait"):
		_c["refill_wait"] = true
		_spawn_list(SP_DAL, _arc(_ppos(), _fwd(), 60.0, 2.0, 3), HAN_GISEAK)
		_later(0.6, &"_white_refilled")
	if _help >= 1 and marks != null:
		marks.set("player_circle_r", _bangul_r())
		var t: Vector2 = _nearest_enemy(EnemyManager.F_PULLIL)
		_set_arrow(t if t != Vector2.INF else _nearest_enemy())


func _white_refilled() -> void:
	_force_pullil()
	_c.erase("refill_wait")


func _help_white(lv: int) -> void:
	if lv == 2:
		_spawn_list(SP_DAL, _arc(_ppos(), _fwd(), 60.0, 2.0, 3), HAN_GISEAK)
		_later(0.6, &"_force_pullil")
	elif lv == 3:
		_c["need"] = 2
		_progress(int(_c["white"]), 2)


# ─── 6 yeongga ───────────────────────────────────────────────────────────

func _enter_yeongga() -> void:
	if run.yeongga.count < 3:
		_feed_yeongga()
	elif marks != null:
		_c["bracket"] = true
		marks.set("bracket_left", 1.5)


func _feed_yeongga() -> void:
	_spawn_list(SP_DAL, _ring_pts(_ppos(), 1.5, 4, 0), HAN_GISEAK)
	_later(0.6, &"_force_pullil")


func _tick_yeongga(_dt: float) -> void:
	var yt: YeonggaTrain = run.yeongga
	if marks != null and float(marks.get("bracket_left")) > 0.0 and yt.count >= 1:
		var pts: PackedVector2Array = PackedVector2Array([_ppos()])
		for k in yt.count:
			pts.append(Vector2(yt.m_x[k], yt.m_y[k]))
		marks.set("bracket_pts", pts)
	var need_n: bool = _help >= 3 or yt.count >= 3
	if step_elapsed() >= 6.0 and need_n:
		_met_now()


func _help_yeongga(lv: int) -> void:
	if lv == 1:
		_feed_yeongga()


# ─── 7 jeomji ────────────────────────────────────────────────────────────

func _enter_jeomji() -> void:
	_c["opened"] = false
	var need: float = maxf(1.0, (Game.xp_next - Game.xp) * 1.1)
	_scatter_orbs(need)
	_c["orb_t"] = Game.time_sec()
	if int(run.get("_lv_hold")) > 0:
		_c["open_at"] = Game.time_sec() + 2.0


func _scatter_orbs(total: float) -> void:
	var f: Vector2 = _fwd()
	var pp: Vector2 = _ppos()
	var n: int = 10
	for k in n:
		var d: float = lerpf(2.0, 9.0, float(k) / float(n - 1))
		pm.spawn_orb(pp + f * d * U, total / float(n))


func _tick_jeomji(_dt: float) -> void:
	var now: float = Game.time_sec()
	if not bool(_c["opened"]):
		var want: bool = bool(_c.get("open_req", false)) or (_c.has("open_at") and now >= float(_c["open_at"]))
		if want and not Game.is_sim_paused():
			_open_teach()
		elif pm.count == 0 and now - float(_c["orb_t"]) > 3.0 and not want:
			# 구슬 값이 모자랐다(능력치 배율 등): 한 번 더 뿌린다
			_scatter_orbs(maxf(1.0, (Game.xp_next - Game.xp) * 1.2))
			_c["orb_t"] = now
		if _help >= 1:
			_set_arrow(_nearest_orb())
	else:
		_set_arrow(Vector2.INF)


func _open_teach() -> void:
	_c["opened"] = true
	var cands: Array[Dictionary] = _teach_cards()
	print("[tutorial] jeomji teach cards=%s" % [cands.map(func(c: Dictionary) -> String: return String(c.get("id", "")))])
	if run.levelup != null and run.levelup.has_method("open_with") and not cands.is_empty():
		run.levelup.call("open_with", cands)
	run.jeomji_gate = true
	_shot(0.6, "b_cards")
	var d: Dictionary = Copy.STEPS[&"jeomji"]
	_lines(String(d["open_goal"]), String(d["open_sub"]))
	_c["goal_now"] = d["goal"]
	if cands.is_empty():
		_met_now()


## 가르치기 카드 3장: ◆ 붉은 새 무구(월도 우선) · ○ 흰 새 무구(부채 우선) · 백지술(신칼의 짝). 빈 자리는 roll_offers.
func _teach_cards() -> Array[Dictionary]:
	var pool: Array[Dictionary] = wm.get_offer_pool()
	var out: Array[Dictionary] = []
	var red: Dictionary = _pick(pool, "weapon", &"wpn_woldo", "red")
	if not red.is_empty():
		out.append(red)
	var white: Dictionary = _pick(pool, "weapon", &"wpn_buchae", "white")
	if not white.is_empty():
		out.append(white)
	for c: Dictionary in pool:
		if String(c.get("kind", "")) == "passive" and StringName(String(c.get("id", ""))) == &"psv_baekjisul":
			out.append(c)
			break
	if out.size() < 3:
		for c2: Dictionary in wm.roll_offers(3):
			if out.size() >= 3:
				break
			var dup: bool = false
			for o: Dictionary in out:
				if String(o.get("id", "")) == String(c2.get("id", "")):
					dup = true
			if not dup:
				out.append(c2)
	return out


func _pick(pool: Array[Dictionary], kind: String, prefer: StringName, color: String) -> Dictionary:
	var any: Dictionary = {}
	for c: Dictionary in pool:
		if String(c.get("kind", "")) != kind or not bool(c.get("is_new", false)):
			continue
		var id: StringName = StringName(String(c.get("id", "")))
		if id == prefer:
			return c
		if any.is_empty() and UiKit.weapon_color(String(id)) == color:
			any = c
	return any


func _help_jeomji(lv: int) -> void:
	if lv == 2:
		pm.pull_all()


# ─── 8 trial ─────────────────────────────────────────────────────────────

func _enter_trial() -> void:
	for a in range(em.active_count - 1, -1, -1):
		var i: int = em.active[a]
		if em.is_alive(i):
			em.vanish(i)
	_c["started"] = false


func _tick_trial(_dt: float) -> void:
	var td: TrialDirector = run.trials
	if not bool(_c["started"]):
		if not Game.is_sim_paused() and td.ph == TrialDirector.Ph.DORMANT:
			if td.slot_next >= td.times.size():
				push_warning("[tutorial] 남은 시련 슬롯이 없다 — 시련 단계를 건너뛴다")
				_met_now()
				return
			td.start_now()
			_c["started"] = true
		return
	if marks != null:
		if td.ph == TrialDirector.Ph.DESCEND:
			marks.set("arrows", PackedVector2Array([td.circle[0], td.circle[1]]))
		else:
			marks.set("arrows", PackedVector2Array())
	# 시련 12초에 두 게이지 모두 낮으면 보조 줄을 번갈아(4초씩)
	if bool(_c.get("trial_on", false)) and td.ph == TrialDirector.Ph.TRIAL:
		var el: float = Game.time_sec() - float(_c["trial_t"])
		if el >= 12.0 and maxf(float(_c.get("gw", 0.0)), float(_c.get("gg", 0.0))) < 0.3:
			var alt: Array = Copy.STEPS[&"trial"]["trial_alt"]
			var k: int = int(floor((el - 12.0) / 4.0)) % alt.size()
			if int(_c.get("alt_k", -1)) != k:
				_c["alt_k"] = k
				_help_max = maxi(_help_max, 1)
				Events.tutorial_help.emit(&"trial", 1, String(alt[k]))


# ─── 9 sal ───────────────────────────────────────────────────────────────

func _enter_sal() -> void:
	if run.hud != null:
		if run.hud.has_method("reveal_giun"):
			run.hud.call("reveal_giun")
		if run.hud.has_method("flash_knots"):
			run.hud.call("flash_knots", 1.5)
	_c["k"] = 0
	_c["b"] = false
	_c["wg"] = {}
	_spawn_list(SP_GAEK, _ring_pts(_ppos(), 6.0, 8, 2))
	_progress(0, 6)


func _tick_sal(_dt: float) -> void:
	var now: float = Game.time_sec()
	if not bool(_c["b"]):
		if int(_c["k"]) >= 6 or step_elapsed() >= 15.0:
			if int(_c["k"]) == 0:
				# 퇴치 기록이 없으면 원귀 회귀가 일어나지 않는다(haewon skip_if_no_toechi) → 아래 직접 스폰으로
				pass
			_c["b"] = true
			_c["b_t"] = now
			var hs: HaewonSystem = run.haewon
			hs.add_salgi(maxf(0.0, 25.0 - Game.salgi + 0.01))
			var d: Dictionary = Copy.STEPS[&"sal"]
			_lines(String(d["b_goal"]), String(d["b_sub"]))
			_c["goal_now"] = d["b_goal"]
			Events.tutorial_step_progress.emit(step_id, 0, 0)   # 9a 의 "(6/6)" 을 지운다(원귀 수가 잡히면 다시 센다)
			_shot(1.5, "b_wongwi")
		elif _alive_count() == 0:
			_spawn_list(SP_GAEK, _ring_pts(_ppos(), 5.0, 4, 1))
		return
	var wg: Dictionary = _c["wg"]
	# 원귀 수집: enemies 가 wongwi_return 처리기에서 같은 틱에 세우면 enemy_spawned 가 우리 처리기보다 먼저 올 수 있다 → 직접 훑는다
	if now - float(_c["b_t"]) <= 4.0:
		for a in em.active_count:
			var i: int = em.active[a]
			if em.is_alive(i) and (em.flags[i] & EnemyManager.F_WONGWI) != 0:
				var hh: int = em.handle_of(i)
				if not wg.has(hh):
					wg[hh] = true
					_c["wg_seen"] = int(_c.get("wg_seen", 0)) + 1
					if int(_c["wg_seen"]) == 1:
						_tag("성난 귀신", "원귀", em.pos_of(i))
	if int(_c.get("wg_seen", 0)) == 0 and now - float(_c["b_t"]) >= 1.6 and not bool(_c.get("fallback", false)):
		_c["fallback"] = true
		var h: int = _spawn(SP_GAEK, _ppos() + _fwd() * 6.0 * U, -1.0,
			{"wongwi": true, "elite_plus": true, "han_mult": Data.num("enemies", "scaling.wongwi.han_mult", 4.0), "no_recycle": true})
		if h >= 0:
			wg[h] = true
			_c["wg_seen"] = 1
			if Game.vfx != null:
				(Game.vfx as VfxPlayer).play(&"vfx_wongwi_form", em.pos_of(em.slot_of(h)))
			Audio.play_sfx(&"sfx_sys_wongwi_rise", &"SFX")
			_tag("성난 귀신", "원귀", em.pos_of(em.slot_of(h)))
	# 사라진(맵 밖·소멸) 핸들 정리
	for h2: int in wg.keys():
		if em.slot_of(h2) < 0:
			wg.erase(h2)
	var seen: int = int(_c.get("wg_seen", 0))
	if seen > 0:
		var pk: int = seen * 100 + (seen - wg.size())
		if int(_c.get("wg_prog", -1)) != pk:
			_c["wg_prog"] = pk
			_progress(seen - wg.size(), seen)
	if seen > 0 and wg.is_empty():
		_met_now()
		return
	if _help >= 1:
		var arr: PackedVector2Array = PackedVector2Array()
		for h3: int in wg.keys():
			arr.append(em.pos_of(em.slot_of(h3)))
		if marks != null:
			marks.set("arrows", arr)


func _help_sal(lv: int) -> void:
	if lv == 3:
		var wg: Dictionary = _c.get("wg", {})
		for h: int in wg.keys():
			var s: int = em.slot_of(h)
			if s >= 0:
				em.vanish(s)
		wg.clear()
		_met_now()


# ─── 10 settle ───────────────────────────────────────────────────────────

func _enter_settle() -> void:
	Events.tutorial_card.emit(&"settle", Copy.settle_card())
	_shot(0.6, "b_card")
	# 자동 테스트이거나 HUD 가 없으면 1.5초 뒤 스스로 확인한다
	if _auto or hud == null:
		_ack_wait_real = 1.5


func _tick_settle(_dt: float) -> void:
	pass
