class_name Run
extends Node2D
## 런 씬 루트: 시스템 배선 + 고정 틱 순서(design/14 §3.2.1). 소유: core(리드).
## 틱 순서를 바꾸면 판정이 달라진다 — 변경은 리드 승인 후. 각 모듈은 자기 sim_* 함수 안만 고친다.

signal finished(result: Dictionary)

@onready var world: Node2D = $World
@onready var ground: Node2D = $World/Ground
@onready var gilbe: GilbeTrail = $World/Gilbe
@onready var ring: RingClosure = $World/Ring
@onready var pickups: PickupManager = $World/Pickups
@onready var enemies: EnemyManager = $World/Enemies
@onready var yeongga: YeonggaTrain = $World/Yeongga
@onready var player: Player = $World/Player
@onready var weapons: WeaponManager = $World/Weapons
@onready var projectiles: ProjectilePool = $World/Projectiles
@onready var vfx: VfxPlayer = $World/Vfx
@onready var damage_numbers: DamageNumbers = $World/DamageNumbers
@onready var camera: GameCamera = $Camera
@onready var spawn: SpawnDirector = $Systems/SpawnDirector
@onready var trials: TrialDirector = $Systems/TrialDirector
@onready var haewon: HaewonSystem = $Systems/HaewonSystem
@onready var feedback: HitFeedback = $Systems/HitFeedback
@onready var hud: Control = $HUDLayer/HUD
@onready var levelup: Control = $OverlayLayer/LevelUp
@onready var pause_menu: Control = $OverlayLayer/PauseMenu

var char_id: StringName = &"char_mansin"
var yeongga_count: int = 0
var _ended: bool = false
var _tick_ms_acc: float = 0.0
var _tick_ms_n: int = 0
var tick_ms_avg: float = 0.0
var _next_report_tick: int = 0
# 봇 계측(--autotest): 스폰·발사·피격·처치·이동 거리 누계
var _st_spawned: int = 0
var _st_fired: Dictionary = {}
var _st_hits: int = 0
var _st_killed: int = 0
var _st_rings: int = 0
var _st_dist: float = 0.0
var _st_last_pos: Vector2 = Vector2.INF
var _prev_frozen: bool = false
var _dying: bool = false
var _death_wait: float = 0.0
var _geodum: bool = false            # 보스 해결 뒤(정산) 정기 0 = '굿판을 거둠'(클리어 유지, 캐논 01 §465)
const HARD_END_SEC: float = 1800.0   # 안전망(30:00). 정상 종료는 stage_finished(강제 사자 23:00 + 살 거둠).
# 점지 몰아받기: 시련·합일·작두·보스 등장 중에는 레벨업을 쌓아 두었다가 쉬는 틈에 연달아 연다.
# 14:00 뒤에는 점지 창 사이를 30초 이상 띄운다(후반 흐름 끊김 방지). 쌓인 것은 levelup 의 '점지 ×N' 으로 한 번에.
const JEOMJI_GAP_LATE_SEC: float = 30.0
const JEOMJI_GAP_MID_SEC: float = 15.0
const JEOMJI_LATE_FROM: float = 840.0
const JEOMJI_MID_FROM: float = 600.0
const JEOMJI_HOLD_MAX_SEC: float = 90.0
const BOSS_INTRO_SEC: float = 6.0
var _lv_hold: int = 0
var _lv_hold_since: float = -1.0
var _jeomji_last_open: float = -1000.0
var _boss_seen_t: float = -1.0
var _st_levelups: int = 0
var _st_jeomji_opens: int = 0
var _st_late_gap_min: float = 1e9
# 봇 계측·디버그 사망(--autotest-die=<sec>|settle)
var _die_at: float = -1.0
var _die_settle: bool = false
var _die_fired: bool = false
var _allow_death: bool = false
var _bot_pick: String = "greedy"
var _bot_pick_idx: int = -1
var _bot_pick_left: float = -1.0
var _st_first_lv8: float = -1.0
var _st_first_evo: float = -1.0
var _st_first_union: float = -1.0
var _st_evos: int = 0
var _st_unions: int = 0
## 연습 굿판(design/17 §7.3): false 면 레벨업을 쌓아만 두고 점지 창을 열지 않는다. TutorialDirector 가 연다.
var jeomji_gate: bool = true


func _ready() -> void:
	Game.run_root = self
	Game.world = world
	Game.player = player
	Game.enemies = enemies
	Game.projectiles = projectiles
	Game.weapons = weapons
	Game.pickups = pickups
	Game.vfx = vfx
	Game.camera = camera
	ring.trail = gilbe
	feedback.vfx = vfx
	camera.target = player
	Game.reset_run(char_id)
	player.setup(char_id)
	weapons.setup_character(char_id)
	var skip: String = DebugTools.arg("start-sec")
	if skip != "":
		Game.game_tick = int(float(skip) * K.TICK_HZ)
		Game.beat_tick = Game.game_tick
	Events.player_died.connect(_on_player_died)
	Events.level_up.connect(_on_level_up)
	Events.stage_finished.connect(_on_stage_finished)
	Events.yeongga_joined.connect(func(c: int, _s: StringName) -> void: yeongga_count = c)
	Events.yeongga_cheondo.connect(func(_c: int, _r: StringName) -> void: yeongga_count = yeongga.count)
	Game.begin_run()
	if Game.autotest:
		_connect_autotest_stats()
		var die: String = DebugTools.arg("autotest-die")
		if die == "settle":
			_die_settle = true
		elif die != "":
			_die_at = float(die)
		_bot_pick = DebugTools.arg("bot-pick", "greedy")
		if _bot_pick != "greedy":
			Events.levelup_offer.connect(_on_bot_offer)
	if Game.autotest and DebugTools.arg("speed") != "":
		Game.set_sim_speed(int(DebugTools.arg("speed")))


func setup(p_char_id: StringName) -> void:
	char_id = p_char_id


## 렌더 동기 단계(GAME_FEEL 1.3, 호출 순서 고정): R1 연출 시계 → R2 플레이어 → R3 카메라 → R4 적 → R5 투사체.
## (R6 vfx·데미지 숫자는 자식 노드 _process 가 이 뒤에 Game.anim_dt 로 진행한다.)
func _process(delta: float) -> void:
	Game.update_anim_clock()                  # R1
	var a: float = Game.render_alpha
	player.render(a)                          # R2 보간·반올림 → 애니·스쿼시·기울기·반동
	camera.render(a, delta)                   # R3 정수 카메라(2.6 공식)
	enemies.render(a)                         # R4
	projectiles.render(a)                     # R5
	if _dying and not _ended:
		_death_wait -= delta
		if _death_wait <= 0.0:
			if _geodum:
				_finish(true, _geodum_result())
			else:
				_finish(false, {"ending": &"death"})
	if _bot_pick_left > 0.0:
		_bot_pick_left -= delta
		if _bot_pick_left <= 0.0 and levelup.visible and levelup.has_method("_choose"):
			# TODO(ui): 공개 choose(i) 가 생기면 그쪽으로. levelup 자동 선택(0.6초)보다 먼저 정책 카드를 고른다.
			levelup.call("_choose", _bot_pick_idx)


func _exit_tree() -> void:
	Game.run_active = false
	Game.clear_services()


func _physics_process(_delta: float) -> void:
	if _ended:
		return
	var t0: int = Time.get_ticks_usec()
	Game.anim_tick_prev = Game.game_tick
	var advanced: bool = false
	for i in Game.sim_speed:
		if Game.advance_tick():
			# 보간 기준점(GAME_FEEL 1.2): 시뮬이 진행된 틱의 시작에서 prev = cur. 적·투사체는 각자 sim 루프 시작에서 복사.
			player.store_prev()
			_sim_step(K.TICK_DT)
			advanced = true
	if not advanced and not _prev_frozen:
		# 히트스톱·일시정지: prev = cur 로 동결(보간이 움직이지 않게)
		player.store_prev()
		enemies.freeze_prev()
		projectiles.freeze_prev()
	_prev_frozen = not advanced
	Game.anim_tick_cur = Game.game_tick
	var dt_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	_tick_ms_acc += dt_ms
	_tick_ms_n += 1
	if _tick_ms_n >= 60:
		tick_ms_avg = _tick_ms_acc / _tick_ms_n
		_tick_ms_acc = 0.0
		_tick_ms_n = 0
	if not _ended and not _dying:
		_jeomji_flush()
		if Game.autotest:
			_autotest_die_check()
	if Game.autotest and Game.game_tick >= _next_report_tick:
		var step: int = 120 * K.TICK_HZ              # 봇: 게임 2분마다 상태 한 줄
		if _next_report_tick > 0:
			_print_autotest_report()
		_next_report_tick = Game.game_tick - Game.game_tick % step + step
	if Game.autotest_quit_sec > 0.0 and Game.time_sec() >= Game.autotest_quit_sec:
		_print_autotest_report()
		_ended = true
		Game.quit_game(0)


## 고정 틱 1회. 순서 고정(design/14 §3.2.1, 1·2단계는 Game.advance_tick/Beat.advance 에서 처리됨).
func _sim_step(dt: float) -> void:
	player.sim_step(dt)                       # 3  이동
	gilbe.sim_record(dt)                      # 4  길베 샘플
	ring.sim_check(dt)                        # 5  길닦음 닫힘(래스터·플러드필·즉시 판정)
	spawn.sim_step(dt)                        # 6  스폰
	trials.sim_step(dt)                       # 6b 흐름(L2): 시련 스케줄
	enemies.sim_think_move(dt)                # 7·8 사고·이동·분리
	enemies.rebuild_hash()                    # 9  공간 해시
	weapons.sim_step(dt)                      # 10·12 무구 발사(박 양자화)·오라·장판
	projectiles.sim_step(dt)                  # 11 투사체 이동·충돌
	enemies.resolve_hits()                    # 13·14 피해 일괄 해석 → 퇴치/해원
	yeongga.sim_step(dt)                      # 15 영가 행렬
	player.crowd_touching = enemies.sim_contact_player(dt)  # 16 접촉 피해
	pickups.sim_step(dt)                      # 17 픽업
	haewon.sim_thresholds(dt)                 # 18 문턱(살기·신명)
	if Game.autotest:
		if _st_last_pos != Vector2.INF:
			_st_dist += player.global_position.distance_to(_st_last_pos)
		_st_last_pos = player.global_position
	# 종료는 waves 의 Events.stage_finished(보스 → 저승사자 정산 → DONE)로만 한다. 아래는 신호가 끝내 오지 않을 때의 안전망.
	if Game.time_sec() >= HARD_END_SEC:
		_finish(false, {"ending": &"hard_cap"})   # timeout 과 같은 정산(사망 환산) — 결과 문구 '사자가 판을 거두었다'와 일치


func _on_player_died() -> void:
	if Game.tutorial_mode:
		Game.hp = Game.hp_max   # 연습 굿판: 명줄 무한(design/17 §5.1)
		return
	if Game.autotest and not _allow_death:
		Game.hp = Game.hp_max  # 봇 테스트는 죽지 않고 계속(사망 경로는 --autotest-die 로 시험)
		print("[autotest] bot_revive t=%.1f" % Game.time_sec())   # 검사 지표: 봇이 실제로 죽은 횟수(시뮬 영향 없음)
		return
	if _dying or _ended:
		return
	# 보스 해결 뒤 '살 거둠'·사자 정산 중: 사망이 아니라 굿판을 거둠(클리어 유지). 사자는 비처벌.
	_geodum = spawn.phase >= SpawnDirector.Phase.RESOLVED and spawn.boss_kind != &""   # 23:00 timeout 정산은 해당 없음
	# GAME_FEEL 2.5: 사망 순간 T3 히트스톱 → death 애니(10fps) → 마지막 프레임 홀드 → 결과 화면(지연 death.result_delay_s)
	_dying = true
	Game.player_dead = true
	if _geodum:
		Game.hp = 1.0
	_death_wait = Data.num("combat_core", "feel.death.result_delay_s", 1.4)
	Game.request_hitstop(int(Data.num("combat_core", "feel.death.hitstop_ms", 150)), 3)
	player.begin_death()
	if Game.autotest:
		print("[autotest] player_died t=%s geodum=%s phase=%d" % [K.fmt_time(Game.time_sec()), _geodum, spawn.phase])


## 굿판 거둠 결과: waves stage_finished 와 같은 꼴(보스 형태·해원 비율)을 싣고 결말만 gutpan_geodum.
func _geodum_result() -> Dictionary:
	return {"victory": true, "ending": &"gutpan_geodum", "boss_form": spawn.boss_form, "boss_kind": spawn.boss_kind,
		"n_final": spawn.n_final}


## waves: 보스·정산이 끝나면 stage_finished(result) — 결과 사전(ending, boss_form …)을 run_ended 에 싣는다.
func _on_stage_finished(result: Dictionary) -> void:
	if _dying:
		if _geodum:
			var r: Dictionary = result.duplicate()
			r["victory"] = true
			r["ending"] = &"gutpan_geodum"
			_finish(true, r)
		else:
			_finish(false, {"ending": &"death"})   # 죽은 뒤 정산 완료 신호가 와도 사망으로
		return
	_finish(bool(result.get("victory", true)), result)


func _finish(victory: bool, extra: Dictionary = {}) -> void:
	if _ended:
		return
	_ended = true
	if Game.run_active:
		Game.end_run(victory, extra)
	if Game.autotest:
		print("[autotest] run_finished victory=%s t=%s ending=%s" % [victory, K.fmt_time(Game.time_sec()), str(Game.last_result.get("ending", ""))])
		_print_autotest_report()
		_print_build_summary()
	finished.emit(Game.last_result.duplicate())


func _on_level_up(_lv: int) -> void:
	if _dying or _ended:
		return
	_st_levelups += 1
	if _lv_hold == 0:
		_lv_hold_since = Game.time_sec()
	_lv_hold += 1


## 지금 점지를 띄우면 흐름이 끊기는 구간인가(시련 강림~해결·합일·작두·보스 등장 연출).
func _jeomji_busy() -> bool:
	var tp: int = trials.ph
	if tp == TrialDirector.Ph.DESCEND or tp == TrialDirector.Ph.CONFIRM or tp == TrialDirector.Ph.CLEAR \
			or tp == TrialDirector.Ph.TRIAL or tp == TrialDirector.Ph.RESOLVE or tp == TrialDirector.Ph.POSSESSION \
			or tp == TrialDirector.Ph.JEOMJI or tp >= TrialDirector.Ph.HAPIL_OMEN:
		return true
	if spawn.jakdu_active:
		return true
	var sp: int = spawn.phase
	if sp == SpawnDirector.Phase.PRE_CLEAR or sp == SpawnDirector.Phase.SILENCE or sp == SpawnDirector.Phase.RESOLVED:
		return true
	if sp == SpawnDirector.Phase.BOSS:
		if _boss_seen_t < 0.0:
			_boss_seen_t = Game.time_sec()
		return Game.time_sec() - _boss_seen_t < BOSS_INTRO_SEC
	return false


func _jeomji_flush() -> void:
	if not jeomji_gate:
		return
	if _lv_hold <= 0 or Game.is_sim_paused() or not Game.run_active:
		return
	var now: float = Game.time_sec()
	var waited: float = now - _lv_hold_since
	if waited < JEOMJI_HOLD_MAX_SEC:
		if _jeomji_busy():
			return
		var gap: float = 0.0
		if now >= JEOMJI_LATE_FROM:
			gap = JEOMJI_GAP_LATE_SEC
		elif now >= JEOMJI_MID_FROM:
			gap = JEOMJI_GAP_MID_SEC
		if now - _jeomji_last_open < gap:
			return
	if now >= JEOMJI_LATE_FROM and _jeomji_last_open >= JEOMJI_LATE_FROM:
		_st_late_gap_min = minf(_st_late_gap_min, now - _jeomji_last_open)
	_jeomji_last_open = now
	_st_jeomji_opens += 1
	var n: int = _lv_hold
	_lv_hold = 0
	if not levelup.has_method("open"):
		return
	for i in n:
		levelup.call("open")   # 열려 있으면 levelup 이 대기 수(_pending)로 쌓는다


func _on_bot_offer(choices: Array) -> void:
	_bot_pick_idx = PlayerBot.pick_offer(choices, _bot_pick)
	_bot_pick_left = 0.45 if _bot_pick_idx > 0 else -1.0


## --autotest-die=<sec>: 그 시각에 봇 부활을 끄고 정기 0. =settle: 보스 해결 뒤 정산 단계에 들어서면.
func _autotest_die_check() -> void:
	if _die_fired:
		return
	var go: bool = (_die_at >= 0.0 and Game.time_sec() >= _die_at) or (_die_settle and spawn.phase == SpawnDirector.Phase.SETTLE)
	if not go:
		return
	_die_fired = true
	_allow_death = true
	Game.debug_invuln = false
	Game.hp = 0.0
	Events.player_damaged.emit(Game.hp_max, &"debug_die", 0.0, Game.hp_max)
	Events.player_died.emit()


## 창이 포커스를 잃으면 쉼 메뉴(뱀서라이크 필수). 점지·빙의 점지·쉼이 이미 열려 있으면(=시뮬 정지) 건드리지 않는다.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	if Game.autotest or _ended or _dying or not Game.run_active or Game.is_sim_paused():
		return
	if pause_menu != null and not pause_menu.visible and pause_menu.has_method("toggle"):
		pause_menu.call("toggle")


func _unhandled_input(event: InputEvent) -> void:
	if _dying or _ended:
		return
	if event.is_action_pressed(&"pause") and not Game.has_pause(&"levelup"):
		if pause_menu.has_method("toggle"):
			pause_menu.call("toggle")
		get_viewport().set_input_as_handled()


func _connect_autotest_stats() -> void:
	Events.enemy_spawned.connect(func(_h: int, _s: StringName, _t: StringName) -> void: _st_spawned += 1)
	Events.weapon_fired.connect(func(w: StringName, _sl: int, _p: Vector2) -> void: _st_fired[w] = int(_st_fired.get(w, 0)) + 1)
	Events.enemy_hit.connect(func(_h: int, _s: StringName, _p: Vector2, _d: float, _c: int, _cr: bool, _k: bool) -> void: _st_hits += 1)
	Events.enemy_killed.connect(func(_h: int, _s: StringName, _p: Vector2, _k: StringName, _c: StringName, _t: StringName) -> void: _st_killed += 1)
	Events.ring_closed.connect(func(_a: int, _n: int, _c: Vector2) -> void: _st_rings += 1)
	Events.weapon_leveled.connect(func(_w: StringName, lv: int) -> void:
		if lv >= 8 and _st_first_lv8 < 0.0:
			_st_first_lv8 = Game.time_sec())
	Events.weapon_evolved.connect(func(_f: StringName, to_id: StringName) -> void:
		if String(to_id).begins_with("union_"):
			_st_unions += 1
			if _st_first_union < 0.0:
				_st_first_union = Game.time_sec()
		else:
			_st_evos += 1
			if _st_first_evo < 0.0:
				_st_first_evo = Game.time_sec())


static func _fmt_opt(t: float) -> String:
	return K.fmt_time(t) if t >= 0.0 else "-"


## --full 비교용 한 줄: 정책·첫 Lv8·첫 진화·첫 결합·점지 횟수·최종 무구.
func _print_build_summary() -> void:
	var parts: PackedStringArray = PackedStringArray()
	for i in weapons.slot_count():
		var w: WeaponBase = weapons.weapon_at(i)
		if w != null:
			parts.append("%s:%d" % [w.id, w.level])
	print("[autotest] build char=%s seed=%s pick=%s lv=%d levelups=%d jeomji_opens=%d late_gap_min=%s first_lv8=%s first_evo=%s evos=%d first_union=%s unions=%d slots=[%s]" % [
		char_id, DebugTools.arg("seed", "-"), _bot_pick, Game.level, _st_levelups, _st_jeomji_opens,
		("%.0fs" % _st_late_gap_min) if _st_late_gap_min < 1e8 else "-", _fmt_opt(_st_first_lv8), _fmt_opt(_st_first_evo), _st_evos,
		_fmt_opt(_st_first_union), _st_unions, ",".join(parts)])


func _print_autotest_report() -> void:
	print("[autotest] t=%s tick_ms=%.2f per_tick_ms=%.3f fps=%d enemies=%d proj=%d orbs=%d lv=%d xp=%.1f/%.0f toechi=%d haewon=%d yeongga=%d salgi=%.2f sinmyeong=%.2f geori=%s draw_calls=%d" % [
		K.fmt_time(Game.time_sec()), tick_ms_avg, tick_ms_avg / maxf(1.0, float(Game.sim_speed)), Engine.get_frames_per_second(), enemies.active_count,
		projectiles.alive_count, pickups.count, Game.level, Game.xp, Game.xp_next, Game.kills_toechi, Game.kills_haewon, yeongga.count,
		Game.salgi, Game.sinmyeong, Beat.geori_id, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	print("[autotest]   spawned=%d fired=%s hits=%d killed=%d rings=%d bot_dist_u=%.0f player=(%.0f,%.0f) hp=%.0f/%.0f weapons=%d" % [
		_st_spawned, str(_st_fired), _st_hits, _st_killed, _st_rings, _st_dist / K.UNIT_PX,
		player.global_position.x, player.global_position.y, Game.hp, Game.hp_max, weapons.slot_count()])
