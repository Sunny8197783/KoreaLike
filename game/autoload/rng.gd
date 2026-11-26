extends Node
## Rng — 스트림별 결정론 RNG. 소유: core(리드).
## 스트림 이름(data/combat_core.json sim.rng_streams + 확장): combat, drop, jeomji, chest, fx, spawn, mboss, ai, trial, pickup(구슬·엽전 흩뿌림 — 화면 연출 fx 와 분리, 11-25)
## 규칙: 시뮬레이션 결과에 영향을 주는 난수는 반드시 해당 스트림을 쓴다. 연출(파티클 흔들림 등)은 "fx" 만.

const DEFAULT_STREAMS: PackedStringArray = ["combat", "drop", "jeomji", "chest", "fx", "spawn", "mboss", "ai", "trial", "pickup"]

var run_seed: int = 0
var _streams: Dictionary = {}   # StringName -> RandomNumberGenerator


func _ready() -> void:
	reseed(int(Time.get_unix_time_from_system()))


func reseed(seed_value: int) -> void:
	run_seed = seed_value
	_streams.clear()
	for s in DEFAULT_STREAMS:
		stream(StringName(s))


func stream(name: StringName) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = _streams.get(name)
	if r == null:
		r = RandomNumberGenerator.new()
		r.seed = hash(str(run_seed) + ":" + String(name))
		_streams[name] = r
	return r


func randf_s(name: StringName) -> float:
	return stream(name).randf()


func range_s(name: StringName, a: float, b: float) -> float:
	return stream(name).randf_range(a, b)


func int_s(name: StringName, a: int, b: int) -> int:
	return stream(name).randi_range(a, b)


func chance(name: StringName, p: float) -> bool:
	return stream(name).randf() < p


## 가중치 선택. items: Array[Dictionary], weight_key 필드 사용. 빈 배열이면 -1.
func pick_weighted_index(name: StringName, items: Array, weight_key: String = "weight") -> int:
	var total: float = 0.0
	for it: Variant in items:
		total += float(it.get(weight_key, 1.0)) if it is Dictionary else 1.0
	if total <= 0.0:
		return -1
	var roll: float = stream(name).randf() * total
	for i in items.size():
		var it: Variant = items[i]
		roll -= float(it.get(weight_key, 1.0)) if it is Dictionary else 1.0
		if roll <= 0.0:
			return i
	return items.size() - 1
