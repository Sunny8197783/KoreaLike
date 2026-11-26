extends Node2D
## 파일럿 렌더 장면(ART_STYLE 6.5 인게임 확인). 소유: core(리드).
## 실제 런 씬(run.tscn)을 그대로 띄우고 연출 조건만 고정한다:
##   - 선바위 굿당(stage1) 지면, 만신 + 시작 무구 신칼 Lv1, 카메라 추적은 런 그대로
##   - 스폰 디렉터 끔 → 달걀귀신 12~20마리를 직접 스폰(처음 16, 이후 살아 있는 수 12 미만이면 보충, 상한 20)
##   - 봇: tests/pilot_bot.gd (정지 → 원 → 지그재그 → 정지 → 원 → 정지, 8초 주기)
##   - HUD 숨김, 레벨업 없음(xp_next 무한), 플레이어 HP 매 틱 회복(사망 화면 방지)
## 연출용 고정값(게임 데이터와 다름, 로그에 출력):
##   - 짝수 번째 달걀귀신은 han_ratio 0.7 로 스폰 → 신칼 1타 퇴치(han_pa). 홀수는 만피 → 1타 후 풀릴 기색(매듭 잠금 때문에 신칼로는 못 죽음)
##   - 신칼 kb = --pilot-kb (기본 0.3u = combat_core.knockback.grades_u.light). weapons.json 신칼 레벨 행에는 kb 가 없다(0 → 1px 넛지만)
## 실행: godot --path game -- --pilot [--pilot-legacy] [--seed=7] [--pilot-sec=8] [--pilot-kb=0.3] [--pilot-hud] [--pilot-count=100]
##   --pilot-count=N: 군중 가독성 판정(ART_STYLE 6.5 기준 5). 달걀귀신 N마리를 화면 안 고리(r 40~300px)에 깔고 N 유지.
##   --pilot-legacy: SpriteLib/VfxLib 의 파일럿 에셋 우선을 끈다(기존 에셋으로 같은 장면). 모션 코드는 현재 코드 그대로.
## 로그: "[pilot] f=<프레임> t=<게임초> ..." — f 는 이 노드 _process 호출 횟수(--write-movie 프레임 번호와 맞춤 확인용).

const RUN_SCENE: PackedScene = preload("res://run/run.tscn")
const PilotBot: GDScript = preload("res://tests/pilot_bot.gd")
const SPECIES: StringName = &"enm_dalgyal_gwisin"
const INIT_COUNT: int = 16
const MIN_ALIVE: int = 12
const MAX_ALIVE: int = 20

var run: Run
var _bot: PlayerBot
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _dur: float = 8.0
var _kb_u: float = 0.3
var _spawned: int = 0
var _frame: int = 0
var _last_phase: StringName = &""
var _refill_cd: int = 0
var _kb_set: bool = false
var _quit: bool = false
var _count: int = 0


func _ready() -> void:
	var seed_v: int = int(DebugTools.arg("seed", "7"))
	_rng.seed = seed_v
	Rng.reseed(seed_v)
	_dur = float(DebugTools.arg("pilot-sec", "8"))
	_kb_u = float(DebugTools.arg("pilot-kb", "0.3"))
	_count = int(DebugTools.arg("pilot-count", "0"))
	Game.state = Game.State.RUN
	run = RUN_SCENE.instantiate() as Run
	run.setup(&"char_mansin")
	add_child(run)
	run.spawn.enabled = false
	if DebugTools.arg("pilot-hud") == "":
		(run.get_node("HUDLayer") as CanvasLayer).visible = false
	Game.xp_next = 1.0e9
	_bot = PilotBot.new()
	run.player._bot = _bot
	Events.weapon_fired.connect(_on_fired)
	Events.enemy_hit.connect(_on_hit)
	Events.enemy_killed.connect(_on_killed)
	Events.pullil_entered.connect(_on_pullil)
	Events.player_damaged.connect(_on_player_damaged)
	var pc: Vector2 = run.player.global_position
	if _count > 0:
		for k in _count:
			_spawn_at(pc + _crowd_offset())
	else:
		for k in INIT_COUNT:
			var ang: float = TAU * float(k) / INIT_COUNT + _rng.randf_range(-0.15, 0.15)
			_spawn_at(pc + Vector2.from_angle(ang) * _rng.randf_range(110.0, 210.0))
	var at: Dictionary = SpriteLib.anim_atlas("char_mansin", PackedStringArray(["walk"]), 64)
	var ea: Dictionary = SpriteLib.anim_atlas(String(SPECIES), PackedStringArray(["move"]), 32)
	print("[pilot] count=%d" % _count)
	print("[pilot] start legacy=%s seed=%d dur=%.1f kb_u=%.2f mansin(pilot=%s canvas=%s pivot=%s body_h=%d) dalgyal(pilot=%s canvas=%s pivot=%s body_h=%d)" % [
		str(SpriteLib.pilot_legacy()), seed_v, _dur, _kb_u, str(at.get("pilot")), str(at.get("canvas")), str(at.get("pivot")), int(at.get("body_h", 0)),
		str(ea.get("pilot")), str(ea.get("canvas")), str(ea.get("pivot")), int(ea.get("body_h", 0))])


## 군중 배치: 화면(640×360) 안 타원 고리, 플레이어 몸 40px 밖.
func _crowd_offset() -> Vector2:
	var ang: float = _rng.randf_range(0.0, TAU)
	var r: float = sqrt(_rng.randf_range(0.04, 1.0))
	return Vector2(cos(ang) * r * 300.0, sin(ang) * r * 165.0)


func _spawn_at(pos: Vector2) -> void:
	var em: EnemyManager = run.enemies
	var opts: Dictionary = {}
	if _spawned % 2 == 0:
		opts["han_ratio"] = 0.7
	em.spawn(SPECIES, pos, opts)
	_spawned += 1


func _process(_delta: float) -> void:
	if _bot != null and _bot.phase != _last_phase:
		_last_phase = _bot.phase
		_log("phase=%s player=(%.1f,%.1f)" % [_last_phase, run.player.global_position.x, run.player.global_position.y])
	_frame += 1


func _physics_process(_delta: float) -> void:
	if run == null or _quit:
		return
	Game.hp = Game.hp_max
	if not _kb_set:
		var wm: WeaponManager = run.weapons
		for w: WeaponBase in wm.slots:
			if w.id == &"wpn_sinkal":
				w.lv = w.lv.duplicate()
				w.lv["kb"] = _kb_u
				_kb_set = true
	var em: EnemyManager = run.enemies
	_refill_cd -= 1
	if _count > 0:
		if em.alive_count_of(SPECIES) < _count:
			_spawn_at(run.player.global_position + _crowd_offset() * 1.1)
	elif _refill_cd <= 0 and em.alive_count_of(SPECIES) < MIN_ALIVE:
		var ang: float = _rng.randf_range(0.0, TAU)
		_spawn_at(run.player.global_position + Vector2.from_angle(ang) * _rng.randf_range(190.0, 230.0))
		_refill_cd = 6
	if Game.time_sec() >= _dur:
		_quit = true
		_log("end spawned=%d alive=%d" % [_spawned, em.alive_count_of(SPECIES)])
		Game.quit_game(0)


func _log(s: String) -> void:
	print("[pilot] f=%d t=%.3f %s" % [_frame, Game.time_sec(), s])


func _on_fired(w: StringName, _slot: int, pos: Vector2) -> void:
	_log("fired %s at=(%.0f,%.0f)" % [w, pos.x, pos.y])


func _on_hit(h: int, _s: StringName, pos: Vector2, dmg: float, _c: int, crit: bool, knot: bool) -> void:
	_log("hit h=%d at=(%.0f,%.0f) dmg=%.1f crit=%s knot=%s" % [h, pos.x, pos.y, dmg, str(crit), str(knot)])


func _on_killed(h: int, _s: StringName, pos: Vector2, kind: StringName, cause: StringName, _t: StringName) -> void:
	_log("killed h=%d at=(%.0f,%.0f) kind=%s cause=%s" % [h, pos.x, pos.y, kind, cause])


func _on_pullil(h: int, _s: StringName, pos: Vector2) -> void:
	_log("pullil h=%d at=(%.0f,%.0f)" % [h, pos.x, pos.y])


func _on_player_damaged(amount: float, src: StringName, _hp: float, _hpm: float) -> void:
	_log("player_damaged %.1f src=%s" % [amount, src])
