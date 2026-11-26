extends Node
## Audio — 오디오 파사드 + 원샷 보이스 엔진. 소유: audio.
##
## 구성(자식 노드/객체는 _ready 에서 한 번 만든다):
##   AudioBuses   (audio/audio_buses.gd)    버스·슬라이더(slider²)·덕킹 엔벨로프·스냅샷
##   SfxBank      (audio/sfx_bank.gd)       data/audio_sfx.json + assets/sfx/sfx_index.json → 정의·테이크·집계 티어·누락 대체
##   MusicDirector(audio/music_director.gd) 장단 스템 레이어(AudioStreamSynchronized) ↔ Beat 박 시계 추종, 크로스페이드, 큐
##   Ambience     (audio/ambience.gd)       앰비언스 베드·시련 오버레이·풍경 원샷·무구 루프·저정기 심장
##   SfxRouter    (audio/sfx_router.gd)     Events → SFX 매핑(해원 토리 사다리, 히트 집계, 시련·의식 큐)
##
## 보이스: 원샷 풀 48(비위치) + 16(2D 위치). 할당 전에 먼저 합친다(물량 후반 타격음 끊김 방지, design/12 11.4 보강):
##   1) 같은 정의·같은 음이 최소 간격(bank.min_gap: 일반 타격 35ms, 의식 12ms) 안에 또 오면 새 보이스 대신 직전 보이스 볼륨 +1dB(최대 +4dB).
##   2) 정의별 동시 상한(voice_cap)에 닿았는데 가장 최근 것이 90ms 안이면 역시 볼륨만 올린다. 그보다 오래됐으면 가장 오래된 것을 끊는다.
##   3) 제 풀이 차면 다른 풀의 빈 보이스를 빌린다(2D↔비위치). 그래도 없으면 우선순위가 낮은 것을 끊는다 —
##      같은 서열은 0.25s 넘게 울린(꼬리만 남은) 것만. 일반 피격끼리는 서로 빼앗지 않고 버린다(보스·해원·고리 > 일반 피격).
## 시계: 실제 재생은 실시간. silent(헤드리스·무비)는 프레임 Δ×sim_speed 게임 시계 — 고속 무인 테스트에서도 1배속 밀도로 센다.
## 히트 집계(11.2): 같은 정의의 적중을 40ms 창으로 모아 1회 재생(티어 1/2-5/6-20/21+ → __agg2..4, 게인 +0/2/4/6dB).
## 헤드리스·무비 모드(silent): 로드·풀 순환·통계는 그대로, play() 만 생략(종료 누수 방지 — ARCHITECTURE §2 Audio).
##   검증용 `-- --audio-live` 는 헤드리스(Dummy 드라이버)에서도 실제로 재생해 박 동기 오차를 잰다(종료는 quit_game 경로).

const AudioBusesScript = preload("res://audio/audio_buses.gd")
const SfxBankScript = preload("res://audio/sfx_bank.gd")
const MusicDirectorScript = preload("res://audio/music_director.gd")
const AmbienceScript = preload("res://audio/ambience.gd")
const SfxRouterScript = preload("res://audio/sfx_router.gd")

const BUSES: PackedStringArray = ["Music", "SFX", "UI", "Ambience", "Voice"]
const POOL_SIZE: int = 48             # tech/perf_budgets caps.audio_oneshot_players
const POOL_2D: int = 16
const NV: int = POOL_SIZE + POOL_2D
const AGG_WINDOW: float = 0.040
const DQ_CAP: int = 64
const NO_POS: Vector2 = Vector2(INF, INF)
const MERGE_STEP_DB: float = 1.0       # 합쳐진 요청 1건당 직전 보이스 볼륨 상승
const MERGE_MAX_DB: float = 4.0
const CAP_MERGE_WIN: float = 0.09      # 상한 도달 시 가장 최근 보이스가 이 안이면 끊지 않고 합친다
const PITCH_SAME: float = 0.03         # 같은 음으로 보는 피치 비 차이(해원 사다리 한 칸 = 12% 이상)
const STEAL_SAME_AGE: float = 0.25     # 같은 서열끼리는 이만큼 울린 것만 끊는다

var silent: bool = false
var live_test: bool = false
var log_enabled: bool = false
var current_cue: StringName = &""

var buses: AudioBusesScript = null
var bank: SfxBankScript = null
var music: MusicDirectorScript = null
var ambience: AmbienceScript = null
var router: SfxRouterScript = null

var _pool: Array[AudioStreamPlayer] = []
var _pool_2d: Array[AudioStreamPlayer2D] = []
var _v_def: PackedInt32Array = PackedInt32Array()
var _v_prio: PackedInt32Array = PackedInt32Array()
var _v_start: PackedFloat64Array = PackedFloat64Array()
var _v_end: PackedFloat64Array = PackedFloat64Array()
var _v_vol: PackedFloat32Array = PackedFloat32Array()     # 보이스 기본 볼륨(합침 상승 전)
var _v_bump: PackedFloat32Array = PackedFloat32Array()    # 합침으로 올린 dB
var _v_pitch: PackedFloat32Array = PackedFloat32Array()   # 요청 피치(랜덤 전)
var _v_plain: PackedByteArray = PackedByteArray()         # 1 = 기본 테이크(집계 군집·이름 변주가 아님)
var _v_stream: Array[AudioStream] = []                    # 보이스가 울리는 스트림(합침 판정용)
var _last_slot: PackedInt32Array = PackedInt32Array()     # [def] 가장 최근 보이스
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# 집계
var _agg_n: PackedInt32Array = PackedInt32Array()
var _agg_t0: PackedFloat64Array = PackedFloat64Array()
var _agg_x: PackedFloat32Array = PackedFloat32Array()
var _agg_y: PackedFloat32Array = PackedFloat32Array()
var _agg_crit: PackedByteArray = PackedByteArray()
var _agg_vol: PackedFloat32Array = PackedFloat32Array()
var _agg_pending: PackedInt32Array = PackedInt32Array()
var _agg_pending_n: int = 0

# 이중 재생 방지: 같은 순간을 다른 모듈(play_sfx 직접 호출)과 SfxRouter(Events 구독)가 둘 다 울리려 할 때 먼저 온 쪽만.
var _ext_t: PackedFloat64Array = PackedFloat64Array()   # [def] 다른 모듈이 마지막으로 직접 재생한 시각
var _rt_t: PackedFloat64Array = PackedFloat64Array()    # [def] 라우터가 재생(예약)한 시각
var stat_dedup: int = 0

# 지연 재생 큐(플램·연출 스냅·폭포 아르페지오)
var _dq_t: PackedFloat64Array = PackedFloat64Array()
var _dq_def: PackedInt32Array = PackedInt32Array()
var _dq_vol: PackedFloat32Array = PackedFloat32Array()
var _dq_pitch: PackedFloat32Array = PackedFloat32Array()
var _dq_x: PackedFloat32Array = PackedFloat32Array()
var _dq_y: PackedFloat32Array = PackedFloat32Array()
var _dq_stream: Array[AudioStream] = []
var _dq_live: PackedByteArray = PackedByteArray()

# 통계(로그·검증)
var stat_plays: int = 0
var stat_steals: int = 0
var stat_drops: int = 0
var stat_cap_cuts: int = 0
var stat_agg_hits: int = 0
var stat_agg_plays: int = 0
var stat_peak_voices: int = 0
var stat_merges: int = 0
var stat_borrows: int = 0
var stat_recycles: int = 0    # 상한에서 끊은 것이 이미 꼬리(0.5s 넘게 울림)였던 경우 — 들리는 손실이 아니다
var _d_cut: PackedInt32Array = PackedInt32Array()     # [def] 진단: 상한 끊김
var _d_drop: PackedInt32Array = PackedInt32Array()    # [def] 진단: 버림
var _d_victim: PackedInt32Array = PackedInt32Array()  # [def] 진단: 빼앗김 당함
var _clock: float = 0.0
var _log_next: float = 0.0
var _shut: bool = false
var _last_now: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var uargs: PackedStringArray = OS.get_cmdline_user_args()
	live_test = uargs.has("--audio-live")
	log_enabled = live_test or uargs.has("--audio-log")
	silent = (DisplayServer.get_name() == "headless" or OS.has_feature("movie") or _is_movie()) and not live_test
	_rng.seed = 0x5EED_A0D1
	buses = AudioBusesScript.new()
	buses.setup()
	bank = SfxBankScript.new()
	bank.load_all()
	_alloc_pools()
	var n: int = bank.count
	_agg_n.resize(n); _agg_n.fill(0)
	_agg_t0.resize(n)
	_agg_x.resize(n)
	_agg_y.resize(n)
	_agg_crit.resize(n)
	_agg_vol.resize(n)
	_agg_pending.resize(n)
	_ext_t.resize(n); _ext_t.fill(-100.0)
	_rt_t.resize(n); _rt_t.fill(-100.0)
	_last_slot.resize(n); _last_slot.fill(-1)
	_d_cut.resize(n); _d_cut.fill(0)
	_d_drop.resize(n); _d_drop.fill(0)
	_d_victim.resize(n); _d_victim.fill(0)
	_dq_t.resize(DQ_CAP)
	_dq_def.resize(DQ_CAP)
	_dq_vol.resize(DQ_CAP)
	_dq_pitch.resize(DQ_CAP)
	_dq_x.resize(DQ_CAP)
	_dq_y.resize(DQ_CAP)
	_dq_stream.resize(DQ_CAP)
	_dq_live.resize(DQ_CAP)
	_dq_live.fill(0)
	music = MusicDirectorScript.new()
	music.name = "MusicDirector"
	add_child(music)
	ambience = AmbienceScript.new()
	ambience.name = "Ambience"
	add_child(ambience)
	router = SfxRouterScript.new()
	router.name = "SfxRouter"
	add_child(router)
	Events.music_cue.connect(play_music)
	print("[audio] ready silent=%s live=%s sfx_defs=%d files=%d fallback=%d missing=%d music_tiers=%d" % [
		silent, live_test, n, bank.file_count, bank.fallback_count, bank.missing_count, music.tier_count()])


func _is_movie() -> bool:
	for a: String in OS.get_cmdline_args():
		if a.begins_with("--write-movie"):
			return true
	return false


func _alloc_pools() -> void:
	for i in POOL_SIZE:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)
	for i in POOL_2D:
		var p2: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		p2.bus = &"SFX"
		p2.max_distance = Data.num("audio_mix", "spatial.godot.max_distance_px", 512.0)
		p2.attenuation = Data.num("audio_mix", "spatial.godot.attenuation", 1.0)
		p2.panning_strength = Data.num("audio_mix", "spatial.godot.panning_strength", 0.7)
		add_child(p2)
		_pool_2d.append(p2)
	_v_def.resize(NV); _v_def.fill(-1)
	_v_prio.resize(NV); _v_prio.fill(0)
	_v_start.resize(NV); _v_start.fill(0.0)
	_v_end.resize(NV); _v_end.fill(0.0)
	_v_vol.resize(NV); _v_vol.fill(0.0)
	_v_bump.resize(NV); _v_bump.fill(0.0)
	_v_pitch.resize(NV); _v_pitch.fill(1.0)
	_v_plain.resize(NV); _v_plain.fill(0)
	_v_stream.resize(NV)


func now() -> float:
	if silent:
		return _clock
	return Time.get_ticks_usec() / 1000000.0


func rng() -> RandomNumberGenerator:
	return _rng


func _process(delta: float) -> void:
	if _shut:
		return
	if silent:
		_clock += delta * float(maxi(1, Game.sim_speed))
	var t: float = now()
	_last_now = t
	buses.update(t, delta)
	router.flush(t)
	_flush_agg(t)
	_flush_queue(t)
	music.update(t, delta)
	ambience.update(t, delta)
	if log_enabled and t >= _log_next:
		_log_next = t + 30.0
		if Game.state == Game.State.RUN:
			print_stats("periodic")


# ─── 공개 API (ARCHITECTURE §2) ─────────────────────────────────────────

## id 재생(비위치). bus 를 &"SFX" 이외로 주면 그 버스로 강제. pitch_var = 비율 랜덤(±), 0 이면 정의의 반음 랜덤.
func play_sfx(id: StringName, bus: StringName = &"SFX", volume_db: float = 0.0, pitch_var: float = 0.0) -> void:
	if _shut:
		return
	var d: int = def_of(id)
	if d < 0:
		return
	var vs: AudioStream = _variant_stream(id, d)
	# 무구 발동·적중음은 combat 도 직접 부른다(weapon_base._fire_sfx / weapon_manager.note_hit). SfxRouter 가 같은 순간을
	# 신호(weapon_fired / enemy_hit)로도 받으므로 여기서 넘겨 한 번만 울리게 한다: 적중 = 무구 귀속 힌트(집계는 enemy_hit 가 센다),
	# 발동 = weapon_fired 가 따라오면 라우터 판(슬롯 플램·토리 피치)으로 대체, 안 따라오면(추가 휘두름) 그대로 재생.
	if vs == null and bus == &"SFX" and router != null:
		var kind: int = bank.wpn_kind[d]
		if kind == 2:
			router.note_hit_source(d)
			return
		if kind == 1:
			router.ext_fire(d, volume_db, pitch_var)
			return
	var t: float = now()
	if absf(t - _rt_t[d]) < 0.7:
		stat_dedup += 1
		return
	_ext_t[d] = t
	var pitch: float = 1.0 + (_rng.randf_range(-pitch_var, pitch_var) if pitch_var > 0.0 else 0.0)
	play_def(d, volume_db, pitch, NO_POS, vs, bus if bus != &"SFX" else &"", pitch_var <= 0.0)


func play_sfx_at(id: StringName, pos: Vector2, volume_db: float = 0.0) -> void:
	if _shut:
		return
	var d: int = def_of(id)
	if d < 0:
		return
	play_def(d, volume_db, 1.0, pos, _variant_stream(id, d))


func play_music(cue: StringName) -> void:
	if _shut:
		return
	current_cue = cue
	music.on_cue(cue)


## 런 중 stop_music = 보스 정적(waves _begin_silence 의 유일한 용도) → 정적 스팅어 + mus_boss_* 큐 대기.
func stop_music() -> void:
	current_cue = &""
	if music == null:
		return
	if Game.run_active:
		music.enter_silence()
	else:
		music.stop_all(0.5)


## 슬라이더 값(0..1). gain = v² (data/audio_mix.json slider_mapping).
func set_bus_volume_linear(bus: StringName, v: float) -> void:
	if buses != null:
		buses.set_user(bus, v)


# ─── 내부 API (audio/ 스크립트용) ──────────────────────────────────────

## 라우터가 신호로 d 를 울려도 되는가(다른 모듈이 방금 직접 울렸으면 false). true 면 예약 시각을 적어 둔다.
func router_claim(d: int, delay: float = 0.0) -> bool:
	var t: float = now()
	if t - _ext_t[d] < 1.2:
		stat_dedup += 1
		return false
	_rt_t[d] = t + delay
	return true


## 라우터 밖(음악 디렉터)에서 d 를 예약했다고 적어 둔다(라우터가 같은 순간 또 울리지 않게).
func note_ext(d: int, delay: float = 0.0) -> void:
	if d >= 0:
		_ext_t[d] = now() + delay


func def_of(id: StringName) -> int:
	return bank.resolve(id)


func _variant_stream(id: StringName, d: int) -> AudioStream:
	var s: String = String(id)
	var k: int = s.find("__")
	if k < 0:
		return null
	return bank.named_stream(d, s.substr(k))


## 정의 재생. pos = NO_POS 면 비위치 풀. stream = null 이면 반복 회피 테이크. bus_override 빈 값이면 정의 버스.
## rand = true 면 정의의 피치(반음)·볼륨 랜덤을 더한다. 반환: 보이스 번호(-1 = 버림).
func play_def(d: int, volume_db: float = 0.0, pitch: float = 1.0, pos: Vector2 = NO_POS, stream: AudioStream = null,
		bus_override: StringName = &"", rand: bool = true) -> int:
	if _shut or d < 0:
		return -1
	var s: AudioStream = stream if stream != null else bank.pick_take(d, _rng)
	if s == null:
		return -1
	var t: float = now()
	var plain: bool = stream == null or (bank.takes[d] as Array).has(stream)
	# 1) 최소 간격 안의 같은 음 → 직전 보이스에 합친다(새 보이스 없음)
	var ls: int = _last_slot[d]
	if ls >= 0 and _v_def[ls] == d and _v_end[ls] > t and t - _v_start[ls] < bank.min_gap[d] and _mergeable(ls, plain, s, pitch):
		_merge_into(ls, volume_db)
		return ls
	var positional: bool = pos.x != INF and Game.camera != null
	var p_prio: int = bank.prio[d]
	var lo: int = POOL_SIZE if positional else 0
	var hi: int = NV if positional else POOL_SIZE
	var same: int = 0
	var oldest_same: int = -1
	var oldest_same_t: float = INF
	var newest_same: int = -1
	var newest_same_t: float = -INF
	var free: int = -1
	var free_other: int = -1
	var victim: int = -1
	var victim_prio: int = 9999
	var victim_t: float = INF
	var active: int = 0
	for i in NV:
		var mine: bool = i >= lo and i < hi
		if _v_end[i] <= t:
			if mine:
				if free < 0:
					free = i
			elif free_other < 0:
				free_other = i
			continue
		active += 1
		if _v_def[i] == d:
			same += 1
			if _v_start[i] > newest_same_t:
				newest_same_t = _v_start[i]
				newest_same = i
			if _v_start[i] < oldest_same_t and mine:
				oldest_same_t = _v_start[i]
				oldest_same = i
		elif mine and (_v_prio[i] < p_prio or (_v_prio[i] == p_prio and t - _v_start[i] >= STEAL_SAME_AGE)):
			if _v_prio[i] < victim_prio or (_v_prio[i] == victim_prio and _v_start[i] < victim_t):
				victim_prio = _v_prio[i]
				victim_t = _v_start[i]
				victim = i
	var slot: int = -1
	if same >= bank.cap[d]:
		# 2) 상한: 방금 울린 같은 음이면 합치고, 아니면 가장 오래된 것을 끊어 새 어택을 낸다
		if newest_same >= 0 and t - newest_same_t < CAP_MERGE_WIN and _mergeable(newest_same, plain, s, pitch):
			_merge_into(newest_same, volume_db)
			return newest_same
		if oldest_same < 0:
			if newest_same >= 0:
				_merge_into(newest_same, volume_db)
				return newest_same
			stat_drops += 1
			_d_drop[d] += 1
			return -1
		slot = oldest_same
		if t - oldest_same_t >= 0.5:
			stat_recycles += 1
		else:
			stat_cap_cuts += 1
			_d_cut[d] += 1
	elif free >= 0:
		slot = free
	elif free_other >= 0 and (positional or Game.camera != null):
		# 3) 다른 풀 빌림: 2D 요청은 비위치로(팬만 잃는다), 비위치 요청은 카메라 중심 2D 로
		slot = free_other
		stat_borrows += 1
		if positional:
			positional = false
		else:
			positional = true
			pos = Game.camera.global_position
	elif victim >= 0:
		slot = victim
		stat_steals += 1
		_d_victim[_v_def[victim]] += 1
	else:
		stat_drops += 1
		_d_drop[d] += 1
		return -1
	var vol: float = volume_db
	var ps: float = pitch
	if rand:
		var st: float = bank.pitch_st[d]
		if st > 0.0:
			ps *= pow(2.0, _rng.randf_range(-st, st) / 12.0)
		var vr: float = bank.vol_rand[d]
		if vr > 0.0:
			vol += _rng.randf_range(-vr, vr) * 0.5
	ps = clampf(ps, 0.25, 4.0)
	var b: StringName = bus_override if bus_override != &"" else bank.bus[d]
	var len_s: float = s.get_length()
	if len_s <= 0.0:
		len_s = 1.0
	_v_def[slot] = d
	_v_prio[slot] = p_prio
	_v_start[slot] = t
	_v_end[slot] = t + len_s / ps + 0.02
	_v_vol[slot] = vol
	_v_bump[slot] = 0.0
	_v_pitch[slot] = pitch
	_v_plain[slot] = 1 if plain else 0
	_v_stream[slot] = s
	_last_slot[d] = slot
	stat_plays += 1
	if active + 1 > stat_peak_voices:
		stat_peak_voices = active + 1
	if positional:
		var p2: AudioStreamPlayer2D = _pool_2d[slot - POOL_SIZE]
		if p2.playing:
			p2.stop()
		p2.stream = s
		p2.bus = b
		p2.volume_db = vol
		p2.pitch_scale = ps
		p2.global_position = pos
		if not silent:
			p2.play()
	else:
		var p: AudioStreamPlayer = _pool[slot]
		if p.playing:
			p.stop()
		p.stream = s
		p.bus = b
		p.volume_db = vol
		p.pitch_scale = ps
		if not silent:
			p.play()
	return slot


## 합칠 수 있는가: 같은 음(피치 비 3% 안) + 둘 다 기본 테이크이거나 같은 스트림(집계 군집·큰 변주는 작은 것에 묻히지 않는다).
func _mergeable(slot: int, plain: bool, s: AudioStream, pitch: float) -> bool:
	if absf(pitch / _v_pitch[slot] - 1.0) >= PITCH_SAME:
		return false
	return (plain and _v_plain[slot] == 1) or _v_stream[slot] == s


## 합침: 요청을 새 보이스 대신 이미 울리는 보이스 s 에 얹는다(더 큰 쪽 볼륨 + 1건당 +1dB, 최대 +4dB).
func _merge_into(s: int, volume_db: float) -> void:
	stat_merges += 1
	if volume_db > _v_vol[s]:
		_v_vol[s] = volume_db
	_v_bump[s] = minf(_v_bump[s] + MERGE_STEP_DB, MERGE_MAX_DB)
	var v: float = _v_vol[s] + _v_bump[s]
	if s >= POOL_SIZE:
		_pool_2d[s - POOL_SIZE].volume_db = v
	else:
		_pool[s].volume_db = v


## delay 초 뒤 재생(실시간). 큐가 차면 즉시 재생. 같은 정의·같은 음이 최소 간격 안에 이미 예약돼 있으면 그 예약에 합친다.
func schedule(delay: float, d: int, volume_db: float = 0.0, pitch: float = 1.0, pos: Vector2 = NO_POS, stream: AudioStream = null) -> void:
	if d < 0 or _shut:
		return
	if delay <= 0.004:
		play_def(d, volume_db, pitch, pos, stream)
		return
	var at: float = now() + delay
	var g: float = bank.min_gap[d]
	for k in DQ_CAP:
		if _dq_live[k] == 1 and _dq_def[k] == d and absf(_dq_t[k] - at) < g and absf(pitch / _dq_pitch[k] - 1.0) < PITCH_SAME:
			stat_merges += 1
			_dq_vol[k] = minf(maxf(_dq_vol[k], volume_db) + MERGE_STEP_DB, maxf(_dq_vol[k], volume_db) + MERGE_MAX_DB)
			return
	for k in DQ_CAP:
		if _dq_live[k] == 0:
			_dq_live[k] = 1
			_dq_t[k] = at
			_dq_def[k] = d
			_dq_vol[k] = volume_db
			_dq_pitch[k] = pitch
			_dq_x[k] = pos.x
			_dq_y[k] = pos.y
			_dq_stream[k] = stream
			return
	play_def(d, volume_db, pitch, pos, stream)


func _flush_queue(t: float) -> void:
	for k in DQ_CAP:
		if _dq_live[k] == 1 and _dq_t[k] <= t:
			_dq_live[k] = 0
			play_def(_dq_def[k], _dq_vol[k], _dq_pitch[k], Vector2(_dq_x[k], _dq_y[k]), _dq_stream[k])
			_dq_stream[k] = null


## 히트 집계에 1건 추가. vol_db 는 창의 기본 게인(처음 건 기준).
func agg_add(d: int, pos: Vector2, crit: bool = false, vol_db: float = 0.0) -> void:
	if d < 0 or _shut:
		return
	stat_agg_hits += 1
	if _agg_n[d] == 0:
		_agg_t0[d] = now()
		_agg_x[d] = 0.0
		_agg_y[d] = 0.0
		_agg_crit[d] = 0
		_agg_vol[d] = vol_db
		_agg_pending[_agg_pending_n] = d
		_agg_pending_n += 1
	_agg_n[d] += 1
	_agg_x[d] += pos.x
	_agg_y[d] += pos.y
	if crit:
		_agg_crit[d] = 1


func _flush_agg(t: float) -> void:
	var k: int = 0
	while k < _agg_pending_n:
		var d: int = _agg_pending[k]
		if t - _agg_t0[d] < AGG_WINDOW:
			k += 1
			continue
		var n: int = _agg_n[d]
		var tier: int = 1 if n <= 1 else (2 if n <= 5 else (3 if n <= 20 else 4))
		var gain: float = _agg_vol[d] + float(tier - 1) * 2.0
		var pitch: float = 1.0
		if _agg_crit[d] == 1:
			gain += 2.0
			pitch = pow(2.0, 1.5 / 12.0)
		var pos: Vector2 = Vector2(_agg_x[d] / n, _agg_y[d] / n) if n > 0 else NO_POS
		var s: AudioStream = bank.agg_stream(d, tier, _rng)
		play_def(d, gain, pitch, pos, s)
		stat_agg_plays += 1
		_agg_n[d] = 0
		_agg_pending_n -= 1
		_agg_pending[k] = _agg_pending[_agg_pending_n]


func active_voices() -> int:
	var t: float = now()
	var n: int = 0
	for i in NV:
		if _v_end[i] > t:
			n += 1
	return n


func print_stats(tag: String) -> void:
	var ms: String = music.stats_line() if music != null else ""
	print("[audio] %s t=%.1f sfx plays=%d agg_hits=%d agg_plays=%d merges=%d borrows=%d tail_recycles=%d cap_cuts=%d steals=%d drops=%d dedup=%d peak_voices=%d | %s" % [
		tag, Game.time_sec(), stat_plays, stat_agg_hits, stat_agg_plays, stat_merges, stat_borrows, stat_recycles, stat_cap_cuts, stat_steals,
		stat_drops, stat_dedup, stat_peak_voices, ms])
	if tag == "shutdown":
		print("[audio] top cut=%s drop=%s stolen=%s" % [_top(_d_cut), _top(_d_drop), _top(_d_victim)])


## 진단(종료 시 1회): 카운트 상위 4개 정의 "id:n".
func _top(arr: PackedInt32Array) -> String:
	var out: PackedStringArray = PackedStringArray()
	var used: Dictionary = {}
	for r in 4:
		var best: int = -1
		for i in arr.size():
			if arr[i] > 0 and not used.has(i) and (best < 0 or arr[i] > arr[best]):
				best = i
		if best < 0:
			break
		used[best] = true
		out.append("%s:%d" % [String(bank.names[best]) if best < bank.names.size() else str(best), arr[best]])
	return ",".join(out)


## 종료 시 재생 중 스트림을 끊고 캐시를 비운다("resources still in use at exit" 방지 — 재생 중 Ogg playback 누수).
## Game.quit_game() 이 호출하고 몇 프레임 기다린 뒤 종료한다.
func shutdown() -> void:
	if _shut:
		return
	if log_enabled or Game.autotest:
		print_stats("shutdown")
	_shut = true
	_release()


func _exit_tree() -> void:
	_release()


func _release() -> void:
	for p in _pool:
		p.stop()
		p.stream = null
	for k in _v_stream.size():
		_v_stream[k] = null
	for p2 in _pool_2d:
		p2.stop()
		p2.stream = null
	for k in DQ_CAP:
		_dq_live[k] = 0
		if k < _dq_stream.size():
			_dq_stream[k] = null
	if music != null:
		music.release()
	if ambience != null:
		ambience.release()
	if bank != null:
		bank.clear()
