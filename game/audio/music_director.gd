extends Node
## MusicDirector — 장단 스템 레이어 + Beat 박 시계 추종 + 거리 크로스페이드 + 흥·신명·시련·보스·합일 큐. 소유: audio.
##
## 스템(assets/music/music_index.json, tools/audio/build_jangdan.py 산출): tier 마다 7스템
##   janggu(L00 장구 박, 상시) · buk(L02 대북=산신) · jing(L03 징=용왕) · kkwaenggwari(L04 꽹과리=칠성)
##   jegeum(L07 제금=제석·대감) · melody(L05 태평소 메김 + L06 피리 받음 = 장군·바리) · bed(L01 바닥)
##   같은 tier 의 스템은 길이·박 0 위치가 같다 → AudioStreamSynchronized 하나로 묶어 샘플 단위로 같이 돈다.
##   레이어 볼륨은 set_sync_stream_volume(매 믹스 블록에서 읽힘) — 재시작 없이 언제든 바꿔도 박이 어긋나지 않는다.
##
## 박 동기(design/12 §3.2, A1: 시뮬레이션 박 틱이 권위, 음악이 따라간다):
##   기대 위치 = fposmod((Beat.beat_pos + 틱 보간) × 60/스템BPM, 루프 샘플 길이/샘플레이트)
##   들리는 위치 = get_playback_position() + time_since_last_mix − output_latency
##   오차(EMA 0.3s)는 재생 속도 미세 조정(±0.8% ≈ ±14센트, 귀로 구분 안 됨)으로 끊김 없이 0 으로 끌어온다(PLL).
##   EMA > 35ms 가 남으면 다음 박 경계 직후에 seek(장구 타점 어택이 가림). 250ms 초과는 즉시.
##   시작·재개 직후 첫 측정에서 18ms 이상이면 한 번 즉시 seek(페이드인 중이라 안 들림). 프레임 멈춤(dt>45ms) 직후 0.25s 는 재지 않는다.
##   보스·결산 장단은 Beat BPM 과 달라도 '소박 격자 맞춤'으로 잠근다: 스템 소박(bpm×subbeats)×p = k×(Beat 그리드/분)
##   이 되는 재생 속도 p(0.84~1.12)를 골라, 무구 발사 그리드가 보스 장단의 소박 위에 정확히 떨어지게 한다.
##   배속(F1)·일시정지 중에는 재지 않는다. 점지·일시정지: 메인 음악 stop(재개는 박 위치에서 다시 play) + 베드 스템만 −12dB·LPF 800Hz 로 흐름.
##
## 빌드 = 악단(design/12 0.1-2, A4):
##   신령 빙의(trial_end winner / possession_changed / trial_resolved) → 그 신령 악기 스템 영구 0dB(미완 −3dB).
##   시련 중에는 후보 신령 악기가 게이지에 비례해 −18 → −6dB 로 '오디션'처럼 커진다(무엇을 모시는지 귀로 안다).
##   무구 획득(2번째부터)도 무구 계열 악기를 부분 음량(−10dB, 같은 계열 추가마다 +2dB, 상한 −4dB)으로 합류시킨다 —
##   빙의가 없더라도 런이 진행될수록 악단이 두꺼워지고, 빙의하면 그 악기가 앞으로 나선다.
## 신명 고조: 흥 단계(Beat.heung_mult 1.04/1.08 → _h1/_h2 스템, 박 위치 보존 120ms 크로스페이드) +
##   흥 표현 레이어(mode_muhan heung_expression: 꽹과리 몰이 흥1 −12dB / 흥2 −6dB / 신명 오름 0dB, 장구 +2dB).
## 강도 I(4.4): 10u 내 적 수·정기·정예·적 탄 → I0..I3(히스테리시스) → 베드 −6/−4dB, 합류 레이어 +0..3dB.

const INDEX_PATH: String = "res://assets/music/music_index.json"
const STEMS: PackedStringArray = ["janggu", "buk", "jing", "kkwaenggwari", "jegeum", "melody", "bed"]
const NS: int = 7
const S_JANGGU: int = 0
const S_BUK: int = 1
const S_JING: int = 2
const S_KKW: int = 3
const S_JEGEUM: int = 4
const S_MELODY: int = 5
const S_BED: int = 6
const Buses = preload("res://audio/audio_buses.gd")
const BAND: PackedInt32Array = [1, 2, 3, 4, 5]          # buk jing kkwaenggwari jegeum melody
const I_UP: PackedFloat32Array = [0.0, 0.30, 0.55, 0.80]
const I_DN: PackedFloat32Array = [0.0, 0.22, 0.45, 0.70]
const MUTE: float = -80.0
const FLOOR: float = -60.0
const RESYNC_MS: float = 35.0         # 오디오 드라이버 언더런 등으로 생긴 계단형 어긋남은 PLL(8ms/s)로 끌지 않고 다음 박에 맞춘다
const PLL_GAIN: float = 0.6           # 오차 1s 당 속도 보정(1/s)
const PLL_MAX: float = 0.008
const ERR_TAU: float = 0.3
const HARD_RESYNC_S: float = 0.25

enum Mode { NONE, TITLE, LOBBY, RUN, BOSS_SILENCE, BOSS, RESULT }

const DEITY_STEM: Dictionary = {
	&"deity_sansin": S_BUK, &"deity_yongwang": S_JING, &"deity_chilseong": S_KKW,
	&"deity_janggun": S_MELODY, &"deity_barigongju": S_MELODY, &"deity_jeseok_daegam": S_JEGEUM,
}
## 무구 → 합류 악기(부분 음량). 적 근접·중량 = 대북, 적 원거리·칼날 = 제금, 백 선율형 = 선율, 백 금속·빛 = 꽹과리, 장구·오방 = 징.
const WEAPON_STEM: Dictionary = {
	&"wpn_sinkal": S_BUK, &"wpn_woldo": S_BUK, &"wpn_jakdu": S_BUK, &"wpn_pyeongon": S_BUK, &"wpn_hojakdo": S_BUK,
	&"wpn_samjichang": S_JEGEUM, &"wpn_sainsageom": S_JEGEUM, &"wpn_gakgung": S_JEGEUM, &"wpn_jangchang": S_JEGEUM,
	&"wpn_cheoljillyeo": S_JEGEUM,
	&"wpn_bangul": S_MELODY, &"wpn_buchae": S_MELODY, &"wpn_neokjeon": S_MELODY, &"wpn_gilbe": S_MELODY,
	&"wpn_ssukmul": S_MELODY,
	&"wpn_jijeon": S_KKW, &"wpn_myeongdu": S_KKW, &"wpn_sogeum": S_KKW,
	&"wpn_janggu": S_JING, &"wpn_obanggi": S_JING,
}

var tiers: Dictionary = {}            # "jd_jungmori" / "jd_jungmori_h1" -> Dictionary
var trims: PackedFloat32Array = PackedFloat32Array()
var mode: Mode = Mode.NONE

var _geori_tier: Dictionary = {}      # geori_id -> tier id
var _geori_start: PackedFloat32Array = PackedFloat32Array()   # waves_stage1 geori 경계(게임 초)
var _fx_div: Dictionary = {}          # tier id -> fx_snap_div
var _ogg: Dictionary = {}             # res path -> AudioStreamOggVorbis
var _requested: Dictionary = {}

# 슬롯 2개(크로스페이드)
var _pl: Array[AudioStreamPlayer] = []
var _stream: Array[AudioStreamSynchronized] = [null, null]
var _key: PackedStringArray = PackedStringArray(["", ""])
var _sync: PackedByteArray = PackedByteArray([0, 0])
var _bpm: PackedFloat32Array = PackedFloat32Array([120.0, 120.0])
var _loop_len: PackedFloat64Array = PackedFloat64Array([32.0, 32.0])
var _gak: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
var _spb: PackedFloat64Array = PackedFloat64Array([0.5, 0.5])    # Beat 1박 당 스트림 초
var _pbase: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])  # 기본 재생 속도(소박 격자 맞춤이면 ≠1)
var _hfollow: PackedByteArray = PackedByteArray([0, 0])          # 1 = 흥 배속을 재생 속도로 따라간다(_h 스템 없음)
var _gain: PackedFloat32Array = PackedFloat32Array([MUTE, MUTE])
var _gain_tgt: PackedFloat32Array = PackedFloat32Array([MUTE, MUTE])
var _gain_rate: PackedFloat32Array = PackedFloat32Array([60.0, 60.0])
var _cur: int = -1
var _tier_id: String = ""
var _heung: int = 0

var _lvl: PackedFloat32Array = PackedFloat32Array()
var _tgt: PackedFloat32Array = PackedFloat32Array()
var _applied: PackedFloat32Array = PackedFloat32Array()

# 게임 상태 입력
var deity_db: PackedFloat32Array = PackedFloat32Array()
var build_db: PackedFloat32Array = PackedFloat32Array()
var _build_n: PackedInt32Array = PackedInt32Array()
var _weapons_seen: Dictionary = {}
var trial_active: bool = false
var _preview_stem: int = -1
var _preview_db: float = MUTE
var intensity: int = 0
var _i_val: float = 0.0
var _i_next: float = 0.0
var _qbuf: PackedInt32Array = PackedInt32Array()
var dead: bool = false
var boss_form: StringName = &""
var mboss: bool = false               # 중간보스 긴장(mus_mboss_* 큐 ~ 거리 큐 복귀): 대북·징 합류, 강도 ≥ I2
var hapil: bool = false               # 합일(18:00 작두거리): 악단 전원 합류

# 동기 상태
var _beat_off: float = 0.0
var _last_bp: float = 0.0
var _last_geori: StringName = &""
var _err_ema: float = 0.0
var _resync_pending: bool = false
var _lead_adj: float = 0.0
var _calib: bool = false
var _snap_left: int = 0               # 시작·재개 직후 즉시 보정 seek 남은 횟수
var _last_gak_i: int = -1
var _settle_until: float = 0.0
var _paused: bool = false
var _pause_pl: AudioStreamPlayer
var _was_speed1: bool = true
var _bridge_for: int = -1
var _boss_t: float = -1.0
var _result_t: float = -1.0
var _state_seen: int = -1

# 통계
var st_err_sum: float = 0.0
var st_err_n: int = 0
var st_err_max: float = 0.0
var st_err_signed: float = 0.0
var w_sum: float = 0.0                # 마지막 stats_line 이후 창(점프·착지 직후 제외한 정상 상태 확인용)
var w_n: int = 0
var w_max: float = 0.0
var st_resyncs: int = 0
var st_hard: int = 0
var st_xfades: int = 0
var st_heung_sw: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_lvl.resize(NS); _lvl.fill(MUTE)
	_tgt.resize(NS); _tgt.fill(MUTE)
	_applied.resize(NS); _applied.fill(999.0)
	deity_db.resize(NS); deity_db.fill(MUTE)
	build_db.resize(NS); build_db.fill(MUTE)
	_build_n.resize(NS); _build_n.fill(0)
	_qbuf.resize(160)
	for i in 2:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_db = MUTE
		add_child(p)
		_pl.append(p)
	_pause_pl = AudioStreamPlayer.new()
	_pause_pl.bus = &"Music"
	add_child(_pause_pl)
	_load_index()
	Events.geori_changed.connect(_on_geori_changed)
	Events.run_started.connect(_on_run_started)
	Events.run_ended.connect(_on_run_ended)
	Events.player_died.connect(func() -> void: dead = true)
	Events.trial_start.connect(_on_trial_start)
	Events.trial_gauge_changed.connect(_on_trial_gauge)
	Events.trial_end.connect(_on_trial_end)
	Events.trial_resolved.connect(_on_trial_resolved)
	Events.possession_changed.connect(_on_possession)
	Events.hapil_start.connect(_on_hapil)
	Events.weapon_added.connect(_on_weapon_added)
	Events.boss_incoming.connect(func(_s: StringName) -> void: _preload_boss())
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.settlement_started.connect(_on_settlement)


func _load_index() -> void:
	if FileAccess.file_exists(INDEX_PATH):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
		if j is Dictionary:
			var t: Variant = j.get("tiers", {})
			if t is Dictionary:
				tiers = t
			var mix: Variant = j.get("layer_mix_db", {})
			trims.resize(NS)
			for i in NS:
				trims[i] = float(mix.get(STEMS[i], 0.0)) if mix is Dictionary else 0.0
	if trims.size() != NS:
		trims.resize(NS)
		trims.fill(0.0)
	var jt: Variant = Data.get_value("audio_jangdan", "tiers", [])
	if jt is Array:
		for e: Variant in jt:
			if e is Dictionary:
				var gid: String = String(e.get("geori", ""))
				if gid != "":
					_geori_tier[gid] = String(e.get("id", ""))
				_fx_div[String(e.get("id", ""))] = int(e.get("fx_snap_div", 4))
	var gl: Variant = Data.get_value("waves_stage1", "geori", [])
	if gl is Array:
		for g: Variant in gl:
			if g is Dictionary and g.get("start_sec", null) != null:
				_geori_start.append(float(g.get("start_sec", 0)))


func tier_count() -> int:
	return tiers.size()


# ─── 스트림 구성 ─────────────────────────────────────────────────────────

func _tier_for_geori(geori_id: StringName, jangdan: StringName) -> String:
	var t: String = String(_geori_tier.get(String(geori_id), ""))
	if t != "" and tiers.has(t):
		return t
	var map: Dictionary = {"jinyangjo": "jd_jinyang", "jinyang": "jd_jinyang"}
	var j: String = String(map.get(String(jangdan), "jd_" + String(jangdan)))
	return j if tiers.has(j) else ""


func _heung_key(tier_id: String, h: int) -> String:
	if h > 0:
		var k: String = tier_id + "_h" + str(h)
		if tiers.has(k):
			return k
	return tier_id


func _stem_path(key: String, i: int) -> String:
	var t: Dictionary = tiers.get(key, {})
	var files: Variant = t.get("files", {})
	if files is Dictionary and files.has(STEMS[i]):
		return "res://" + String(files[STEMS[i]])
	return ""


## 다음에 쓸 tier 스템을 백그라운드로 읽기 시작(전환 프레임 히치 방지).
func preload_tier(key: String) -> void:
	if not tiers.has(key):
		return
	for i in NS:
		var p: String = _stem_path(key, i)
		if p == "" or _ogg.has(p) or _requested.has(p):
			continue
		if ResourceLoader.exists(p):
			if ResourceLoader.load_threaded_request(p, "AudioStreamOggVorbis") == OK:
				_requested[p] = true


func _get_ogg(p: String) -> AudioStreamOggVorbis:
	if _ogg.has(p):
		return _ogg[p]
	var s: AudioStreamOggVorbis = null
	if _requested.has(p):
		var st: int = ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			s = ResourceLoader.load_threaded_get(p) as AudioStreamOggVorbis
		_requested.erase(p)
	if s == null and ResourceLoader.exists(p):
		s = load(p) as AudioStreamOggVorbis
	if s != null:
		s.loop = true
		s.loop_offset = 0.0
		_ogg[p] = s
	return s


func _build(key: String) -> AudioStreamSynchronized:
	var s: AudioStreamSynchronized = AudioStreamSynchronized.new()
	s.stream_count = NS
	for i in NS:
		var p: String = _stem_path(key, i)
		var o: AudioStreamOggVorbis = _get_ogg(p) if p != "" else null
		s.set_sync_stream(i, o)
		s.set_sync_stream_volume(i, _stem_db(i))
	return s


func _stem_db(i: int) -> float:
	return MUTE if _lvl[i] <= FLOOR + 0.5 else _lvl[i]


# ─── 재생 제어 ───────────────────────────────────────────────────────────

## tier 시작. synced = Beat 박 위치에 맞춰 시작·추종. fade_in 0 = 즉시 0dB, xfade = 이전 슬롯 페이드아웃 초.
func _start(tier_id: String, synced: bool, fade_in: float, xfade: float) -> void:
	var key: String = _heung_key(tier_id, _heung if synced else 0)
	if not tiers.has(key):
		return
	var t: Dictionary = tiers[key]
	var n: int = 0 if _cur != 0 else 1
	if _cur >= 0:
		_gain_tgt[_cur] = MUTE
		_gain_rate[_cur] = 70.0 / maxf(xfade, 0.05)
	var s: AudioStreamSynchronized = _build(key)
	_stream[n] = s
	_key[n] = key
	_sync[n] = 1 if synced else 0
	_bpm[n] = float(t.get("bpm", 120.0))
	var sr: float = float(t.get("sample_rate", 44100))
	_loop_len[n] = float(t.get("loop_samples", 0)) / sr if int(t.get("loop_samples", 0)) > 0 else float(t.get("loop_s", 32.0))
	var bpc: int = int(t.get("beats_per_cycle", 4))
	var gak: float = maxf(1.0, float(bpc) / 4.0)
	if gak >= 6.0:
		gak *= 0.5   # 진양조: 반각(3박)을 마디로 본다(audio_jangdan heung.switch_on)
	_gak[n] = gak
	_spb[n] = 60.0 / _bpm[n]
	_pbase[n] = 1.0
	_hfollow[n] = 0
	if synced and absf(float(tiers[tier_id].get("bpm", 0.0)) - Beat.bpm) >= 0.5:
		var rp: float = _ratio_pitch(tier_id)
		_pbase[n] = rp
		_hfollow[n] = 1
		_spb[n] = rp * 60.0 / Beat.bpm
	_gain[n] = MUTE if fade_in > 0.0 else 0.0
	_gain_tgt[n] = 0.0
	_gain_rate[n] = 70.0 / maxf(fade_in, 0.05)
	_tier_id = tier_id
	var p: AudioStreamPlayer = _pl[n]
	p.stream = s
	p.stream_paused = false
	p.volume_db = _gain[n]
	_applied.fill(999.0)
	var from: float = 0.0
	if synced:
		from = fposmod(_expected_beats() * _spb[n], _loop_len[n]) + _lead() * _pbase[n]
	p.pitch_scale = _pbase[n] * (Beat.heung_mult if _hfollow[n] == 1 else 1.0)
	if not Audio.silent:
		p.play(from)
	_cur = n
	_err_ema = 0.0
	_resync_pending = false
	_calib = true
	_snap_left = 1
	_settle_until = Audio.now() + 0.35
	st_xfades += 1
	if Audio.log_enabled:
		print("[audio] music start %s synced=%s from=%.3fs loop=%.6fs gak=%.1f beats bpm=%.2f pitch=%.4f (beat bpm=%.2f x%.2f)" % [
			key, synced, from, _loop_len[n], gak, _bpm[n], _pbase[n], Beat.bpm, Beat.heung_mult])


## 시작·seek 때 미리 당겨 둘 시간: 출력 지연 + 믹스 블록 대기. _lead_adj 는 시작 직후 실측 오차로 스스로 보정된다.
func _lead() -> float:
	return AudioServer.get_output_latency() + 0.004 + _lead_adj


func stop_all(fade: float) -> void:
	for i in 2:
		_gain_tgt[i] = MUTE
		_gain_rate[i] = 70.0 / maxf(fade, 0.05)
	_cur = -1
	_tier_id = ""


func on_cue(cue: StringName) -> void:
	# 런 안의 거리 전환 자체는 geori_changed 가 박 위치 맞춰 처리한다. 여기서는 waves 큐의 '의미'만 받는다:
	#   stg_*            스팅어 원샷(다음 박)            mus_mboss_*   중간보스 긴장 레이어 on
	#   mus_guksadang_*  거리 음악 복귀(중간보스 off)     mus_boss_*    보스 장단 시작(형태 = 접미 han/sal)
	var c: String = String(cue)
	if c.begins_with("stg_"):
		var d: int = Audio.def_of(cue)
		if d >= 0:
			var delay: float = Audio.router.snap_delay(true) if Audio.router != null else 0.0
			Audio.schedule(delay, d)
			Audio.note_ext(d, delay)
		return
	if c == "mus_title":
		_enter_mode(Mode.TITLE)
	elif c.begins_with("mus_hub") or (c.begins_with("jd_gutgeori") and not Game.run_active):
		_enter_mode(Mode.LOBBY)
	elif c == "mus_results":
		_enter_mode(Mode.RESULT)
	elif not Game.run_active:
		return
	elif c.begins_with("mus_mboss"):
		mboss = true
	elif c.begins_with("mus_guksadang"):
		mboss = false
	elif c.begins_with("mus_boss"):
		if c.ends_with("_han"):
			boss_form = &"han"
		elif c.ends_with("_sal"):
			boss_form = &"sal"
		if mode != Mode.BOSS:
			_start_boss()


func _enter_mode(m: Mode) -> void:
	if m == mode:
		return
	mode = m
	match m:
		Mode.TITLE:
			_start("jd_jinyang", false, 2.5, 1.5)
		Mode.LOBBY:
			_start("jd_gutgeori", false, 2.0, 1.2)
		Mode.RESULT:
			stop_all(2.0)
			_result_t = Audio.now() + 2.2


func _expected_beats() -> float:
	var b: float = Beat.beat_pos + _beat_off
	if Game.run_active and not Game.is_sim_paused() and Game.sim_speed == 1:
		b += Engine.get_physics_interpolation_fraction() * Beat.bpm * Beat.heung_mult / 3600.0
	return b


# ─── 이벤트 ─────────────────────────────────────────────────────────────

func _on_run_started(_c: StringName) -> void:
	mode = Mode.RUN
	dead = false
	boss_form = &""
	mboss = false
	hapil = false
	trial_active = false
	_preview_stem = -1
	_boss_t = -1.0
	_bridge_for = -1
	_beat_off = 0.0
	_last_bp = 0.0
	_heung = 0
	deity_db.fill(MUTE)
	build_db.fill(MUTE)
	_build_n.fill(0)
	_weapons_seen.clear()
	_i_val = 0.0
	intensity = 0
	st_err_sum = 0.0; st_err_n = 0; st_err_max = 0.0; st_err_signed = 0.0; st_resyncs = 0; st_hard = 0
	_last_geori = Beat.geori_id
	var t: String = _tier_for_geori(Beat.geori_id, Beat.jangdan)
	if t != "":
		_start(t, _can_sync(t), 0.0, 0.6)
	_preload_next()


func _on_geori_changed(geori_id: StringName, bpm: float, jangdan: StringName) -> void:
	if not Game.run_active:
		return
	_beat_off = 0.0
	_last_bp = 0.0
	_last_geori = geori_id
	if String(geori_id) == "geori_myeongbu" or String(jangdan) == "boss":
		_boss_silence()
		return
	var t: String = _tier_for_geori(geori_id, jangdan)
	if t == "" or (t == _tier_id and _cur >= 0):
		return
	_start(t, _can_sync(t), 0.0, 0.45)
	Audio.play_sfx(&"stg_geori_land")
	if Audio.log_enabled:
		print("[audio] geori %s -> %s (beat bpm %.1f)" % [geori_id, t, bpm])
	_preload_next()


func _can_sync(tier_id: String) -> bool:
	var t: Dictionary = tiers.get(tier_id, {})
	return absf(float(t.get("bpm", 0.0)) - Beat.bpm) < 0.5 or _ratio_pitch(tier_id) > 0.0


## 소박 격자 맞춤 재생 속도(0 = 불가). 스템 소박/분 × p = k × Beat 그리드/분 (k = 1..4), p 는 1 에 가장 가까운 것.
func _ratio_pitch(tier_id: String) -> float:
	var t: Dictionary = tiers.get(tier_id, {})
	var sub: float = float(t.get("bpm", 0.0)) * float(t.get("subbeats_per_beat", 1))
	var grid: float = Beat.bpm / maxf(Beat.grid_frac, 0.05)
	if sub <= 0.0 or grid <= 0.0:
		return 0.0
	var best: float = 0.0
	for k in range(1, 5):
		var p: float = float(k) * grid / sub
		if p >= 0.84 and p <= 1.12 and (best == 0.0 or absf(p - 1.0) < absf(best - 1.0)):
			best = p
	return best


func _preload_next() -> void:
	var tnow: float = Game.time_sec()
	for st: float in _geori_start:
		if st > tnow + 0.5:
			var k: int = _geori_index_at(st)
			if k >= 0:
				var g: Dictionary = Beat.geori_list[k]
				var tid: String = _tier_for_geori(StringName(String(g.get("id", ""))), StringName(String(g.get("jangdan", ""))))
				if tid != "":
					preload_tier(tid)
			return


func _geori_index_at(t: float) -> int:
	var idx: int = -1
	for i in Beat.geori_list.size():
		var st: Variant = Beat.geori_list[i].get("start_sec", null)
		if st != null and t >= float(st):
			idx = i
	return idx


func _on_run_ended(_r: Dictionary) -> void:
	_enter_mode(Mode.RESULT)


func _on_trial_start(_slot: int, deity_id: StringName) -> void:
	trial_active = true
	_preview_stem = int(DEITY_STEM.get(deity_id, -1))
	_preview_db = -18.0


func _on_trial_gauge(_slot: int, wieom: float, gaho: float) -> void:
	_preview_db = -18.0 + 12.0 * clampf(maxf(wieom, gaho), 0.0, 1.0)


func _on_trial_end(_slot: int, deity_id: StringName, winner: StringName) -> void:
	trial_active = false
	_preview_stem = -1
	_possess(deity_id, 0.0 if winner != &"none" else -3.0)


func _on_trial_resolved(_slot: int, deity_id: StringName, _face: StringName, complete: bool) -> void:
	_possess(deity_id, 0.0 if complete else -3.0)


func _on_possession(deity_id: StringName, active: bool) -> void:
	if active:
		_possess(deity_id, 0.0)
	else:
		var s: int = int(DEITY_STEM.get(deity_id, -1))
		if s >= 0:
			deity_db[s] = MUTE


func _possess(deity_id: StringName, db: float) -> void:
	var s: int = int(DEITY_STEM.get(deity_id, -1))
	if s >= 0:
		deity_db[s] = maxf(deity_db[s], db)


func _on_hapil(_ids: Array) -> void:
	hapil = true
	for i in NS:
		if deity_db[i] > MUTE:
			deity_db[i] = 0.0   # 합일: 미완 빙의 −3dB 를 풀고 완성


func _on_weapon_added(weapon_id: StringName, _slot: int) -> void:
	if _weapons_seen.has(weapon_id):
		return
	_weapons_seen[weapon_id] = true
	if _weapons_seen.size() <= 1:
		return   # 시작 무구는 장구·베드만의 '아직 아무것도 없음'(진양조 편곡 지시 4.3)을 지킨다
	var s: int = int(WEAPON_STEM.get(weapon_id, -1))
	if s < 0:
		return
	_build_n[s] += 1
	build_db[s] = minf(-10.0 + 2.0 * float(_build_n[s] - 1), -4.0)


func _on_boss_spawned(_h: int, _sp: StringName, form: StringName) -> void:
	if form != &"":
		boss_form = form


## 보스 예고(19:57): 두 형태 장단을 미리 읽어 둔다(보스 등장 프레임 히치 방지).
func _preload_boss() -> void:
	preload_tier("jd_salpuri")
	preload_tier("jd_eotmori")


## 20:00 보스 정적(waves stop_music / 명부 거리 진입) → mus_boss_<form> 큐(20:02)에 형태별 보스 장단.
## 큐가 오지 않으면(구버전 waves·테스트) 3.5s 뒤 스스로 시작.
func enter_silence() -> void:
	if mode == Mode.BOSS_SILENCE or mode == Mode.BOSS or not Game.run_active:
		return
	mode = Mode.BOSS_SILENCE
	stop_all(0.4)
	Audio.buses.duck(Buses.Duck.BOSS_SILENCE)
	Audio.play_sfx(&"stg_boss_silence")
	_boss_t = Audio.now() + 3.5


func _boss_silence() -> void:
	enter_silence()


func _start_boss() -> void:
	mode = Mode.BOSS
	_boss_t = -1.0
	mboss = false
	Audio.buses.cancel(Buses.Duck.BOSS_SILENCE)
	var form: String = String(boss_form)
	var han: bool
	if form != "":
		han = form.contains("han")
	else:
		var tot: int = Game.kills_toechi + Game.kills_haewon
		han = tot == 0 or float(Game.kills_haewon) / float(tot) >= 0.5
	var t: String = "jd_salpuri" if han else "jd_eotmori"
	_start(t, _can_sync(t), 0.6, 0.3)
	Audio.play_sfx(&"stg_geori_land")


func _on_settlement(route: StringName, _p: Dictionary) -> void:
	if route == &"sal_geodum":
		_start("jd_hwimori", _can_sync("jd_hwimori"), 0.5, 0.5)
	elif route == &"saja_bow":
		_start("jd_gutgeori", false, 2.5, 2.0)


# ─── 매 프레임 ───────────────────────────────────────────────────────────

func update(now: float, dt: float) -> void:
	_poll_state()
	if _result_t > 0.0 and now >= _result_t:
		_result_t = -1.0
		_start("jd_gutgeori", false, 3.0, 0.5)
	if _boss_t > 0.0 and now >= _boss_t:
		_boss_t = -1.0
		_start_boss()
	if Game.run_active and (mode == Mode.RUN or mode == Mode.BOSS):
		_track_segments()
		_pause_logic()
		_heung_logic()
		_bridge_logic()
		if now >= _i_next:
			_i_next = now + 0.25
			_intensity_step(0.25)
	_compute_targets()
	_smooth_levels(dt)
	_apply_levels()
	_fade_slots(dt)
	if _cur >= 0 and _sync[_cur] == 1 and Game.run_active:
		_sync_check(now, dt)


func _poll_state() -> void:
	var s: int = int(Game.state)
	if s == _state_seen:
		return
	_state_seen = s
	match Game.state:
		Game.State.TITLE:
			_enter_mode(Mode.TITLE)
		Game.State.LOBBY:
			_enter_mode(Mode.LOBBY)
		Game.State.RESULT:
			_enter_mode(Mode.RESULT)


## Beat 구간이 같은 거리 안에서 다시 시작되면(흥 전환을 구간으로 구현한 경우) 박 위치를 이어 붙인다.
func _track_segments() -> void:
	var bp: float = Beat.beat_pos
	if Beat.geori_id == _last_geori and bp + 0.25 < _last_bp:
		_beat_off += _last_bp - bp
	_last_bp = bp


func _pause_logic() -> void:
	var paused: bool = Game.is_sim_paused()
	if paused == _paused or _cur < 0:
		return
	_paused = paused
	var p: AudioStreamPlayer = _pl[_cur]
	if paused:
		# 멈춤은 stop, 재개는 Beat 박 위치에서 다시 play(짧은 페이드인) — stream_paused 는 동기화 스트림 위치가 어긋나 재개 때 seek 가 튄다
		var at: float = p.get_playback_position()
		p.stop()
		Audio.buses.set_music_lpf(true)
		Audio.buses.set_snapshot(&"Ambience", -10.0)
		var bed: AudioStreamOggVorbis = _ogg.get(_stem_path(_key[_cur], S_BED), null)
		if bed != null and not Audio.silent:
			_pause_pl.stream = bed
			_pause_pl.volume_db = -12.0
			_pause_pl.play(fposmod(at, maxf(bed.get_length(), 1.0)))
	else:
		_pause_pl.stop()
		_pause_pl.stream = null
		Audio.buses.set_music_lpf(dead)
		Audio.buses.set_snapshot(&"Ambience", 0.0)
		_gain[_cur] = -12.0
		_gain_rate[_cur] = 60.0   # 200ms 페이드인
		p.volume_db = -12.0
		var base: float = _pbase[_cur] * (Beat.heung_mult if _hfollow[_cur] == 1 else 1.0)
		var from: float = p.get_playback_position()
		if _sync[_cur] == 1:
			from = fposmod(_expected_beats() * _spb[_cur] + _lead() * base, _loop_len[_cur])
		p.pitch_scale = base
		if not Audio.silent and p.stream != null:
			p.play(from)
		_err_ema = 0.0
		_calib = true
		_snap_left = 1
		_settle_until = Audio.now() + 0.3


func _heung_logic() -> void:
	if _cur < 0 or _sync[_cur] == 0:
		return
	var m: float = Beat.heung_mult
	var h: int = 0 if m < 1.02 else (1 if m < 1.06 else 2)
	if h == _heung:
		return
	_heung = h
	var key: String = _heung_key(_tier_id, h)
	if key == _key[_cur]:
		return
	st_heung_sw += 1
	_start(_tier_id, true, 0.12, 0.12)   # 박 위치 보존 + 120ms 크로스페이드(audio_jangdan heung.transition)


## 거리 경계 T−3s: 굴림 브리지(장구 굴림+라이저, 끝이 T 정각) + 장구 외 레이어 서서히 −9dB.
func _bridge_logic() -> void:
	if mode != Mode.RUN or Game.sim_speed != 1 or Game.is_sim_paused():
		return
	var t: float = Game.time_sec()
	for k in _geori_start.size():
		var st: float = _geori_start[k]
		if st <= t:
			continue
		var rem: float = st - t
		if rem <= 3.0 and _bridge_for != k and rem > 0.6:
			_bridge_for = k
			var d: int = Audio.def_of(&"stg_bridge_gullim")
			if d >= 0:
				var s: AudioStream = Audio.bank.pick_take(d, Audio.rng())
				var len_s: float = s.get_length() if s != null else 3.0
				Audio.schedule(maxf(0.0, rem - len_s), d, 0.0, 1.0, Audio.NO_POS, s)
			Audio.buses.duck(Buses.Duck.BRIDGE, maxf(0.0, rem - 2.6))
			var gk: int = _geori_index_at(st)
			if gk >= 0:
				var g: Dictionary = Beat.geori_list[gk]
				preload_tier(_tier_for_geori(StringName(String(g.get("id", ""))), StringName(String(g.get("jangdan", "")))))
		return


func _intensity_step(dt: float) -> void:
	var d: float = 0.0
	var e: float = 0.0
	var em: Node = Game.enemies
	if em != null and Game.player != null:
		var ppos: Vector2 = Game.player.global_position
		var n: int = int(em.call(&"query_circle", ppos, 10.0 * K.UNIT_PX, _qbuf, _qbuf.size()))
		d = clampf(float(n) / 120.0, 0.0, 1.0)
		var fl: PackedInt32Array = em.get(&"flags")
		var elite_bit: int = int(em.get(&"F_ELITE_PLUS")) if em.get(&"F_ELITE_PLUS") != null else 4
		for k in n:
			if (fl[_qbuf[k]] & elite_bit) != 0:
				e = 1.0
				break
	var h: float = clampf((0.6 - Game.hp / maxf(Game.hp_max, 1.0)) / 0.5, 0.0, 1.0)
	var p: float = 0.0
	var pp: Node = Game.projectiles
	if pp != null:
		var a: Variant = pp.get(&"alive_count")
		var pa: Variant = pp.get(&"player_alive")
		var ea: int = int(a) - (int(pa) if pa != null else 0)
		p = clampf(float(ea) / 40.0, 0.0, 1.0)
	var raw: float = clampf(0.40 * d + 0.25 * h + 0.20 * e + 0.15 * p, 0.0, 1.0)
	var tau: float = 1.5 if raw > _i_val else 4.0
	_i_val += (raw - _i_val) * (1.0 - exp(-dt / tau))
	if intensity < 3 and _i_val >= I_UP[intensity + 1]:
		intensity += 1
	elif intensity > 0 and _i_val < I_DN[intensity]:
		intensity -= 1


func _compute_targets() -> void:
	for i in NS:
		_tgt[i] = MUTE
	match mode:
		Mode.TITLE:
			_tgt[S_BED] = -1.0
			_tgt[S_MELODY] = -3.0
			_tgt[S_JING] = -14.0
		Mode.LOBBY:
			_tgt[S_JANGGU] = -7.0
			_tgt[S_BED] = -2.0
			_tgt[S_MELODY] = -2.0
		Mode.RESULT:
			_tgt[S_JANGGU] = -10.0
			_tgt[S_BED] = -2.0
			_tgt[S_MELODY] = -4.0
		Mode.RUN, Mode.BOSS, Mode.BOSS_SILENCE:
			_run_targets()
		_:
			pass
	for i in NS:
		if _tgt[i] > MUTE:
			_tgt[i] += trims[i]


func _run_targets() -> void:
	var ch: PackedFloat32Array = Audio.buses.ch_db
	var duck_m: float = ch[Buses.CH_MUSIC_DUCK]
	var duck_d: float = ch[Buses.CH_DEITY]
	var oreum: bool = Game.sinmyeong_oreum
	_tgt[S_JANGGU] = (2.0 if oreum else 0.0) + float(intensity) * 0.5
	var melody_owned: bool = deity_db[S_MELODY] > MUTE or build_db[S_MELODY] > MUTE
	_tgt[S_BED] = (-6.0 if intensity == 0 else -4.0) + (0.0 if melody_owned else 2.0) + duck_m
	var boost: float = float(maxi(intensity, 2 if mboss else 0))
	for s: int in BAND:
		var v: float = maxf(deity_db[s], build_db[s])
		if v > MUTE:
			v += boost
			if trial_active and deity_db[s] > MUTE:
				v -= 3.0   # mix_trial: 기존 신령 레이어 −3dB
		if trial_active and s == _preview_stem:
			v = maxf(v, _preview_db)
		if s == S_KKW:
			var sm: float = Game.sinmyeong
			var hx: float = 0.0 if oreum else (-6.0 if sm >= 0.70 else (-12.0 if sm >= 0.35 else MUTE))
			v = maxf(v, hx)
		if mode == Mode.BOSS and s == S_MELODY:
			v = maxf(v, -2.0)   # 보스 장단 선율 = 아쟁(적 팔레트)
		if mboss and (s == S_BUK or s == S_JING):
			v = maxf(v, -5.0)   # 중간보스: 대북·징이 밀고 들어와 긴장을 올린다
		if hapil and mode == Mode.RUN:
			v = maxf(v, -6.0)   # 합일: 모든 신령 악기가 함께 탄다(작두거리)
		if v > MUTE:
			v += duck_m + duck_d
		_tgt[s] = v


func _smooth_levels(dt: float) -> void:
	for i in NS:
		var cur: float = _lvl[i]
		var tgt: float = maxf(_tgt[i], MUTE)
		if absf(cur - tgt) < 0.01:
			_lvl[i] = tgt
			continue
		if tgt > cur:
			if cur <= FLOOR:
				cur = maxf(FLOOR, tgt - 30.0)   # 무음에서 들어올 때는 −30dB 지점부터 올린다(2각 ≈ 2~4s)
			_lvl[i] = minf(tgt, cur + 15.0 * dt)
		else:
			_lvl[i] = maxf(tgt, cur - 30.0 * dt)


func _apply_levels() -> void:
	if _cur < 0 or _stream[_cur] == null:
		return
	var s: AudioStreamSynchronized = _stream[_cur]
	for i in NS:
		var v: float = _stem_db(i)
		if absf(v - _applied[i]) > 0.05:
			_applied[i] = v
			s.set_sync_stream_volume(i, v)


func _fade_slots(dt: float) -> void:
	var all_db: float = Audio.buses.ch_db[Buses.CH_MUSIC_ALL] + (-8.0 if dead else 0.0)
	if dead:
		Audio.buses.set_music_lpf(true)
	for i in 2:
		var g: float = _gain[i]
		var tg: float = _gain_tgt[i]
		if g != tg:
			var step: float = _gain_rate[i] * dt
			g = minf(tg, g + step) if tg > g else maxf(tg, g - step)
			_gain[i] = g
		var p: AudioStreamPlayer = _pl[i]
		if g <= MUTE + 0.5 and tg <= MUTE:
			if p.playing or p.stream != null:
				p.stop()
				p.stream = null
				_stream[i] = null
				_key[i] = ""
			continue
		var v: float = g + (all_db if i == _cur else 0.0)
		if absf(p.volume_db - v) > 0.02:
			p.volume_db = maxf(v, MUTE)


func _sync_check(now: float, dt: float) -> void:
	if Audio.silent or Game.is_sim_paused():
		return
	var n: int = _cur
	var p: AudioStreamPlayer = _pl[n]
	if not p.playing or p.stream_paused:
		return
	var base: float = _pbase[n] * (Beat.heung_mult if _hfollow[n] == 1 else 1.0)
	if Game.sim_speed != 1:
		_was_speed1 = false
		_set_pitch(p, base)
		return
	var eb: float = _expected_beats()
	var L: float = _loop_len[n]
	var expect: float = fposmod(eb * _spb[n], L)
	if not _was_speed1:
		_was_speed1 = true
		_seek(p, expect, L, base, now)
		st_hard += 1
		return
	if dt > 0.045:
		# 프레임 멈춤(저사양·로딩): 물리 틱이 몇 프레임에 걸쳐 따라잡는 동안의 박 위치는 일시적으로 뒤처져 있다.
		# 그 순간을 재고 seek 하면 음악이 뒤로 튄다 → 멈춤 직후 0.25s 는 재지 않는다.
		_settle_until = now + 0.25
		return
	if now < _settle_until:
		return
	var heard: float = p.get_playback_position() + (AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * base
	var err: float = (fposmod(heard - expect + L * 0.5, L) - L * 0.5) / base   # 실시간 초(+ = 음악이 앞섬)
	var ae: float = absf(err)
	if _calib:
		_calib = false
		if ae < 0.08:
			_lead_adj = clampf(_lead_adj - err * 0.5, -0.04, 0.04)
		# 시작·재개 직후 한 번: 프레임 지터로 생긴 18ms 이상 어긋남은 PLL(±0.8%, 수 초) 대신 즉시 맞춘다.
		# 이 시점은 새 슬롯이 아직 페이드인 중이라 seek 가 들리지 않는다.
		if _snap_left > 0 and ae >= 0.018 and ae <= HARD_RESYNC_S:
			_snap_left -= 1
			_seek(p, expect, L, base, now)
			st_resyncs += 1
			return
	st_err_sum += ae
	st_err_signed += err
	st_err_n += 1
	if ae > st_err_max:
		st_err_max = ae
	w_sum += ae
	w_n += 1
	if ae > w_max:
		w_max = ae
	if ae > HARD_RESYNC_S:
		_seek(p, expect, L, base, now)
		st_hard += 1
		return
	_err_ema = lerpf(_err_ema, err, 1.0 - exp(-dt / ERR_TAU))
	_set_pitch(p, base * (1.0 - clampf(_err_ema * PLL_GAIN, -PLL_MAX, PLL_MAX)))
	if absf(_err_ema) * 1000.0 > RESYNC_MS:
		_resync_pending = true
	# 재동기 seek 은 박 경계 직후(장구 타점의 어택이 가린다). 각(마디) 단위로 기다리면 진양조는 4s 나 끌린다.
	var gi: int = int(floor(eb))
	if _resync_pending and gi != _last_gak_i:
		_seek(p, expect, L, base, now)
		st_resyncs += 1
	_last_gak_i = gi


func _seek(p: AudioStreamPlayer, expect: float, L: float, base: float, now: float) -> void:
	p.seek(fposmod(expect + _lead() * base, L))
	_set_pitch(p, base)
	_resync_pending = false
	_calib = true
	_err_ema = 0.0
	_settle_until = now + 0.3


func _set_pitch(p: AudioStreamPlayer, v: float) -> void:
	if absf(p.pitch_scale - v) > 0.0002:
		p.pitch_scale = v


func stats_line() -> String:
	var avg: float = (st_err_sum / st_err_n * 1000.0) if st_err_n > 0 else 0.0
	var lv: PackedStringArray = PackedStringArray()
	for i in NS:
		lv.append("%s:%s" % [STEMS[i].substr(0, 3), ("--" if _lvl[i] <= FLOOR + 0.5 else "%.0f" % _lvl[i])])
	var wavg: float = (w_sum / w_n * 1000.0) if w_n > 0 else 0.0
	var sgn: float = (st_err_signed / st_err_n * 1000.0) if st_err_n > 0 else 0.0
	var line: String = "music key=%s mode=%d sync_n=%d win[n=%d avg_ms=%.2f max_ms=%.2f] all[avg_ms=%.2f signed_ms=%.2f max_ms=%.1f] pitch=%.4f resync=%d hard=%d xfades=%d heung_sw=%d I=%d layers=[%s]" % [
		(_key[_cur] if _cur >= 0 else "-"), mode, st_err_n, w_n, wavg, w_max * 1000.0, avg, sgn, st_err_max * 1000.0,
		(_pl[_cur].pitch_scale if _cur >= 0 else 1.0), st_resyncs, st_hard, st_xfades, st_heung_sw, intensity, " ".join(lv)]
	w_sum = 0.0
	w_n = 0
	w_max = 0.0
	return line


func fx_snap_div() -> int:
	return int(_fx_div.get(_tier_id, 4))


func release() -> void:
	for i in 2:
		_pl[i].stop()
		_pl[i].stream = null
		_stream[i] = null
	if _pause_pl != null:
		_pause_pl.stop()
		_pause_pl.stream = null
	for p: String in _requested:
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(p)
	_requested.clear()
	_ogg.clear()
