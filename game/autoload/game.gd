extends Node
## Game — 런 상태, 이중 시계(게임 시계/박 시계), 일시정지 스택, 히트스톱, 서비스 참조. 소유: core(리드).
##
## 이중 시계 (design/14 §3.9.1)
##   game_tick : 시뮬레이션 시계. 일시정지·점지·히트스톱에서 멈춘다. 런 시각 = game_tick / 60.
##   beat_tick : 박 시계. 히트스톱 중에도 흐르고 일시정지·점지에서만 멈춘다. = game_tick + hitstop_ticks_total.
## 고정 틱 실행은 run/run.gd 가 _physics_process 에서 advance_tick() → (true면) 시뮬레이션 단계 순서대로 호출.

enum State { BOOT, TITLE, LOBBY, RUN, RESULT }

var state: State = State.BOOT

# --- 시계 ---
var game_tick: int = 0
var beat_tick: int = 0
var hitstop_ticks_total: int = 0
var hitstop_remaining: int = 0
var sim_speed: int = 1                       # 디버그 F1 (1 또는 10). 프레임당 틱 수.
var _pause_reasons: Dictionary = {}          # StringName -> true

# --- 히트스톱 예산 (combat_core.hitstop) ---
var _hs_budget_ms: int = 400
var _hs_window_ticks: int = 600
var _hs_log_tick: PackedInt32Array = PackedInt32Array()
var _hs_log_ms: PackedInt32Array = PackedInt32Array()
var _hs_log_head: int = 0
var _hs_log_tier: PackedInt32Array = PackedInt32Array()
var _hs_t2_budget_ms: int = 200
var _hs_t4_min_ms: int = 100
var _hs_max_single_ms: int = 200
var _hs_post_cd_ticks: int = 18
var _hs_end_tick: int = -100000
var hitstop_scale: float = 1.0               # 접근성(GAME_FEEL 7): 1 기본 / 0.5 짧게 / 0 끔(국소 정지만 유지)

# --- 런 상태 (런 시작 시 reset_run) ---
var char_id: StringName = &"char_mansin"
var run_active: bool = false
var level: int = 1
var xp: float = 0.0
var xp_next: float = 5.0
var hp: float = 100.0
var hp_max: float = 100.0
var kills_toechi: int = 0
var kills_haewon: int = 0
var salgi: float = 0.0
var sinmyeong: float = 0.0                    # 0..1
var sinmyeong_oreum: bool = false
var cur_neok: int = 0
var stats: Dictionary = {}                   # stat_* -> float (characters.json stat_base + overrides + passives)
var pullil_threshold: float = 0.35

# --- 디버그 / 자동 테스트 ---
var debug_invuln: bool = false
var player_dead: bool = false                # run.gd 사망 연출 중(구슬 흡수·레벨업 차단)
var autotest: bool = false
var autotest_quit_sec: float = -1.0
## 연습 굿판(design/17). main.start_tutorial 이 런 씬을 만들기 전에 켜고 나갈 때 끈다. 소유: tutorial_run(변수만).
var tutorial_mode: bool = false

# --- 서비스 참조 (run.gd 가 _ready 에서 채우고 종료 시 비운다). 타입은 Node 로 두고 각 모듈이 캐스팅. ---
var run_root: Node = null
var world: Node2D = null
var player: Node2D = null
var enemies: Node = null          # EnemyManager
var projectiles: Node = null      # ProjectilePool
var weapons: Node = null          # WeaponManager
var pickups: Node = null          # PickupManager
var vfx: Node = null              # VfxPlayer
var camera: Camera2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hs_log_tick.resize(32)
	_hs_log_ms.resize(32)
	_hs_log_tier.resize(32)
	_hs_log_tick.fill(-100000)
	_install_input_map()
	# 창 닫기(X/Alt+F4)도 quit_game 경로로: 오디오 정리 후 종료(재생 중 playback 누수 방지)
	get_tree().auto_accept_quit = false
	_init_display.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game(0)


# ─── 화면 모드 (Alt+Enter / F11, 릴리스에서도 동작) ─────────────────────
## 저장 키 Save "settings.display_fullscreen"(bool). ui 설정 화면은 set_fullscreen()/is_fullscreen() 을 부른다.
const DISPLAY_SAVE_KEY: String = "settings.display_fullscreen"


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke: InputEventKey = event as InputEventKey
	if not ke.pressed or ke.echo:
		return
	var kc: Key = ke.keycode
	if kc == KEY_F11 or (ke.alt_pressed and (kc == KEY_ENTER or kc == KEY_KP_ENTER)):
		set_fullscreen(not is_fullscreen())
		get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	var m: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(on: bool, save_pref: bool = true) -> void:
	if _display_locked():
		return
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_fit_window()
	if save_pref and not autotest:
		Save.set_value(DISPLAY_SAVE_KEY, on)
		Save.save_profile()


## 헤드리스·무비 캡처·--resolution 지정 실행은 창을 건드리지 않는다.
func _display_locked() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	var all: PackedStringArray = OS.get_cmdline_args()
	return all.has("--write-movie") or all.has("--resolution")


## 시작 시: 저장된 선호 → 없으면 창(640×360 의 정수배, 작업 영역 안). ×2 도 안 들어가면 전체 화면.
func _init_display() -> void:
	if _display_locked():
		return
	var pref: Variant = Save.get_value(DISPLAY_SAVE_KEY, null)
	if pref is bool:
		set_fullscreen(pref as bool, false)
		return
	if not _fit_window():
		set_fullscreen(true, false)


## 창 크기를 작업 영역(제목 표시줄 여유 40px)에 들어가는 가장 큰 정수배로 맞추고 가운데 둔다. ×2 미만이면 false.
func _fit_window() -> bool:
	var scr: int = DisplayServer.window_get_current_screen()
	var area: Rect2i = DisplayServer.screen_get_usable_rect(scr)
	var vw: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 640))
	var vh: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	var k: int = mini(area.size.x / vw, (area.size.y - 40) / vh)
	if k < 2:
		return false
	var sz: Vector2i = Vector2i(vw * k, vh * k)
	DisplayServer.window_set_size(sz)
	DisplayServer.window_set_position(area.position + (area.size - sz) / 2 + Vector2i(0, 16))
	return true


# ─── 시계 ──────────────────────────────────────────────────────────────

func time_sec() -> float:
	return float(game_tick) / K.TICK_HZ


func beat_sec() -> float:
	return float(beat_tick) / K.TICK_HZ


func is_sim_paused() -> bool:
	return not _pause_reasons.is_empty()


func is_hitstop() -> bool:
	return hitstop_remaining > 0


func push_pause(reason: StringName) -> void:
	if _pause_reasons.has(reason):
		return
	_pause_reasons[reason] = true
	Events.pause_changed.emit(true, reason)


func pop_pause(reason: StringName) -> void:
	if not _pause_reasons.has(reason):
		return
	_pause_reasons.erase(reason)
	Events.pause_changed.emit(not _pause_reasons.is_empty(), reason)


func has_pause(reason: StringName) -> bool:
	return _pause_reasons.has(reason)


## run.gd 가 물리 틱마다 호출. true 면 이번 틱에 시뮬레이션을 진행한다.
func advance_tick() -> bool:
	if not run_active or is_sim_paused():
		return false
	beat_tick += 1
	Beat.advance()
	if hitstop_remaining > 0:
		hitstop_remaining -= 1
		hitstop_ticks_total += 1
		return false
	game_tick += 1
	return true


## 전역 히트스톱 요청(ms). 규칙(GAME_FEEL 5.2): max_remaining 누적, 10초 창 400ms 예산(combat_core.hitstop),
## T2 는 그중 t2_budget_ms(200)까지, T4 는 예산이 없어도 t4_min_ms(100) 보장, 단일 최대 max_single_ms(200),
## 히트스톱 종료 후 post_cooldown_low_tier(0.3s) 안의 T2 요청은 버림. 접근성 배율 hitstop_scale(0 = 끔).
## tier: 2..4 (0 = ms 로 추정: ≤80 T2, <200 T3, 그 이상 T4). 반환: 실제로 적용된 ms (예산 초과 시 0).
func request_hitstop(ms: int, tier: int = 0) -> int:
	if ms <= 0 or not run_active:
		return 0
	if tier <= 0:
		tier = 2 if ms <= 80 else (3 if ms < 200 else 4)
	ms = int(roundf(float(ms) * hitstop_scale))
	if ms <= 0:
		return 0
	ms = mini(ms, _hs_max_single_ms)
	if tier <= 2 and hitstop_remaining <= 0 and beat_tick >= _hs_end_tick and beat_tick - _hs_end_tick < _hs_post_cd_ticks:
		return 0
	var used: int = 0
	var used_t2: int = 0
	for i in _hs_log_tick.size():
		if beat_tick - _hs_log_tick[i] < _hs_window_ticks:
			used += _hs_log_ms[i]
			if _hs_log_tier[i] <= 2:
				used_t2 += _hs_log_ms[i]
	var allowed: int = mini(ms, _hs_budget_ms - used)
	if tier <= 2:
		allowed = mini(allowed, _hs_t2_budget_ms - used_t2)
	elif tier >= 4:
		allowed = maxi(allowed, mini(ms, _hs_t4_min_ms))
	if allowed <= 0:
		return 0
	var ticks: int = maxi(1, int(round(allowed * K.TICK_HZ / 1000.0)))
	if ticks > hitstop_remaining:
		hitstop_remaining = ticks
		_hs_end_tick = beat_tick + ticks
	_hs_log_tick[_hs_log_head] = beat_tick
	_hs_log_ms[_hs_log_head] = allowed
	_hs_log_tier[_hs_log_head] = tier
	_hs_log_head = (_hs_log_head + 1) % _hs_log_tick.size()
	Events.hitstop_started.emit(allowed)
	return allowed


# ─── 연출 시계 (GAME_FEEL 1.1) ─────────────────────────────────────────
## 시뮬 틱에서 파생: 히트스톱·일시정지에서 멈추고 배속에서 같이 빨라진다. run.gd 가 물리 프레임마다
## anim_tick_prev/cur 를 채우고 렌더 단계 R1 에서 update_anim_clock() 을 부른다.

## 마지막 물리 프레임 직전·직후의 game_tick(진행 안 된 프레임이면 같다).
var anim_tick_prev: int = 0
var anim_tick_cur: int = 0
var render_alpha: float = 0.0       # Engine.get_physics_interpolation_fraction() (0..1)
var anim_dt: float = 0.0            # 이번 렌더 프레임의 연출 시계 증분(초)
var _anim_last: float = 0.0


func anim_time() -> float:
	return (float(anim_tick_prev) + render_alpha * float(anim_tick_cur - anim_tick_prev)) / K.TICK_HZ


## 연출 시계의 정수 틱(스쿼시·플래시 타이머용). 렌더 보간 위치와 같은 시점.
func anim_tick() -> int:
	return anim_tick_prev + int(floorf(render_alpha * float(anim_tick_cur - anim_tick_prev)))


## 렌더 단계 R1(run.gd._process). 반환: anim_dt.
func update_anim_clock() -> float:
	render_alpha = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var t: float = anim_time()
	anim_dt = clampf(t - _anim_last, 0.0, 0.25)
	_anim_last = t
	return anim_dt


func set_sim_speed(s: int) -> void:
	sim_speed = clampi(s, 1, 20)
	Events.sim_speed_changed.emit(sim_speed)


# ─── 런 ────────────────────────────────────────────────────────────────

func reset_run(p_char_id: StringName) -> void:
	char_id = p_char_id
	game_tick = 0
	beat_tick = 0
	hitstop_ticks_total = 0
	hitstop_remaining = 0
	_hs_log_tick.fill(-100000)
	_pause_reasons.clear()
	sim_speed = 1          # F1 ×10 이 다음 런으로 새지 않게(autotest --speed 는 run._ready 에서 다시 설정)
	player_dead = false
	level = 1
	xp = 0.0
	xp_next = xp_required(1)
	kills_toechi = 0
	kills_haewon = 0
	salgi = 0.0
	sinmyeong = 0.0
	sinmyeong_oreum = false
	cur_neok = 0
	_hs_budget_ms = int(Data.num("combat_core", "hitstop.budget_ms", 400))
	_hs_window_ticks = int(Data.num("combat_core", "hitstop.budget_window", 10.0) * K.TICK_HZ)
	_hs_t2_budget_ms = int(Data.num("combat_core", "hitstop.t2_budget_ms", 200))
	_hs_t4_min_ms = int(Data.num("combat_core", "hitstop.t4_min_ms", 100))
	_hs_max_single_ms = int(Data.num("combat_core", "hitstop.max_single_ms", 200))
	_hs_post_cd_ticks = int(Data.num("combat_core", "hitstop.post_cooldown_low_tier", 0.3) * K.TICK_HZ)
	_hs_end_tick = -100000
	anim_tick_prev = 0
	anim_tick_cur = 0
	render_alpha = 0.0
	anim_dt = 0.0
	_anim_last = 0.0
	pullil_threshold = Data.num("combat_core", "han.giseak_threshold", 0.35)
	_build_stats()
	hp_max = stat(&"stat_jeonggi", 100.0)
	hp = hp_max
	Beat.reset()


func begin_run() -> void:
	run_active = true
	state = State.RUN
	Events.run_started.emit(char_id)


var last_result: Dictionary = {}   # 마지막 end_run 결과(정산 화면 입력, main.gd 가 읽음)

func end_run(victory: bool, extra: Dictionary = {}) -> void:
	if not run_active:
		return
	run_active = false
	state = State.RESULT
	var total: int = kills_toechi + kills_haewon
	var result: Dictionary = {
		"victory": victory, "time_sec": time_sec(), "char_id": char_id, "level": level,
		"toechi": kills_toechi, "haewon": kills_haewon,
		"haewon_ratio": (float(kills_haewon) / total) if total > 0 else 0.0,
		"salgi": salgi, "neok": cur_neok,
	}
	result.merge(extra, true)
	last_result = result
	Events.run_ended.emit(result)


## 앱 종료는 반드시 이 함수로(get_tree().quit() 직접 호출 금지).
## 오디오 재생을 먼저 끊고 2프레임 기다려 AudioServer 가 playback 을 놓게 한 뒤 종료한다
## ("resources still in use at exit" / Ogg playback 누수 방지).
var _quitting: bool = false

func quit_game(code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	run_active = false
	Audio.shutdown()
	# AudioServer 는 믹스 스레드에서 playback 을 놓는다 — 실시간으로 한두 버퍼 기다린다
	# (헤드리스 --fixed-fps 에선 프레임이 몇 ms 라 프레임 대기만으론 부족).
	for i in 3:
		await get_tree().process_frame
		OS.delay_msec(40)
	get_tree().quit(code)


func clear_services() -> void:
	run_root = null
	world = null
	player = null
	enemies = null
	projectiles = null
	weapons = null
	pickups = null
	vfx = null
	camera = null


func _build_stats() -> void:
	stats.clear()
	var base: Variant = Data.get_value("characters", "stat_base", {})
	if base is Dictionary:
		for k: String in base:
			stats[StringName(k)] = float(base[k])
	var ch: Dictionary = Data.character(String(char_id))
	var ov: Variant = ch.get("stat_overrides", {})
	if ov is Dictionary:
		for k: String in ov:
			var v: Variant = ov[k]
			if v is float or v is int:
				stats[StringName(k)] = float(v)


func stat(id: StringName, default: float = 0.0) -> float:
	return float(stats.get(id, default))


# ─── 경험치 (combat_core.xp) ───────────────────────────────────────────

func xp_required(lv: int) -> float:
	var c0: float = Data.num("combat_core", "xp.req_c0", 5.0)
	var c1: float = Data.num("combat_core", "xp.req_c1", 6.0)
	var c2: float = Data.num("combat_core", "xp.req_c2", 0.13)
	# 후반 가속(적응형 스폰으로 처치가 불어나도 14분 뒤 점지 간격 ≥30초): + c3·(L − c3_from)³
	var c3: float = Data.num("combat_core", "xp.req_c3", 0.5)
	var c3_from: int = int(Data.num("combat_core", "xp.req_c3_from", 30))
	var l1: float = float(lv - 1)
	var r: float = c0 + c1 * l1 + c2 * l1 * l1
	if lv > c3_from:
		var d: float = float(lv - c3_from)
		r += c3 * d * d * d
	return roundf(r)


func add_xp(amount: float) -> void:
	if player_dead or not run_active:
		return   # 사망 연출 중 흡인 구슬이 점지를 띄우지 않게
	xp += amount
	Events.xp_collected.emit(amount)
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = xp_required(level)
		Events.level_up.emit(level)


# ─── 입력 맵 (data/input_bindings.json 은 ui 담당이 리바인딩 UI 에서 덮어쓴다) ──

func _install_input_map() -> void:
	_add_keys(&"move_left", [KEY_A, KEY_LEFT])
	_add_keys(&"move_right", [KEY_D, KEY_RIGHT])
	_add_keys(&"move_up", [KEY_W, KEY_UP])
	_add_keys(&"move_down", [KEY_S, KEY_DOWN])
	_add_keys(&"pause", [KEY_ESCAPE, KEY_P])
	_add_keys(&"confirm", [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER])
	_add_keys(&"cancel", [KEY_BACKSPACE])
	_add_keys(&"choice_1", [KEY_1])
	_add_keys(&"choice_2", [KEY_2])
	_add_keys(&"choice_3", [KEY_3])
	_add_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis(&"move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis(&"move_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_button(&"move_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button(&"move_right", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_button(&"move_up", JOY_BUTTON_DPAD_UP)
	_add_joy_button(&"move_down", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button(&"pause", JOY_BUTTON_START)
	_add_joy_button(&"confirm", JOY_BUTTON_A)
	_add_joy_button(&"cancel", JOY_BUTTON_B)
	var dz: float = Data.num("combat_core", "input.stick_deadzone_inner", 0.2)
	for a: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		InputMap.action_set_deadzone(a, dz)


func _ensure_action(a: StringName) -> void:
	if not InputMap.has_action(a):
		InputMap.add_action(a)


func _add_keys(a: StringName, keys: Array) -> void:
	_ensure_action(a)
	for k: int in keys:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = k as Key
		InputMap.action_add_event(a, ev)


func _add_axis(a: StringName, axis: JoyAxis, sign_v: float) -> void:
	_ensure_action(a)
	var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = sign_v
	InputMap.action_add_event(a, ev)


func _add_joy_button(a: StringName, b: JoyButton) -> void:
	_ensure_action(a)
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.button_index = b
	InputMap.action_add_event(a, ev)
