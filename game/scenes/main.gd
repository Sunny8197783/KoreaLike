extends Node
## 화면 라우터: 타이틀 → (신당) → 런 → 정산 → 타이틀. 소유: core(리드).
## --autotest 면 타이틀을 건너뛰고 바로 런(--char=). 런 씬은 매번 새로 만든다(상태 누수 방지).

const TITLE_SCENE: PackedScene = preload("res://ui/title.tscn")
const RUN_SCENE: PackedScene = preload("res://run/run.tscn")
const RESULT_SCENE: PackedScene = preload("res://ui/result.tscn")
const LOBBY_SCENE: PackedScene = preload("res://meta/sindang_lobby.tscn")

var _current: Node = null
var _last_char: StringName = &"char_mansin"


func _ready() -> void:
	if DebugTools.args.has("pilot") or DebugTools.args.has("pilot-legacy"):
		# 파일럿 렌더 장면(tests/pilot_scene): --pilot [--pilot-legacy]
		_swap((load("res://tests/pilot_scene.tscn") as PackedScene).instantiate())
		return
	Events.tutorial_exit_requested.connect(_on_tutorial_exit)
	# 연습 굿판(design/17 §7.6): --tutorial-autotest(+ --autotest) / --tutorial-step=<id> 는 타이틀 없이 연습 굿판.
	# 단, --intro-test 가 같이 오면 첫 실행 흐름 검사: 타이틀 인트로 → 권유 창(--intro-choice) → 연습/실전.
	var via_title: bool = DebugTools.args.has("intro-test")
	if not via_title and (DebugTools.args.has("tutorial-autotest") or DebugTools.arg("tutorial-step") != ""):
		start_tutorial(StringName(DebugTools.arg("tutorial-step")))
		return
	if Game.autotest and not via_title:
		var c: String = DebugTools.arg("char", "char_mansin")
		_go_run(StringName(c))
	else:
		_go_title()


func _swap(n: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = n
	add_child(n)


func _go_title() -> void:
	Game.state = Game.State.TITLE
	var t: Node = TITLE_SCENE.instantiate()
	t.connect("start_requested", _go_run)
	t.connect("lobby_requested", _go_lobby)
	if t.has_signal(&"tutorial_requested"):
		t.connect("tutorial_requested", start_tutorial)
	_swap(t)


func _go_lobby() -> void:
	Game.state = Game.State.LOBBY
	var l: Node = LOBBY_SCENE.instantiate()
	l.connect("back_requested", _go_title)
	l.connect("start_requested", _go_run)
	_swap(l)


func _go_run(char_id: StringName) -> void:
	Game.tutorial_mode = false
	_last_char = char_id
	var r: Run = RUN_SCENE.instantiate() as Run
	r.setup(char_id)
	r.finished.connect(_on_run_finished)
	_swap(r)
	var pm: Node = r.get_node("OverlayLayer/PauseMenu")
	pm.connect("quit_to_title", _after_result)   # 거두기 뒤에도 신당 개방이면 신당으로


## 런 결과(Game.end_run → Events.run_ended 와 같은 사전: victory·time_sec·toechi·haewon·ending·boss_form …) → 정산 화면.
## 정산(메타 화폐)은 Save 가 run_ended 구독 시점에 이미 끝냈다. 정산 화면을 닫으면 신당 개방 뒤엔 신당으로, 아니면 타이틀로.
func _on_run_finished(r: Dictionary) -> void:
	var res: Dictionary = r.duplicate()
	if res.is_empty():
		var total: int = Game.kills_toechi + Game.kills_haewon
		res = {"victory": false, "time_sec": Game.time_sec(), "toechi": Game.kills_toechi,
			"haewon": Game.kills_haewon, "haewon_ratio": float(Game.kills_haewon) / maxi(total, 1),
			"neok": Game.cur_neok, "salgi": Game.salgi, "level": Game.level}
	var s: Node = RESULT_SCENE.instantiate()
	s.call("setup", res)
	s.connect("retry_requested", func() -> void: _go_run(_last_char))
	s.connect("title_requested", _after_result)
	_swap.call_deferred(s)
	if Game.autotest:
		# 봇: 정산 화면을 잠깐 띄운 뒤(무비 캡처용) 종료. --autotest-lobby 면 신당 로비도 거쳐 본다.
		await get_tree().create_timer(float(DebugTools.arg("result-hold", "3.0"))).timeout
		if DebugTools.args.has("autotest-lobby"):
			_go_lobby()
			await get_tree().create_timer(3.0).timeout
		Game.quit_game(0)


func _after_result() -> void:
	if Save.lobby_route():
		_go_lobby()
	else:
		_go_title()


# ─── 연습 굿판(design/17 §3·§7.3). 소유: tutorial_run ─────────────────────

## 연습 굿판 시작: 만신 고정, 런 씬 + TutorialDirector(마지막 자식). 쉼 메뉴 quit_to_title 은 연결하지 않는다
## (연습 중 '연습 그만두기'는 Events.tutorial_exit_requested(&"title")).
func start_tutorial(from_step: StringName = &"") -> void:
	Game.tutorial_mode = true
	_last_char = &"char_mansin"
	var r: Run = RUN_SCENE.instantiate() as Run
	r.setup(&"char_mansin")
	var d: TutorialDirector = TutorialDirector.new()
	d.from_step = from_step
	r.add_child(d)
	# 안전망(30:00 hard_cap 등)으로 런이 끝나면 정산 화면 없이 타이틀로
	r.finished.connect(func(_res: Dictionary) -> void: _on_tutorial_exit(&"title"))
	_swap(r)


## 끝 화면·쉼 메뉴 → &"real" 실전 / &"again" 다시 연습 / &"title" 타이틀.
## Save 는 연습 런을 추적하지 않았다(_run_live=false) → end_run 은 음악·연출 정리만 한다.
func _on_tutorial_exit(next: StringName) -> void:
	if not Game.tutorial_mode:
		return
	Game.end_run(false, {"ending": &"tutorial"})
	Game.tutorial_mode = false
	for reason: StringName in [&"menu", &"levelup", &"bingui_jeomji", &"tutorial_card", &"tutorial_end"]:
		Game.pop_pause(reason)
	_tutorial_route.call_deferred(next)


## 연습 런 씬을 먼저 동기적으로 떼어 낸다: queue_free 만 하면 옛 런의 _exit_tree(Game.clear_services)가
## 새 런의 _ready 뒤에 돌아 새 런의 서비스 참조를 지운다(다시 연습·실전 직행).
func _tutorial_route(next: StringName) -> void:
	if _current != null and _current is Run:
		remove_child(_current)
		_current.queue_free()
		_current = null
	var pending: bool = Save.first_run_pending()
	print("[tutorial] route=%s first_run_pending=%s runs_done=%d" % [next, str(pending), Save.runs_done()])
	match next:
		&"real":
			if pending:
				_go_run(&"char_mansin")
			else:
				_go_lobby()
		&"again":
			start_tutorial(&"")
		_:
			_go_title()
	# 자동 테스트(--tutorial-exit=title): 타이틀이 섰는지 찍고 끝낸다
	if next == &"title" and DebugTools.args.has("tutorial-autotest"):
		await get_tree().process_frame
		print("[tutorial] title_back state=%d" % Game.state)
		await get_tree().create_timer(1.0).timeout
		Game.quit_game(0)
		return
	# 자동 테스트(--tutorial-exit=real): 첫 실전이 만신 직행 + 첫 굿판 완화로 섰는지 찍고 끝낸다(design/17 §9-3)
	if next == &"real" and DebugTools.args.has("tutorial-autotest"):
		await get_tree().process_frame
		var r: Run = _current as Run
		print("[tutorial] real_run char=%s assist=%s" % [
			String(Game.char_id), str(r != null and r.spawn != null and r.spawn.assist)])
		await get_tree().create_timer(1.0).timeout
		Game.quit_game(0)
