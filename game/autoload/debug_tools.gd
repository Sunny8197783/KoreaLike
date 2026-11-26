extends Node
## DebugTools — 디버그 키 + 명령행 인자. 소유: core(리드).
##   F1  시간 ×10 토글(프레임당 10틱)      F2  즉시 레벨업
##   F3  무적 토글                          F4  적 200 즉시 스폰(성능 확인)
##   F5  시련 즉시 시작                     F6  풀릴 기색 강제(화면 안 적 전부)
##   F9  성능 덤프(콘솔)
## 명령행(엔진 인자 뒤 또는 `--` 뒤 모두 인식):
##   --autotest            타이틀 건너뛰고 런 시작, 봇 이동·점지 자동 선택
##   --char=<char_id>      캐릭터 지정 (기본 char_mansin)
##   --seed=<int>          RNG 시드 고정
##   --start-sec=<sec>     런 시작 시각 건너뛰기(스폰 디렉터 테스트)
##   --speed=<n>           시뮬레이션 배속
##   --quit-at=<sec>       런 시각 sec 에 종료(봇 테스트용, 게임 시각 기준)
##   --autotest-die=<sec>|settle  그 시각(또는 보스 해결 뒤 정산 단계)에 봇 부활을 끄고 정기 0 → 사망/굿판 거둠 경로 시험
##   --bot-pick=greedy|random|pair  봇 점지 정책(pair: 짝 패시브 > 빈 칸 새 무구 > 진화 짝 패시브 > 강화)
##   --result-hold=<sec> / --autotest-lobby  정산 화면 유지 시간 / 정산 뒤 신당 로비 거치기
##   --vis-stats --vis-at=<초,초..> --vis-out=<절대경로>  가시성 기준 캡처(tests/vis_probe.gd 머리말)
##   (릴리스 포함) Alt+Enter·F11 전체 화면 토글 = Game._input

var args: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var all: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in all:
		if not a.begins_with("--"):
			continue
		var s: String = a.substr(2)
		var eq: int = s.find("=")
		if eq >= 0:
			args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			args[s] = "true"
	Game.autotest = args.has("autotest")
	if args.has("seed"):
		Rng.reseed(int(args["seed"]))
	if args.has("quit-at"):
		Game.autotest_quit_sec = float(args["quit-at"])
	if Game.autotest:
		print("[DebugTools] autotest on, args=", args)
	# --vis-stats: 가시성 기준 캡처(tests/vis_probe.gd, 디버그 빌드 전용 — 내보내기에서 tests/ 제외)
	if args.has("vis-stats") and OS.is_debug_build() and ResourceLoader.exists("res://tests/vis_probe.gd"):
		add_child.call_deferred((load("res://tests/vis_probe.gd") as GDScript).new())


func arg(name: String, default: String = "") -> String:
	return String(args.get(name, default))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not OS.is_debug_build():
		return
	var k: Key = (event as InputEventKey).keycode
	match k:
		KEY_F1:
			Game.set_sim_speed(10 if Game.sim_speed == 1 else 1)
		KEY_F2:
			if Game.run_active:
				Game.add_xp(maxf(0.0, Game.xp_next - Game.xp))
		KEY_F3:
			Game.debug_invuln = not Game.debug_invuln
			Events.debug_toggled.emit(&"invuln", Game.debug_invuln)
		KEY_F4:
			if Game.enemies != null and Game.enemies.has_method("debug_spawn_ring"):
				Game.enemies.call("debug_spawn_ring", 200)
		KEY_F5:
			Events.debug_trial_now.emit()
		KEY_F6:
			if Game.enemies != null and Game.enemies.has_method("debug_force_pullil"):
				Game.enemies.call("debug_force_pullil")
		KEY_F9:
			_dump_perf()
		_:
			return
	get_viewport().set_input_as_handled()


func _dump_perf() -> void:
	var n: int = int(Game.enemies.get("active_count")) if Game.enemies != null else 0
	print("[perf] fps=%d enemies=%d draw_calls=%d obj=%d t=%s" % [
		Engine.get_frames_per_second(), n,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_COUNT), K.fmt_time(Game.time_sec())])
