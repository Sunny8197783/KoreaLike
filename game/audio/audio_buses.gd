extends RefCounted
## AudioBuses — 버스 구성·플레이어 슬라이더·덕킹 엔벨로프·스냅샷 오프셋. 소유: audio.
## 원본: data/audio_mix.json (buses / ducking / snapshots / slider_mapping "gain = slider²").
##
## 버스(런타임 생성, 기본 레이아웃은 Master 만):
##   Master(하드 리미터 -1dBTP)
##   ├ Music(슬라이더, [0] LPF 800Hz 점지·사망 / [1] 고역 셸프 -3dB@4k 저정기) ─ MusicStinger(스팅어)
##   ├ SFX(슬라이더) ─ SfxPlayer · SfxRed(컴프 -18/3) · SfxWhite(컴프 -18/3) · SfxRitual(리버브 '넋') · SfxEnemy(컴프 -20/4) · SfxPickup
##   ├ UI · Ambience · Voice
## 음악 덕킹(bus_music_duck / bus_mus_deity)은 버스가 아니라 MusicDirector 가 스템 볼륨으로 적용한다
##   (동기화 스트림의 스템은 한 플레이어 = 한 버스라서). 그래서 채널 값만 계산해 넘긴다.

const LAYOUT: Array = [
	["Music", "Master"], ["MusicStinger", "Music"],
	["SFX", "Master"], ["SfxPlayer", "SFX"], ["SfxRed", "SFX"], ["SfxWhite", "SFX"],
	["SfxRitual", "SFX"], ["SfxEnemy", "SFX"], ["SfxPickup", "SFX"],
	["UI", "Master"], ["Ambience", "Master"], ["Voice", "Master"],
]

# 덕 채널
const CH_MUSIC_ALL: int = 0     # 음악 전체(장구 포함) — 정적 이벤트
const CH_MUSIC_DUCK: int = 1    # bus_music_duck: 장구 제외 음악
const CH_DEITY: int = 2         # bus_mus_deity: 신령·선율 레이어
const CH_SFX: int = 3
const CH_ENEMY: int = 4
const CH_RED: int = 5
const CH_WHITE: int = 6
const CH_AMB: int = 7
const NCH: int = 8
const CH_BUS: Array[StringName] = [&"", &"", &"", &"SFX", &"SfxEnemy", &"SfxRed", &"SfxWhite", &"Ambience"]

# 덕 프리셋(audio_mix.json ducking[] 값 그대로 — 행 순서가 아니라 의미로 묶는다)
enum Duck { GILDAKKEUM, BINGUI, BOSS_SILENCE, PLAYER_HIT, WONGWI, BRIDGE, HAEWON_ELITE }

const MAX_DUCKS: int = 8

var _base_db: Dictionary = {}      # bus -> 믹스 트림(dB)
var _user_db: Dictionary = {}      # bus -> 슬라이더(dB)
var _snap_db: Dictionary = {}      # bus -> 스냅샷 오프셋 목표(dB)
var _snap_cur: Dictionary = {}     # bus -> 현재 스냅샷 오프셋(dB, 블렌드 중)
var _applied: Dictionary = {}      # bus -> 마지막 적용 dB
var _bus_idx: Dictionary = {}      # bus -> index

var _d_t0: PackedFloat64Array = PackedFloat64Array()
var _d_a: PackedFloat32Array = PackedFloat32Array()
var _d_h: PackedFloat32Array = PackedFloat32Array()
var _d_r: PackedFloat32Array = PackedFloat32Array()
var _d_depth: PackedFloat32Array = PackedFloat32Array()   # MAX_DUCKS * NCH
var _d_live: PackedByteArray = PackedByteArray()
var ch_db: PackedFloat32Array = PackedFloat32Array()      # 채널별 현재 덕(dB, ≤0)
var _music_lpf_on: bool = false
var _music_shelf_on: bool = false


func setup() -> void:
	for row: Array in LAYOUT:
		var name: StringName = StringName(row[0])
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
	for row: Array in LAYOUT:
		var bi: int = AudioServer.get_bus_index(StringName(row[0]))
		AudioServer.set_bus_send(bi, StringName(row[1]))
	_add_effects()
	_base_db = {
		&"Master": 0.0, &"Music": 0.0, &"MusicStinger": _trim("MusicStinger", -2.0),
		&"SFX": 0.0, &"SfxPlayer": _trim("SfxPlayer", -1.0), &"SfxRed": _trim("SfxRed", -6.0),
		&"SfxWhite": _trim("SfxWhite", -7.0), &"SfxRitual": _trim("SfxRitual", -4.0),
		&"SfxEnemy": _trim("SfxEnemy", -9.0), &"SfxPickup": _trim("SfxPickup", -9.0),
		&"UI": _trim("UI", -4.0), &"Ambience": _trim("Ambience", -2.0), &"Voice": 0.0,
	}
	for b: StringName in _base_db:
		_bus_idx[b] = AudioServer.get_bus_index(b)
		if not _user_db.has(b):
			_user_db[b] = 0.0
		_snap_db[b] = 0.0
		_snap_cur[b] = 0.0
		_applied[b] = 999.0
	_d_t0.resize(MAX_DUCKS)
	_d_a.resize(MAX_DUCKS)
	_d_h.resize(MAX_DUCKS)
	_d_r.resize(MAX_DUCKS)
	_d_live.resize(MAX_DUCKS)
	_d_live.fill(0)
	_d_depth.resize(MAX_DUCKS * NCH)
	_d_depth.fill(0.0)
	ch_db.resize(NCH)
	ch_db.fill(0.0)
	apply_all()


## 버스 믹스 트림: data audio_mix.json runtime.bus_trim_db.<bus> 가 있으면 그것, 없으면 기본값.
func _trim(bus_name: String, default_db: float) -> float:
	return Data.num("audio_mix", "runtime.bus_trim_db." + bus_name, default_db)


func _add_effects() -> void:
	var m: int = AudioServer.get_bus_index(&"Master")
	if AudioServer.get_bus_effect_count(m) == 0:
		var lim: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		lim.release = 0.05
		AudioServer.add_bus_effect(m, lim)
	var mu: int = AudioServer.get_bus_index(&"Music")
	if AudioServer.get_bus_effect_count(mu) == 0:
		var lpf: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 800.0
		lpf.resonance = 0.5
		AudioServer.add_bus_effect(mu, lpf)
		AudioServer.set_bus_effect_enabled(mu, 0, false)
		var sh: AudioEffectHighShelfFilter = AudioEffectHighShelfFilter.new()
		sh.cutoff_hz = 4000.0
		sh.gain = db_to_linear(-3.0)
		AudioServer.add_bus_effect(mu, sh)
		AudioServer.set_bus_effect_enabled(mu, 1, false)
	for b: StringName in [&"SfxRed", &"SfxWhite", &"SfxEnemy"]:
		var bi: int = AudioServer.get_bus_index(b)
		if AudioServer.get_bus_effect_count(bi) == 0:
			var c: AudioEffectCompressor = AudioEffectCompressor.new()
			c.threshold = -20.0 if b == &"SfxEnemy" else -18.0
			c.ratio = 4.0 if b == &"SfxEnemy" else 3.0
			c.attack_us = 6000.0     # 6ms: 첫 타격(0~5ms 트랜지언트)은 통과시키고 물량 꼬리만 누른다
			c.release_ms = 120.0
			AudioServer.add_bus_effect(bi, c)
	var ri: int = AudioServer.get_bus_index(&"SfxRitual")
	if AudioServer.get_bus_effect_count(ri) == 0:
		# bus_rev_neok 근사: 넓고 밝은 잔향(해원 방울·풍경이 굿판 공간에 번진다)
		var rv: AudioEffectReverb = AudioEffectReverb.new()
		rv.room_size = 0.78
		rv.damping = 0.22
		rv.spread = 1.0
		rv.hipass = 0.18
		rv.predelay_msec = 28.0
		rv.predelay_feedback = 0.25
		rv.dry = 1.0
		rv.wet = 0.17
		AudioServer.add_bus_effect(ri, rv)


## 플레이어 슬라이더(0..1). data slider_mapping: gain_linear = slider². 0 이면 뮤트.
func set_user(bus: StringName, v: float) -> void:
	var s: float = clampf(v, 0.0, 1.0)
	_user_db[bus] = -80.0 if s <= 0.001 else linear_to_db(s * s)
	if not _bus_idx.has(bus):
		_bus_idx[bus] = AudioServer.get_bus_index(bus)
		_base_db[bus] = 0.0
		_snap_db[bus] = 0.0
		_snap_cur[bus] = 0.0
		_applied[bus] = 999.0
	_apply(bus)


func set_snapshot(bus: StringName, db: float) -> void:
	if _snap_db.has(bus):
		_snap_db[bus] = db


func set_music_lpf(on: bool) -> void:
	if on == _music_lpf_on:
		return
	_music_lpf_on = on
	var mu: int = AudioServer.get_bus_index(&"Music")
	if mu >= 0 and AudioServer.get_bus_effect_count(mu) > 0:
		AudioServer.set_bus_effect_enabled(mu, 0, on)


func set_music_shelf(on: bool) -> void:
	if on == _music_shelf_on:
		return
	_music_shelf_on = on
	var mu: int = AudioServer.get_bus_index(&"Music")
	if mu >= 0 and AudioServer.get_bus_effect_count(mu) > 1:
		AudioServer.set_bus_effect_enabled(mu, 1, on)


## 덕 시작. 같은 프리셋이 살아 있으면 다시 시작(겹치지 않고 갱신).
func duck(preset: int, hold_override: float = -1.0) -> void:
	var a: float = 0.0
	var h: float = 0.0
	var r: float = 0.0
	var dep: PackedFloat32Array = PackedFloat32Array()
	dep.resize(NCH)
	dep.fill(0.0)
	match preset:
		Duck.GILDAKKEUM:
			a = 0.010; h = 0.120; r = 0.400
			dep[CH_MUSIC_DUCK] = -6.0; dep[CH_ENEMY] = -8.0; dep[CH_RED] = -4.0
		Duck.BINGUI:
			a = 0.030; h = 0.900; r = 0.300
			dep[CH_MUSIC_DUCK] = -4.0; dep[CH_ENEMY] = -10.0; dep[CH_RED] = -6.0; dep[CH_WHITE] = -6.0
		Duck.BOSS_SILENCE:
			a = 0.400; h = 2.600; r = 0.050
			dep[CH_MUSIC_ALL] = -60.0; dep[CH_ENEMY] = -60.0; dep[CH_AMB] = -12.0
		Duck.PLAYER_HIT:
			a = 0.005; h = 0.060; r = 0.200
			dep[CH_ENEMY] = -3.0
		Duck.WONGWI:
			a = 0.200; h = 2.0; r = 0.800
			dep[CH_DEITY] = -12.0
		Duck.BRIDGE:
			a = 2.6; h = 0.35; r = 0.15
			dep[CH_MUSIC_DUCK] = -9.0
		Duck.HAEWON_ELITE:
			a = 0.020; h = 0.300; r = 0.400
			dep[CH_ENEMY] = -6.0; dep[CH_RED] = -3.0
	if hold_override >= 0.0:
		h = hold_override
	var slot: int = preset % MAX_DUCKS
	_d_live[slot] = 1
	_d_t0[slot] = Audio.now()
	_d_a[slot] = a
	_d_h[slot] = h
	_d_r[slot] = r
	for c in NCH:
		_d_depth[slot * NCH + c] = dep[c]


## 덕 즉시 해제(예: 보스 장단이 정적 덕 홀드가 끝나기 전에 시작될 때).
func cancel(preset: int) -> void:
	_d_live[preset % MAX_DUCKS] = 0


## 매 프레임(실시간). 덕 엔벨로프 → 채널 dB, 스냅샷 블렌드 → 버스 볼륨.
func update(now: float, dt: float) -> void:
	for c in NCH:
		ch_db[c] = 0.0
	for k in MAX_DUCKS:
		if _d_live[k] == 0:
			continue
		var t: float = now - _d_t0[k]
		var a: float = _d_a[k]
		var h: float = _d_h[k]
		var r: float = _d_r[k]
		var f: float = 0.0
		if t < a:
			f = t / a if a > 0.0 else 1.0
		elif t < a + h:
			f = 1.0
		elif t < a + h + r:
			f = 1.0 - (t - a - h) / r
		else:
			_d_live[k] = 0
			continue
		for c in NCH:
			var v: float = _d_depth[k * NCH + c] * f
			if v < ch_db[c]:
				ch_db[c] = v
	var blend: float = clampf(dt / 0.15, 0.0, 1.0)
	for b: StringName in _snap_cur:
		var cur: float = _snap_cur[b]
		var tgt: float = _snap_db[b]
		if absf(cur - tgt) > 0.01:
			_snap_cur[b] = lerpf(cur, tgt, blend)
	apply_all()


func apply_all() -> void:
	for b: StringName in _base_db:
		_apply(b)


func _apply(bus: StringName) -> void:
	var bi: int = int(_bus_idx.get(bus, -1))
	if bi < 0:
		return
	var v: float = float(_base_db.get(bus, 0.0)) + float(_user_db.get(bus, 0.0)) + float(_snap_cur.get(bus, 0.0))
	for c in NCH:
		if CH_BUS[c] == bus:
			v += ch_db[c]
	if absf(v - float(_applied.get(bus, 999.0))) < 0.02:
		return
	_applied[bus] = v
	AudioServer.set_bus_volume_db(bi, maxf(v, -80.0))
