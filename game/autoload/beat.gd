extends Node
## Beat — 장단 박 시계 + 무구 발사 양자화(phase_carry). 소유: core(리드), 사용: combat/audio/vfx/ui.
##
## 권위: 시뮬레이션 정수 틱(Game.beat_tick)이 권위, 음악이 따라간다(design/14 §3.9.1).
## 그리드: 거리(geori)별 BPM·grid(박 분수). 진양조는 1/4박, 나머지 1/2박(waves_stage1.json geori[].quant_grid).
## 거리 전환은 게임 시각(Game.time_sec) 기준, 위상은 박 시계 기준으로 구간 시작 틱에서 다시 계산(누적 오차 없음).
##
## 무구 API
##   try_fire(key, cooldown, downbeat=false) -> bool   : 시뮬레이션 틱마다 호출. 그리드 경계 틱에서만 true 가능.
##       알고리즘(weapons.json globals.quantization.phase_carry):
##         on grid tick t: fire if t >= ideal_t and t >= last_fire_t + grid
##                         ideal_t += P_eff ; if t - ideal_t > grid: ideal_t = t + P_eff
##   request_fire(key, cooldown, downbeat=false) -> float : 부작용 없음. 다음 발사 예정 박 시각(초, 박 시계).
##   히트스톱 중 지나간 그리드 경계는 따라잡지 않는다(시뮬레이션이 try_fire 를 부르지 않으므로 자동 보장).

const EPS: float = 0.5 / 60.0

var geori_list: Array = []
var geori_idx: int = -1
var geori_id: StringName = &""
var jangdan: StringName = &""
var bpm: float = 45.0
var grid_frac: float = 0.25           # 박 분수
var beats_per_cycle: int = 4          # 장단 한 바퀴(박 머리 판정)
var heung_mult: float = 1.0           # 흥 가속 (1.0 / 1.04 / 1.08), 마디 경계에서만 바꿀 것

var beat_pos: float = 0.0             # 구간 시작 이후 박 수
var beat_index: int = 0               # 런 누적 박 번호
var grid_index: int = 0               # 런 누적 그리드 번호
var is_grid_tick: bool = false        # 이번 박 틱에 그리드 경계를 넘었는가
var is_beat_tick: bool = false
var is_downbeat_tick: bool = false

var cooldown_floor: float = 0.4
var cooldown_floor_sinmyeong: float = 0.25

var _seg_start_tick: int = 0
var _seg_start_sec: float = 0.0
var _seg_grid_count: int = 0
var _seg_beat_count: int = 0
var _fire_ideal: Dictionary = {}      # StringName -> float (박 시계 초)
var _fire_last: Dictionary = {}

# 장단별 한 바퀴 박 수(audio_jangdan.json 미정 시 기본값). audio 담당이 데이터로 대체.
const CYCLE_BEATS: Dictionary = {
	&"jinyangjo": 6, &"jungmori": 12, &"jungjungmori": 4, &"jajinmori": 4,
	&"danmori": 4, &"jinobangjin": 4, &"boss": 4,
}


func _ready() -> void:
	reset()


func reset() -> void:
	geori_list = Data.get_value("waves_stage1", "geori", [])
	if geori_list.is_empty():
		var j: Variant = Data.get_value("combat_core", "jangdan.geori", [])
		for g: Variant in j:
			geori_list.append({"id": g.get("id", ""), "start_sec": g.get("start", 0), "bpm": g.get("bpm", 60), "quant_grid": 1.0 / float(g.get("grid_div", 2)), "jangdan": ""})
	if geori_list.is_empty():
		geori_list = [{"id": "geori_default", "start_sec": 0, "bpm": 90, "quant_grid": 0.5, "jangdan": "jungjungmori"}]
	cooldown_floor = Data.num("combat_core", "jangdan.cooldown_floor", 0.4)
	cooldown_floor_sinmyeong = Data.num("combat_core", "jangdan.cooldown_floor_sinmyeong", 0.25)
	geori_idx = -1
	beat_index = 0
	grid_index = 0
	beat_pos = 0.0
	_fire_ideal.clear()
	_fire_last.clear()
	_enter_geori(0, 0)


func _geori_for_time(t: float) -> int:
	var idx: int = 0
	for i in geori_list.size():
		var st: Variant = geori_list[i].get("start_sec", 0)
		if st != null and t >= float(st):
			idx = i
	return idx


func _enter_geori(idx: int, at_tick: int) -> void:
	geori_idx = idx
	var g: Dictionary = geori_list[idx]
	geori_id = StringName(String(g.get("id", "")))
	jangdan = StringName(String(g.get("jangdan", "")))
	var b: Variant = g.get("bpm", 90)
	bpm = float(b) if (b is float or b is int) else 90.0
	var q: Variant = g.get("quant_grid", 0.5)
	grid_frac = float(q) if (q is float or q is int) else 0.5
	beats_per_cycle = int(CYCLE_BEATS.get(jangdan, 4))
	_seg_start_tick = at_tick
	_seg_start_sec = float(at_tick) / K.TICK_HZ
	_seg_grid_count = 0
	_seg_beat_count = 0
	Events.geori_changed.emit(geori_id, bpm, jangdan)


## Game.advance_tick 가 박 틱마다 호출(히트스톱 중에도).
func advance() -> void:
	var want: int = _geori_for_time(Game.time_sec())
	if want != geori_idx:
		_enter_geori(want, Game.beat_tick)
	var eff_bpm: float = bpm * heung_mult
	beat_pos = float(Game.beat_tick - _seg_start_tick) * eff_bpm / (60.0 * K.TICK_HZ)
	var g_count: int = int(floor(beat_pos / grid_frac + 1e-6))
	var b_count: int = int(floor(beat_pos + 1e-6))
	is_grid_tick = g_count > _seg_grid_count or Game.beat_tick == _seg_start_tick
	is_beat_tick = b_count > _seg_beat_count or Game.beat_tick == _seg_start_tick
	is_downbeat_tick = false
	if is_grid_tick:
		_seg_grid_count = g_count
		grid_index += 1
		Events.grid_tick.emit(grid_index)
	if is_beat_tick:
		_seg_beat_count = b_count
		beat_index += 1
		is_downbeat_tick = (b_count % beats_per_cycle) == 0
		Events.beat.emit(beat_index, is_downbeat_tick)


func beat_len_sec() -> float:
	return 60.0 / (bpm * heung_mult)


func grid_sec() -> float:
	return beat_len_sec() * grid_frac


## 0..1 박 안의 위상(UI 박 표시·VFX 맥동용).
func beat_phase() -> float:
	return fposmod(beat_pos, 1.0)


func effective_period(cooldown: float) -> float:
	var floor_v: float = cooldown_floor_sinmyeong if Game.sinmyeong_oreum else cooldown_floor
	return maxf(cooldown, floor_v)


## 다음 그리드(또는 박) 경계 시각(박 시계 초) >= t.
func next_grid_time(t: float, downbeat: bool = false) -> float:
	var step: float = beat_len_sec() if downbeat else grid_sec()
	var k: float = ceil((t - _seg_start_sec) / step - 1e-6)
	return _seg_start_sec + maxf(k, 0.0) * step


## 부작용 없음. 이 무구가 다음에 발사될 박 시각.
func request_fire(key: StringName, cooldown: float, downbeat: bool = false) -> float:
	var now: float = Game.beat_sec()
	var step: float = beat_len_sec() if downbeat else grid_sec()
	var ideal: float = float(_fire_ideal.get(key, now))
	var last: float = float(_fire_last.get(key, -1e9))
	return next_grid_time(maxf(maxf(ideal, last + step - EPS), now), downbeat)


## 시뮬레이션 틱마다 호출. 발사해야 하면 true(상태 갱신 포함).
func try_fire(key: StringName, cooldown: float, downbeat: bool = false) -> bool:
	var on_edge: bool = is_beat_tick if downbeat else is_grid_tick  # downbeat 무구(장구 등)는 온박에만
	if not on_edge:
		return false
	var t: float = Game.beat_sec()
	var step: float = beat_len_sec() if downbeat else grid_sec()
	if not _fire_ideal.has(key):
		_fire_ideal[key] = t
	var ideal: float = _fire_ideal[key]
	var last: float = float(_fire_last.get(key, -1e9))
	if t + EPS < ideal or t + EPS < last + step:
		return false
	var p_eff: float = effective_period(cooldown)
	ideal += p_eff
	if t - ideal > step:
		ideal = t + p_eff
	_fire_ideal[key] = ideal
	_fire_last[key] = t
	return true


func reset_weapon(key: StringName) -> void:
	_fire_ideal.erase(key)
	_fire_last.erase(key)
