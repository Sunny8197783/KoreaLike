extends Node
## Ambience — 앰비언스 베드(화면별) · 시련 오버레이 · 풍경 원샷 · 무구 루프(방울 오라·명두 공전) · 저정기 심장
##   · 길베 스침(이동속도) · 거점 유지 허밍(산신 가호). 소유: audio.
## design/12 9.2: 베드 + 원샷 풀(랜덤 간격·랜덤 패닝). 전투 중 −34 LUFS-S 근처(소스 정규화), 강도 I2 이상 −4dB, 보스 −8dB.
## 풍경 원샷 간격은 영가 행렬이 길수록 짧아진다(18s → 4s): '넋이 모일수록 굿판이 맑아진다'(L12 넋 레이어 대용).

const BED_RUN: StringName = &"amb_guksadang"
const BED_LOBBY: StringName = &"amb_lobby_sindang"
const TRIAL_BED: StringName = &"amb_trial_field"
const CHIME: StringName = &"sfx_amb_pungyeong"
const MUTE: float = -80.0

var _bed: Array[AudioStreamPlayer] = []
var _bed_id: PackedStringArray = PackedStringArray(["", ""])
var _bed_gain: PackedFloat32Array = PackedFloat32Array([MUTE, MUTE])
var _bed_tgt: PackedFloat32Array = PackedFloat32Array([MUTE, MUTE])
var _bed_cur: int = -1
var _trial: AudioStreamPlayer
var _trial_gain: float = MUTE
var _trial_on: bool = false
const NLOOP: int = 5
var _loops: Array[AudioStreamPlayer] = []      # 0 방울 오라, 1 명두 공전, 2 저정기 심장, 3 길베 스침, 4 거점 유지 허밍
var _loop_id: Array[StringName] = [&"sfx_wpn_bangul__aura", &"sfx_wpn_myeongdu__hum", &"sfx_sys_eoduk_heart", &"sfx_sys_gilbe_loop", &"sfx_trl_grm_hold_loop"]
var _loop_bus: Array[StringName] = [&"SfxWhite", &"SfxWhite", &"SfxPlayer", &"SfxRitual", &"SfxRitual"]
var _loop_db: PackedFloat32Array = PackedFloat32Array([-15.0, -17.0, -10.0, -14.0, -6.0])
var _loop_want: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0])
var _loop_gain: PackedFloat32Array = PackedFloat32Array([MUTE, MUTE, MUTE, MUTE, MUTE])
var _hold_pitch: float = 1.0
var _yeongga: int = 0
var _next_chime: float = 0.0
var _state_seen: int = -1
var _boss: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = &"Ambience"
		p.volume_db = MUTE
		add_child(p)
		_bed.append(p)
	_trial = AudioStreamPlayer.new()
	_trial.bus = &"Ambience"
	add_child(_trial)
	for i in NLOOP:
		var lp: AudioStreamPlayer = AudioStreamPlayer.new()
		lp.bus = _loop_bus[i]
		lp.volume_db = MUTE
		add_child(lp)
		_loops.append(lp)
	Events.trial_start.connect(func(_s: int, _d: StringName) -> void: _trial_on = true)
	Events.trial_end.connect(func(_s: int, _d: StringName, _w: StringName) -> void: _trial_on = false)
	Events.yeongga_joined.connect(func(c: int, _sp: StringName) -> void: _yeongga = c)
	Events.yeongga_cheondo.connect(func(c: int, _r: StringName) -> void: _yeongga = maxi(0, c))
	Events.weapon_added.connect(_on_weapon_added)
	Events.run_started.connect(_on_run_started)
	Events.boss_incoming.connect(func(_s: StringName) -> void: _boss = true)


func _on_run_started(_c: StringName) -> void:
	_loop_want.fill(0)
	_yeongga = 0
	_boss = false
	_trial_on = false
	_next_chime = Audio.now() + 6.0


func _on_weapon_added(weapon_id: StringName, _slot: int) -> void:
	if weapon_id == &"wpn_bangul":
		_loop_want[0] = 1
	elif weapon_id == &"wpn_myeongdu":
		_loop_want[1] = 1


func _stream(id: StringName) -> AudioStream:
	var d: int = Audio.def_of(id)
	if d < 0:
		return null
	var s: AudioStream = Audio.bank.named_stream(d, String(id).substr(String(id).find("__"))) if String(id).contains("__") else Audio.bank.pick_take(d, Audio.rng())
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


func _set_bed(id: StringName, db: float) -> void:
	if _bed_cur >= 0 and _bed_id[_bed_cur] == String(id):
		_bed_tgt[_bed_cur] = db
		return
	if _bed_cur >= 0:
		_bed_tgt[_bed_cur] = MUTE
	if id == &"":
		_bed_cur = -1
		return
	var s: AudioStream = _stream(id)
	if s == null:
		_bed_cur = -1
		return
	var n: int = 0 if _bed_cur != 0 else 1
	_bed_id[n] = String(id)
	_bed_gain[n] = MUTE
	_bed_tgt[n] = db
	_bed[n].stream = s
	if not Audio.silent:
		_bed[n].play(Audio.rng().randf_range(0.0, maxf(s.get_length() - 1.0, 0.0)))
	_bed_cur = n


func update(now: float, dt: float) -> void:
	var st: int = int(Game.state)
	var level: float = 0.0
	match Game.state:
		Game.State.TITLE:
			_want_bed(st, BED_RUN, -5.0)
		Game.State.LOBBY:
			_want_bed(st, BED_LOBBY, 0.0)
		Game.State.RUN:
			var inten: int = Audio.music.intensity if Audio.music != null else 0
			level = (-4.0 if inten >= 2 else 0.0) + (-8.0 if _boss else 0.0)
			_want_bed(st, BED_RUN, level)
		Game.State.RESULT:
			_want_bed(st, BED_RUN, -6.0)
	for i in 2:
		var g: float = _bed_gain[i]
		var tg: float = _bed_tgt[i]
		if g != tg:
			g = minf(tg, g + 30.0 * dt) if tg > g else maxf(tg, g - 40.0 * dt)
			_bed_gain[i] = g
			if g <= MUTE + 0.5 and tg <= MUTE:
				_bed[i].stop()
				_bed[i].stream = null
				_bed_id[i] = ""
			else:
				_bed[i].volume_db = g
	_update_trial(dt)
	_update_loops(dt)
	if Game.state == Game.State.RUN and Game.run_active and not Game.is_sim_paused() and now >= _next_chime:
		_chime(now)


func _want_bed(st: int, id: StringName, db: float) -> void:
	if st != _state_seen:
		_state_seen = st
		_set_bed(id, db)
	elif _bed_cur >= 0:
		_bed_tgt[_bed_cur] = db


func _update_trial(dt: float) -> void:
	var want: float = -2.0 if (_trial_on and Game.state == Game.State.RUN) else MUTE
	if want > MUTE and _trial.stream == null:
		var s: AudioStream = _stream(TRIAL_BED)
		if s == null:
			return
		_trial.stream = s
		_trial_gain = MUTE
		if not Audio.silent:
			_trial.play()
	if _trial.stream == null:
		return
	_trial_gain = minf(want, _trial_gain + 25.0 * dt) if want > _trial_gain else maxf(want, _trial_gain - 30.0 * dt)
	_trial.volume_db = _trial_gain
	if _trial_gain <= MUTE + 0.5 and want <= MUTE:
		_trial.stop()
		_trial.stream = null


func _update_loops(dt: float) -> void:
	var run: bool = Game.state == Game.State.RUN and Game.run_active
	var low: bool = run and Game.hp > 0.0 and Game.hp / maxf(Game.hp_max, 1.0) <= 0.25
	_loop_want[2] = 1 if low else 0
	Audio.buses.set_music_shelf(low)
	_gilbe_level(run)
	_hold_level(run)
	var paused: bool = Game.is_sim_paused()
	for i in NLOOP:
		var p: AudioStreamPlayer = _loops[i]
		var want: float = _loop_db[i] if (run and _loop_want[i] == 1) else MUTE
		if want > MUTE and p.stream == null:
			var s: AudioStream = _stream(_loop_id[i])
			if s == null:
				_loop_want[i] = 0
				continue
			p.stream = s
			_loop_gain[i] = MUTE
			if not Audio.silent:
				p.play()
		if p.stream == null:
			continue
		p.stream_paused = paused
		var g: float = _loop_gain[i]
		g = minf(want, g + 20.0 * dt) if want > g else maxf(want, g - 30.0 * dt)
		_loop_gain[i] = g
		p.volume_db = g
		if i == 4:
			p.pitch_scale = _hold_pitch
		if g <= MUTE + 0.5 and want <= MUTE:
			p.stop()
			p.stream = null


## 길베 스침: 무명 리본이 바닥을 끄는 루프. 볼륨 = 이동속도(−24 → −14dB), 신명 오름 중 +3dB. 멈추면 잦아든다.
func _gilbe_level(run: bool) -> void:
	_loop_want[3] = 0
	if not run or Game.player == null:
		return
	var v: Variant = Game.player.get("vel")
	var sp: float = (v as Vector2).length() if v is Vector2 else 0.0
	if sp < 20.0:
		return
	var k: float = clampf(sp / (4.0 * K.UNIT_PX), 0.0, 1.3)
	_loop_db[3] = lerpf(-24.0, -14.0, minf(k, 1.0)) + (3.0 if Game.sinmyeong_oreum else 0.0)
	_loop_want[3] = 1


## 거점 유지(산신 가호 grm_hold): 쉼터 안에 서 있는 동안 허밍, 가호 진척 비례 피치 0 → +7반음.
func _hold_level(run: bool) -> void:
	_loop_want[4] = 0
	if not run or not _trial_on or Audio.router == null:
		return
	var td: Node = Audio.router.trial_node()
	if td == null:
		return
	var task: Variant = td.get("task")
	if not (task is Object):
		return
	var tk: Object = task
	if int(tk.get("kind")) != 1 or bool(tk.get("done")) or Game.player == null:   # trial_task.Kind.HOLD
		return
	var zone: Variant = tk.get("zone")
	if not (zone is Vector2) or Game.player.global_position.distance_to(zone) > float(tk.get("zone_r")):
		return
	_hold_pitch = pow(2.0, 7.0 * clampf(float(Audio.router.gaho_steps()) / 10.0, 0.0, 1.0) / 12.0)
	_loop_want[4] = 1


## 풍경 원샷: 무당 둘레 6~11u 임의 방위(2D 패닝), 행렬이 길수록 자주.
func _chime(now: float) -> void:
	var r: RandomNumberGenerator = Audio.rng()
	var p: float = clampf(float(_yeongga) / 24.0, 0.0, 1.0)
	var base: float = lerpf(18.0, 4.0, p)
	_next_chime = now + base * r.randf_range(0.6, 1.4)
	var d: int = Audio.def_of(CHIME)
	if d < 0:
		return
	var pos: Vector2 = Audio.NO_POS
	if Game.player != null:
		pos = Game.player.global_position + Vector2.from_angle(r.randf() * TAU) * r.randf_range(6.0, 11.0) * K.UNIT_PX
	var tori: PackedInt32Array = Audio.router.tori
	var semi: int = tori[r.randi_range(0, tori.size() - 1)]
	Audio.play_def(d, -6.0 + 4.0 * p, pow(2.0, float(semi) / 12.0), pos)


func release() -> void:
	for p in _bed:
		p.stop()
		p.stream = null
	_trial.stop()
	_trial.stream = null
	for lp in _loops:
		lp.stop()
		lp.stream = null
