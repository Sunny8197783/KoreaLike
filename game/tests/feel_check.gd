extends Node
## GAME_FEEL 9.1 일부 자동 검증(헤드리스). 소유: core.
## 실행: godot --headless --path game res://tests/feel_check.tscn   (오토로드가 필요해 -s 가 아니라 씬으로 실행)
## 검사: K.rnd/K.dir4_from_vec 구간, 넉백 거리 모델(월도 kb 0.6u → 일반 잡귀 19px, 0.12s), 국소 정지 2틱, 정예 ×0.25,
##       히트스톱 T2 예산 200ms·T4 최소 100ms.

var _fails: int = 0


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("[feel_check] %s %s %s" % ["PASS" if ok else "FAIL", name, detail])


func _ready() -> void:
	await get_tree().process_frame
	# --- K ---
	_check("rnd(-0.5)", K.rnd(-0.5) == 0.0, str(K.rnd(-0.5)))
	_check("rnd(2.5)", K.rnd(2.5) == 3.0)
	_check("dir SE 30deg -> E", K.dir4_from_vec(Vector2.from_angle(deg_to_rad(30)), K.Dir.SOUTH, 0.0) == K.Dir.EAST)
	_check("dir 60deg -> S", K.dir4_from_vec(Vector2.from_angle(deg_to_rad(60)), K.Dir.EAST, 0.0) == K.Dir.SOUTH)
	_check("dir hysteresis keeps E at 62deg", K.dir4_from_vec(Vector2.from_angle(deg_to_rad(62)), K.Dir.EAST, 10.0) == K.Dir.EAST)
	_check("dir -140deg -> W", K.dir4_from_vec(Vector2.from_angle(deg_to_rad(-140)), K.Dir.NORTH, 0.0) == K.Dir.WEST)
	# --- 넉백 ---
	var fake: Node2D = Node2D.new()
	add_child(fake)
	fake.global_position = Vector2(0, 400)   # 재배치 반경(22u) 안, 접촉 밖
	Game.player = fake
	Game.reset_run(&"char_mansin")
	Game.run_active = true
	var em: EnemyManager = EnemyManager.new()
	add_child(em)
	Game.enemies = em
	var d1: float = _kb_once(em, &"enm_dalgyal_gwisin", 1.0, 0.6)
	_check("knockback woldo common 19px", absf(d1 - 19.2) <= 1.0, "%.2fpx" % d1)
	var d2: float = _kb_once(em, &"elite_geogu_gwi", 1.0, 0.6)
	_check("knockback woldo elite x0.25", absf(d2 - 4.8) <= 1.0, "%.2fpx" % d2)
	# 국소 정지: 큰 피해(≥25%) → 2틱 정지 후 넉백 시작
	var h: int = em.spawn(&"enm_dalgyal_gwisin", Vector2(0, 0))
	var s: int = em.slot_of(h)
	em.speed[s] = 0.0
	em.queue_hit(s, em.han_max[s] * 0.3, K.DmgColor.RED, false, Vector2(1, 0), 0.6)
	em.resolve_hits()
	var x0: float = em.px[s]
	var moved_at: int = -1
	for t in 14:
		Game.game_tick += 1
		em.sim_think_move(K.TICK_DT)
		if moved_at < 0 and absf(em.px[s] - x0) > 0.01:
			moved_at = t + 1
	_check("local freeze 2 ticks then knockback", moved_at == 3, "first move at tick %d" % moved_at)
	em.clear_all()
	# --- 히트스톱 예산 ---
	Game.reset_run(&"char_mansin")
	Game.run_active = true
	var a: int = Game.request_hitstop(80, 2)
	Game.hitstop_remaining = 0
	Game.beat_tick += 60
	var b: int = Game.request_hitstop(80, 2)
	Game.hitstop_remaining = 0
	Game.beat_tick += 60
	var c: int = Game.request_hitstop(80, 2)
	_check("T2 budget 200ms", a + b + c == 200, "%d+%d+%d" % [a, b, c])
	Game.hitstop_remaining = 0
	Game.beat_tick += 60
	var d: int = Game.request_hitstop(200, 3)
	Game.hitstop_remaining = 0
	Game.beat_tick += 60
	var e: int = Game.request_hitstop(200, 4)
	_check("T4 min 100ms when budget gone", e >= 100, "T3=%d T4=%d" % [d, e])
	Game.run_active = false
	Game.clear_services()
	print("[feel_check] done, fails=%d" % _fails)
	Game.quit_game(1 if _fails > 0 else 0)


func _kb_once(em: EnemyManager, sp: StringName, dmg: float, kb_u: float) -> float:
	var h: int = em.spawn(sp, Vector2(0, 0))
	var s: int = em.slot_of(h)
	em.speed[s] = 0.0
	em.queue_hit(s, dmg, K.DmgColor.RED, false, Vector2(1, 0), kb_u)
	em.resolve_hits()
	var x0: float = em.px[s]
	for t in 20:
		Game.game_tick += 1
		em.sim_think_move(K.TICK_DT)
	var dist: float = em.px[s] - x0
	em.force_toechi(s)
	em.clear_all()
	return dist
